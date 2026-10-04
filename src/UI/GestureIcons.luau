--[[
	Small animated illustrations of each gesture, drawn with frames only.

	Every builder returns the icon frame and a list of looping tweens. The
	tweens are created paused; the panel plays them only while visible.
]]

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local Create = require(script.Parent.Create)

local Color = Theme.Color

local FINGER = 9 -- finger dot size

-- A tween that repeats forever (optionally bouncing back and forth).
local function loop(instance: Instance, duration: number, goal, style: Enum.EasingStyle?, reverses: boolean?): Tween
	local info =
		TweenInfo.new(duration, style or Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, reverses == true)
	return TweenService:Create(instance, info, goal)
end

local function canvas(): Frame
	return Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})
end

local function finger(position: UDim2?): Frame
	return Create.dot(FINGER, Color.Accent, position)
end

local function ghost(position: UDim2): Frame
	local dot = Create.dot(FINGER, Color.White, position)
	dot.BackgroundTransparency = 0.82
	return dot
end

local Icons = {}

-- One finger orbiting around a faint circle.
function Icons.rotate()
	local spinner = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		Finger = finger(UDim2.new(0.5, 0, 0.5, -11)),
	})
	local icon = canvas()
	Create.ring(22, Color.White, 0.75, 1.5).Parent = icon
	spinner.Parent = icon

	local tweens = {
		loop(spinner, 2.4, { Rotation = 360 }, Enum.EasingStyle.Linear),
	}
	return icon, tweens
end

-- Two fingers moving apart and back together along a diagonal.
function Icons.zoom()
	local icon = canvas()
	Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(28, 2),
		Rotation = -45,
		BackgroundColor3 = Color.White,
		BackgroundTransparency = 0.8,
		Parent = icon,
	})
	local a = finger(UDim2.fromScale(0.4, 0.6))
	local b = finger(UDim2.fromScale(0.6, 0.4))
	a.Parent = icon
	b.Parent = icon

	local tweens = {
		loop(a, 0.9, { Position = UDim2.fromScale(0.22, 0.78) }, nil, true),
		loop(b, 0.9, { Position = UDim2.fromScale(0.78, 0.22) }, nil, true),
	}
	return icon, tweens
end

-- Two fingers sliding sideways together.
function Icons.pan()
	local icon = canvas()
	ghost(UDim2.fromScale(0.28, 0.36)).Parent = icon
	ghost(UDim2.fromScale(0.28, 0.64)).Parent = icon
	local a = finger(UDim2.fromScale(0.28, 0.36))
	local b = finger(UDim2.fromScale(0.28, 0.64))
	a.Parent = icon
	b.Parent = icon

	local tweens = {
		loop(a, 1.1, { Position = UDim2.fromScale(0.72, 0.36) }, Enum.EasingStyle.Quad, true),
		loop(b, 1.1, { Position = UDim2.fromScale(0.72, 0.64) }, Enum.EasingStyle.Quad, true),
	}
	return icon, tweens
end

local function rippleIcon(period: number, badge: string?)
	local icon = canvas()
	local ring = Create.ring(FINGER, Color.Accent, 0.1, 2)
	ring.Parent = icon
	finger().Parent = icon

	if badge then
		Create("TextLabel", {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, 1, 1, 2),
			Size = UDim2.fromOffset(18, 12),
			Text = badge,
			FontFace = Theme.Font.ExtraBold,
			TextSize = 11,
			TextColor3 = Color.Text,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = icon,
		})
	end

	local info = TweenInfo.new(period, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1, false, 0.25)
	local tweens = {
		TweenService:Create(ring, info, { Size = UDim2.fromOffset(30, 30) }),
		TweenService:Create(ring.Stroke, info, { Transparency = 1 }),
	}
	return icon, tweens
end

-- A finger with a ripple spreading out.
function Icons.tap()
	return rippleIcon(0.9)
end

-- Faster ripple with a "2×" badge.
function Icons.doubleTap()
	return rippleIcon(0.5, "2×")
end

-- A finger pressing down while a ring fills in.
function Icons.longPress()
	local icon = canvas()
	local ring = Create.ring(26, Color.Accent, 0.9, 2)
	ring.Parent = icon
	local dot = finger()
	dot.Parent = icon
	local scale = Create("UIScale", { Parent = dot })

	local tweens = {
		loop(ring.Stroke, 1.1, { Transparency = 0.05 }, nil, true),
		loop(scale, 1.1, { Scale = 0.7 }, nil, true),
	}
	return icon, tweens
end

return Icons
