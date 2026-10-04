local FONT_FAMILY = "rbxasset://fonts/families/BuilderSans.json"

local Theme = {}

Theme.Font = {
	Regular = Font.new(FONT_FAMILY, Enum.FontWeight.Regular),
	Medium = Font.new(FONT_FAMILY, Enum.FontWeight.Medium),
	SemiBold = Font.new(FONT_FAMILY, Enum.FontWeight.SemiBold),
	Bold = Font.new(FONT_FAMILY, Enum.FontWeight.Bold),
	ExtraBold = Font.new(FONT_FAMILY, Enum.FontWeight.ExtraBold),
}

Theme.Color = {
	Background = Color3.fromRGB(15, 17, 24),
	Surface = Color3.fromRGB(23, 26, 36),
	SurfaceHigh = Color3.fromRGB(32, 36, 49),
	SurfaceHover = Color3.fromRGB(44, 49, 66),
	White = Color3.fromRGB(255, 255, 255),
	Black = Color3.fromRGB(0, 0, 0),
	Text = Color3.fromRGB(238, 241, 249),
	TextDim = Color3.fromRGB(150, 158, 182),
	TextFaint = Color3.fromRGB(96, 104, 128),
	Accent = Color3.fromRGB(0, 198, 255),
	AccentAlt = Color3.fromRGB(132, 92, 255),
	Success = Color3.fromRGB(56, 222, 138),
	Warning = Color3.fromRGB(255, 188, 56),
	Danger = Color3.fromRGB(255, 94, 116),
}

Theme.AccentGradient = ColorSequence.new(Theme.Color.Accent, Theme.Color.AccentAlt)

Theme.Tween = {
	Fast = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Smooth = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	Spring = TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	Close = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
}

Theme.Size = {
	PanelWidth = 324,
	PanelHeight = 640,
	CollapsedWidth = 264,
	Header = 62,
	Padding = 14,
	ScreenMargin = 10,
}

return Theme
