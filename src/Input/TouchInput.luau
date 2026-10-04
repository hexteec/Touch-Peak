--[[
	Feeds UserInputService touches (and, optionally, the left mouse button as a
	single "finger") into a GestureRecognizer.

	Touches that start on top of the plugin's own UI are left alone for their
	whole lifetime, so dragging the window never moves the camera.

	Roblox Studio on Windows often hands a touch screen to plugins as a plain
	mouse (one pointer, no second finger). Everything here is written so the
	mouse path keeps working even when events get lost, and `Stats` records
	what Studio actually delivers so the diagnostics panel can show it.
]]

local UserInputService = game:GetService("UserInputService")

local Maid = require(script.Parent.Parent.Util.Maid)
local Signal = require(script.Parent.Parent.Util.Signal)

local MOUSE_ID = "Mouse"
-- Windows turns touches into fake mouse clicks right after the real touch
-- events; ignore the mouse for a moment after a touch to avoid doubling up.
local MOUSE_AFTER_TOUCH_COOLDOWN = 0.35
-- Windows already filters jitter out of the pointer, so the mouse may start a
-- drag sooner than a raw finger.
local MOUSE_TAP_SLOP = 5

local TouchInput = {}
TouchInput.__index = TouchInput

export type Options = {
	isBlocked: (position: Vector2) -> boolean,
	mouseEnabled: () -> boolean,
}

local function toVector2(position: Vector3): Vector2
	return Vector2.new(position.X, position.Y)
end

local function newStats()
	return {
		touchBegan = 0,
		touchChanged = 0,
		touchEnded = 0,
		touchFingers = 0, -- most real fingers seen down at the same time
		mouseDown = 0,
		mouseMoves = 0,
		wheel = 0,
		pinch = 0,
		pan = 0,
	}
end

function TouchInput.new(recognizer, options: Options)
	local self = setmetatable({}, TouchInput)
	self._recognizer = recognizer
	self._isBlocked = options.isBlocked
	self._mouseEnabled = options.mouseEnabled
	self._maid = Maid.new()
	self._running = false
	self._touches = {} -- InputObject -> true for touches we forward
	self._down = {} -- InputObject -> true for every real finger on screen (stats)
	self._mouseDown = false
	self._lastTouchTime = -math.huge
	self._pinchScale = nil

	self.Stats = newStats()
	self.StatsChanged = Signal.new()

	-- Visual feedback hooks (only real fingers, the mouse has its own cursor).
	self.TouchBegan = Signal.new()
	self.TouchMoved = Signal.new()
	self.TouchEnded = Signal.new()

	-- Roblox's own pinch gesture, as a backup when raw fingers are not reported:
	-- Pinch(scaleStep, centroid?) where scaleStep < 1 means the fingers spread apart.
	self.PinchBegan = Signal.new()
	self.Pinch = Signal.new()

	return self
end

function TouchInput:IsRunning(): boolean
	return self._running
end

-- True while the only "finger" is the mouse pointer.
function TouchInput:IsMouseActive(): boolean
	return self._mouseDown
end

function TouchInput:Start()
	if self._running then
		return
	end
	self._running = true

	-- gameProcessedEvent is deliberately ignored: in edit mode Studio may
	-- mark viewport touches as processed. Our own UI is filtered by isBlocked.
	self._maid:Give(UserInputService.InputBegan:Connect(function(input)
		self:_onBegan(input)
	end))
	self._maid:Give(UserInputService.InputChanged:Connect(function(input)
		self:_onChanged(input)
	end))
	self._maid:Give(UserInputService.InputEnded:Connect(function(input)
		self:_onEnded(input)
	end))
	-- Touches cancelled by the OS (e.g. a palm rejection) may skip InputEnded.
	self._maid:Give(UserInputService.TouchEnded:Connect(function(input)
		self:_onEnded(input)
	end))

	-- Optional events: missing ones (or ones Studio never fires) are simply skipped.
	self:_connectOptional("WindowFocusReleased", function()
		self:_releaseAll()
	end)
	self:_connectOptional("TouchPinch", function(positions, scale, _velocity, state)
		self:_onPinch(positions, scale, state)
	end)
	self:_connectOptional("TouchPan", function()
		self:_count("pan")
	end)
end

function TouchInput:Stop()
	if not self._running then
		return
	end
	self._running = false
	self._maid:Clean()
	self:_releaseAll()
	table.clear(self._down)
end

function TouchInput:_connectOptional(name: string, callback)
	pcall(function()
		self._maid:Give(UserInputService[name]:Connect(callback))
	end)
end

function TouchInput:_count(key: string)
	self.Stats[key] += 1
	self.StatsChanged:Fire(self.Stats)
end

-- Forgets every finger without triggering taps or inertia.
function TouchInput:_releaseAll()
	for input in self._touches do
		self.TouchEnded:Fire(input)
	end
	table.clear(self._touches)
	self._mouseDown = false
	self._pinchScale = nil
	self._recognizer:Cancel()
end

-- If a finger finished without telling us, start over instead of mixing it
-- into the next gesture (and without turning it into a tap).
function TouchInput:_dropStaleTouches()
	for input in self._touches do
		local state = input.UserInputState
		if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			self:_releaseAll()
			return
		end
	end
end

local function isLeftButtonDown(): boolean
	local ok, pressed = pcall(function()
		return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
	end)
	-- If Studio cannot tell, assume it is still held.
	return not ok or pressed ~= false
end

function TouchInput:_onBegan(input: InputObject)
	local inputType = input.UserInputType

	if inputType == Enum.UserInputType.Touch then
		self._lastTouchTime = os.clock()
		self._down[input] = true
		local fingers = 0
		for _ in self._down do
			fingers += 1
		end
		self.Stats.touchFingers = math.max(self.Stats.touchFingers, fingers)
		self:_count("touchBegan")

		if self._touches[input] then
			-- The same InputObject began again: its previous end was lost.
			self:_releaseAll()
		end
		local position = toVector2(input.Position)
		if self._isBlocked(position) then
			return
		end
		-- A real touch takes over from a mouse "finger" Windows synthesized from
		-- it. Drop that one silently so it cannot count as a tap.
		if self._mouseDown then
			self._mouseDown = false
			self._recognizer:Cancel()
		end
		self:_dropStaleTouches()
		self._touches[input] = true
		self.TouchBegan:Fire(input, position)
		self._recognizer:TouchBegan(input, position)
	elseif inputType == Enum.UserInputType.MouseButton1 then
		self:_count("mouseDown")
		if not self._mouseEnabled() or next(self._touches) then
			return
		end
		if os.clock() - self._lastTouchTime < MOUSE_AFTER_TOUCH_COOLDOWN then
			return
		end
		if self._mouseDown then
			-- We never saw the previous release (e.g. it happened outside the
			-- viewport). Forget that press instead of ignoring this one.
			self._mouseDown = false
			self._recognizer:Cancel()
		end
		local position = toVector2(input.Position)
		if self._isBlocked(position) then
			return
		end
		self._mouseDown = true
		self._recognizer:TouchBegan(MOUSE_ID, position, MOUSE_TAP_SLOP)
	end
end

function TouchInput:_onChanged(input: InputObject)
	local inputType = input.UserInputType

	if inputType == Enum.UserInputType.Touch then
		self._lastTouchTime = os.clock()
		self:_count("touchChanged")
		if self._touches[input] then
			local position = toVector2(input.Position)
			self.TouchMoved:Fire(input, position)
			self._recognizer:TouchMoved(input, position)
		end
	elseif inputType == Enum.UserInputType.MouseMovement then
		self:_count("mouseMoves")
		if self._mouseDown then
			if not isLeftButtonDown() then
				-- The button was released somewhere we could not see it.
				self._mouseDown = false
				self._recognizer:Cancel()
				return
			end
			self._recognizer:TouchMoved(MOUSE_ID, toVector2(input.Position))
		end
	elseif inputType == Enum.UserInputType.MouseWheel then
		self:_count("wheel")
	end
end

function TouchInput:_onEnded(input: InputObject)
	local inputType = input.UserInputType

	if inputType == Enum.UserInputType.Touch then
		self._lastTouchTime = os.clock()
		if self._down[input] then
			self._down[input] = nil
			self:_count("touchEnded")
		end
		if self._touches[input] then
			self._touches[input] = nil
			self.TouchEnded:Fire(input)
			self._recognizer:TouchEnded(input, toVector2(input.Position))
		end
	elseif inputType == Enum.UserInputType.MouseButton1 then
		if self._mouseDown then
			self._mouseDown = false
			-- The button's InputObject may still hold the press position; keep the last move.
			self._recognizer:TouchEnded(MOUSE_ID)
		end
	end
end

-- UserInputService.TouchPinch reports the total scale since the pinch began.
function TouchInput:_onPinch(positions, scale: number, state: Enum.UserInputState)
	self:_count("pinch")
	-- Raw fingers already drive zoom whenever Studio reports two of them.
	if self._recognizer:GetTouchCount() >= 2 or type(scale) ~= "number" or scale <= 0 then
		self._pinchScale = nil
		return
	end

	local centroid = nil
	if type(positions) == "table" and #positions > 0 then
		local sum = Vector2.zero
		for _, position in positions do
			sum += Vector2.new(position.X, position.Y)
		end
		centroid = sum / #positions
	end

	if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		self._pinchScale = nil
		return
	end
	if state == Enum.UserInputState.Begin or self._pinchScale == nil then
		-- Fingers on the plugin window must not zoom the camera.
		if centroid and self._isBlocked(centroid) then
			return
		end
		self._recognizer:Cancel()
		self._pinchScale = scale
		self.PinchBegan:Fire(centroid)
		return
	end

	-- Spreading the fingers grows `scale`; the camera wants < 1 to move closer.
	self.Pinch:Fire(self._pinchScale / scale, centroid)
	self._pinchScale = scale
end

return TouchInput
