--[[
	Picks objects under a screen position and updates Studio's selection.

	Mirrors Studio's click rules: locked and fully transparent parts are
	skipped, terrain is not selectable, and (optionally) clicking a part inside
	a model selects the whole top-level model.
]]

local Selection = game:GetService("Selection")
local Workspace = game:GetService("Workspace")

local Raycast = require(script.Parent.Parent.Camera.Raycast)

local function isPickable(instance: Instance): boolean
	if instance:IsA("Terrain") then
		return true -- blocks the ray, but is not selectable (handled below)
	end
	if instance:IsA("BasePart") then
		return not instance.Locked and instance.Transparency < 1
	end
	return false
end

local SelectionController = {}
SelectionController.__index = SelectionController

function SelectionController.new(settings)
	local self = setmetatable({}, SelectionController)
	self._settings = settings
	return self
end

function SelectionController:_resolve(part: Instance): Instance
	if not self._settings:Get("selectModels") then
		return part
	end
	local target = part
	local current = part.Parent
	while current and current ~= Workspace do
		if current:IsA("Model") then
			target = current
		end
		current = current.Parent
	end
	return target
end

-- Returns the object a tap at `position` would select, or nil for empty space.
function SelectionController:TargetAt(position: Vector2): Instance?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local result = Raycast.fromScreen(camera, position, isPickable)
	if not result or result.Instance:IsA("Terrain") then
		return nil
	end
	return self:_resolve(result.Instance)
end

-- Replaces the selection with whatever is under `position` (or clears it).
function SelectionController:SelectAt(position: Vector2): Instance?
	local target = self:TargetAt(position)
	Selection:Set(if target then { target } else {})
	return target
end

-- Adds or removes the object under `position`. Returns the object and whether it is now selected.
function SelectionController:ToggleAt(position: Vector2): (Instance?, boolean)
	local target = self:TargetAt(position)
	if not target then
		return nil, false
	end

	local selected = Selection:Get()
	local index = table.find(selected, target)
	if index then
		table.remove(selected, index)
	else
		table.insert(selected, target)
	end
	Selection:Set(selected)
	return target, index == nil
end

function SelectionController:Get(): { Instance }
	return Selection:Get()
end

function SelectionController:Set(instances: { Instance })
	Selection:Set(instances)
end

return SelectionController
