local addon = Postmaster
local class = addon.classes
local debug = false

class.TakeAll = ZO_CallbackObject:Subclass()

function class.TakeAll:New(...)
    local instance = ZO_CallbackObject.New(self)
    instance:Initialize(...)
    return instance
end
function class.TakeAll:Initialize(name)
    self.name = name or addon.name .. "_TakeAll"
    self.queue = {}
    self.state = "stopped"
end

function class.TakeAll:Cancel()
    self:SetState("stopped")
end

function class.TakeAll:CanDelete(mailData)
    return addon:TakeAllCanDelete(mailData, debug)
end

function class.TakeAll:CanTake(mailData)
    return addon:TakeAllCanTake(mailData, debug)
end

function class.TakeAll:CreateMailTakerDoneCallback()
    return function(mailData, attachmentData)
        if self:HasQueuedMail() then
            self:SetState("stopped")
        else
            self:DelayStart()
        end
    end
end

function class.TakeAll:CreateMailTakerFailedCallback()
    return function(reason, mailData, attachmentData)
        self:OnMailFailed(reason, mailData, attachmentData)
        local doneCallback = self:CreateMailTakerDoneCallback()
        doneCallback()
    end
end

function class.TakeAll:CreateMailTakerRemovedCallback()
    return function(mailData, attachmentData)
        self:OnMailRemoved(mailData, attachmentData)
    end
end

function class.TakeAll:CreateMailTakerTakenCallback()
    return function(mailData, attachmentData)
        self:OnMailTaken(mailData, attachmentData)
    end
end

function class.TakeAll:DelayStart(milliseconds)
    if not milliseconds then
        milliseconds = 40
    end
    EVENT_MANAGER:RegisterForUpdate(self.name .. "_Start", milliseconds, function() self:Start() end)
end

function class.TakeAll:DequeueById(mailId)
    for index, #self.queue do
        if AreId64sEqual(mailId, self.queue[index].mailId) then
            return table.remove(self.queue, index)
        end
    end
end

function class.TakeAll:HasQueuedMail()
    return #self.queue > 0
end

function class.TakeAll:OnMailFailed(reason, mailData, attachmentData)
    self:FireCallbacks("MailFailed", reason, mailData, attachmentData)
end

function class.TakeAll:OnMailRemoved(mailData, attachmentData)
    self:FireCallbacks("MailRemoved", mailData, attachmentData)
end

function class.TakeAll:OnMailTaken(mailData, attachmentData)
    self:FireCallbacks("MailTaken", mailData, attachmentData)
end

function class.TakeAll:OnStateChanged(oldState)
    self:FireCallbacks("StateChanged", oldState, self.state)
end

function class.TakeAll:SetState(state)
    addon.Debug("Setting TakeAll state to " .. tostring(state), debug)
    local oldState = self.state
    self.state = state
    if state == "stopped" and self.mailTaker then
        self.mailTaker:Reset()
        self.mailTaker = nil
    end
    if oldState ~= state then
        self:OnStateChanged(oldState)
    end
end

function class.TakeAll:Start()
    if not self:HasQueuedMail() then
        return
    end
    self:SetState("active")
    local mailData = table.remove(self.queue, 1)
    self.mailTaker = class.MailTaker:New(mailData, self:CanDelete(mailData))
    self.mailTaker:RegisterCallback("Done", self:CreateMailTakerDoneCallback())
    self.mailTaker:RegisterCallback("Failed", self:CreateMailTakerFailedCallback())
    self.mailTaker:RegisterCallback("Removed", self:CreateMailTakerRemovedCallback())
    self.mailTaker:RegisterCallback("Taken", self:CreateMailTakerTakenCallback())
    
    if self:CanTake(mailData) then
        self.mailTaker:Take()
    else
        self.mailTaker:Remove()
    end
end

function class.TakeAll:TryQueue(mailData)
    if not self:CanTake(mailData) and not self:CanDelete(mailData) then
        return false
    end
    table.insert(self.queue, mailData)
    return true
end