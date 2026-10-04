--[[
	A vertical bar on the left edge of the viewport that picks what a
	one-finger drag does: rotate, pan or zoom.

	Studio usually reports a touch screen as a single mouse pointer, so this
	is how pan and zoom stay possible with one finger (or a pen / mouse).
]]

local Theme = require(script.Parent.Theme)
local Create = require(script.Parent.Create)
local Maid = require(script.Parent.Parent.Util.Maid)

local Color = Theme.Color
local Font = Theme.Font

local BUTTON_HEIGHT = 56
local PADDING = 7
local GAP = 6
local WIDTH = 66

local MODES = { "rotate", "pan", "zoom" }
local LABELS = { rotate = "modeRotate", pan = "modePan", zoom = "modeZoom" }

local function bar(width: number, height: number, position: UDim2, rotation: number?): Frame
	return Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(width, height),
		Rotation = rotation or 0,
		BackgroundColor3 = Color.TextDim,
	}, { Create.round() })
end

local function center(dx: number, dy: number): UDim2
	return UDim2.new(0.5, dx, 0.5, dy)
end

-- Icons are drawn with frames so they can be recoloured by `tint`.
local ICONS = {
	rotate = function(icon)
		Create.ring(18, Color.TextDim, 0, 2).Parent = icon
		bar(6, 6, center(0, -9)).Parent = icon
	end,
	pan = function(icon)
		bar(18, 2, center(0, 0)).Parent = icon
		bar(2, 18, center(0, 0)).Parent = icon
		for _, offset in { Vector2.new(0, -9), Vector2.new(0, 9), Vector2.new(-9, 0), Vector2.new(9, 0) } do
			bar(5, 5, center(offset.X, offset.Y)).Parent = icon
		end
	end,
	zoom = function(icon)
		Create.ring(14, Color.TextDim, 0, 2, center(-2, -2)).Parent = icon
		bar(6, 2, center(-2, -2)).Parent = icon
		bar(2, 6, center(-2, -2)).Parent = icon
		bar(7, 3, center(6, 6), 45).Parent = icon
	end,
}

local function tint(icon: Instance, color: Color3)
	for _, descendant in icon:GetDescendants() do
		if descendant:IsA("UIStroke") then
			descendant.Color = color
		elseif descendant:IsA("Frame") and descendant.BackgroundTransparency < 1 then
			descendant.BackgroundColor3 = color
		end
	end
end

local ModeBar = {}
ModeBar.__index = ModeBar

ModeBar.Modes = MODES

export type Params = {
	parent: GuiBase2d,
	locale: any,
	mode: string,
	onModeChanged: (string) -> (),
}

function ModeBar.new(params: Params)
	local self = setmetatable({}, ModeBar)
	self._params = params
	self._maid = Maid.new()
	self._buttons = {}
	self._mode = params.mode

	local height = PADDING * 2 + BUTTON_HEIGHT * #MODES + GAP * (#MODES - 1)

	local body = Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color.Background,
		BackgroundTransparency = 0.03,
		ZIndex = 2,
	}, {
		Create.corner(20),
		Create.stroke(Color.White, 0.87),
		Create.padding(PADDING),
		Create.list(GAP),
	})

	local root = Create("Frame", {
		Name = "TouchPeakModeBar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(WIDTH, height),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 9,
	}, {
		Body = body,
	})

	for index, layer in { { 4, 0.9 }, { 12, 0.95 } } do
		local spread, transparency = layer[1], layer[2]
		Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 2 + index),
			Size = UDim2.new(1, spread, 1, spread),
			BackgroundColor3 = Color.Black,
			BackgroundTransparency = transparency,
			ZIndex = 1,
			Parent = root,
		}, { Create.corner(20 + spread / 2) })
	end

	for index, mode in MODES do
		local icon = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 9),
			Size = UDim2.fromOffset(24, 24),
			BackgroundTransparency = 1,
			ZIndex = 2,
		})
		ICONS[mode](icon)

		local fill = Create("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color.White,
			BackgroundTransparency = 1,
		}, {
			Create.corner(14),
			Create.accentGradient(90),
		})

		local label = Create("TextLabel", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, -6),
			Size = UDim2.new(1, 0, 0, 12),
			Text = params.locale:t(LABELS[mode]),
			FontFace = Font.Bold,
			TextSize = 11,
			TextColor3 = Color.TextDim,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 2,
		})

		local button = Create("TextButton", {
			Name = mode,
			Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT),
			LayoutOrder = index,
		}, {
			Fill = fill,
			Icon = icon,
			Label = label,
		})
		button.Parent = body

		self._maid:Give(button.Activated:Connect(function()
			if self._mode ~= mode then
				self:SetMode(mode)
				params.onModeChanged(mode)
			end
		end))

		self._buttons[mode] = { button = button, fill = fill, icon = icon, label = label }
	end

	root.Parent = params.parent
	self._maid:Give(root)
	self._root = root
	self._body = body

	self:SetMode(params.mode, true)
	return self
end

function ModeBar:GetMode(): string
	return self._mode
end

function ModeBar:SetMode(mode: string, instant: boolean?)
	if not self._buttons[mode] then
		return
	end
	self._mode = mode
	local info = if instant then nil else Theme.Tween.Fast
	for name, entry in self._buttons do
		local selected = name == mode
		Create.animate(entry.fill, info, { BackgroundTransparency = if selected then 0 else 1 })
		Create.animate(entry.label, info, { TextColor3 = if selected then Color.White else Color.TextDim })
		tint(entry.icon, if selected then Color.White else Color.TextDim)
	end
end

function ModeBar:SetVisible(visible: boolean)
	self._root.Visible = visible
end

function ModeBar:IsVisible(): boolean
	return self._root.Visible
end

-- True when a screen point lies on the bar (so it should not move the camera).
function ModeBar:ContainsPoint(point: Vector2): boolean
	if not self._root.Visible then
		return false
	end
	local position = self._body.AbsolutePosition
	local size = self._body.AbsoluteSize
	local margin = 6
	return point.X >= position.X - margin
		and point.X <= position.X + size.X + margin
		and point.Y >= position.Y - margin
		and point.Y <= position.Y + size.Y + margin
end

function ModeBar:Destroy()
	self._maid:Clean()
end

return ModeBar
