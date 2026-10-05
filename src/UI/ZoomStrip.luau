--[[
	Zoom control along the edge of the viewport, drawn like the distance
	scale on a lens barrel: the tick marks travel with your finger and the
	camera follows. Drag up to move in, down to move out.

	It reports finger movement in pixels (Moved(dy)); App turns that into
	camera zoom, so the strip itself knows nothing about the camera.
]]

local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local Create = require(script.Parent.Create)
local Components = require(script.Parent.Components)
local Maid = require(script.Parent.Parent.Util.Maid)
local Signal = require(script.Parent.Parent.Util.Signal)

local Color = Theme.Color

local WIDTH = 46
local EDGE_GAP = 14
local CAP = 30 -- space for the + / − marks at the ends
local TICK_SPACING = 11
local MAJOR_EVERY = 5
local CYCLE = TICK_SPACING * MAJOR_EVERY

local function toVector2(position: Vector3): Vector2
	return Vector2.new(position.X, position.Y)
end

local function isPointer(input: InputObject): boolean
	local inputType = input.UserInputType
	return inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch
end

local function isLeftButtonDown(): boolean
	local ok, pressed = pcall(function()
		return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
	end)
	return not ok or pressed ~= false
end

local ZoomStrip = {}
ZoomStrip.__index = ZoomStrip

export type Params = {
	parent: GuiBase2d,
	side: string, -- "left" | "right"
}

function ZoomStrip.new(params: Params)
	local self = setmetatable({}, ZoomStrip)
	self._params = params
	self._maid = Maid.new()
	self._tracking = nil -- { input, isTouch, last }
	self._scroll = 0
	self._ticks = {}

	self.Began = Signal.new()
	self.Moved = Signal.new()
	self.Ended = Signal.new()

	local ticks = Create("Frame", {
		Position = UDim2.fromOffset(0, CAP),
		Size = UDim2.new(1, 0, 1, -CAP * 2),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	})

	local index = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -10, 0, 2),
		BackgroundColor3 = Color.Blue,
		ZIndex = 3,
	}, { Create.round() })

	local function mark(plus: boolean, position: UDim2): Frame
		return Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = position,
			Size = UDim2.fromOffset(12, 12),
			BackgroundTransparency = 1,
		}, {
			H = Components.bar(10, 2, 0, nil, Color.Ash),
			V = if plus then Components.bar(2, 10, 0, nil, Color.Ash) else nil,
		})
	end

	local stroke = Create.stroke(Color.Bone, 0.88)
	local body = Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color.Graphite,
		BackgroundTransparency = 0.04,
		ZIndex = 2,
	}, {
		Create.corner(12),
		Stroke = stroke,
		Plus = mark(true, UDim2.new(0.5, 0, 0, CAP / 2)),
		Minus = mark(false, UDim2.new(0.5, 0, 1, -CAP / 2)),
		Ticks = ticks,
		Index = index,
	})

	local root = Create("Frame", {
		Name = "TouchPeakZoomStrip",
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 9,
	}, {
		Body = body,
		Shadow = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 3),
			Size = UDim2.new(1, 8, 1, 8),
			BackgroundColor3 = Color.Black,
			BackgroundTransparency = 0.86,
			ZIndex = 1,
		}, { Create.corner(16) }),
	})

	self._root = root
	self._body = body
	self._ticksFrame = ticks
	self._stroke = stroke
	self._index = index

	self:SetSide(params.side)
	self:_layout()

	self._maid:Give(params.parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_layout()
	end))

	self._maid:Give(body.InputBegan:Connect(function(input)
		if self._tracking or not isPointer(input) then
			return
		end
		local position = toVector2(input.Position)
		self._tracking = {
			input = input,
			isTouch = input.UserInputType == Enum.UserInputType.Touch,
			last = position,
		}
		Create.tween(stroke, Theme.Tween.Fast, { Color = Color.Blue, Transparency = 0.25 })
		Create.tween(index, Theme.Tween.Fast, { Size = UDim2.new(1, -4, 0, 2) })
		self.Began:Fire()
	end))

	self._maid:Give(UserInputService.InputChanged:Connect(function(input)
		local track = self._tracking
		if not track then
			return
		end
		if track.isTouch then
			if input ~= track.input then
				return
			end
		elseif input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		elseif not isLeftButtonDown() then
			-- The release happened somewhere we could not see it.
			self:_release()
			return
		end

		local position = toVector2(input.Position)
		local dy = position.Y - track.last.Y
		track.last = position
		if dy ~= 0 then
			self:_scrollBy(dy)
			self.Moved:Fire(dy)
		end
	end))

	self._maid:Give(UserInputService.InputEnded:Connect(function(input)
		local track = self._tracking
		if not track then
			return
		end
		if
			(track.isTouch and input == track.input)
			or (not track.isTouch and input.UserInputType == Enum.UserInputType.MouseButton1)
		then
			self:_release()
		end
	end))

	root.Parent = params.parent
	self._maid:Give(root)
	return self
end

function ZoomStrip:_layout()
	local screenHeight = self._params.parent.AbsoluteSize.Y
	local height = math.clamp(math.floor(screenHeight * 0.46), 200, 360)
	self._root.Size = UDim2.fromOffset(WIDTH, height)

	-- Enough ticks to fill the track while it scrolls by one major cycle.
	local trackHeight = height - CAP * 2
	local needed = math.ceil(trackHeight / TICK_SPACING) + MAJOR_EVERY + 1
	for index = #self._ticks + 1, needed do
		local major = (index - 1) % MAJOR_EVERY == 0
		self._ticks[index] = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(if major then 18 else 9, if major then 2 else 1),
			BackgroundColor3 = Color.Bone,
			BackgroundTransparency = if major then 0.35 else 0.7,
			Parent = self._ticksFrame,
		})
	end
	self:_scrollBy(0)
end

function ZoomStrip:_scrollBy(dy: number)
	self._scroll = (self._scroll + dy) % CYCLE
	local offset = self._scroll - CYCLE
	for index, tick in self._ticks do
		tick.Position = UDim2.new(0.5, 0, 0, offset + (index - 1) * TICK_SPACING)
	end
end

function ZoomStrip:_release()
	if not self._tracking then
		return
	end
	self._tracking = nil
	Create.tween(self._stroke, Theme.Tween.Smooth, { Color = Color.Bone, Transparency = 0.88 })
	Create.tween(self._index, Theme.Tween.Smooth, { Size = UDim2.new(1, -10, 0, 2) })
	self.Ended:Fire()
end

function ZoomStrip:SetSide(side: string)
	if side == "right" then
		self._root.AnchorPoint = Vector2.new(1, 0.5)
		self._root.Position = UDim2.new(1, -EDGE_GAP, 0.5, 0)
	else
		self._root.AnchorPoint = Vector2.new(0, 0.5)
		self._root.Position = UDim2.new(0, EDGE_GAP, 0.5, 0)
	end
end

function ZoomStrip:SetVisible(visible: boolean)
	self._root.Visible = visible
	if not visible then
		self:_release()
	end
end

function ZoomStrip:IsVisible(): boolean
	return self._root.Visible
end

-- Horizontal space the strip takes up at its screen edge, gap included.
function ZoomStrip:GetFootprint(): number
	return WIDTH + EDGE_GAP
end

function ZoomStrip:IsHeld(): boolean
	return self._tracking ~= nil
end

-- True when a screen point lies on the strip (so it should not move the camera).
function ZoomStrip:ContainsPoint(point: Vector2): boolean
	if not self._root.Visible then
		return false
	end
	local position, size = self._body.AbsolutePosition, self._body.AbsoluteSize
	local margin = 8
	return point.X >= position.X - margin
		and point.X <= position.X + size.X + margin
		and point.Y >= position.Y - margin
		and point.Y <= position.Y + size.Y + margin
end

function ZoomStrip:Destroy()
	self._tracking = nil
	self._maid:Clean()
end

return ZoomStrip
