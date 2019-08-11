local addon = Postmaster
local class = addon.classes
class.GamepadModule = class.SharedModule:Subclass()
local debug = false
local gamepadKeybindOrder

function class.GamepadModule:New(...)
    local name = addon.name .. "_GamepadModule"
    return class.SharedModule.New(self, name, GAMEPAD_MAIL_INBOX_FRAGMENT)
end

function class.GamepadModule:GetMailList()
    return MAIL_MANAGER_GAMEPAD.inbox.mailList.dataList, "dataSource"
end

function class.GamepadModule:Reply(address, subject)
    MAIL_MANAGER_GAMEPAD.send:EnterOutbox()
    MAIL_MANAGER_GAMEPAD.send.mailView.addressEdit.edit:SetText(address)
    MAIL_MANAGER_GAMEPAD.send.mailView.subjectEdit.edit:SetText(subject)
    MAIL_MANAGER_GAMEPAD.send.mainList:SetSelectedDataByEval(function(data) return data.text == GetString(SI_GAMEPAD_MAIL_BODY_LABEL) end)
end

function class.GamepadModule:SetupKeybinds()
    local inbox = MAIL_MANAGER_GAMEPAD.inbox
    self.keybindWrapper = class.KeybindWrapper:New(
        self.name .. "_KeybindWrapper", 
        inbox, "mainKeybindDescriptor", 
        gamepadKeybindOrder)
    local returnOption = inbox.optionsList.datalist[1]
    
    self.keybindWrapper:SetCustomKeybinds(
        {
            -- Take / Delete
            -- Note: The new keybind is "UI_SHORTCUT_PRIMARY".
            -- The parameter here refers to the original delete keybind,
            -- for lookup purposes
            self:CreateTakeDeleteKeybind("UI_SHORTCUT_SECONDARY"),
            
            -- Take All
            self:CreateTakeAllKeybind("UI_SHORTCUT_QUATERNARY"),

            -- Return to Sender
            {
                keybind = "UI_SHORTCUT_SECONDARY",
                name = returnOption.text,
                callback = returnOption.selectedCallback,
                visible = function() return IsMailReturnable(inbox:GetActiveMailId()) end
            },
            
            -- Reply
            self:CreateReplyKeybind(),
        }
    )
end

-- Local functions and variables
gamepadKeybindOrder = {
    "UI_SHORTCUT_NEGATIVE",
    "UI_SHORTCUT_PRIMARY",
    "UI_SHORTCUT_SECONDARY",
    "UI_SHORTCUT_TERTIARY",
    "UI_SHORTCUT_QUATERNARY",
    "UI_SHORTCUT_RIGHT_STICK",
    "UI_SHORTCUT_LEFT_STICK",
    "UI_SHORTCUT_INPUT_LEFT",
    "UI_SHORTCUT_INPUT_RIGHT",
    "UI_SHORTCUT_REPORT_PLAYER",
    "UI_SHORTCUT_EXIT",
    "UI_SHORTCUT_LEFT_TRIGGER",
    "UI_SHORTCUT_RIGHT_TRIGGER",
    "UI_SHORTCUT_LEFT_SHOULDER",
    "UI_SHORTCUT_RIGHT_SHOULDER",
}