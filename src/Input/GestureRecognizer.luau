--[[
	Turns raw touch points into high level gestures.

	  1 finger drag ............ Rotate(delta)        -> RotateEnded(velocity)
	  2 fingers, apart/together  Zoom(scale, centroid)
	  2 fingers, same direction  Pan(delta, centroid) -> PanEnded(velocity)
	  quick tap ................ Tap(position)
	  second quick tap ......... DoubleTap(position)
	  press and hold ........... LongPress(position)

	Touches are identified by any key (Roblox reuses the same InputObject for
	the whole life of a finger), so the recognizer does not depend on Studio
	and can be driven from tests with a fake clock.

	A two-finger gesture is locked to either zoom or pan once the fingers have
	moved far enough to tell the two apart, unless `combine` is enabled.
	After a two-finger gesture (or a long press) the remaining finger is
	ignored until every finger is lifted, so lifting one finger never makes
	the camera jump.

	Roblox reports each finger in its own input event. Two-finger movement is
	therefore collected and evaluated once per frame by `Flush()` (call it from
	Heartbeat); otherwise the first finger of a pan would look like a pinch.
	If nobody flushes, pending movement is evaluated after `maxBatchDelay`.
]]

local Signal = require(script.Parent.Parent.Util.Signal)

local DEFAULT_CONFIG = {
	tapSlop = 10, -- px a finger may drift and still count as a tap
	doubleTapTime = 0.35, -- s between two taps
	doubleTapSlop = 40, -- px between two taps
	longPressTime = 0.55, -- s
	twoFingerLockDistance = 10, -- px before deciding between zoom and pan
	velocityWindow = 0.1, -- s of movement used for the release velocity
	releaseStaleTime = 0.08, -- s without movement before release cancels inertia
	maxReleaseSpeed = 6000, -- px/s
	maxBatchDelay = 0.05, -- s two-finger movement may wait for Flush()
}

export type Mode = "idle" | "pending" | "rotate" | "pendingTwo" | "zoom" | "pan" | "both" | "blocked"

local GestureRecognizer = {}
GestureRecognizer.__index = GestureRecognizer

GestureRecognizer.DefaultConfig = DEFAULT_CONFIG

export type Options = {
	clock: (() -> number)?,
	delay: ((number, () -> ()) -> any)?,
	config: { [string]: number }?,
}

function GestureRecognizer.new(options: Options?)
	local opts: Options = options or {}
	local self = setmetatable({}, GestureRecognizer)

	self._clock = opts.clock or os.clock
	self._delay = opts.delay or task.delay
	self._config = table.clone(DEFAULT_CONFIG)
	for key, value in opts.config or {} do
		self._config[key] = value
	end

	self._combine = false
	self._mode = "idle" :: Mode
	self._gesture = nil :: string?
	self._touches = {} -- id -> record
	self._order = {} -- ids of the (at most two) tracked fingers
	self._ignored = {} -- id -> true for extra fingers
	self._count = 0
	self._samples = {}
	self._lastTap = nil
	self._longPressToken = 0

	self._startCentroid = nil
	self._startDistance = nil
	self._prevCentroid = nil
	self._prevDistance = nil
	self._pendingSince = nil -- time of the oldest unflushed two-finger movement

	self.InteractionBegan = Signal.new()
	self.TouchCountChanged = Signal.new()
	self.GestureChanged = Signal.new()
	self.Rotate = Signal.new()
	self.RotateEnded = Signal.new()
	self.TwoFingerBegan = Signal.new()
	self.Pan = Signal.new()
	self.PanEnded = Signal.new()
	self.Zoom = Signal.new()
	self.Tap = Signal.new()
	self.DoubleTap = Signal.new()
	self.LongPress = Signal.new()

	return self
end

function GestureRecognizer:SetCombine(combine: boolean)
	self._combine = combine
end

function GestureRecognizer:GetMode(): Mode
	return self._mode
end

function GestureRecognizer:GetGesture(): string?
	return self._gesture
end

function GestureRecognizer:GetTouchCount(): number
	return self._count
end

function GestureRecognizer:IsTracking(id: any): boolean
	return self._touches[id] ~= nil or self._ignored[id] ~= nil
end

-- Touch events ----------------------------------------------------------------

function GestureRecognizer:TouchBegan(id: any, position: Vector2)
	if self:IsTracking(id) then
		return
	end
	self:Flush()

	if #self._order >= 2 or self._mode == "blocked" then
		self._ignored[id] = true
		self:_updateCount()
		return
	end

	local record = {
		id = id,
		start = position,
		position = position,
		startTime = self._clock(),
	}
	self._touches[id] = record
	table.insert(self._order, id)

	if #self._order == 1 then
		self._mode = "pending"
		self._samples = {}
		self.InteractionBegan:Fire()
		self:_scheduleLongPress(record)
	else
		self:_cancelLongPress()
		self._lastTap = nil
		self._samples = {}

		local a, b = self:_pair()
		local centroid = (a.position + b.position) / 2
		local distance = math.max((a.position - b.position).Magnitude, 1)
		self._startCentroid = centroid
		self._startDistance = distance
		self._prevCentroid = centroid
		self._prevDistance = distance

		self._mode = "pendingTwo"
		self:_setGesture(nil)
		self.TwoFingerBegan:Fire(centroid)
	end

	self:_updateCount()
end

function GestureRecognizer:TouchMoved(id: any, position: Vector2)
	local record = self._touches[id]
	if not record then
		return
	end

	local previous = record.position
	record.position = position
	local mode = self._mode
	local now = self._clock()

	if mode == "pending" then
		local offset = position - record.start
		if offset.Magnitude > self._config.tapSlop then
			self:_cancelLongPress()
			self._mode = "rotate"
			self:_setGesture("rotate")
			-- Include the slop so the camera catches up with the finger.
			self:_addSample(now, offset)
			self.Rotate:Fire(offset)
		end
	elseif mode == "rotate" then
		local delta = position - previous
		if delta.Magnitude > 0 then
			self:_addSample(now, delta)
			self.Rotate:Fire(delta)
		end
	elseif mode == "pendingTwo" or mode == "zoom" or mode == "pan" or mode == "both" then
		self._pendingSince = self._pendingSince or now
		if now - self._pendingSince >= self._config.maxBatchDelay then
			self:Flush()
		end
	end
end

-- Applies two-finger movement collected since the last call. Call once per frame.
function GestureRecognizer:Flush()
	if self._pendingSince == nil then
		return
	end
	self._pendingSince = nil
	local mode = self._mode
	if mode == "pendingTwo" or mode == "zoom" or mode == "pan" or mode == "both" then
		self:_updateTwoFinger(self._clock())
	end
end

function GestureRecognizer:TouchEnded(id: any, position: Vector2?)
	if self._ignored[id] then
		self._ignored[id] = nil
		self:_settle()
		return
	end

	local record = self._touches[id]
	if not record then
		return
	end
	if position and position ~= record.position then
		self:TouchMoved(id, position)
	end
	self:Flush()

	local now = self._clock()
	local mode = self._mode
	self._touches[id] = nil
	table.remove(self._order, table.find(self._order, id))

	if mode == "pending" then
		self:_cancelLongPress()
		self._mode = "idle"
		self:_handleTap(record, now)
	elseif mode == "rotate" then
		self._mode = "idle"
		self:_setGesture(nil)
		self.RotateEnded:Fire(self:_releaseVelocity(now))
	elseif mode == "pan" or mode == "both" then
		self._mode = "blocked"
		self:_setGesture(nil)
		self.PanEnded:Fire(self:_releaseVelocity(now))
	elseif mode == "zoom" or mode == "pendingTwo" then
		self._mode = "blocked"
		self:_setGesture(nil)
	end

	self:_settle()
end

-- Forget every finger (e.g. when the plugin gets paused).
function GestureRecognizer:Cancel()
	self:_cancelLongPress()
	table.clear(self._touches)
	table.clear(self._order)
	table.clear(self._ignored)
	self._samples = {}
	self._lastTap = nil
	self._pendingSince = nil
	self._mode = "idle"
	self:_setGesture(nil)
	self:_updateCount()
end

-- Internals -------------------------------------------------------------------

function GestureRecognizer:_pair()
	return self._touches[self._order[1]], self._touches[self._order[2]]
end

function GestureRecognizer:_updateTwoFinger(now: number)
	local a, b = self:_pair()
	if not (a and b) then
		return
	end

	local centroid = (a.position + b.position) / 2
	local distance = math.max((a.position - b.position).Magnitude, 1)

	if self._mode == "pendingTwo" then
		local spread = math.abs(distance - self._startDistance)
		local travel = (centroid - self._startCentroid).Magnitude
		if math.max(spread, travel) < self._config.twoFingerLockDistance then
			return
		end

		local mode
		if self._combine then
			mode = "both"
		elseif spread > travel then
			mode = "zoom"
		else
			mode = "pan"
		end
		self._mode = mode
		self:_setGesture(mode)
		-- _prevCentroid/_prevDistance still hold the starting values, so the
		-- movement made while deciding is applied below.
	end

	local mode = self._mode
	local panDelta = centroid - self._prevCentroid
	local scale = self._prevDistance / distance

	if (mode == "pan" or mode == "both") and panDelta.Magnitude > 0 then
		self:_addSample(now, panDelta)
		self.Pan:Fire(panDelta, centroid)
	end
	if (mode == "zoom" or mode == "both") and scale ~= 1 then
		self.Zoom:Fire(scale, centroid)
	end

	self._prevCentroid = centroid
	self._prevDistance = distance
end

function GestureRecognizer:_handleTap(record, now: number)
	local position = record.position
	local last = self._lastTap
	local config = self._config

	if
		last
		and now - last.time <= config.doubleTapTime
		and (position - last.position).Magnitude <= config.doubleTapSlop
	then
		self._lastTap = nil
		self.DoubleTap:Fire(position)
	else
		self._lastTap = { time = now, position = position }
		self.Tap:Fire(position)
	end
end

function GestureRecognizer:_scheduleLongPress(record)
	self._longPressToken += 1
	local token = self._longPressToken

	self._delay(self._config.longPressTime, function()
		if token ~= self._longPressToken then
			return
		end
		if self._mode ~= "pending" or self._touches[record.id] ~= record then
			return
		end
		self._mode = "blocked"
		self._lastTap = nil
		self.LongPress:Fire(record.position)
	end)
end

function GestureRecognizer:_cancelLongPress()
	self._longPressToken += 1
end

function GestureRecognizer:_addSample(now: number, delta: Vector2)
	local samples = self._samples
	table.insert(samples, { time = now, delta = delta })

	local cutoff = now - self._config.velocityWindow
	while samples[1] and samples[1].time < cutoff do
		table.remove(samples, 1)
	end
end

function GestureRecognizer:_releaseVelocity(now: number): Vector2
	local samples = self._samples
	self._samples = {}

	local config = self._config
	local newest = samples[#samples]
	if not newest or now - newest.time > config.releaseStaleTime then
		return Vector2.zero
	end

	local cutoff = now - config.velocityWindow
	local total = Vector2.zero
	local first, count = nil, 0
	for _, sample in samples do
		if sample.time >= cutoff then
			total += sample.delta
			first = first or sample.time
			count += 1
		end
	end
	if count == 0 then
		return Vector2.zero
	end

	-- n samples spaced dt apart describe n intervals of movement.
	local span = newest.time - first
	span = if count > 1 then span + span / (count - 1) else 1 / 60
	span = math.max(span, 1 / 240)

	local velocity = total / span
	if velocity.Magnitude > config.maxReleaseSpeed then
		velocity = velocity.Unit * config.maxReleaseSpeed
	end
	return velocity
end

function GestureRecognizer:_settle()
	if #self._order == 0 and next(self._ignored) == nil and self._mode == "blocked" then
		self._mode = "idle"
	end
	self:_updateCount()
end

function GestureRecognizer:_setGesture(gesture: string?)
	if self._gesture == gesture then
		return
	end
	self._gesture = gesture
	self.GestureChanged:Fire(gesture)
end

function GestureRecognizer:_updateCount()
	local count = #self._order
	for _ in self._ignored do
		count += 1
	end
	if count ~= self._count then
		self._count = count
		self.TouchCountChanged:Fire(count)
	end
end

return GestureRecognizer
