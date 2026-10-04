--[[
	Feeds UserInputService touches (and, optionally, the left mouse button as a
	single "finger") into a GestureRecognizer.

	Touches that start on top of the plugin's own UI are left alone for their
	whole lifetime, so dragging the panel never moves the camera.
]]

local UserInputService = game:GetService("UserInputService")

local Maid = require(script.Parent.Parent.Util.Maid)
local Signal = require(script.Parent.Parent.Util.Signal)

local MOUSE_ID = "Mouse"
-- Windows turns touches into fake mouse clicks shortly after the real touch
-- events; ignore the mouse for a moment after any touch to avoid doubling up.
local MOUSE_AFTER_TOUCH_COOLDOWN = 0.75

local TouchInput = {}
TouchInput.__index = TouchInput

export type Options = {
	isBlocked: (position: Vector2) -> boolean,
	mouseEnabled: () -> boolean,
}

local function toVector2(position: Vector3): Vector2
	return Vector2.new(position.X, position.Y)
end

function TouchInput.new(recognizer, options: Options)
	local self = setmetatable({}, TouchInput)
	self._recognizer = recognizer
	self._isBlocked = options.isBlocked
	self._mouseEnabled = options.mouseEnabled
	self._maid = Maid.new()
	self._running = false
	self._touches = {} -- InputObject -> true for touches we forward
	self._mouseDown = false
	self._lastTouchTime = -math.huge

	-- Visual feedback hooks (only real fingers, the mouse has its own cursor).
	self.TouchBegan = Signal.new()
	self.TouchMoved = Signal.new()
	self.TouchEnded = Signal.new()

	return self
end

function TouchInput:IsRunning(): boolean
	return self._running
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
	-- Fingers lifted while Studio is in the background never report back.
	pcall(function()
		self._maid:Give(UserInputService.WindowFocusReleased:Connect(function()
			self:_releaseAll()
		end))
	end)
end

function TouchInput:Stop()
	if not self._running then
		return
	end
	self._running = false
	self._maid:Clean()
	self:_releaseAll()
end

-- Forgets every finger without triggering taps or inertia.
function TouchInput:_releaseAll()
	for input in self._touches do
		self.TouchEnded:Fire(input)
	end
	table.clear(self._touches)
	self._mouseDown = false
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

function TouchInput:_onBegan(input: InputObject)
	local inputType = input.UserInputType

	if inputType == Enum.UserInputType.Touch then
		self._lastTouchTime = os.clock()
		if self._touches[input] then
			return
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
		if not self._mouseEnabled() or self._mouseDown or next(self._touches) then
			return
		end
		if os.clock() - self._lastTouchTime < MOUSE_AFTER_TOUCH_COOLDOWN then
			return
		end
		local position = toVector2(input.Position)
		if self._isBlocked(position) then
			return
		end
		self._mouseDown = true
		self._recognizer:TouchBegan(MOUSE_ID, position)
	end
end

function TouchInput:_onChanged(input: InputObject)
	local inputType = input.UserInputType

	if inputType == Enum.UserInputType.Touch then
		self._lastTouchTime = os.clock()
		if self._touches[input] then
			local position = toVector2(input.Position)
			self.TouchMoved:Fire(input, position)
			self._recognizer:TouchMoved(input, position)
		end
	elseif inputType == Enum.UserInputType.MouseMovement then
		if self._mouseDown then
			self._recognizer:TouchMoved(MOUSE_ID, toVector2(input.Position))
		end
	end
end

function TouchInput:_onEnded(input: InputObject)
	local inputType = input.UserInputType

	if inputType == Enum.UserInputType.Touch then
		self._lastTouchTime = os.clock()
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

return TouchInput
