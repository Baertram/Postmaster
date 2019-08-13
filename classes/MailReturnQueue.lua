local addon = Postmaster
local class = addon.classes
local debug = false

class.MailReturnQueue = ZO_CallbackObject:Subclass()

function class.MailReturnQueue:New(...)
    local instance = ZO_CallbackObject.New(self)
    instance:Initialize(...)
    return instance
end
function class.MailReturnQueue:Initialize(name)
    self.name = name or addon.name .. "_MailReturnQueue"
    self.queue = {}
    self.state = "stopped"
end

function class.MailReturnQueue:Cancel()
    self:SetState("stopped")
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

function class.MailReturnQueue:OnStateChanged(oldState)
    self:FireCallbacks("StateChanged", oldState, self.state)
end

function class.MailReturnQueue:SetState(state)
    addon.Debug("Setting MailReturnQueue state to " .. tostring(state), debug)
    local oldState = self.state
    self.state = state
    if oldState ~= state then
        if state == "stopped" then
            -- Unsubscribe from mail removed events
        end
        self:OnStateChanged(oldState)
    end
end

function class.MailReturnQueue:Start()
    if not self:HasQueuedMail() then
        return
    end
    self:SetState("active")
    local mailData = table.remove(self.queue, 1)
    
    -- TODO: Set up mail removed callback
end

function class.MailReturnQueue:TryQueue(mailData)
    if not addon.settings.bounce then
        return
    end
    
    if mailData and mailData.mailId and not mailData.fromCS 
       and not mailData.fromSystem and mailData.codAmount == 0 
       and (mailData.numAttachments > 0 or mailData.attachedMoney > 0)
       and not mailData.returned
       and addon.StringMatchFirstPrefix(zo_strupper(mailData.subject), PM_BOUNCE_MAIL_PREFIXES) 
    then
        table.insert(self.queue, mailData)
        return true
    end
end