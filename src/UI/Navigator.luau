--[[
	On-screen camera controls in the bottom-left corner of the viewport:

	  * a joystick: push it and the camera flies that way across the screen,
	    faster the further it is pushed (pan),
	  * a zoom slider next to it: push up to move in, down to move out.

	Both spring back when released. They work with a single pointer, which
	matters because Studio usually reports a touch screen as one mouse, and
	with real multi-touch the joystick can be held while the other hand
	rotates the camera.
]]

local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local Create = require(script.Parent.Create)
local Components = require(script.Parent.Components)
local Maid = require(script.Parent.Parent.Util.Maid)
local Signal = require(script.Parent.Parent.Util.Signal)

local Color = Theme.Color
local Font = Theme.Font

local BASE = 136 -- joystick diameter
local KNOB = 56
local RAIL_WIDTH = 56
local RAIL_KNOB = 44
local GAP = 14
local LABEL_HEIGHT = 20
local DEAD_ZONE = 0.08

local STICK_RADIUS = (BASE - KNOB) / 2
local RAIL_TRAVEL = (BASE - RAIL_KNOB) / 2

local function toVector2(position: Vector3): Vector2
	return Vector2.new(position.X, position.Y)
end

local function isPointer(input: InputObject): boolean
	local inputType = input.UserInputType
	return inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch
end

-- Glassy rounded surface shared by the joystick base and the slider.
local function surface(size: UDim2, position: UDim2): Frame
	return Create("Frame", {
		Position = position,
		Size = size,
		BackgroundColor3 = Color.Background,
		BackgroundTransparency = 0.22,
		ZIndex = 2,
	}, {
		Create.round(),
		Stroke = Create.stroke(Color.White, 0.84, 1.5),
	})
end

-- A gradient knob with a soft shadow, wrapped in a holder that moves as one.
local function knob(size: number): (Frame, UIScale)
	local scale = Create("UIScale", { Scale = 1 })
	local holder = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, {
		Scale = scale,
		Shadow = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 3),
			Size = UDim2.new(1, 8, 1, 8),
			BackgroundColor3 = Color.Black,
			BackgroundTransparency = 0.75,
			ZIndex = 3,
		}, { Create.round() }),
		Knob = Create("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color.White,
			ZIndex = 4,
		}, {
			Create.round(),
			Create.accentGradient(45),
			Create.stroke(Color.White, 0.5, 2),
			Dot = Create.dot(10, Color.White),
		}),
	})
	holder.Knob.Dot.ZIndex = 5
	holder.Name = "Knob"
	return holder, scale
end

local function hint(glyph: GuiObject, position: UDim2, rotation: number?): GuiObject
	glyph.Position = position
	glyph.Rotation = rotation or 0
	glyph.ZIndex = 3
	for _, part in glyph:GetDescendants() do
		if part:IsA("Frame") then
			part.BackgroundTransparency = 0.45
			part.ZIndex = 3
		end
	end
	return glyph
end

local function plusMinus(plus: boolean, position: UDim2): Frame
	local bar = function(width: number, height: number)
		return Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(width, height),
			BackgroundColor3 = Color.Text,
			BackgroundTransparency = 0.45,
			ZIndex = 3,
		}, { Create.round() })
	end
	return Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(14, 14),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, {
		H = bar(12, 2),
		V = if plus then bar(2, 12) else nil,
	})
end

local function caption(text: string, position: UDim2, width: number): TextLabel
	return Create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = position,
		Size = UDim2.fromOffset(width, LABEL_HEIGHT),
		Text = text,
		FontFace = Font.Bold,
		TextSize = 11,
		TextColor3 = Color.Text,
		TextTransparency = 0.25,
		TextStrokeTransparency = 0.55,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 2,
	})
end

local Navigator = {}
Navigator.__index = Navigator

export type Params = {
	parent: GuiBase2d,
	locale: any,
}

function Navigator.new(params: Params)
	local self = setmetatable({}, Navigator)
	self._maid = Maid.new()
	self._tracking = {} -- "stick" | "rail" -> { input, isTouch }
	self._springs = {} -- "stick" | "rail" -> the tween returning a knob to the middle
	self._pan = Vector2.zero
	self._zoom = 0

	self.PanBegan = Signal.new()
	self.ZoomBegan = Signal.new()

	local stick = surface(UDim2.fromOffset(BASE, BASE), UDim2.fromOffset(0, 0))
	stick.Name = "Stick"
	Create.ring(BASE - 44, Color.White, 0.88, 1).Parent = stick
	hint(Components.ChevronGlyph(), UDim2.new(0.5, 0, 0, 15)).Parent = stick
	hint(Components.ChevronGlyph(), UDim2.new(1, -15, 0.5, 0), 90).Parent = stick
	hint(Components.ChevronGlyph(), UDim2.new(0.5, 0, 1, -15), 180).Parent = stick
	hint(Components.ChevronGlyph(), UDim2.new(0, 15, 0.5, 0), -90).Parent = stick
	local stickKnob, stickScale = knob(KNOB)
	stickKnob.Parent = stick

	local rail = surface(UDim2.fromOffset(RAIL_WIDTH, BASE), UDim2.fromOffset(BASE + GAP, 0))
	rail.Name = "Rail"
	plusMinus(true, UDim2.new(0.5, 0, 0, 16)).Parent = rail
	plusMinus(false, UDim2.new(0.5, 0, 1, -16)).Parent = rail
	local railKnob, railScale = knob(RAIL_KNOB)
	railKnob.Parent = rail

	local root = Create("Frame", {
		Name = "TouchPeakNavigator",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 22, 1, -18),
		Size = UDim2.fromOffset(BASE + GAP + RAIL_WIDTH, BASE + LABEL_HEIGHT),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 9,
	}, {
		Stick = stick,
		Rail = rail,
		PanLabel = caption(params.locale:t("navPan"), UDim2.new(0, BASE / 2, 0, BASE + 2), BASE),
		ZoomLabel = caption(
			params.locale:t("navZoom"),
			UDim2.new(0, BASE + GAP + RAIL_WIDTH / 2, 0, BASE + 2),
			RAIL_WIDTH + GAP
		),
	})

	self._root = root
	self._stick = stick
	self._rail = rail
	self._knobs = { stick = stickKnob, rail = railKnob }
	self._scales = { stick = stickScale, rail = railScale }
	self._surfaces = { stick = stick, rail = rail }

	self:_bind("stick", stick)
	self:_bind("rail", rail)

	self._maid:Give(UserInputService.InputChanged:Connect(function(input)
		for kind, track in self._tracking do
			if
				(track.isTouch and input == track.input)
				or (not track.isTouch and input.UserInputType == Enum.UserInputType.MouseMovement)
			then
				self:_move(kind, toVector2(input.Position))
			end
		end
	end))
	self._maid:Give(UserInputService.InputEnded:Connect(function(input)
		for kind, track in self._tracking do
			if
				(track.isTouch and input == track.input)
				or (not track.isTouch and input.UserInputType == Enum.UserInputType.MouseButton1)
			then
				self:_release(kind)
			end
		end
	end))

	root.Parent = params.parent
	self._maid:Give(root)
	return self
end

function Navigator:_bind(kind: string, frame: GuiObject)
	self._maid:Give(frame.InputBegan:Connect(function(input)
		if not isPointer(input) or self._tracking[kind] then
			return
		end
		local isTouch = input.UserInputType == Enum.UserInputType.Touch
		if not isTouch then
			-- A mouse is one pointer: it can only hold one control at a time.
			for _, track in self._tracking do
				if not track.isTouch then
					return
				end
			end
		end
		self._tracking[kind] = { input = input, isTouch = isTouch }
		local spring = self._springs[kind]
		if spring then
			spring:Cancel()
		end
		Create.tween(self._scales[kind], Theme.Tween.Fast, { Scale = 1.08 })
		Create.tween(self._surfaces[kind].Stroke, Theme.Tween.Fast, { Transparency = 0.55 })
		if kind == "stick" then
			self.PanBegan:Fire()
		else
			self.ZoomBegan:Fire()
		end
		self:_move(kind, toVector2(input.Position))
	end))
end

function Navigator:_move(kind: string, position: Vector2)
	if kind == "stick" then
		local center = self._stick.AbsolutePosition + self._stick.AbsoluteSize / 2
		local offset = position - center
		if offset.Magnitude > STICK_RADIUS then
			offset = offset.Unit * STICK_RADIUS
		end
		self._knobs.stick.Position = UDim2.new(0.5, offset.X, 0.5, offset.Y)
		local value = offset / STICK_RADIUS
		self._pan = if value.Magnitude < DEAD_ZONE then Vector2.zero else value
	else
		local centerY = self._rail.AbsolutePosition.Y + self._rail.AbsoluteSize.Y / 2
		local offset = math.clamp(position.Y - centerY, -RAIL_TRAVEL, RAIL_TRAVEL)
		self._knobs.rail.Position = UDim2.new(0.5, 0, 0.5, offset)
		local value = -offset / RAIL_TRAVEL
		self._zoom = if math.abs(value) < DEAD_ZONE then 0 else value
	end
end

function Navigator:_release(kind: string)
	if not self._tracking[kind] then
		return
	end
	self._tracking[kind] = nil
	if kind == "stick" then
		self._pan = Vector2.zero
	else
		self._zoom = 0
	end
	self._springs[kind] = Create.tween(self._knobs[kind], Theme.Tween.Spring, { Position = UDim2.fromScale(0.5, 0.5) })
	Create.tween(self._scales[kind], Theme.Tween.Smooth, { Scale = 1 })
	Create.tween(self._surfaces[kind].Stroke, Theme.Tween.Smooth, { Transparency = 0.84 })
end

-- Joystick deflection in screen space (X right, Y down), length 0..1.
function Navigator:GetPan(): Vector2
	return self._pan
end

-- Slider deflection: positive zooms in, negative zooms out.
function Navigator:GetZoom(): number
	return self._zoom
end

function Navigator:IsHeld(): boolean
	return next(self._tracking) ~= nil
end

-- Call every frame: lets go of controls whose mouse release Studio never reported.
function Navigator:Step()
	for kind, track in self._tracking do
		if not track.isTouch then
			local ok, pressed = pcall(function()
				return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
			end)
			if ok and pressed == false then
				self:_release(kind)
			end
		end
	end
end

function Navigator:SetVisible(visible: boolean)
	self._root.Visible = visible
	if not visible then
		for kind in self._tracking do
			self:_release(kind)
		end
	end
end

function Navigator:IsVisible(): boolean
	return self._root.Visible
end

-- True when a screen point lies on the joystick or the slider.
function Navigator:ContainsPoint(point: Vector2): boolean
	if not self._root.Visible then
		return false
	end
	local margin = 8
	for _, frame in { self._stick, self._rail } do
		local position, size = frame.AbsolutePosition, frame.AbsoluteSize
		if
			point.X >= position.X - margin
			and point.X <= position.X + size.X + margin
			and point.Y >= position.Y - margin
			and point.Y <= position.Y + size.Y + margin
		then
			return true
		end
	end
	return false
end

function Navigator:Destroy()
	self._tracking = {}
	self._maid:Clean()
end

return Navigator
