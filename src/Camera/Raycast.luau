--[[
	Raycasting helpers that can skip over unwanted hits (locked or invisible
	parts) instead of stopping at them.
]]

local Workspace = game:GetService("Workspace")

local Raycast = {}

Raycast.MaxDistance = 15000 -- longest ray workspace:Raycast supports
local MAX_SKIPS = 32

-- Casts a ray and returns the first hit accepted by `accept` (or nil).
function Raycast.cast(origin: Vector3, direction: Vector3, accept: (Instance) -> boolean): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local excluded = {}

	for _ = 1, MAX_SKIPS do
		params.FilterDescendantsInstances = excluded
		local result = Workspace:Raycast(origin, direction, params)
		if not result then
			return nil
		end
		if accept(result.Instance) then
			return result
		end
		table.insert(excluded, result.Instance)
	end
	return nil
end

-- Casts from a GUI-space screen position (as reported by InputObject.Position).
function Raycast.fromScreen(camera: Camera, position: Vector2, accept: (Instance) -> boolean): (RaycastResult?, Ray)
	local ray = camera:ScreenPointToRay(position.X, position.Y)
	return Raycast.cast(ray.Origin, ray.Direction * Raycast.MaxDistance, accept), ray
end

-- Anything the eye can see stops the ray (used for camera pivots).
function Raycast.isVisible(instance: Instance): boolean
	if instance:IsA("BasePart") then
		return instance.Transparency < 0.98
	end
	return true
end

return Raycast
