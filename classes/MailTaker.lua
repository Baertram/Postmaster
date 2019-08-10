local addon = Postmaster
local class = addon.classes
local debug = false
local timeoutMilliseconds = 4000
local maxRetries = 5
local takeOrRemove, createTimeout

class.MailTaker = ZO_CallbackObject:Subclass()

function class.MailTaker:New(...)
    local instance = ZO_CallbackObject.New(self)
    instance:Initialize(...)
    return instance
end

function class.MailTaker:Initialize(mailId, remove)
    self.name = addon.name .. "_MailTaker_" .. tostring(mailId)
    self.mailId = mailId
    self.mailIdString = zo_getSafeId64Key(mailId)  
    self.remove = remove  
    -- Contains detailed information about mail attachments (links, money, cod)
    -- for mail currently being taken.  Used to display summaries to chat.
    self.attachmentData = {}
    self.awaitingAttachments = {}
    addon.Debug("MailTaker:New(" .. self.mailIdString .. "), name = " .. self.name, debug)
end

function class.MailTaker:CreateMailReadableHandler(retries)
    return function(eventCode, mailId)
        if not AreId64sEqual(mailId, self.mailId) then
            return
        end
        EVENT_MANAGER:UnregisterForUpdate(self.name .. "Readable")
        EVENT_MANAGER:UnregisterForEvent(self.name, EVENT_MAIL_READABLE)
        
        addon.Debug("EVENT_MAIL_READABLE(" .. tostring(eventCode) ..", " .. self.mailIdString .. ")", debug)
        
        local numAttachments, attachedMoney, codAmount = GetMailAttachmentInfo(mailId)
        self.attachmentData = { items = {}, money = attachedMoney, cod = codAmount }
        self.awaitingAttachments = { items = false, money = attachedMoney, cod = codAmount }
        local uniqueAttachmentConflictCount = 0
        for attachIndex=1,numAttachments do
            local _, stack = GetAttachedItemInfo(mailId, attachIndex)
            local attachmentItem = { link = GetAttachedItemLink(mailId, attachIndex), count = stack or 1 }
            if addon:IsItemUniqueInBackpack(attachmentItem.link) then
                uniqueAttachmentConflictCount = uniqueAttachmentConflictCount + 1
            else
                table.insert(self.attachmentData.items, attachmentItem)
                self.awaitingAttachments.items = true
            end
        end
        
        -- If all attachments were unique and already in the backpack
        if numAttachments > 0 and uniqueAttachmentConflictCount == numAttachments then
            self.Debug("Not taking attachments for " .. self.mailIdString
                       .." because it contains only unique items that are already in the backpack", debug)
            self:FireCallbacks("Failed", mailId, "Contains Unique Items In Bag")
            return
        end
                
        if #self.attachmentData.items > 0 or self.money > 0 then
          
            EVENT_MANAGER:RegisterForUpdate(self.name .. "Taken", timeoutMilliseconds, createTimeout(self, "Taken", true, retries))
            
            if self.awaitingAttachments.items then
                EVENT_MANAGER:RegisterForEvent(self.name, EVENT_MAIL_TAKE_ATTACHED_ITEM_SUCCESS, self:CreateMailTakeAttachedItemSuccessHandler())
                if self.cod > 0 then
                    EVENT_MANAGER:RegisterForEvent(self.name, EVENT_MONEY_UPDATE, self:CreateMoneyUpdateHandler())
                end
                TakeMailAttachedItems(mailId)
            end
            if self.awaitingAttachments.money then
                EVENT_MANAGER:RegisterForEvent(self.name, EVENT_MAIL_TAKE_ATTACHED_MONEY_SUCCESS, self:CreateMailTakeAttachedMoneySuccessHandler())
                TakeMailAttachedMoney(mailId)
            end
            
        elseif self.remove then
            
            EVENT_MANAGER:RegisterForUpdate(self.name .. "Removed", timeoutMilliseconds, createTimeout(self, "Removed", false, retries))
            EVENT_MANAGER:RegisterForEvent(self.name, EVENT_MAIL_REMOVED, self:CreateMailRemovedHandler())
            DeleteMail(self.mailId, false)
            
        else
            self:OnDone()
            
        end
    end
end

--[[ Raised in response to a successful DeleteMail() call. ]]
function class.MailTaker:CreateMailRemovedHandler()
    return function(eventCode, mailId)
        if not AreId64sEqual(mailId, self.mailId) then
            return
        end
        
        EVENT_MANAGER:UnregisterForUpdate(self.name .. "Removed")
        EVENT_MANAGER:UnregisterForEvent(self.name, EVENT_MAIL_REMOVED)
        
        self.Debug("EVENT_MAIL_REMOVED(" .. tostring(eventCode) .. ", " .. self.mailIdString .. ")", debug)
        
        PlaySound(SOUNDS.MAIL_ITEM_DELETED)
        
        self:OnDone()
    end
end

--[[ Raised when attached items are all received into inventory from a mail. ]]
function class.MailTaker:CreateMailTakeAttachedItemSuccessHandler()
    return function (eventCode, mailId)
        if not AreId64sEqual(mailId, self.mailId) then
            return
        end
        
        self.Debug("EVENT_MAIL_TAKE_ATTACHED_ITEM_SUCCESS(" .. tostring(eventCode) .. ", " .. self.mailIdString .. ")", debug)
        
        EVENT_MANAGER:UnregisterForEvent(self.name, EVENT_MAIL_TAKE_ATTACHED_ITEM_SUCCESS)
        
        self.awaitingAttachments.items = false
        if self.awaitingAttachments.money == 0 and self.awaitingAttachments.cod == 0 then
            self:OnTaken()
        end
    end
end

--[[ Raised when attached gold is all received from a mail.  ]]
function class.MailTaker:CreateMailTakeAttachedMoneySuccessHandler()
    return function(eventCode, mailId)
        if not AreId64sEqual(mailId, self.mailId) then
            return
        end
      
        self.Debug("EVENT_MAIL_TAKE_ATTACHED_MONEY_SUCCESS(" .. tostring(eventCode) .. ", " .. self.mailIdString .. ")", debug)
        
        EVENT_MANAGER:UnregisterForEvent(self.name, EVENT_MAIL_TAKE_ATTACHED_MONEY_SUCCESS)
        
        self.awaitingAttachments.money = 0
        if not self.awaitingAttachments.items and self.awaitingAttachments.cod == 0 then
            self:OnTaken()
        end
    end
end

--[[ Raised whenever gold enters or leaves the player's inventory.  We only care
     about money leaving inventory due to a mail event, indicating a C.O.D. payment. ]]--
function class.MailTaker:CreateMoneyUpdateHandler()
    return function(eventCode, newMoney, oldMoney, reason)
        self.Debug("EVENT_MONEY_UPDATE("..tostring(eventCode)..","..tostring(newMoney)..","..tostring(oldMoney)..","..tostring(reason)..")", debug)
        if reason ~= CURRENCY_CHANGE_REASON_MAIL then 
            self.Debug("Currency change did not due to mail.", debug)
            return
        elseif oldMoney <= newMoney then
            self.Debug("Money increased, so event can't be from a COD payment.", debug)
            return
        end
        
        local goldChanged = oldMoney - newMoney
        if self.awaitingAttachments.cod ~= (oldMoney - newMoney) then
            return
        end
        
        EVENT_MANAGER:UnregisterForEvent(self.name, EVENT_MONEY_UPDATE)
        self.awaitingAttachments.cod = 0
        if not self.awaitingAttachments.items and self.awaitingAttachments.money == 0 then
            self:OnTaken()
        end
    end
end

function class.MailTaker:Remove(retries)
    addon.Debug("Remove() mail id " .. self.mailIdString, debug)
    takeOrRemove(self, false, retries)
end

function class.MailTaker:OnDone()
    addon.Debug("Done() mail id " .. self.mailIdString, debug)
    self:FireCallbacks("Done", self.mailId, self.attachmentData)
end

function class.MailTaker:OnFailed(reason)
    addon.Debug("Failed(" .. reason .. ") mail id " .. self.mailIdString, debug)
    self:FireCallbacks("Failed", reason, self.mailId, self.attachmentData)
    self:Reset()
end

function class.MailTaker:OnTaken()
    addon.Debug("Taken() mail id " .. self.mailIdString, debug)
    EVENT_MANAGER:UnregisterForUpdate(self.name .. "Taken")
    self:FireCallbacks("Taken", self.mailId, self.attachmentData)
    if self.remove then
        self:Remove()
    else
        self:OnDone()
    end
end

function class.MailTaker:Reset()
    EVENT_MANAGER:UnregisterForUpdate(self.name .. "Readable")
    EVENT_MANAGER:UnregisterForEvent(self.name, EVENT_MAIL_READABLE)
    EVENT_MANAGER:UnregisterForUpdate(self.name .. "Removed")
    EVENT_MANAGER:UnregisterForEvent(self.name, EVENT_MAIL_REMOVED)
    EVENT_MANAGER:UnregisterForUpdate(self.name .. "Taken")
    EVENT_MANAGER:UnregisterForEvent(self.name, EVENT_MAIL_TAKE_ATTACHED_ITEM_SUCCESS)
    EVENT_MANAGER:UnregisterForEvent(self.name, EVENT_MAIL_TAKE_ATTACHED_MONEY_SUCCESS)
    EVENT_MANAGER:UnregisterForEvent(self.name, EVENT_MONEY_UPDATE)
end

function class.MailTaker:Take(retries)
    addon.Debug("Take() mail id " .. self.mailIdString, debug)
    takeOrRemove(self, true, retries)
end


-- Local functions

function createTimeout(self, name, take, retries)
    return function()
        EVENT_MANAGER:UnregisterForUpdate(self.name .. name)
        addon.Debug("Timeout for mail id " .. self.mailIdString .. " " .. name .. ".", debug)
        if not retries then
            retries = 1
        else
            retries = retries + 1
            if retries > maxRetries then
                self:OnFailed(name)
                return
            end
        end
        if take then
            self:Take(retries)
        else
            self:Remove(retries)
        end
    end
end

function takeOrRemove(self, take, retries)
    if retries then
        addon.Debug("Attempt #" .. tostring(retries), debug)
    end
    local readable = IsReadMailInfoReady(self.mailId)
    local handler = self:CreateMailReadableHandler(retries)
    if readable then
        addon.Debug("Mail id " .. self.mailIdString .. " is READABLE.", debug)
        handler(nil, self.mailId)
        return
    end
    addon.Debug("Mail id " .. self.mailIdString .. " is NOT readable. Requesting mail read.", debug)
    EVENT_MANAGER:RegisterForUpdate(self.name .. "Readable", timeoutMilliseconds, createTimeout(self, "Readable", take, retries))
    EVENT_MANAGER:RegisterForEvent(self.name, EVENT_MAIL_READABLE, handler)
    ReadMail(self.mailId)
end