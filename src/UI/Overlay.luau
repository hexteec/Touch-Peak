--[[
	Viewport feedback drawn on top of the 3D view:
	  * a thin ring under each finger, tinted with the colour of the camera
	    move it is driving (and a line joining two fingers),
	  * a ring that expands where you tap,
	  * a tag at the bottom naming the move in progress,
	  * short notes at the top ("Selected: Part").
]]

local Theme = require(script.Parent.Theme)
local Create = require(script.Parent.Create)
local Maid = require(script.Parent.Parent.Util.Maid)

local Color = Theme.Color
local Font = Theme.Font

local TOUCH_SIZE = 46
local NOTE_TIME = 1.6

local Overlay = {}
Overlay.__index = Overlay

-- A small dark tag with a coloured notch on its left edge; fades in and out.
local function makeTag(parent: Instance, anchor: Vector2, position: UDim2)
	local notch = Create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -9, 0.5, 0),
		Size = UDim2.new(0, 3, 1, -12),
		BackgroundColor3 = Color.Bone,
		BackgroundTransparency = 1,
	}, { Create.round() })

	local label = Create("TextLabel", {
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		FontFace = Font.Medium,
		TextSize = 14,
		TextTransparency = 1,
	})

	local tag = Create("Frame", {
		AnchorPoint = anchor,
		Position = position,
		Size = UDim2.fromOffset(0, 32),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Color.Graphite,
		BackgroundTransparency = 1,
		Visible = false,
		Parent = parent,
	}, {
		Create.corner(Theme.Radius.Tag),
		Create.padding(0, 12, 0, 19),
		Notch = notch,
		Label = label,
	})

	local api = {}
	local token = 0

	function api.show(text: string, color: Color3?)
		token += 1
		label.Text = text
		notch.BackgroundColor3 = color or Color.Bone
		tag.Visible = true
		Create.tween(tag, Theme.Tween.Fast, { BackgroundTransparency = 0.04 })
		Create.tween(label, Theme.Tween.Fast, { TextTransparency = 0 })
		Create.tween(notch, Theme.Tween.Fast, { BackgroundTransparency = 0 })
	end

	function api.hide()
		token += 1
		local myToken = token
		Create.tween(tag, Theme.Tween.Smooth, { BackgroundTransparency = 1 })
		Create.tween(label, Theme.Tween.Smooth, { TextTransparency = 1 })
		Create.tween(notch, Theme.Tween.Smooth, { BackgroundTransparency = 1 })
		task.delay(Theme.Tween.Smooth.Time, function()
			if token == myToken then
				tag.Visible = false
			end
		end)
	end

	function api.flash(text: string, color: Color3?, duration: number)
		api.show(text, color)
		local myToken = token
		task.delay(duration, function()
			if token == myToken then
				api.hide()
			end
		end)
	end

	return api
end

function Overlay.new(parent: Instance, settings)
	local self = setmetatable({}, Overlay)
	self._settings = settings
	self._maid = Maid.new()
	self._touches = {} -- id -> { frame, position }
	self._touchColor = Color.Bone

	self._root = self._maid:Give(Create("Frame", {
		Name = "TouchPeakOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = parent,
	}))

	self._link = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(0, 1),
		BackgroundColor3 = Color.Bone,
		BackgroundTransparency = 0.45,
		Visible = false,
		Parent = self._root,
	})

	self._gestureTag = makeTag(self._root, Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -22))
	self._note = makeTag(self._root, Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 16))

	return self
end

-- Finger rings -----------------------------------------------------------------------

function Overlay:TouchBegan(id: any, position: Vector2)
	if not self._settings:Get("showTouches") or self._touches[id] then
		return
	end

	local scale = Create("UIScale", { Scale = 0.6 })
	local frame = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(position.X, position.Y),
		Size = UDim2.fromOffset(TOUCH_SIZE, TOUCH_SIZE),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = self._root,
	}, {
		Create.round(),
		Stroke = Create.stroke(self._touchColor, 0.1, 2),
		Core = Create.dot(6, Color.Bone),
		Scale = scale,
	})
	Create.tween(scale, Theme.Tween.Smooth, { Scale = 1 })

	self._touches[id] = { frame = frame, position = position }
	self:_updateLink()
end

function Overlay:TouchMoved(id: any, position: Vector2)
	local touch = self._touches[id]
	if not touch then
		return
	end
	touch.position = position
	touch.frame.Position = UDim2.fromOffset(position.X, position.Y)
	self:_updateLink()
end

function Overlay:TouchEnded(id: any)
	local touch = self._touches[id]
	if not touch then
		return
	end
	self._touches[id] = nil
	self:_updateLink()

	local frame = touch.frame
	Create.tween(frame.Scale, Theme.Tween.Smooth, { Scale = 1.25 })
	Create.tween(frame.Stroke, Theme.Tween.Smooth, { Transparency = 1 })
	Create.tween(frame.Core, Theme.Tween.Smooth, { BackgroundTransparency = 1 })
	task.delay(Theme.Tween.Smooth.Time, function()
		frame:Destroy()
	end)
end

function Overlay:_updateLink()
	local points = {}
	for _, touch in self._touches do
		table.insert(points, touch.position)
	end

	if #points ~= 2 then
		self._link.Visible = false
		return
	end

	local a, b = points[1], points[2]
	local offset = b - a
	local middle = (a + b) / 2
	self._link.Visible = true
	self._link.Position = UDim2.fromOffset(middle.X, middle.Y)
	self._link.Size = UDim2.fromOffset(offset.Magnitude, 1)
	self._link.Rotation = math.deg(math.atan2(offset.Y, offset.X))
end

-- A ring that expands where a tap landed.
function Overlay:Ripple(position: Vector2, color: Color3?)
	if not self._settings:Get("showTouches") then
		return
	end
	local ring = Create.ring(12, color or Color.Bone, 0.1, 1.5, UDim2.fromOffset(position.X, position.Y))
	ring.ZIndex = 2
	ring.Parent = self._root

	local info = TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	Create.tween(ring, info, { Size = UDim2.fromOffset(58, 58) })
	Create.tween(ring.Stroke, info, { Transparency = 1 })
	task.delay(info.Time, function()
		ring:Destroy()
	end)
end

-- Tags --------------------------------------------------------------------------------

-- Names the camera move in progress and tints the finger rings with its colour.
function Overlay:ShowGesture(text: string?, color: Color3?)
	self._touchColor = color or Color.Bone
	for _, touch in self._touches do
		Create.tween(touch.frame.Stroke, Theme.Tween.Fast, { Color = self._touchColor })
	end
	if text then
		self._gestureTag.show(text, color)
	else
		self._gestureTag.hide()
	end
end

function Overlay:Toast(text: string, color: Color3?)
	self._note.flash(text, color, NOTE_TIME)
end

function Overlay:HideToast()
	self._note.hide()
end

function Overlay:ClearTouches()
	for id in table.clone(self._touches) do
		self:TouchEnded(id)
	end
end

function Overlay:Destroy()
	self._touches = {}
	self._maid:Clean()
end

return Overlay
