local addon = Postmaster
local class = addon.classes
local debug = false

class.SharedModule = ZO_Object:Subclass()

function class.SharedModule:New(...)
    local instance = ZO_Object.New(self)
    instance:Initialize(...)
    return instance
end
function class.SharedModule:Initialize(name, sceneOrFragment)
    self.name = name or addon.name .. "_SharedModule"
    self.sceneOrFragment = sceneOrFragment
    self.stateChangeCallback = self:CreateSceneOrFragmentStateChangeCallback()
    self.sceneOrFragment:RegisterCallback("StateChange", self.stateChangeCallback)
end

function class.SharedModule:CreateSceneOrFragmentStateChangeCallback()
    return function(oldState, newState)
        
        -- Inbox shown
        if newState == SCENE_SHOWN or newState == SCENE_FRAGMENT_SHOWN then
            
            self.takeAll = class.TakeAll:New(self.name .. "_TakeAll")
            self.takeAll:RegisterCallback("StateChanged", function() self.keybindWrapper:Refresh() end)
            local mailList, dataField = self:GetMailList()
            
            -- TODO: whenever a new mail is added, removed, or updated, need to update the queue
            for _, entry in ipairs(mailList) do
                self.takeAll:TryQueue(entry[dataField])
            end
            if not self.keybindWrapper then
                self:SetupKeybinds()
            end
            self.keybindWrapper:WrapKeybinds()
        
        -- Inbox hidden
        -- Reset state back to default when inbox hidden, since most server events
        -- will no longer fire with the inbox closed.
        elseif newState == SCENE_HIDDEN or newState == SCENE_FRAGMENT_HIDDEN then
        
            self.keybindWrapper:UnwrapKeybinds()
            self.takeAll = nil
        end
    end
end

--[[   
 
    Reply
    
  ]]
function class.SharedModule:CreateReplyKeybind()
    return {
        name = GetString(SI_MAIL_READ_REPLY),
        keybind = "UI_SHORTCUT_TERTIARY",
        callback = function() 
            -- Look up the current mail message in the inbox
            local mailData = addon.GetOpenMailData()
            
            -- Make sure it's a non-returned mail from another player
            if not mailData or mailData.fromSystem or mailData.returned then return end
            
            -- Populate the sender and subject for the reply
            local address = mailData.senderDisplayName
            local subject = mailData.subject
            self:Reply(address, subject)
        end,
        visible = function()
            if self.takeAll and self.takeAll.state == "active" then
                return false
            end
            local mailData = addon.GetOpenMailData()
            if not mailData then return false end
            return not (mailData.fromCS or mailData.fromSystem)
        end
    }
end
function class.SharedModule:CreateCancelReturnKeybind(keybind, originalReturnKeybind)
    return {
        keybind = "UI_SHORTCUT_NEGATIVE",
        name = function()
            if self.takeAll and self.takeAll.state == "active" then
                return GetString(SI_CANCEL)
            end
            return originalReturnKeybind.name
        end,
        callback = function()
            if self.takeAll and self.takeAll.state == "active" then
                self.takeAll:Cancel()
                return
            end
            originalReturnKeybind.callback()
        end,
        visible = function()
            if self.takeAll and self.takeAll.state == "active" then
                return false
            end
            return originalReturnKeybind.visible()
        end
    }
end

--[[   
 
    Take All
    
  ]]
function class.SharedModule:CreateTakeAllKeybind(keybind)
    return {
        keybind = keybind,
        name = GetString(SI_LOOT_TAKE_ALL),
        callback = function()
            if not self.takeAll 
               or self.takeAll.state == "active" 
            then
                return
            end
            self.takeAll:Start()
        end,
        visible = function()
            return self.takeAll 
                   and self.takeAll.state == "stopped"
                   and self.takeAll:HasQueuedMail()
        end
    }
end

--[[   
 
    Take or Delete, depending on if the current mail has attachments or not.
    
  ]]
function class.SharedModule:CreateTakeDeleteKeybind(originalDeleteKeybind)
    local take = self.keybindWrapper:GetOriginalKeybind("UI_SHORTCUT_PRIMARY")
    local delete = self.keybindWrapper:GetOriginalKeybind(originalDeleteKeybind)
    return {
        keybind = "UI_SHORTCUT_PRIMARY",
        name = function()
            if delete.visible() or
               (MailR and MailR.IsMailIdSentMail(self.mailId))
            then
                return delete.name
            end
            local mailData = addon.GetOpenMailData()
            if addon:QuickTakeCanTake(mailData) then
                return GetString(SI_LOOT_TAKE)
            else
                return GetString(SI_MAIL_READ_ATTACHMENTS_TAKE)
            end
        end,
        callback = function()
            local mailData = addon:GetOpenMailData()
            local mailIdString = mailData.mailId and zo_getSafeId64Key(mailData.mailId) or ""
            if delete.visible()
               or (MailR and MailR.IsMailIdSentMail(mailData.mailId))
            then
                addon.Debug("Deleting mail id " .. mailIdString, debug)
                delete.callback()
                return
            end
            
            addon.Debug("Taking attachments from mail id " .. mailIdString, debug)
            if addon:QuickTakeCanTake(mailData) then
                local mailTaker = class.MailTaker:New(mailData, true)
                mailTaker:Take()
            else
                take.callback()
            end
        end,
        visible = function()
            if self.takeAll and self.takeAll.state == "active" then return false end
            if take.visible() then return true end
            if MailR and MailR.IsMailIdSentMail(self.GetOpenMailData().mailId) then return true end
            return delete.visible()
        end
    }
end

function class.SharedModule:GetMailList()
    -- TODO: overload this
end

function class.SharedModule:Reply(address, subject)
    -- TODO: overload this
end

function class.SharedModule:Reset()
    self.takeAll = nil
    self.sceneOrFragment:UnregisterCallback("StateChange", self.stateChangeCallback)
end

function class.SharedModule:SetupKeybinds()
    -- Todo: overload this
end