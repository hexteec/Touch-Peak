--[[
	Visual language: Roblox Studio's transform gizmo.

	Colour carries meaning and nothing else. The three camera moves use the
	colours of Studio's axis handles (rotate around Y = green, pan = X red,
	zoom along Z = blue); everything else is graphite and bone white.
]]

local UI_FAMILY = "rbxasset://fonts/families/BuilderSans.json"
local WORDMARK_FAMILY = "rbxasset://fonts/families/Michroma.json"

local Theme = {}

Theme.Font = {
	Regular = Font.new(UI_FAMILY, Enum.FontWeight.Regular),
	Medium = Font.new(UI_FAMILY, Enum.FontWeight.Medium),
	SemiBold = Font.new(UI_FAMILY, Enum.FontWeight.SemiBold),
	Bold = Font.new(UI_FAMILY, Enum.FontWeight.Bold),
	Wordmark = Font.new(WORDMARK_FAMILY, Enum.FontWeight.Regular),
}

Theme.Color = {
	Graphite = Color3.fromRGB(35, 37, 39), -- panel body
	Well = Color3.fromRGB(26, 27, 29), -- recessed tracks
	Ridge = Color3.fromRGB(52, 55, 59), -- raised parts
	Bone = Color3.fromRGB(236, 232, 223), -- text, knobs, "on"
	Ash = Color3.fromRGB(143, 141, 134), -- secondary text
	Dim = Color3.fromRGB(96, 95, 91), -- disabled, ticks
	Black = Color3.fromRGB(0, 0, 0),

	Red = Color3.fromRGB(239, 83, 80), -- pan (X)
	Green = Color3.fromRGB(92, 201, 122), -- rotate (Y), "on"
	Blue = Color3.fromRGB(76, 141, 246), -- zoom (Z)
	Amber = Color3.fromRGB(233, 180, 76), -- paused
}

-- Colour of each camera move, as reported by the gesture recognizer.
Theme.GestureColor = {
	rotate = Theme.Color.Green,
	pan = Theme.Color.Red,
	zoom = Theme.Color.Blue,
	both = Theme.Color.Bone,
}

Theme.Tween = {
	Fast = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Smooth = TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
	Close = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
}

Theme.Radius = {
	Panel = 14,
	Control = 8,
	Tag = 6,
}

Theme.Size = {
	PanelWidth = 312,
	PanelHeight = 500,
	CollapsedWidth = 232,
	Header = 46,
	Status = 34,
	Tabs = 40,
	Inset = 16,
	ScreenMargin = 10,
}

return Theme
