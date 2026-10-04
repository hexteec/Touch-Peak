--[[
	Viewport feedback drawn on top of the 3D view:
	  * glowing circles under each finger (and a line joining two fingers),
	  * a ripple where you tap,
	  * a pill at the bottom naming the current gesture,
	  * short toasts at the top ("Selected: Part").
]]

local Theme = require(script.Parent.Theme)
local Create = require(script.Parent.Create)
local Maid = require(script.Parent.Parent.Util.Maid)

local Color = Theme.Color
local Font = Theme.Font

local TOUCH_SIZE = 58
local TOAST_TIME = 1.6

local Overlay = {}
Overlay.__index = Overlay

-- A pill with a coloured dot and a label that can fade in and out.
local function makePill(parent: Instance, anchor: Vector2, position: UDim2)
	local dot = Create.dot(8, Color.Accent, UDim2.new(0, 0, 0.5, 0))
	dot.AnchorPoint = Vector2.new(0, 0.5)
	dot.BackgroundTransparency = 1

	local label = Create("TextLabel", {
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		FontFace = Font.SemiBold,
		TextSize = 14,
		TextTransparency = 1,
	})

	local stroke = Create.stroke(Color.White, 1)
	local scale = Create("UIScale", { Scale = 0.9 })

	local pill = Create("Frame", {
		AnchorPoint = anchor,
		Position = position,
		Size = UDim2.fromOffset(0, 38),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Color.Background,
		BackgroundTransparency = 1,
		Visible = false,
		Parent = parent,
	}, {
		Create.round(),
		Create.padding(0, 16),
		Stroke = stroke,
		Scale = scale,
		Content = Create("Frame", {
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
		}, {
			Dot = dot,
			Label = label,
		}),
	})

	local api = {}
	local token = 0

	function api.show(text: string, color: Color3?)
		token += 1
		label.Text = text
		dot.BackgroundColor3 = color or Color.Accent
		pill.Visible = true
		Create.tween(pill, Theme.Tween.Fast, { BackgroundTransparency = 0.08 })
		Create.tween(stroke, Theme.Tween.Fast, { Transparency = 0.85 })
		Create.tween(label, Theme.Tween.Fast, { TextTransparency = 0 })
		Create.tween(dot, Theme.Tween.Fast, { BackgroundTransparency = 0 })
		Create.tween(scale, Theme.Tween.Spring, { Scale = 1 })
	end

	function api.hide()
		token += 1
		local myToken = token
		Create.tween(pill, Theme.Tween.Smooth, { BackgroundTransparency = 1 })
		Create.tween(stroke, Theme.Tween.Smooth, { Transparency = 1 })
		Create.tween(label, Theme.Tween.Smooth, { TextTransparency = 1 })
		Create.tween(dot, Theme.Tween.Smooth, { BackgroundTransparency = 1 })
		Create.tween(scale, Theme.Tween.Smooth, { Scale = 0.9 })
		task.delay(Theme.Tween.Smooth.Time, function()
			if token == myToken then
				pill.Visible = false
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

	self._root = self._maid:Give(Create("Frame", {
		Name = "TouchPeakOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = parent,
	}))

	self._link = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(0, 3),
		BackgroundColor3 = Color.White,
		BackgroundTransparency = 0.35,
		Visible = false,
		Parent = self._root,
	}, {
		Create.round(),
		Create.accentGradient(),
	})

	self._gesturePill = makePill(self._root, Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -26))
	self._toast = makePill(self._root, Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 18))

	return self
end

-- Finger circles -----------------------------------------------------------------

function Overlay:TouchBegan(id: any, position: Vector2)
	if not self._settings:Get("showTouches") or self._touches[id] then
		return
	end

	local scale = Create("UIScale", { Scale = 0.4 })
	local frame = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(position.X, position.Y),
		Size = UDim2.fromOffset(TOUCH_SIZE, TOUCH_SIZE),
		BackgroundColor3 = Color.Accent,
		BackgroundTransparency = 0.82,
		ZIndex = 2,
		Parent = self._root,
	}, {
		Create.round(),
		Stroke = Create.stroke(Color.Accent, 0.1, 2),
		Core = Create.dot(14, Color.White),
		Scale = scale,
	})
	Create.tween(scale, Theme.Tween.Spring, { Scale = 1 })

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
	Create.tween(frame.Scale, Theme.Tween.Smooth, { Scale = 1.35 })
	Create.tween(frame, Theme.Tween.Smooth, { BackgroundTransparency = 1 })
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
	self._link.Size = UDim2.fromOffset(offset.Magnitude, 3)
	self._link.Rotation = math.deg(math.atan2(offset.Y, offset.X))
end

-- Expanding ring where a tap landed.
function Overlay:Ripple(position: Vector2, color: Color3?)
	if not self._settings:Get("showTouches") then
		return
	end
	local ring = Create.ring(16, color or Color.Accent, 0, 3, UDim2.fromOffset(position.X, position.Y))
	ring.ZIndex = 2
	ring.Parent = self._root

	local info = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	Create.tween(ring, info, { Size = UDim2.fromOffset(76, 76) })
	Create.tween(ring.Stroke, info, { Transparency = 1 })
	task.delay(info.Time, function()
		ring:Destroy()
	end)
end

-- Feedback pills -----------------------------------------------------------------

function Overlay:ShowGesture(text: string?)
	if text then
		self._gesturePill.show(text, Color.Accent)
	else
		self._gesturePill.hide()
	end
end

function Overlay:Toast(text: string, color: Color3?)
	self._toast.flash(text, color, TOAST_TIME)
end

function Overlay:HideToast()
	self._toast.hide()
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
