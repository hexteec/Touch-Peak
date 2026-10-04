--[[
	Moves the Studio edit camera in response to gestures.

	The camera orbits around a pivot point: whatever is in the middle of the
	screen when a gesture starts (or the object you focused on last). Panning
	keeps the point under your fingers glued to them, and pinching zooms
	toward the point between your fingers. When the camera gets very close to
	that point it switches to flying forward, so you can pinch your way
	through walls and into buildings.
]]

local Workspace = game:GetService("Workspace")

local Raycast = require(script.Parent.Raycast)

local MAX_PITCH = math.rad(88)
local DEFAULT_PIVOT_DISTANCE = 40
local MIN_ORBIT_DISTANCE = 0.5
local MIN_ZOOM_DISTANCE = 2
local MAX_ZOOM_DISTANCE = 15000
local MIN_PAN_DEPTH = 1
local FOCUS_AXIS_COS = math.cos(math.rad(3))
local FOCUS_DURATION = 0.45
local FOCUS_MARGIN = 1.15
local MAX_FOCUS_PARTS = 5000

local INERTIA_FRICTION = 7 -- 1/s; a flick at v px/s coasts another v / 7 px
local INERTIA_START_SPEED = 80 -- px/s
local INERTIA_STOP_SPEED = 10 -- px/s

local function sameCFrame(a: CFrame, b: CFrame): boolean
	return (a.Position - b.Position).Magnitude < 1e-3
		and a.LookVector:Dot(b.LookVector) > 1 - 1e-6
		and a.UpVector:Dot(b.UpVector) > 1 - 1e-6
end

-- Camera right vector flattened onto the ground plane, so pitching never rolls the view.
local function horizontalRight(cframe: CFrame): Vector3
	local right = cframe.RightVector
	local flat = Vector3.new(right.X, 0, right.Z)
	if flat.Magnitude < 1e-4 then
		local look = cframe.LookVector
		flat = Vector3.new(-look.Z, 0, look.X)
	end
	if flat.Magnitude < 1e-4 then
		return Vector3.xAxis
	end
	return flat.Unit
end

local function expandBounds(bounds, cframe: CFrame, size: Vector3)
	local half = size / 2
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				local corner = cframe:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z))
				local min, max = bounds.min, bounds.max
				if min then
					bounds.min =
						Vector3.new(math.min(min.X, corner.X), math.min(min.Y, corner.Y), math.min(min.Z, corner.Z))
					bounds.max =
						Vector3.new(math.max(max.X, corner.X), math.max(max.Y, corner.Y), math.max(max.Z, corner.Z))
				else
					bounds.min, bounds.max = corner, corner
				end
			end
		end
	end
end

local function addToBounds(instance: Instance, bounds)
	if instance:IsA("Terrain") then
		return
	elseif instance:IsA("BasePart") then
		expandBounds(bounds, instance.CFrame, instance.Size)
	elseif instance:IsA("Model") then
		local ok, cframe, size = pcall(instance.GetBoundingBox, instance)
		if ok then
			expandBounds(bounds, cframe, size)
		end
	elseif instance:IsA("Attachment") then
		expandBounds(bounds, instance.WorldCFrame, Vector3.zero)
	else
		-- Folders and other containers: use the parts inside them.
		local counted = 0
		for _, descendant in instance:GetDescendants() do
			if descendant:IsA("BasePart") and not descendant:IsA("Terrain") then
				expandBounds(bounds, descendant.CFrame, descendant.Size)
				counted += 1
				if counted >= MAX_FOCUS_PARTS then
					break
				end
			end
		end
	end
end

local CameraController = {}
CameraController.__index = CameraController

function CameraController.new(settings)
	local self = setmetatable({}, CameraController)
	self._settings = settings
	self._pivot = nil :: Vector3?
	self._focusDepth = nil :: number? -- "look" mode: how far ahead Studio's focus sits
	self._lastCFrame = nil :: CFrame?
	self._anchor = nil :: Vector3?
	self._inertia = nil
	self._focus = nil
	return self
end

function CameraController:_camera(): Camera?
	return Workspace.CurrentCamera
end

-- True while the camera is still where we last put it.
function CameraController:_isOurs(camera: Camera): boolean
	return self._lastCFrame ~= nil and sameCFrame(camera.CFrame, self._lastCFrame)
end

-- Studio's edit camera keeps aiming at Camera.Focus: a focus point that is not
-- straight ahead makes Studio turn the camera back toward it. So Focus always
-- moves along with the camera, on its line of sight.
function CameraController:_apply(camera: Camera, cframe: CFrame, pivot: Vector3)
	local depth
	if self._settings:Get("rotateMode") == "look" then
		depth = self._focusDepth or DEFAULT_PIVOT_DISTANCE
	else
		depth = (pivot - cframe.Position):Dot(cframe.LookVector)
	end
	depth = math.clamp(depth, MIN_ORBIT_DISTANCE, MAX_ZOOM_DISTANCE)

	camera.Focus = CFrame.new(cframe.Position + cframe.LookVector * depth)
	camera.CFrame = cframe
	self._pivot = pivot
	self._lastCFrame = camera.CFrame
end

function CameraController:_resolvePivot(camera: Camera): Vector3
	local cframe = camera.CFrame
	local look = cframe.LookVector

	-- 1. Whatever sits in the middle of the screen.
	local viewport = camera.ViewportSize
	local ray = camera:ViewportPointToRay(viewport.X / 2, viewport.Y / 2)
	local hit = Raycast.cast(ray.Origin, ray.Direction * Raycast.MaxDistance, Raycast.isVisible)
	if hit then
		local depth = math.max((hit.Position - cframe.Position):Dot(look), MIN_ORBIT_DISTANCE)
		return cframe.Position + look * depth
	end

	-- 2. Studio's own focus point, if it is still in front of the camera.
	local toFocus = camera.Focus.Position - cframe.Position
	local depth = toFocus:Dot(look)
	if depth > MIN_ORBIT_DISTANCE and depth < MAX_ZOOM_DISTANCE and toFocus.Unit:Dot(look) > FOCUS_AXIS_COS then
		return cframe.Position + look * depth
	end

	-- 3. Empty sky: a point a little in front of the camera.
	return cframe.Position + look * DEFAULT_PIVOT_DISTANCE
end

function CameraController:_getPivot(camera: Camera): Vector3
	if self._settings:Get("rotateMode") == "look" then
		-- Turning in place: remember how far ahead Studio's focus was, to keep it there.
		if self._focusDepth == nil or not self:_isOurs(camera) then
			local cframe = camera.CFrame
			local depth = (camera.Focus.Position - cframe.Position):Dot(cframe.LookVector)
			self._focusDepth = if depth > MIN_ORBIT_DISTANCE and depth < MAX_ZOOM_DISTANCE
				then depth
				else DEFAULT_PIVOT_DISTANCE
		end
		return camera.CFrame.Position
	end
	if self._pivot and self:_isOurs(camera) then
		return self._pivot
	end
	local pivot = self:_resolvePivot(camera)
	self._pivot = pivot
	return pivot
end

-- World point under a screen position, used as the zoom target and pan depth.
function CameraController:_findAnchor(camera: Camera, screenPosition: Vector2, pivot: Vector3): Vector3
	local hit, ray = Raycast.fromScreen(camera, screenPosition, Raycast.isVisible)
	if hit then
		return hit.Position
	end

	local cframe = camera.CFrame
	local depth = (pivot - cframe.Position):Dot(cframe.LookVector)
	if depth < MIN_PAN_DEPTH then
		depth = DEFAULT_PIVOT_DISTANCE
	end
	local along = depth / math.max(ray.Direction:Dot(cframe.LookVector), 0.05)
	return ray.Origin + ray.Direction * along
end

-- Gesture entry points ------------------------------------------------------------

function CameraController:BeginInteraction()
	self._inertia = nil
	self._focus = nil
	self._anchor = nil
end

-- Starts a pan or zoom: the world point under `screenPosition` becomes the
-- zoom target and the depth at which panning follows the finger(s).
function CameraController:AnchorAt(screenPosition: Vector2)
	self._inertia = nil
	self._focus = nil
	local camera = self:_camera()
	if not camera then
		return
	end
	self._anchor = self:_findAnchor(camera, screenPosition, self:_getPivot(camera))
end

function CameraController:Rotate(delta: Vector2)
	local camera = self:_camera()
	if not camera then
		return
	end

	local settings = self._settings
	local viewport = camera.ViewportSize
	-- Dragging across the short side of the viewport turns the camera 180 degrees.
	local radiansPerPixel = math.pi / math.max(math.min(viewport.X, viewport.Y), 100)
	radiansPerPixel *= settings:Get("rotateSensitivity")
	if settings:Get("invertRotate") then
		radiansPerPixel = -radiansPerPixel
	end

	local cframe = camera.CFrame
	local pivot = self:_getPivot(camera)
	local look = cframe.LookVector

	local yaw = -delta.X * radiansPerPixel
	local currentPitch = math.asin(math.clamp(look.Y, -1, 1))
	local targetPitch = math.clamp(currentPitch - delta.Y * radiansPerPixel, -MAX_PITCH, MAX_PITCH)
	local pitch = targetPitch - currentPitch

	local rotation = CFrame.fromAxisAngle(Vector3.yAxis, yaw) * CFrame.fromAxisAngle(horizontalRight(cframe), pitch)
	local position = pivot + rotation:VectorToWorldSpace(cframe.Position - pivot)
	local newLook = rotation:VectorToWorldSpace(look)

	self:_apply(camera, CFrame.lookAt(position, position + newLook), pivot)
end

function CameraController:Pan(delta: Vector2)
	local camera = self:_camera()
	if not camera then
		return
	end

	local settings = self._settings
	local cframe = camera.CFrame
	local pivot = self:_getPivot(camera)
	local anchor = self._anchor or pivot

	-- Size of one pixel at the depth of the point under the fingers.
	local depth = math.max((anchor - cframe.Position):Dot(cframe.LookVector), MIN_PAN_DEPTH)
	local viewport = camera.ViewportSize
	local studsPerPixel = 2 * depth * math.tan(math.rad(camera.FieldOfView) / 2) / math.max(viewport.Y, 1)
	studsPerPixel *= settings:Get("panSensitivity")
	if settings:Get("invertPan") then
		studsPerPixel = -studsPerPixel
	end

	local offset = (cframe.UpVector * delta.Y - cframe.RightVector * delta.X) * studsPerPixel
	self:_apply(camera, cframe + offset, pivot + offset)
end

-- scale < 1 moves closer (fingers spread apart), scale > 1 moves away.
function CameraController:Zoom(scale: number, centroid: Vector2)
	local camera = self:_camera()
	if not camera then
		return
	end

	local factor = scale ^ self._settings:Get("zoomSensitivity")
	if factor ~= factor or factor <= 0 then
		return
	end

	local cframe = camera.CFrame
	local position = cframe.Position
	local pivot = self:_getPivot(camera)
	local anchor = self._anchor
	if not anchor then
		anchor = self:_findAnchor(camera, centroid, pivot)
		self._anchor = anchor
	end

	local toAnchor = anchor - position
	local distance = toAnchor.Magnitude
	if distance < 1e-4 then
		return
	end
	local direction = toAnchor / distance

	local move = (1 - factor) * math.max(distance, MIN_ZOOM_DISTANCE)
	local newDistance = distance - move
	if newDistance > MAX_ZOOM_DISTANCE then
		newDistance = math.max(MAX_ZOOM_DISTANCE, distance)
		move = distance - newDistance
	end
	local offset = direction * move

	local newPivot
	if distance >= MIN_ZOOM_DISTANCE and newDistance >= MIN_ZOOM_DISTANCE then
		-- Scale everything around the anchor; the pivot stays on the view axis.
		newPivot = anchor + (pivot - anchor) * (newDistance / distance)
	else
		-- Too close to scale any further: fly forward and push the anchor ahead.
		newPivot = pivot + offset
		self._anchor = anchor + offset
	end

	self:_apply(camera, cframe + offset, newPivot)
end

function CameraController:StartInertia(kind: "rotate" | "pan", velocity: Vector2)
	if not self._settings:Get("inertia") or velocity.Magnitude < INERTIA_START_SPEED then
		return
	end
	self._inertia = { kind = kind, velocity = velocity }
end

-- Smoothly moves the camera so the given instances fill the view.
function CameraController:FocusOn(instances: { Instance }): boolean
	local camera = self:_camera()
	if not camera then
		return false
	end

	local bounds = {}
	for _, instance in instances do
		addToBounds(instance, bounds)
	end
	if not bounds.min then
		return false
	end

	local center = (bounds.min + bounds.max) / 2
	local radius = math.max((bounds.max - bounds.min).Magnitude / 2, 1)

	local viewport = camera.ViewportSize
	local verticalFov = math.rad(camera.FieldOfView)
	local horizontalFov = 2 * math.atan(math.tan(verticalFov / 2) * viewport.X / math.max(viewport.Y, 1))
	local halfAngle = math.min(verticalFov, horizontalFov) / 2
	local distance = math.clamp(radius / math.sin(halfAngle) * FOCUS_MARGIN, MIN_ZOOM_DISTANCE, MAX_ZOOM_DISTANCE)

	local from = camera.CFrame
	local to = CFrame.new(center - from.LookVector * distance) * from.Rotation

	self._inertia = nil
	self._anchor = nil
	self._lastCFrame = from
	self._focus = { from = from, to = to, pivot = center, elapsed = 0 }
	return true
end

function CameraController:IsAnimating(): boolean
	return self._focus ~= nil or self._inertia ~= nil
end

function CameraController:Stop()
	self._inertia = nil
	self._focus = nil
	self._anchor = nil
end

-- Advances inertia and focus animations; call every frame.
function CameraController:Step(dt: number)
	if not (self._focus or self._inertia) then
		return
	end
	local camera = self:_camera()
	if not camera then
		return
	end
	if not self:_isOurs(camera) then
		-- Something else (Studio's own controls) moved the camera: give way.
		self:Stop()
		return
	end

	local focus = self._focus
	if focus then
		focus.elapsed += dt
		local alpha = math.clamp(focus.elapsed / FOCUS_DURATION, 0, 1)
		local eased = 1 - (1 - alpha) ^ 3
		self:_apply(camera, focus.from:Lerp(focus.to, eased), focus.pivot)
		if alpha >= 1 then
			self._focus = nil
		end
		return
	end

	local inertia = self._inertia
	local decay = math.exp(-INERTIA_FRICTION * dt)
	-- Exact distance travelled by an exponentially decaying velocity over dt.
	local delta = inertia.velocity * ((1 - decay) / INERTIA_FRICTION)
	inertia.velocity *= decay
	if inertia.velocity.Magnitude < INERTIA_STOP_SPEED then
		self._inertia = nil
	end

	if inertia.kind == "rotate" then
		self:Rotate(delta)
	else
		self:Pan(delta)
	end
end

return CameraController
