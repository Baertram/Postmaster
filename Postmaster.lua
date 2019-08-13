-- Postmaster Addon for Elder Scrolls Online
-- Original Authors: Anthony Korchak aka Zierk + Garkin
-- Completely rewritten by silvereyes

Postmaster = {
    name = "Postmaster",
    title = GetString(SI_PM_NAME),
    version = "4.0.0",
    author = "silvereyes, Garkin & Zierk",
    
    -- For development use only. Set to true to see a ridiculously verbose 
    -- activity log for this addon in the chat window.
    debugMode = true,
    
    -- Flag to signal that once one email is taken and deleted, the next message 
    -- should be selected and the process should continue on it
    takingAll = false,
    
    -- Flag to signal that a message is in the process of having its attachments
    -- taken and then subsequently being deleted.  Used to disable other keybinds
    -- while this occurs.
    taking = false,
    
    -- Used to synchronize item and money attachment retrieval events so that
    -- we know when to issue a DeleteMail() call.  DeleteMail() will not work
    -- unless all server-side events related to a mail are done processing.
    -- For normal mail, this includes EVENT_MAIL_TAKE_ATTACHED_ITEM_SUCCESS
    -- and/or EVENT_MAIL_TAKE_ATTACHED_MONEY_SUCCESS.  
    -- For C.O.D. mail, the events are EVENT_MAIL_TAKE_ATTACHED_ITEM_SUCCESS, 
    -- EVENT_MONEY_UPDATE, and EVENT_MAIL_SEND_SUCCESS (for the outgoing gold mail)
    awaitingAttachments = {},
    
    -- Contains detailed information about mail attachments (links, money, cod)
    -- for mail currently being taken.  Used to display summaries to chat.
    attachmentData = {},
    
    -- Remembers mail removal requests that don't receive a mail removed event from the server
    -- or which have the event come in while the inbox is closed
    -- so that the removals can be processed once the inbox opens again.
    mailIdsMarkedForDeletion = {},
    
    -- Remembers mail ids that fail to delete during a Take All operation
    -- for whatever reason, and therefore should not be taken again during the same
    -- operation.
    mailIdsFailedDeletion = {},
    
    -- Contains details about C.O.D. mail being taken, since events related to
    -- taking C.O.D.s do not contain mail ids as parameters.
    codMails = {},
    
    classes = {},
}

local addon = Postmaster
addon.logger = LibDebugLogger and LibDebugLogger(addon.name)

-- Format for chat print and debug messages, with addon title prefix
PM_CHAT_PREFIX = zo_strformat("<<1>>", addon.title) .. "|cFFFFFF: "
PM_CHAT_FORMAT = PM_CHAT_PREFIX .. " <<1>>|r"

-- Prefixes for bounce mail subjects
PM_BOUNCE_MAIL_PREFIXES = {
    "RTS",
    "BOUNCE",
    "RETURN"
}

local LibLootSummary = LibLootSummary.New and LibLootSummary:New(addon.name) 
                       or LibLootSummary
local hiddenStates = {
    [SCENE_HIDDEN]          = true,
    [SCENE_HIDING]          = true,
    [SCENE_FRAGMENT_HIDDEN] = true,
    [SCENE_FRAGMENT_HIDING] = true,
}

-- Initalizing the addon
local function OnAddonLoaded(eventCode, addOnName)

    local self = addon
    
    if ( addOnName ~= self.name ) then return end
    EVENT_MANAGER:UnregisterForEvent(self.name, eventCode)
    
    -- Initialize settings menu, saved vars, and slash commands to open settings
    self:SettingsSetup()
    self:PosthookSetup()
    
    self:SetActiveModule(IsInGamepadPreferredMode())
    
    EVENT_MANAGER:RegisterForEvent(self.name, EVENT_GAMEPAD_PREFERRED_MODE_CHANGED,
        function(eventCode, gamepadPreferred)
            self:SetActiveModule(gamepadPreferred)
        end)
end

local systemEmailSubjects = {
    ["craft"] = {
        zo_strlower(GetString(SI_PM_CRAFT_BLACKSMITH)),
        zo_strlower(GetString(SI_PM_CRAFT_CLOTHIER)),
        zo_strlower(GetString(SI_PM_CRAFT_ENCHANTER)),
        zo_strlower(GetString(SI_PM_CRAFT_PROVISIONER)),
        zo_strlower(GetString(SI_PM_CRAFT_WOODWORKER)),
    },
    ["guildStore"] = {
        zo_strlower(GetString(SI_PM_GUILD_STORE_CANCELED)),
        zo_strlower(GetString(SI_PM_GUILD_STORE_EXPIRED)),
        zo_strlower(GetString(SI_PM_GUILD_STORE_PURCHASED)),
        zo_strlower(GetString(SI_PM_GUILD_STORE_SOLD)),
    },
    ["pvp"] = {
        zo_strlower(GetString(SI_PM_PVP_FOR_THE_WORTHY)),
        zo_strlower(GetString(SI_PM_PVP_THANKS)),
        zo_strlower(GetString(SI_PM_PVP_FOR_THE_ALLIANCE_1)),
        zo_strlower(GetString(SI_PM_PVP_FOR_THE_ALLIANCE_2)),
        zo_strlower(GetString(SI_PM_PVP_FOR_THE_ALLIANCE_3)),
        zo_strlower(GetString(SI_PM_PVP_THE_ALLIANCE_THANKS_1)),
        zo_strlower(GetString(SI_PM_PVP_THE_ALLIANCE_THANKS_2)),
        zo_strlower(GetString(SI_PM_PVP_THE_ALLIANCE_THANKS_3)),
        zo_strlower(GetString(SI_PM_PVP_LOYALTY)),
    }
}

local systemEmailSenders = {
    ["undaunted"] = {
        zo_strlower(GetString(SI_PM_UNDAUNTED_NPC_NORMAL)),
        zo_strlower(GetString(SI_PM_UNDAUNTED_NPC_VET)),
        zo_strlower(GetString(SI_PM_UNDAUNTED_NPC_TRIAL_1)),
        zo_strlower(GetString(SI_PM_UNDAUNTED_NPC_TRIAL_2)),
        zo_strlower(GetString(SI_PM_UNDAUNTED_NPC_TRIAL_3)),
    },
    ["pvp"] = {
        zo_strlower(GetString(SI_PM_BATTLEGROUNDS_NPC)),
    },
}

function addon:SetActiveModule(gamepadPreferred)
    if self.activeModule then
        self.activeModule:Reset()
    end
    if gamepadPreferred then
        self.activeModule = self.classes.GamepadModule:New()
    else
        self.activeModule = self.classes.KeyboardModule:New()
    end
end

local function CanTakeAllDelete(mailData, attachmentData)

    local self = addon
    
    if not mailData or not mailData.mailId or type(mailData.mailId) ~= "number" then 
        self.Debug("mailData parameter not working right")
        return false 
    end
    
    local mailIdString = self.GetMailIdString(mailData.mailId)
    if self.mailIdsFailedDeletion[mailIdString] == true then 
        self.Debug("Cannot delete because this mail already failed deletion")
        return false
    end
    
    -- Item was meant to be deleted, but the inbox closed, so include it in 
    -- the take all list
    if self:IsMailMarkedForDeletion(mailData.mailId) then
        return true
    end
    
    
    local deleteSettings = {
        cod              = self.settings.takeAllCodDelete,
        playerEmpty      = self.settings.takeAllPlayerDeleteEmpty,
        playerAttached   = self.settings.takeAllPlayerAttachedDelete,
        playerReturned   = self.settings.takeAllPlayerReturnedDelete,
        systemEmpty      = self.settings.takeAllSystemDeleteEmpty,
        systemAttached   = self.settings.takeAllSystemAttachedDelete,
        systemGuildStore = self.settings.takeAllSystemGuildStoreDelete,
        systemHireling   = self.settings.takeAllSystemHirelingDelete,
        systemOther      = self.settings.takeAllSystemOtherDelete,
        systemPvp        = self.settings.takeAllSystemPvpDelete,
        systemUndaunted  = self.settings.takeAllSystemUndauntedDelete,
    }
    
    -- Handle C.O.D. mail
    if attachmentData and attachmentData.cod > 0 then
        if not deleteSettings.cod then
            self.Debug("Cannot delete COD mail")
        end
        return deleteSettings.cod
    end
    
    local fromSystem = (mailData.fromCS or mailData.fromSystem)
    local hasAttachments = attachmentData and (attachmentData.money > 0 or #attachmentData.items > 0)
    if hasAttachments then
        
        -- Special handling for hireling mail, since we know even without opening it that
        -- all the attachments can potentially go straight to the craft bag
        local subjectField = "subject"
        local isHirelingMail = fromSystem and self:MailFieldMatch(mailData, subjectField, systemEmailSubjects["craft"])
        
        if fromSystem then 
            if deleteSettings.systemAttached then
                
                if isHirelingMail then
                    if not deleteSettings.systemHireling then
                        self.Debug("Cannot delete hireling mail")
                    end
                    return deleteSettings.systemHireling
                
                elseif self:MailFieldMatch(mailData, subjectField, systemEmailSubjects["guildStore"]) then
                    if not deleteSettings.systemGuildStore then
                        self.Debug("Cannot delete guild store mail")
                    end
                    return deleteSettings.systemGuildStore
                    
                elseif self:MailFieldMatch(mailData, subjectField, systemEmailSubjects["pvp"]) 
                       or self:MailFieldMatch(mailData, "senderDisplayName", systemEmailSenders["pvp"])
                then
                    if not deleteSettings.systemPvp then
                        self.Debug("Cannot delete PvP rewards mail")
                    end
                    return deleteSettings.systemPvp
                
                elseif self:MailFieldMatch(mailData, "senderDisplayName", systemEmailSenders["undaunted"]) then
                    if not deleteSettings.systemUndaunted then
                        self.Debug("Cannot delete Undaunted rewards mail")
                    end
                    return deleteSettings.systemUndaunted
                    
                else 
                    if not deleteSettings.systemOther then
                        self.Debug("Cannot delete uncategorized system mail")
                    end
                    return deleteSettings.systemOther
                end
                    
            else
                if not deleteSettings.systemAttached then
                    self.Debug("Cannot delete system mail")
                end
                return false
            end
        elseif mailData.returned then
                if not deleteSettings.playerReturned then
                    self.Debug("Cannot delete returned mail")
                end
            return deleteSettings.playerReturned 
        else
            if not deleteSettings.playerAttached then
                self.Debug("Cannot delete player mail with attachments")
            end
            return deleteSettings.playerAttached 
        end
    else
        if fromSystem then
            if not deleteSettings.systemEmpty then
                self.Debug("Cannot delete empty system mail")
            end
            return deleteSettings.systemEmpty
        else 
            if not deleteSettings.playerEmpty then
                self.Debug("Cannot delete empty player mail")
            end
            return deleteSettings.playerEmpty 
        end
    end
    
end

-- Extracting item ids from item links
local function GetItemIdFromLink(itemLink)
    local itemId = select(4, ZO_LinkHandler_ParseLink(itemLink))
    if itemId and itemId ~= "" then
        return tonumber(itemId)
    end
end

local function MailDeleteFailed(timeoutData)
    ZO_Alert(UI_ALERT_CATEGORY_ALERT, nil, SI_PM_DELETE_FAILED)
    addon:Reset()
end

local MailDelete
local function GetMailDeleteCallback(mailId, retries)
    return function()
        retries = retries - 1
        if retries < 0 then
            MailDeleteFailed()
        else
            MailDelete(mailId, retries)
        end
    end
end

function MailDelete(mailId, retries)
    -- Wire up timeout callback
    local self = addon
    if not retries then
        retries = PM_DELETE_MAIL_MAX_RETRIES
    end
    EVENT_MANAGER:RegisterForUpdate(self.name .. "Delete", PM_DELETE_MAIL_TIMEOUT_MS, GetMailDeleteCallback(mailId, retries))
    
    DeleteMail(mailId, false)
end

local MailRead
local function GetMailReadCallback(retries)
    return function()
        local self = addon
        retries = retries - 1
        if retries < 0 then
            ZO_Alert(UI_ALERT_CATEGORY_ALERT, nil, SI_PM_READ_FAILED)
            self:Reset()
        else
            MailRead(retries)
        end
    end
end

function MailRead(retries)

    local self = addon
    if not retries then
        retries = PM_MAIL_READ_MAX_RETRIES
    end
    EVENT_MANAGER:RegisterForUpdate(self.name .. "Read", PM_MAIL_READ_TIMEOUT_MS, GetMailReadCallback(retries) )
    
    -- If there exists another message in the inbox that has attachments, select it. otherwise, clear the selection.
    local nextMailData, nextMailIndex = self:TakeAllGetNext()
    if IsInGamepadPreferredMode() then
        --[[if not self:TakeAllCanTake(MAIL_MANAGER_GAMEPAD.inbox:GetActiveMailData()) then
            self.Debug("Setting mail list selected index to " .. tostring(nextMailIndex))
            MAIL_MANAGER_GAMEPAD.inbox.mailList:SetSelectedIndex(nextMailIndex)
        end]]
    else
        ZO_ScrollList_SelectData(ZO_MailInboxList, nextMailData)
    end
    return nextMailData
end

local function TakeFailed()
    ZO_Alert(UI_ALERT_CATEGORY_ALERT, nil, SI_PM_TAKE_ATTACHMENTS_FAILED)
    addon:Reset()
end

local TakeTimeout
local function GetTakeCallback(mailId, retries)
    return function()
        retries = retries - 1
        if retries < 0 then
            TakeFailed()
        else
            TakeTimeout(mailId, retries)
            ZO_MailInboxShared_TakeAll(mailId)
        end
    end
end
function TakeTimeout(mailId, retries)
    local self = addon
    if not retries then
        retries = PM_TAKE_ATTACHMENTS_MAX_RETRIES
    end
    EVENT_MANAGER:RegisterForUpdate(self.name .. "Take", PM_TAKE_TIMEOUT_MS, GetTakeCallback(mailId, retries) )
end

-- Register events
EVENT_MANAGER:RegisterForEvent(addon.name, EVENT_ADD_ON_LOADED, OnAddonLoaded)

function addon:ClearSelectedMail()
    MAIL_INBOX.mailId = nil
    if MAIL_MANAGER_GAMEPAD.inbox.mailList and MAIL_MANAGER_GAMEPAD.inbox.mailList.enabled then
        local oldTargetSelectedIndex = MAIL_MANAGER_GAMEPAD.inbox.mailList.targetSelectedIndex
        if oldTargetSelectedIndex then
            MAIL_MANAGER_GAMEPAD.inbox.mailList:SetSelectedIndexWithoutAnimation(nil)
        end
    end
end

--[[ Outputs formatted message to chat window if debugging is turned on ]]
function addon.Debug(input, scopeDebug)
    if not addon.debugMode and not scopeDebug then return end
    addon.Print(input)
end

--[[ Registers a potential backpack slot as unique ]]--
function addon:DiscoverUniqueBackpackItem(slotIndex)
    local itemLink = GetItemLink(BAG_BACKPACK, slotIndex)
    if not itemLink or itemLink == "" then
        self.backpackUniqueItems[slotIndex] = nil
    end
    local isUnique = IsItemLinkUnique(itemLink)
    if isUnique then
        self.backpackUniqueItems[slotIndex] = GetItemIdFromLink(itemLink)
    end
end

--[[ Scans the backpack and generates a list of unique items ]]--
function addon:DiscoverUniqueItemsInBackpack()
    self.backpackUniqueItems = {}
    local slotIndex, _
    for slotIndex, _ in pairs(PLAYER_INVENTORY.inventories[INVENTORY_BACKPACK].slots) do
        self:DiscoverUniqueBackpackItem(slotIndex)
    end
    return self.backpackUniqueItems
end

--[[ Places the cursor in the send mail body field. Used by the Reply action. ]]
function addon.FocusSendMailBody()
    ZO_MailSendBodyField:TakeFocus()
end

--[[ Searches self.codMails for the first mail id and C.O.D. mail data taht
     match the given expected amount. ]]
function addon:GetCodMailByGoldChangeAmount(goldChanged)
    for mailIdString,codMail in pairs(self.codMails) do
        if codMail.amount == goldChanged then
            return mailIdString,codMail
        end
    end
end

--[[ Searches self.codMails for the first mail id and C.O.D. mail data that 
     is marked as "complete". ]]
function addon:GetFirstCompleteCodMail()
    for mailIdString,codMail in pairs(self.codMails) do
        if codMail.complete then
            return mailIdString,codMail
        end
    end
end

function addon:GetInboxState()
    if IsInGamepadPreferredMode() then
        return GAMEPAD_MAIL_INBOX_FRAGMENT.state
    else
        return MAIL_INBOX_SCENE.state
    end
end

function addon:GetSelectedData()
    return IsInGamepadPreferredMode() and MAIL_MANAGER_GAMEPAD.inbox:GetActiveMailData() 
          or MAIL_INBOX.selectedData 
end

--[[ Returns a sorted list of mail data for the current inbox, whether keyboard 
     or gamepad. The second output parameter is the name of the mailData field 
     for items in the returned list. ]]
function addon.GetMailData()
    if IsInGamepadPreferredMode() then 
        return MAIL_MANAGER_GAMEPAD.inbox.mailList.dataList, "dataSource"
    else
        return ZO_MailInboxList.data, "data"
    end
end

function addon.GetMailDataById(mailId)
    if IsInGamepadPreferredMode() then 
        return MAIL_MANAGER_GAMEPAD.inbox.mailDataById[zo_getSafeId64Key(mailId)]
    else
        return MAIL_INBOX:GetMailData(mailId)
    end
end

--[[ Returns a safe string representation of the given mail ID. Useful as an 
     associative array key for lookups. ]]
function addon.GetMailIdString(mailId)
    local mailIdType = type(mailId)
    if mailIdType == "string" then 
        return mailId 
    elseif mailIdType == "number" then 
        return zo_getSafeId64Key(mailId) 
    else return 
        tostring(mailId) 
    end
end

--[[ True if Postmaster is doing any operations on the inbox. ]]
function addon:IsBusy()
    return self.taking or self.takingAll or self.deleting or self.returning
end

function addon:IsInboxShowing()
    if IsInGamepadPreferredMode() then
        return SCENE_MANAGER:IsShowing("mailManagerGamepad") 
               and MAIL_MANAGER_GAMEPAD.activeFragment == GAMEPAD_MAIL_INBOX_FRAGMENT
    else
        return SCENE_MANAGER:IsShowing("mailInbox") 
    end
end

--[[ Returns true if the given item link is for a unique item that is already in the player backpack. ]]--
function addon:IsItemUniqueInBackpack(itemLink)
    local isUnique = IsItemLinkUnique(itemLink)
    if isUnique then
        local itemId = GetItemIdFromLink(itemLink)
        for slotIndex, backpackItemId in pairs(self.backpackUniqueItems) do
            if backpackItemId == itemId then
                return true
            end
        end
    end
end

--[[ True if the inbox was closed when a RequestMailDelete() call came in for 
     the given mail ID, and therefore needs to be deleted when the inbox opens
     once more. ]]
function addon:IsMailMarkedForDeletion(mailId)
    if not mailId then return end
    for deleteIndex=1,#self.mailIdsMarkedForDeletion do
        if AreId64sEqual(self.mailIdsMarkedForDeletion[deleteIndex],mailId) then
            return deleteIndex
        end
    end
end

--[[ Checks the given field of a mail message for a given list of
     substrings and returns true if a match is found.
     Note, returns true for "body" requests when the read info isn't yet ready. ]]
function addon:MailFieldMatch(mailData, field, substrings)
    
    -- We need to read mail contents
    if field == "body" then
    
        -- the mail isn't ready. Return true for now to trigger the read request,
        -- and we'll have to match again after it's ready.
        if not mailData.isReadInfoReady then
            return true
        end
        
        -- Match on body text
        local body = zo_strlower(ReadMail(mailData.mailId))
        if addon.StringMatchFirst(body, substrings) then
            return true
        end
    
    -- All other fields are available without a read request first
    else
        local value = zo_strlower(mailData[field])
        if addon.StringMatchFirst(value, substrings) then
            return true
        end
    end
end

--[[ Opens the addon settings panel ]]
function addon.OpenSettingsPanel()
    LibAddonMenu2:OpenToPanel(addon.settingsPanel)
end

--[[ Similar to ZO_PreHook(), except runs the hook function after the existing
     function.  If the hook function returns a value, that value is returned
     instead of the existing function's return value.]]
function addon.PostHook(objectTable, existingFunctionName, hookFunction)
    if(type(objectTable) == "string") then
        hookFunction = existingFunctionName
        existingFunctionName = objectTable
        objectTable = _G
    end
     
    local existingFn = objectTable[existingFunctionName]
    if((existingFn ~= nil) and (type(existingFn) == "function"))
    then    
        local newFn =   function(...)
                            local returnVal = existingFn(...)
                            local hookVal = hookFunction(...)
                            if hookVal then
                                returnVal = hookVal
                            end
                            return returnVal
                        end

        objectTable[existingFunctionName] = newFn
    end
end

--[[ Outputs formatted message to chat window ]]
function addon.Print(input)
    local self = addon
    local lines = addon.SplitLines(input, PM_MAX_CHAT_LENGTH, {"%s","\n","|h|h"})
    for i=1,#lines do
        local output = self.prefix .. lines[i] .. self.suffix
        d(output)
    end
end

--[[ Outputs a verbose summary of all attachments and gold transferred by the 
     current Take or Take All command. ]]
function addon.PrintAttachmentSummary(attachmentData)
    local self = addon
    if not self.settings.verbose or not attachmentData then return end
    
    local summary = ""
    LibLootSummary:SetPrefix(self.prefix)
    LibLootSummary:SetSuffix(self.suffix)
    if LibLootSummary.SetSorted then
        LibLootSummary:SetSorted(true)
    end
    
    -- Add items summary
    for attachIndex=1,#attachmentData.items do
        local attachmentItem = attachmentData.items[attachIndex]
        LibLootSummary:AddItemLink(attachmentItem.link, attachmentItem.count)
    end
    
    -- Add money summary
    local money
    if attachmentData.money > 0 then 
        money = attachmentData.money
    elseif attachmentData.cod > 0 then 
        money = -attachmentData.cod 
    end
    if money then
        LibLootSummary:AddCurrency(CURT_MONEY, money)
    end
    
    LibLootSummary:Print()
end

--[[ Called to delete the current mail after all attachments are taken and all 
     C.O.D. money has been removed from the player's inventory.  ]]
function addon:RequestMailDelete(mailId)
    local mailIdString = self.GetMailIdString(mailId)
    
    -- If the we haven't received confirmation that the server received the
    -- payment for a C.O.D. mail, exit without deleting the mail. 
    -- This method will be called again from Event_MailSendSuccess(), at which
    -- time it should proceed with the delete because the mail id string is
    -- removed from self.codMails.
    local codMail = self.codMails[self.GetMailIdString(mailId)]
    if codMail then
        codMail.complete = true
        return
    end
    
    -- Print summary if verbose setting is on. 
    -- Do this here, immediately after all attachments are collected and C.O.D. are paid, 
    -- Don't wait until the mail removed event, because it may or may not go 
    -- through if the user closes the inbox.
    self.PrintAttachmentSummary(self.attachmentData[mailIdString])
    
    -- Clean up tracking arrays
    self.awaitingAttachments[mailIdString] = nil
    
    local attachmentData = self.attachmentData[mailIdString]
    self.attachmentData[mailIdString] = nil
    
    local mailData = self.GetMailDataById(mailId)
    if not IsInGamepadPreferredMode() then
        if (mailData.attachedMoney and mailData.attachedMoney > 0) or (mailData.numAttachments and mailData.numAttachments > 0) then
            self.Debug("Cannot delete mail id "..mailIdString.." because it is not empty")
            self.mailIdsFailedDeletion[mailIdString] = true
            self.Event_MailRemoved(nil, mailId)
            return
        end
    end
    
    
    -- Check that the current type of mail should be deleted
    if self.takingAll then
        if not CanTakeAllDelete(mailData, attachmentData) then
            self.Debug("Not deleting mail id "..mailIdString.." because of configured options")
            -- Skip actual mail removal and go directly to the postprocessing logic
            self.mailIdsFailedDeletion[mailIdString] = true
            self.Event_MailRemoved(nil, mailId)
            return
        end
    end
    
    
    -- Mark mail for deletion
    self.Debug("Marking mail id " .. mailIdString .. " for deletion")
    table.insert(self.mailIdsMarkedForDeletion, mailId)
    
    -- If inbox is open...
    if self.IsInboxShowing() then
        -- If all attachments are gone, remove the message
        self.Debug("Deleting " .. mailIdString)
        
        MailDelete(mailId)
        
    -- Inbox is no longer open, so delete events won't be raised
    else
        if not AreId64sEqual(self.mailIdLastOpened, mailId) then
            self.Debug("Marking mail id " .. mailIdString .. " to be opened when inbox does")
            self.requestMailId = mailId
            MAIL_INBOX.mailId = nil
            if MAIL_MANAGER_GAMEPAD.inbox.mailList and MAIL_MANAGER_GAMEPAD.inbox.mailList.enabled then
                local oldTargetSelectedIndex = MAIL_MANAGER_GAMEPAD.inbox.mailList.targetSelectedIndex
                if oldTargetSelectedIndex then
                    MAIL_MANAGER_GAMEPAD.inbox.mailList:SetSelectedIndexWithoutAnimation(nil)
                end
            end
        end
    end
end

--[[ Sets state variables back to defaults and ensures a consistent inbox state ]]
function addon:Reset()
    self.Debug("Reset")
    self.taking = false
    self.takingAll = false
    self.mailIdsFailedDeletion = {}
    if IsInGamepadPreferredMode() then
        MAIL_MANAGER_GAMEPAD.inbox.mailList.autoSelect = true
    else
        ZO_MailInboxList.autoSelect = true
    end
    -- Unwire timeout callbacks
    EVENT_MANAGER:UnregisterForUpdate(self.name .. "Delete")
    EVENT_MANAGER:UnregisterForUpdate(self.name .. "Read")
    EVENT_MANAGER:UnregisterForUpdate(self.name .. "Take")
    self.UpdateKeybindStrip()
    
    if not IsInGamepadPreferredMode() and MAIL_INBOX.mailId then
        local currentMailData = ZO_MailInboxList.selectedData
        if not currentMailData then
            self.Debug("Current mail data is nil. Setting MAIL_INBOX.mailId=nil")
            MAIL_INBOX.mailId = nil
            MAIL_INBOX.selectedData = nil
            ZO_ScrollList_AutoSelectData(ZO_MailInboxList)
        elseif not MAIL_INBOX.selectedData then
            MAIL_INBOX.mailId = currentMailData.mailId
            MAIL_INBOX.selectedData = currentMailData
        end
    end
end

--[[ Generates an array of lines all less than the given maximum string length,
     optionally using an array of word boundary strings for pretty wrapping.
     If a line has no word boundaries, or if no boundaries were specified, then
     each line will just be split at the maximum string length. ]]
function addon.SplitLines(text, maxStringLength, wordBoundaries)
    wordBoundaries = wordBoundaries or {}
    local lines = {}
    local index = 1
    local textMax = string.len(text) + 1
    while textMax > index do
        local splitAt
        if index + maxStringLength > textMax then
            splitAt = textMax - index
        else
            local substring = string.sub(text, index, index + maxStringLength - 1)
            for _,delimiter in ipairs(wordBoundaries) do
                local pattern = ".*("..delimiter..")"
                local _,matchIndex = string.find(substring, pattern)
                if matchIndex and (splitAt == nil or matchIndex > splitAt) then
                    splitAt = matchIndex
                end
            end
            splitAt = splitAt or maxStringLength
        end
        local line = string.sub(text, index, index + splitAt - 1 )
        table.insert(lines, line)
        index = index + splitAt 
    end
    return lines
end

--[[ Checks the given string for a given list of
     substrings and returns the start and end indexes if a match is found. ]]
function addon.StringMatchFirst(s, substrings)
    assert(type(s) == "string", "s parameter must be a string")
    if s == "" then return end
    for i=1,#substrings do
        local sub = substrings[i]
        if sub ~= "" then
            local matchStart, matchEnd = s:find(sub, 1, true)
            if matchStart then
                return matchStart, matchEnd
            end
        end
    end
end

--[[ Checks the given string for a given list of
     prefixes and returns the start and end indexes if a match is found. ]]
function addon.StringMatchFirstPrefix(s, prefixes)
    assert(type(s) == "string", "s parameter must be a string")
    if s == "" then return end
    local sLen = s:len()
    for i=1,#prefixes do
        local prefix = prefixes[i]
        if prefix ~= "" then
            local pLen = prefix:len()
            if sLen == pLen then
                if s == prefix then
                    return 1, pLen
                end
            elseif sLen > pLen then
                prefix = prefix .. GetString(SI_PM_WORD_SEPARATOR)
                if prefix:len() > pLen then
                    pLen = prefix:len()
                    if sLen == pLen then
                        if s == prefix then
                            return 1, pLen
                        end
                    end
                end
                if sLen > pLen then
                    if s:sub(1, pLen) == prefix then
                        return 1, pLen
                    end
                end
            end
        end
    end
end


--[[ True if the given mail can be taken according to the given settings ]]
local function CanTakeShared(mailData, settings, debug)

    local self = addon
    
    if not mailData or not mailData.mailId or type(mailData.mailId) ~= "number" then 
        return false 
    end
    
    local mailIdString = self.GetMailIdString(mailData.mailId)
    if self.mailIdsFailedDeletion[mailIdString] == true then
        return false
    end
    
    -- Item was meant to be deleted, but the inbox closed, so include it in 
    -- the take all list
    if self:IsMailMarkedForDeletion(mailData.mailId) then
        return true
    
    -- Handle C.O.D. mail
    elseif mailData.codAmount and mailData.codAmount > 0 then
    
        -- Skip C.O.D. mails, if so configured
        if not settings.codTake then return false
        
        -- Enforce C.O.D. absolute gold limit
        elseif settings.codGoldLimit > 0 and mailData.codAmount > settings.codGoldLimit then return false
        
        -- Skip C.O.D. mails that we don't have enough money to pay for
        elseif mailData.codAmount > GetCurrentMoney() then return false 
        
        else return true end
    end
    
    local fromSystem = (mailData.fromCS or mailData.fromSystem)
    local hasAttachments = (mailData.attachedMoney and mailData.attachedMoney > 0) or (mailData.numAttachments and mailData.numAttachments > 0)
    if hasAttachments then
        
        -- Special handling for hireling mail, since we know even without opening it that
        -- all the attachments can potentially go straight to the craft bag
        local subjectField = "subject"
        local isHirelingMail = fromSystem and self:MailFieldMatch(mailData, subjectField, systemEmailSubjects["craft"])
        local freeSlots = GetNumBagFreeSlots(BAG_BACKPACK)
        local attachmentsToCraftBag = isHirelingMail and HasCraftBagAccess() and GetSetting(SETTING_TYPE_LOOT, LOOT_SETTING_AUTO_ADD_TO_CRAFT_BAG) == "1" and freeSlots > 0
        
        -- Check to make sure there are enough slots available in the backpack
        -- to contain all attachments.  This logic is overly simplistic, since 
        -- theoretically, stacking and craft bags could free up slots. But 
        -- reproducing that business logic here sounds hard, so I gave up.
        if mailData.numAttachments and mailData.numAttachments > 0 
           and (freeSlots - mailData.numAttachments) < settings.reservedSlots
           and not attachmentsToCraftBag
        then 
            return false 
        end
        
        if fromSystem then 
            if settings.systemAttached then
                
                if isHirelingMail then
                    return settings.systemHireling
                
                elseif self:MailFieldMatch(mailData, subjectField, systemEmailSubjects["guildStore"]) then
                    return settings.systemGuildStore
                    
                elseif self:MailFieldMatch(mailData, subjectField, systemEmailSubjects["pvp"])
                       or self:MailFieldMatch(mailData, "senderDisplayName", systemEmailSenders["pvp"])
                then
                    return settings.systemPvp
                
                elseif self:MailFieldMatch(mailData, "senderDisplayName", systemEmailSenders["undaunted"]) then
                    return settings.systemUndaunted
                    
                else 
                    return settings.systemOther
                end
                    
            else
                return false
            end
        elseif mailData.returned then
            return settings.playerReturned 
        else
            return settings.playerAttached 
        end
    else
        if fromSystem then 
            return settings.systemDeleteEmpty
        else 
            return settings.playerDeleteEmpty 
        end
    end
end


--[[ True if the given mail can be taken by Take operations according
     to current options panel criteria. ]]
function addon:QuickTakeCanTake(mailData)
    return CanTakeShared(mailData, {
        ["codTake"]           = self.settings.quickTakeCodTake,
        ["codGoldLimit"]      = self.settings.quickTakeCodGoldLimit,
        ["reservedSlots"]     = 0,
        ["systemAttached"]    = self.settings.quickTakeSystemAttached,
        ["systemHireling"]    = self.settings.quickTakeSystemHireling,
        ["systemGuildStore"]  = self.settings.quickTakeSystemGuildStore,
        ["systemPvp"]         = self.settings.quickTakeSystemPvp,
        ["systemUndaunted"]   = self.settings.quickTakeSystemUndaunted,
        ["systemOther"]       = self.settings.quickTakeSystemOther,
        ["playerReturned"]    = self.settings.quickTakePlayerReturned,
        ["playerAttached"]    = self.settings.quickTakePlayerAttached,
        ["systemDeleteEmpty"] = true,
        ["playerDeleteEmpty"] = true,
    })
end

function addon:TakeAllCanDelete(mailData, debug)
    
    if not mailData or not mailData.mailId or type(mailData.mailId) ~= "number" then 
        self.Debug("Cannot take mail with empty mail id.", debug)
        return false 
    end
    
    local mailIdString = self.GetMailIdString(mailData.mailId)
    if self.mailIdsFailedDeletion[mailIdString] == true then 
        self.Debug("Cannot delete mail id " .. mailIdString .. " because it already failed deletion", debug)
        return false
    end
    
    -- Item was meant to be deleted, but the inbox closed, so include it in 
    -- the take all list
    if self:IsMailMarkedForDeletion(mailData.mailId) then
        return true
    end
    
    local deleteSettings = {
        cod              = self.settings.takeAllCodDelete,
        playerEmpty      = self.settings.takeAllPlayerDeleteEmpty,
        playerAttached   = self.settings.takeAllPlayerAttachedDelete,
        playerReturned   = self.settings.takeAllPlayerReturnedDelete,
        systemEmpty      = self.settings.takeAllSystemDeleteEmpty,
        systemAttached   = self.settings.takeAllSystemAttachedDelete,
        systemGuildStore = self.settings.takeAllSystemGuildStoreDelete,
        systemHireling   = self.settings.takeAllSystemHirelingDelete,
        systemOther      = self.settings.takeAllSystemOtherDelete,
        systemPvp        = self.settings.takeAllSystemPvpDelete,
        systemUndaunted  = self.settings.takeAllSystemUndauntedDelete,
    }
    
    -- Handle C.O.D. mail
    if mailData.codAmount and mailData.codAmount > 0 then
        if not deleteSettings.cod then
            self.Debug("Cannot delete COD mail id " .. mailIdString, debug)
        end
        return deleteSettings.cod
    end
    
    local fromSystem = (mailData.fromCS or mailData.fromSystem)
    local hasAttachments = (mailData.attachedMoney and mailData.attachedMoney > 0) or (mailData.numAttachments and mailData.numAttachments > 0)
    if hasAttachments then
        
        -- Special handling for hireling mail, since we know even without opening it that
        -- all the attachments can potentially go straight to the craft bag
        local subjectField = "subject"
        local isHirelingMail = fromSystem and self:MailFieldMatch(mailData, subjectField, systemEmailSubjects["craft"])
        
        if fromSystem then 
            if deleteSettings.systemAttached then
                
                if isHirelingMail then
                    if not deleteSettings.systemHireling then
                        self.Debug("Cannot delete hireling mail id " .. mailIdString, debug)
                    end
                    return deleteSettings.systemHireling
                
                elseif self:MailFieldMatch(mailData, subjectField, systemEmailSubjects["guildStore"]) then
                    if not deleteSettings.systemGuildStore then
                        self.Debug("Cannot delete guild store mail id " .. mailIdString, debug)
                    end
                    return deleteSettings.systemGuildStore
                    
                elseif self:MailFieldMatch(mailData, subjectField, systemEmailSubjects["pvp"]) 
                       or self:MailFieldMatch(mailData, "senderDisplayName", systemEmailSenders["pvp"])
                then
                    if not deleteSettings.systemPvp then
                        self.Debug("Cannot delete PvP rewards mail id " .. mailIdString, debug)
                    end
                    return deleteSettings.systemPvp
                
                elseif self:MailFieldMatch(mailData, "senderDisplayName", systemEmailSenders["undaunted"]) then
                    if not deleteSettings.systemUndaunted then
                        self.Debug("Cannot delete Undaunted rewards mail id " .. mailIdString, debug)
                    end
                    return deleteSettings.systemUndaunted
                    
                else 
                    if not deleteSettings.systemOther then
                        self.Debug("Cannot delete uncategorized system mail id " .. mailIdString, debug)
                    end
                    return deleteSettings.systemOther
                end
                    
            else
                if not deleteSettings.systemAttached then
                    self.Debug("Cannot delete system mail with attachments id " .. mailIdString, debug)
                end
                return false
            end
        elseif mailData.returned then
                if not deleteSettings.playerReturned then
                    self.Debug("Cannot delete returned mail id " .. mailIdString, debug)
                end
            return deleteSettings.playerReturned 
        else
            if not deleteSettings.playerAttached then
                self.Debug("Cannot delete player mail with attachments id " .. mailIdString, debug)
            end
            return deleteSettings.playerAttached 
        end
    else
        if fromSystem then
            if not deleteSettings.systemEmpty then
                self.Debug("Cannot delete empty system mail id " .. mailIdString, debug)
            end
            return deleteSettings.systemEmpty
        else 
            if not deleteSettings.playerEmpty then
                self.Debug("Cannot delete empty player mail id " .. mailIdString, debug)
            end
            return deleteSettings.playerEmpty 
        end
    end
end

--[[ True if the given mail can be taken by Take All operations according
     to current options panel criteria. ]]
function addon:TakeAllCanTake(mailData, debug)
    return CanTakeShared(mailData, {
        ["codTake"]           = self.settings.takeAllCodTake,
        ["codGoldLimit"]      = self.settings.takeAllCodGoldLimit,
        ["reservedSlots"]     = self.settings.reservedSlots,
        ["systemAttached"]    = self.settings.takeAllSystemAttached,
        ["systemHireling"]    = self.settings.takeAllSystemHireling,
        ["systemGuildStore"]  = self.settings.takeAllSystemGuildStore,
        ["systemPvp"]         = self.settings.takeAllSystemPvp,
        ["systemUndaunted"]   = self.settings.takeAllSystemUndaunted,
        ["systemOther"]       = self.settings.takeAllSystemOther,
        ["playerReturned"]    = self.settings.takeAllPlayerReturned,
        ["playerAttached"]    = self.settings.takeAllPlayerAttached,
        ["systemDeleteEmpty"] = self.settings.takeAllSystemDeleteEmpty,
        ["playerDeleteEmpty"] = self.settings.takeAllPlayerDeleteEmpty,
    },
    debug)
end

--[[ True if the currently-selected mail can be taken by Take All operations 
     according to current options panel criteria. ]]
function addon:TakeAllCanTakeSelectedMail()
    
    local selectedData = self:GetSelectedData()
    if selectedData and self:TakeAllCanTake(selectedData) then 
        return true 
    end
end

--[[ Gets the next highest-priority mail data instance that Take All can take ]]
function addon:TakeAllGetNext()
    local data, mailDataIndex = self.GetMailData()
    for entryIndex, entry in pairs(data) do
        local mailData = entry[mailDataIndex]
        if self:TakeAllCanTake(mailData) then
            return mailData, entryIndex
        end
    end
end

--[[ Selects the next highest-priority mail data instance that Take All can take ]]
function addon:TakeAllSelectNext()
    -- Don't need to get anything. The current selection already has attachments.
    if self:TakeAllCanTakeSelectedMail() then return true end
    
    local nextMailData = MailRead()
    if nextMailData then
        return true
    end
end

--[[ Takes attachments from the selected (readable) mail if they exist, or 
     deletes the mail if it has no attachments. ]]
function addon:TakeOrDeleteSelected()
    if self:TryTakeAllCodMail() then return end
    local mailData = self:GetSelectedData()
    local hasAttachments = (mailData.attachedMoney and mailData.attachedMoney) > 0 
      or (mailData.numAttachments and mailData.numAttachments > 0)
    if hasAttachments then
        self.taking = true
        local keybinds = self:GetOriginalKeybinds()
        keybinds.take.callback()
    else
        -- If all attachments are gone, remove the message
        self.Debug("Deleting "..tostring(mailData.mailId))
        
        -- Delete the mail
        self:RequestMailDelete(mailData.mailId)
    end
end

--[[ Scans the inbox for any player messages starting with RTS, BOUNCE or RETURN
     in the subject, and automatically returns them to sender, if so configured ]]
function addon:TryAutoReturnMail()
    if not self.settings.bounce or not self.inboxUpdated or self:IsBusy() then
        return
    end
    
    self.returning = true
    local data, mailDataIndex = self.GetMailData()
    for _,entry in pairs(data) do
        local mailData = entry[mailDataIndex]
        if mailData and mailData.mailId and not mailData.fromCS 
           and not mailData.fromSystem and mailData.codAmount == 0 
           and (mailData.numAttachments > 0 or mailData.attachedMoney > 0)
           and not mailData.returned
           and addon.StringMatchFirstPrefix(zo_strupper(mailData.subject), PM_BOUNCE_MAIL_PREFIXES) 
        then
            ReturnMail(mailData.mailId)
            if self.settings.verbose then
                self.Print(zo_strformat(GetString(SI_PM_BOUNCE_MESSAGE), mailData.senderDisplayName))
            end
        end
    end
    self.inboxUpdated = false
    self.returning = false
end

--[[ Called when the inbox opens to automatically delete any mail that finished
     a Take or Take All operation after the inbox was closed. ]]
function addon:TryDeleteMarkedMail(mailId)
    local deleteIndex = self:IsMailMarkedForDeletion(mailId)
    if not deleteIndex then return end
    -- Resume the Take operation. will be cleared when the mail removed event handler fires.
    self.taking = true 
    self.Debug("deleting mail id " .. self.GetMailIdString(mailId))
    self:RequestMailDelete(mailId)
    self.UpdateKeybindStrip()
    return deleteIndex
end

--[[ Bypasses the original "Take attachments" logic for C.O.D. mail during a
     Take All operation. ]]
function addon:TryTakeAllCodMail()
    if not self.settings.takeAllCodTake then return end
    local mailData = self:GetSelectedData()
    if mailData.codAmount and mailData.codAmount > 0 then
        self.taking = true
        MAIL_INBOX.pendingAcceptCOD = true
        ZO_MailInboxShared_TakeAll(mailData.mailId)
        MAIL_INBOX.pendingAcceptCOD = false
        return true
    end
end

function addon.UpdateKeybindStrip()
    if IsInGamepadPreferredMode() then
        KEYBIND_STRIP:UpdateKeybindButtonGroup(MAIL_MANAGER_GAMEPAD.inbox.mainKeybindDescriptor)
    else
        KEYBIND_STRIP:UpdateKeybindButtonGroup(MAIL_INBOX.selectionKeybindStripDescriptor)
    end
end




--[[ 
    ===================================
                CALLBACKS
    ===================================
  ]]
  
--[[ Wire up all callback handlers ]]
function addon:CallbackSetup()
    CALLBACK_MANAGER:RegisterCallback("BackpackFullUpdate", self.Callback_BackpackFullUpdate)
end

--[[ Raised whenever the backpack inventory is populated. ]]
function addon.Callback_BackpackFullUpdate()
    local self = addon
    self:DiscoverUniqueItemsInBackpack()
end





--[[ 
    ===================================
               SERVER EVENTS 
    ===================================
  ]]

function addon:EventSetup()
    EVENT_MANAGER:RegisterForEvent(self.name, EVENT_INVENTORY_IS_FULL, self.Event_InventoryIsFull)
    EVENT_MANAGER:RegisterForEvent(self.name, EVENT_INVENTORY_SINGLE_SLOT_UPDATE, self.Event_InventorySingleSlotUpdate)
    EVENT_MANAGER:RegisterForEvent(self.name, EVENT_MAIL_INBOX_UPDATE, self.Event_MailInboxUpdate)
    EVENT_MANAGER:RegisterForEvent(self.name, EVENT_MAIL_READABLE,     self.Event_MailReadable)
    EVENT_MANAGER:RegisterForEvent(self.name, EVENT_MAIL_REMOVED,      self.Event_MailRemoved)
    EVENT_MANAGER:RegisterForEvent(self.name, EVENT_MAIL_SEND_SUCCESS, self.Event_MailSendSuccess)
    EVENT_MANAGER:RegisterForEvent(self.name, EVENT_MAIL_TAKE_ATTACHED_ITEM_SUCCESS, 
        self.Event_MailTakeAttachedItemSuccess)
    EVENT_MANAGER:RegisterForEvent(self.name, EVENT_MAIL_TAKE_ATTACHED_MONEY_SUCCESS,  
        self.Event_MailTakeAttachedMoneySuccess)
    EVENT_MANAGER:RegisterForEvent(self.name, EVENT_MONEY_UPDATE,      self.Event_MoneyUpdate)
    
    -- Fix for Wykkyd Mailbox keybind conflicts
    if type(WYK_MailBox) == "table" then
        WYK_MailBox:UnregisterEvent(EVENT_MAIL_READABLE)
    end
end

--[[ Raised when an attempted item transfer to the backpack fails due to not 
     enough slots being available.  When this happens, we should abort any 
     pending operations and reset controller state. ]]
function addon.Event_InventoryIsFull(eventCode, numSlotsRequested, numSlotsFree)
    local self = addon
    self:Reset()
    self.UpdateKeybindStrip()
end

--[[ Raised when a player inventory slot is updated. ]]
function addon.Event_InventorySingleSlotUpdate(eventCode, bagId, slotIndex, isNewItem, itemSoundCategory, inventoryUpdateReason, stackCountChange)
    if bagId ~= BAG_BACKPACK then
        return
    end
    local self = addon
    self:DiscoverUniqueBackpackItem(slotIndex)
end

--[[ Raised whenever new mail arrives.  When this happens, mark that we need to 
     check for auto-return mail. ]]
function addon.Event_MailInboxUpdate(eventCode)
    local self = addon
    if not self.settings.bounce then return end
    
    self.Debug("Setting self.inboxUpdated to true")
    self.inboxUpdated = true
end

--[[ Raised in response to a successful RequestReadMail() call. Indicates that
     the mail is now open and ready for actions. It is necessary for this event 
     to fire before most actions on a mail message will be allowed by the server.
     Here, we trigger or cancel the next Take All loop,
     as well as automatically delete any empty messages marked for removal in the
     self.mailIdsMarkedForDeletion array. ]]
function addon.Event_MailReadable(eventCode, mailId)
    local self = addon
    self.Debug("Event_MailReadable(" .. self.GetMailIdString(mailId) .. ")")
    EVENT_MANAGER:UnregisterForUpdate(self.name .. "Read")
        
    -- If taking all, then go ahead and start the next Take loop, since the
    -- mail and attachments are readable now.
    if self.takingAll then 
        self:TakeOrDeleteSelected()
        
    -- If a mail is selected that was previously marked for deletion but never
    -- finished, automatically delete it.
    else
        local mailData = self:GetSelectedData()
        if not self:TryDeleteMarkedMail(mailData.mailId) then
            -- Otherwise, try auto-returning any new mail that's arrived
            self:TryAutoReturnMail()
        end
    end
end

--[[ Raised in response to a successful DeleteMail() call. Used to trigger 
     opening the next mail with attachments for Take All, or reset state 
     variables and refresh the keybind strip for Take. ]]
function addon.Event_MailRemoved(eventCode, mailId)
    local self = addon
    if not self.taking then return end
    local deleteIndex = self:IsMailMarkedForDeletion(mailId)
    table.remove(self.mailIdsMarkedForDeletion, deleteIndex)
    
    if eventCode then
        
        -- Unwire timeout callback
        EVENT_MANAGER:UnregisterForUpdate(self.name .. "Delete")
        PlaySound(SOUNDS.MAIL_ITEM_DELETED)
        self.Debug("deleted mail id " .. self.GetMailIdString(mailId))
    end
    
    -- In the middle of auto-return
    if self.returning then return end
    
    local isInboxOpen = self.IsInboxShowing()
    
    -- For non-canceled take all requests, select the next mail for taking.
    -- It will be taken automatically by Event_MailReadable() once the 
    -- EVENT_MAIL_READABLE event comes back from the server.
    if isInboxOpen and self.takingAll then
        self.Debug("Selecting next mail with attachments")
        if self:TakeAllSelectNext() then return end
    end
    
    -- This was either a normal take, or there are no more valid mails
    -- for take all, or an abort was requested, so cancel out.
    self:Reset()
    
    -- If the inbox is still open when the delete comes through, refresh the
    -- keybind strip.
    if isInboxOpen then
        self.UpdateKeybindStrip()
        
    -- If the inbox was closed when the actual delete came through from the
    -- server, it leaves the inbox list in an inconsistent (dirty) state.
    else
        self.Debug("Clearing selected mail")
        self:ClearSelectedMail()
        
        -- if the inbox is open, try auto returning mail now
        self:TryAutoReturnMail()
    end
end

--[[ Raised after a sent mail message is received by the server. We only care
     about this event because C.O.D. mail cannot be deleted until it is raised. ]]
function addon.Event_MailSendSuccess(eventCode) 
    local self = addon
    if not self.taking then return end
    self.Debug("Event_MailSendSuccess()")
    local mailIdString,codMail = self:GetFirstCompleteCodMail()
    if not codMail then return end
    self.codMails[mailIdString] = nil
    -- Now that we've seen that the gold is sent, we can delete COD mail
    self:RequestMailDelete(codMail.mailId)
end

--[[ Raised when attached items are all received into inventory from a mail.
     Used to automatically trigger mail deletion. ]]
function addon.Event_MailTakeAttachedItemSuccess(eventCode, mailId)
    local self = addon
    if not self.taking then return end
    local mailIdString = self.GetMailIdString(mailId)
    self.Debug("attached items taken " .. mailIdString)
    local waitingForMoney = table.remove(self.awaitingAttachments[mailIdString])
    if waitingForMoney then 
        self.Debug("still waiting for money or COD. exiting.")
    else
        -- Stop take attachments retries
        EVENT_MANAGER:UnregisterForUpdate(self.name .. "Take")
        self:RequestMailDelete(mailId)
    end
end

--[[ Raised when attached gold is all received into inventory from a mail.
     Used to automatically trigger mail deletion. ]]
function addon.Event_MailTakeAttachedMoneySuccess(eventCode, mailId)
    local self = addon
    if not self.taking then return end
    local mailIdString = self.GetMailIdString(mailId)
    self.Debug("attached money taken " .. mailIdString)
    local waitingForItems = table.remove(self.awaitingAttachments[mailIdString])
    if waitingForItems then 
        self.Debug("still waiting for items. exiting.")
    else
        -- Stop take attachments retries
        EVENT_MANAGER:UnregisterForUpdate(self.name .. "Take")
        self:RequestMailDelete(mailId)
    end
end

--[[ Raised whenever gold enters or leaves the player's inventory.  We only care
     about money leaving inventory due to a mail event, indicating a C.O.D. payment.
     Used to automatically trigger mail deletion. ]]
function addon.Event_MoneyUpdate(eventCode, newMoney, oldMoney, reason)
    local self = addon
    if not self.taking then return end
    self.Debug("Event_MoneyUpdate("..tostring(eventCode)..","..tostring(newMoney)..","..tostring(oldMoney)..","..tostring(reason)..")")
    if reason ~= CURRENCY_CHANGE_REASON_MAIL or oldMoney <= newMoney then 
        self.Debug("not mail reason or money change not negative")
        return
    end
   
    -- Unfortunately, since this isn't a mail-specific event 
    -- (thanks ZOS for not providing one), it doesn't have a mailId parameter, 
    -- so we kind of kludge it by using C.O.D. amount and assuming first-in-first-out
    local goldChanged = oldMoney - newMoney
    local mailIdString,codMail = self:GetCodMailByGoldChangeAmount(goldChanged)
    
    -- This gold removal event is unrelated to C.O.D. mail. Exit.
    if not codMail then
        self.Debug("did not find any mail items with a COD amount of "..tostring(goldChanged))
        return
    end
    
    -- Stop take attachments retries
    EVENT_MANAGER:UnregisterForUpdate(self.name .. "Take")
    
    -- This is a C.O.D. payment, so trigger a mail delete if all items have been
    -- removed from the mail already.
    self.Debug("COD amount of "..tostring(goldChanged).." paid "..mailIdString)
    local waitingForItems = table.remove(self.awaitingAttachments[mailIdString])
    if waitingForItems then 
        self.Debug("still waiting for items. exiting.")
    else
        self:RequestMailDelete(codMail.mailId)
    end
end

--[[ 
    ===================================
                 PREHOOKS
    ===================================
  ]]

--[[ Wire up all prehook handlers ]]
function addon:PrehookSetup()
    ZO_PreHook(KEYBIND_STRIP, "SetUpButton", self.Prehook_KeybindStrip_ButtonSetup)
    ZO_PreHook("ZO_MailInboxShared_TakeAll", self.Prehook_MailInboxShared_TakeAll)
    ZO_PreHook("RequestReadMail", self.Prehook_RequestReadMail)
    ZO_PreHook("ZO_ScrollList_SelectData", self.Prehook_ScrollList_SelectData)
    ZO_PreHook("ZO_Dialogs_ShowDialog", self.Prehook_Dialogs_ShowDialog)
    ZO_PreHook("ZO_Dialogs_ShowGamepadDialog", self.Prehook_Dialogs_ShowGamepadDialog)
    ZO_PreHook(MAIL_MANAGER_GAMEPAD.inbox, "InitializeEvents", self.KeybindSetupGamepad)
end


--[[ Suppress mail delete and/or return to sender dialog in keyboard mode, if configured ]]
function addon.Prehook_Dialogs_ShowDialog(name, data, textParams, isGamepad)
    local self = addon
    if self.settings.deleteDialogSuppress and name == "DELETE_MAIL" then 
        MAIL_INBOX:ConfirmDelete(MAIL_INBOX.mailId)
        return true
    elseif addon.settings.returnDialogSuppress and name == "MAIL_RETURN_ATTACHMENTS" then
        ReturnMail(MAIL_INBOX.mailId)
        return true
    end
end

--[[ Suppress mail delete and/or return to sender dialog in gamepad mode, if configured ]]
function addon.Prehook_Dialogs_ShowGamepadDialog(name, data, textParams)
    local self = addon
    if self.settings.deleteDialogSuppress and name == "DELETE_MAIL" then 
        MAIL_MANAGER_GAMEPAD.inbox:Delete()
        return true
    elseif addon.settings.returnDialogSuppress and name == "MAIL_RETURN_ATTACHMENTS" then
        MAIL_MANAGER_GAMEPAD.inbox:ReturnToSender()
        return true
    end
end

--[[ Keybind callback and visible functions do not always reliably pass on data
     about their related descriptor.  Wire up callback and visible events on
     the button to save the current button instance to addon.keybindButtonForCallback
     and addon.keybindButtonForVisible, respectively.  They can then be used for
     the "Other" keybind callbacks and visible methods that don't know which 
     button they were called from. ]]
function addon.Prehook_KeybindStrip_ButtonSetup(keybindStrip, button)
    local self = addon
    if not self.IsInboxShowing() then return end
    local buttonDescriptor = button.keybindButtonDescriptor
    if not buttonDescriptor or not buttonDescriptor.callback or type(buttonDescriptor.callback) ~= "function" then return end
    local callback = buttonDescriptor.callback
    buttonDescriptor.callback = function(...)
        self.keybindButtonForCallback = button
        callback(...)
    end
    if not buttonDescriptor.visible or type(buttonDescriptor.visible) ~= "function" then return end
    local visible = buttonDescriptor.visible
    buttonDescriptor.visible = function(...)
        self.keybindButtonForVisible = button
        return visible(...)
    end
end

--[[ Runs before a mail's attachments are taken, recording attachment information
     and initializing controller state variables for the take operation. ]]
function addon.Prehook_MailInboxShared_TakeAll(mailId)
    local self = addon
    if not self.taking then
        return
    end
    local numAttachments, attachedMoney, codAmount = GetMailAttachmentInfo(mailId)
    if codAmount > 0 then
        if self.takingAll then
            if not self.settings.takeAllCodTake then return end
        elseif not MAIL_INBOX.pendingAcceptCOD then return end
    end 
    local mailIdString = self.GetMailIdString(mailId)
    self.Debug("ZO_MailInboxShared_TakeAll(" .. mailIdString .. ")")
    self.awaitingAttachments[mailIdString] = {}
    local attachmentData = { items = {}, money = attachedMoney, cod = codAmount }
    local uniqueAttachmentConflictCount = 0
    for attachIndex=1,numAttachments do
        local _, stack = GetAttachedItemInfo(mailId, attachIndex)
        local attachmentItem = { link = GetAttachedItemLink(mailId, attachIndex), count = stack or 1 }
        if self:IsItemUniqueInBackpack(attachmentItem.link) then
            uniqueAttachmentConflictCount = uniqueAttachmentConflictCount + 1
        else
            table.insert(attachmentData.items, attachmentItem)
        end
    end
    
    if numAttachments > 0 then
    
        -- If all attachments were unique and already in the backpack
        if uniqueAttachmentConflictCount == numAttachments then
            self.Debug("Not taking attachments for " .. mailIdString
                       .." because it contains only unique items that are already in the backpack")
            self.mailIdsFailedDeletion[mailIdString] = true
            self.Event_MailRemoved(nil, mailId)
            return true
        end
        if attachedMoney > 0 or codAmount > 0 then
            table.insert(self.awaitingAttachments[mailIdString], true)
            -- Wire up timeout callback
            TakeTimeout(mailId)
        end
    end
    self.attachmentData[mailIdString] = attachmentData
    if codAmount > 0 then
        self.codMails[mailIdString] = { mailId = mailId, amount = codAmount, complete = false }
    end
end

--[[ Listen for mail read requests when the inbox is closed and deny them.
     The server won't raise the EVENT_MAIL_READABLE event anyways, and it
     will filter out any subsequent requests for the same mail id until after
     a different mailId is requested.  Record the mail id as self.mailIdLastOpened
     so that we can request the mail again immediately when the inbox is opened. ]]
function addon.Prehook_RequestReadMail(mailId)
    local self = addon
    self.Debug("RequestReadMail(" .. self.GetMailIdString(mailId) .. ")")
    self.mailIdLastOpened = mailId
    local inboxState = self:GetInboxState()
    -- Avoid a double read request on inbox open
    local deny = hiddenStates[inboxState]
    if deny then
        self.Debug("Inbox isn't open. Request denied.")
    end
    return deny
end

--[[ Runs before any scroll list selects an item by its data. We listen for inbox
     items that are selected when the inbox is closed, and then remember them 
     in self.requestMailId so that the items can be selected as soon as 
     the inbox opens again. ]]
function addon.Prehook_ScrollList_SelectData(list, data, control, reselectingDuringRebuild)
    if list ~= ZO_MailInboxList and list ~= MAIL_MANAGER_GAMEPAD.inbox.mailList then return end
    local self = addon
    self.Debug("ZO_ScrollList_SelectData("..tostring(list)
        ..", "..tostring(data)..", "..tostring(control)..", "
        ..tostring(reselectingDuringRebuild)..")")
    local inboxState = self:GetInboxState()
    if hiddenStates[inboxState] then
        self.Debug("Clearing inbox mail id")
        -- clear mail id to avoid exceptions during inbox open
        -- it will be reselected by the EVENT_MAIL_READABLE event
        self:ClearSelectedMail()
        -- remember the mail id so that it can be requested on mailbox open
        if data and type(data.mailId) == "number" then 
            self.Debug("Setting inbox requested mail id to "..tostring(data.mailId))
            self.requestMailId = data.mailId 
        end
    end
end



--[[ 
    ===================================
                 POSTHOOKS
    ===================================
  ]]

--[[ Wire up all posthook handlers ]]
function addon:PosthookSetup()
    self.PostHook(MAIL_MANAGER_GAMEPAD.inbox, "RefreshMailList", self.Posthook_InboxScrollList_RefreshData)
    self.PostHook(ZO_MailInboxList, "RefreshData", self.Posthook_InboxScrollList_RefreshData)
end

--[[ Runs after the inbox scroll list's data refreshes, for both gamepad and 
     keyboard mail fragments. Used to trigger automatic mail return. ]]
function addon.Posthook_InboxScrollList_RefreshData(scrollList)
    addon:TryAutoReturnMail()
end