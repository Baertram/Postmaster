local addon = Postmaster
local class = addon.classes
class.KeyboardModule = class.SharedModule:Subclass()
local debug = false
local keyboardKeybindOrder

function class.KeyboardModule:New(...)
    local name = addon.name .. "_KeyboardModule"
    return class.SharedModule.New(self, name, MAIL_INBOX_SCENE)
end

function class.KeyboardModule:GetMailList()
    return ZO_MailInboxList.data, "data"
end

function class.KeyboardModule:Reply(address, subject)
    MAIL_SEND:ClearFields()
    MAIL_SEND:SetReply(address, subject)
    SCENE_MANAGER:CallWhen("mailSend", SCENE_SHOWN, function() ZO_MailSendBodyField:TakeFocus() end)
    ZO_MainMenuSceneGroupBar.m_object:SelectDescriptor("mailSend")
end

function class.KeyboardModule:SetupKeybinds()
    self.keybindWrapper = class.KeybindWrapper:New(
        self.name .. "_KeybindWrapper", 
        MAIL_INBOX, "selectionKeybindStripDescriptor", 
        keyboardKeybindOrder)
    
    local returnKeybind = self.keybindWrapper:GetOriginalKeybind("UI_SHORTCUT_SECONDARY")
    
    self.keybindWrapper:SetCustomKeybinds(
        {
            -- Take / Delete
            -- Note: The new keybind is "UI_SHORTCUT_NEGATIVE".
            -- The parameter here refers to the original delete keybind,
            -- for lookup purposes
            self:CreateTakeDeleteKeybind("UI_SHORTCUT_NEGATIVE"),
            
            -- Take All
            self:CreateTakeAllKeybind("UI_SHORTCUT_SECONDARY"),

            -- Cancel / Return to Sender
            self:CreateCancelReturnKeybind("UI_SHORTCUT_NEGATIVE", returnKeybind)
        }
    )
    
    -- Reply
    -- Add it only if it's not already defined by MailR
    self.keybindWrapper:AddKeybindIfNotDefined(self:CreateReplyKeybind())
end

-- Local functions and variables
keyboardKeybindOrder = {
    "UI_SHORTCUT_PRIMARY",
    "UI_SHORTCUT_SECONDARY",
    "UI_SHORTCUT_NEGATIVE",
    "UI_SHORTCUT_TERTIARY",
    "UI_SHORTCUT_QUATERNARY",
    "UI_SHORTCUT_REPORT_PLAYER",
    "UI_SHORTCUT_EXIT",
}