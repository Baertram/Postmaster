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
    
end

function class.TakeAll:Start()
  
end