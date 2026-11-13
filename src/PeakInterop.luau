--[[
	Living next to other "Peak" plugins (Optimize Peak's floating dot, ...).

	Peak plugins draw into CoreGui and agree on a tiny convention:

	  * A plugin's ScreenGui carries the attribute `PeakSuite` (its name).
	  * Any GuiObject that should swallow touches carries `PeakBlocksInput = true`.

	Touch Peak marks its window and zoom strip, and leaves touches that start
	on another Peak plugin's blocking UI alone: no camera move, no tap-select.
]]

local CoreGui = game:GetService("CoreGui")

local PeakInterop = {}

PeakInterop.SuiteAttribute = "PeakSuite"
PeakInterop.BlockAttribute = "PeakBlocksInput"

function PeakInterop.registerGui(gui: ScreenGui, name: string)
	gui:SetAttribute(PeakInterop.SuiteAttribute, name)
end

function PeakInterop.blockInput(object: GuiObject)
	object:SetAttribute(PeakInterop.BlockAttribute, true)
end

local function isShown(object: GuiObject): boolean
	local current: Instance? = object
	while current and current:IsA("GuiObject") do
		if not current.Visible then
			return false
		end
		current = current.Parent
	end
	if current and current:IsA("LayerCollector") then
		return current.Enabled
	end
	return current ~= nil
end

local function contains(object: GuiObject, point: Vector2, margin: number): boolean
	local position, size = object.AbsolutePosition, object.AbsoluteSize
	return point.X >= position.X - margin
		and point.X <= position.X + size.X + margin
		and point.Y >= position.Y - margin
		and point.Y <= position.Y + size.Y + margin
end

-- True when `point` lies on a blocking element of a Peak plugin other than `ownGui`.
function PeakInterop.isBlocked(point: Vector2, ownGui: Instance?): boolean
	for _, gui in CoreGui:GetChildren() do
		if gui ~= ownGui and gui:IsA("ScreenGui") and gui.Enabled and gui:GetAttribute(PeakInterop.SuiteAttribute) then
			for _, object in gui:GetDescendants() do
				if
					object:IsA("GuiObject")
					and object:GetAttribute(PeakInterop.BlockAttribute)
					and isShown(object)
					and contains(object, point, 4)
				then
					return true
				end
			end
		end
	end
	return false
end

return PeakInterop
