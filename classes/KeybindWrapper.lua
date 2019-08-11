local addon = Postmaster
local class = addon.classes
local debug = false
local mapByKeybind

class.KeybindWrapper = ZO_Object:Subclass()

function class.KeybindWrapper:New(...)
    local instance = ZO_Object.New(self)
    instance:Initialize(...)
    return instance
end

function class.KeybindWrapper:Initialize(name, target, descriptorName, keybindOrder, customKeybinds)
    self.name = name or addon.name .. "_KeybindWrapper"
    self.target = target
    self.descriptorName = descriptorName
    self.keybindOrder = keybindOrder
    self.originalKeybinds = self.target[self.descriptorName]
    self.originalKeybindMap = mapByKeybind(self.originalKeybinds)
    self:SetCustomKeybinds(customKeybinds)
end

function class.KeybindWrapper:AddKeybindIfNotDefined(keybind, keybindOptions)
    if self:GetOriginalKeybind(keybind) then
        return
    end
    self.customKeybindMap[keybind] = keybindOptions
end

function class.KeybindWrapper:GetCustomKeybind(keybind)
    return self.customKeybindMap[keybind]
end

function class.KeybindWrapper:GetOriginalKeybind(keybind)
    return self.originalKeybindMap[keybind]
end

function class.KeybindWrapper:Refresh()
    KEYBIND_STRIP:UpdateKeybindButtonGroup(self.target[self.descriptorName])
end

function class.KeybindWrapper:SetCustomKeybinds(customKeybinds)
    if customKeybinds then
        self.customKeybindMap = mapByKeybind(customKeybinds)
    end
end

function class.KeybindWrapper:UnwrapKeybinds()
    self.target[self.descriptorName] = self.originalKeybinds
    self:Refresh()
end

function class.KeybindWrapper:WrapKeybinds()
    local descriptor = {
        alignment = self.originalKeybinds.alignment
    }
    for _, keybind in ipairs(self.keybindOrder) do
        local keybindOptions = self:GetCustomKeybind(keybind) or self:GetOriginalKeybind(keybind)
        if keybindOptions then
            table.insert(descriptor, keybindOptions)
        end
    end
    KEYBIND_STRIP:RemoveKeybindButtonGroup(self.target[self.descriptorName])
    self.target[self.descriptorName] = descriptor
    KEYBIND_STRIP:AddKeybindButtonGroup(self.target[self.descriptorName])
    self:Refresh()
end

-- Local functions

function mapByKeybind(keybinds)
    local map = {}
    for _, keybindOptions in ipairs(keybinds) do
        map[keybindOptions.keybind] = keybindOptions
    end
    return map
end