--[[
	Reusable, touch friendly controls. Each constructor returns a table with
	`instance` plus a `set` function to update it from code.
]]

local Theme = require(script.Parent.Theme)
local Create = require(script.Parent.Create)

local Color = Theme.Color
local Font = Theme.Font

local Components = {}

-- Hover (mouse) and press (mouse or touch) feedback for a button's background.
function Components.pressable(button: GuiButton, restTransparency: number, hoverTransparency: number)
	local hovering = false
	local function refresh(pressed: boolean?)
		local goal = if pressed
			then hoverTransparency - 0.04
			elseif hovering then hoverTransparency
			else restTransparency
		Create.tween(button, Theme.Tween.Fast, { BackgroundTransparency = goal })
	end
	button.MouseEnter:Connect(function()
		hovering = true
		refresh()
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		refresh()
	end)
	button.InputBegan:Connect(function(input)
		local inputType = input.UserInputType
		if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch then
			refresh(true)
		end
	end)
	button.InputEnded:Connect(function(input)
		local inputType = input.UserInputType
		if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch then
			if inputType == Enum.UserInputType.Touch then
				hovering = false
			end
			refresh()
		end
	end)
end

-- Small square button with a vector glyph inside (built from frames, no images needed).
function Components.IconButton(props: { glyph: GuiObject, onActivated: () -> () })
	local button = Create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(34, 34),
		BackgroundColor3 = Color.White,
		BackgroundTransparency = 0.95,
		ZIndex = 3,
	}, {
		Create.corner(10),
		Glyph = props.glyph,
	})
	Components.pressable(button, 0.95, 0.86)
	button.Activated:Connect(props.onActivated)
	return { instance = button }
end

local function bar(width: number, height: number, rotation: number, position: UDim2?): Frame
	return Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position or UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(width, height),
		Rotation = rotation,
		BackgroundColor3 = Color.Text,
	}, { Create.round() })
end

function Components.CloseGlyph(): Frame
	return Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(16, 16),
		BackgroundTransparency = 1,
	}, {
		A = bar(14, 2, 45),
		B = bar(14, 2, -45),
	})
end

-- An upward chevron; rotate the returned frame 180 degrees to point it down.
function Components.ChevronGlyph(): Frame
	return Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(16, 16),
		BackgroundTransparency = 1,
	}, {
		Left = bar(9, 2, -45, UDim2.new(0.5, -3, 0.5, 0)),
		Right = bar(9, 2, 45, UDim2.new(0.5, 3, 0.5, 0)),
	})
end

function Components.Toggle(props: { value: boolean, onChanged: (boolean) -> () })
	local value = props.value

	local fill = Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color.White,
		BackgroundTransparency = if value then 0 else 1,
	}, {
		Create.round(),
		Create.accentGradient(),
	})

	local knob = Create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, if value then 23 else 3, 0.5, 0),
		Size = UDim2.fromOffset(20, 20),
		BackgroundColor3 = Color.White,
		ZIndex = 2,
	}, { Create.round() })

	local track = Create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(46, 26),
		BackgroundColor3 = Color.SurfaceHover,
		BackgroundTransparency = 0,
	}, {
		Create.round(),
		Fill = fill,
		Knob = knob,
	})

	local api = { instance = track }

	function api.set(newValue: boolean, instant: boolean?)
		value = newValue
		local info = if instant then nil else Theme.Tween.Smooth
		Create.animate(fill, info, { BackgroundTransparency = if value then 0 else 1 })
		Create.animate(knob, info, { Position = UDim2.new(0, if value then 23 else 3, 0.5, 0) })
	end

	track.Activated:Connect(function()
		api.set(not value)
		props.onChanged(value)
	end)

	return api
end

local function formatMultiplier(value: number): string
	local text = string.format("%.2f", value)
	text = string.gsub(text, "0$", "")
	return text .. "×"
end

function Components.Stepper(props: {
	value: number,
	min: number,
	max: number,
	step: number,
	onChanged: (number) -> (),
})
	local value = props.value

	local function stepButton(isPlus: boolean, position: UDim2, anchor: Vector2)
		local glyph = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(12, 12),
			BackgroundTransparency = 1,
		}, {
			H = bar(11, 2, 0),
			V = if isPlus then bar(2, 11, 0) else nil,
		})
		local button = Create("TextButton", {
			AnchorPoint = anchor,
			Position = position,
			Size = UDim2.fromOffset(30, 30),
			BackgroundColor3 = Color.White,
			BackgroundTransparency = 0.96,
		}, {
			Create.corner(9),
			Glyph = glyph,
		})
		Components.pressable(button, 0.96, 0.88)
		return button
	end

	local label = Create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -64, 1, 0),
		FontFace = Font.Bold,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = formatMultiplier(value),
	})

	local minus = stepButton(false, UDim2.fromScale(0, 0.5), Vector2.new(0, 0.5))
	local plus = stepButton(true, UDim2.fromScale(1, 0.5), Vector2.new(1, 0.5))

	local container = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(112, 30),
		BackgroundColor3 = Color.SurfaceHigh,
	}, {
		Create.corner(9),
		Minus = minus,
		Plus = plus,
		Value = label,
	})

	local api = { instance = container }

	function api.set(newValue: number)
		value = math.clamp(newValue, props.min, props.max)
		label.Text = formatMultiplier(value)
		minus.Glyph.H.BackgroundTransparency = if value <= props.min then 0.7 else 0
		plus.Glyph.H.BackgroundTransparency = if value >= props.max then 0.7 else 0
		plus.Glyph.V.BackgroundTransparency = if value >= props.max then 0.7 else 0
	end

	local function change(direction: number)
		local newValue = math.clamp(value + direction * props.step, props.min, props.max)
		-- Avoid floating point drift (0.1 + 0.2 ...).
		newValue = math.round(newValue / props.step) * props.step
		if newValue ~= value then
			api.set(newValue)
			props.onChanged(value)
		end
	end

	minus.Activated:Connect(function()
		change(-1)
	end)
	plus.Activated:Connect(function()
		change(1)
	end)

	api.set(value)
	return api
end

-- Pill-shaped segmented control with a sliding gradient highlight.
function Components.Segmented(props: {
	options: { { id: string, label: string } },
	value: string,
	onChanged: (string) -> (),
	size: UDim2?,
	textSize: number?,
})
	local count = #props.options
	local value = props.value

	local highlight = Create("Frame", {
		Size = UDim2.new(1 / count, -4, 1, -4),
		BackgroundColor3 = Color.White,
	}, {
		Create.corner(8),
		Create.accentGradient(),
	})

	local container = Create("Frame", {
		Size = props.size or UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = Color.SurfaceHigh,
	}, {
		Create.corner(10),
		Highlight = highlight,
	})

	local api = { instance = container }
	local buttons = {}

	function api.set(id: string, instant: boolean?)
		local entry = buttons[id]
		if not entry then
			return
		end
		value = id
		local info = if instant then nil else Theme.Tween.Smooth
		Create.animate(highlight, info, {
			Position = UDim2.new((entry.index - 1) / count, 2, 0, 2),
		})
		for optionId, other in buttons do
			Create.animate(other.button, info, {
				TextColor3 = if optionId == id then Color.White else Color.TextDim,
			})
		end
	end

	for index, option in props.options do
		local button = Create("TextButton", {
			Position = UDim2.fromScale((index - 1) / count, 0),
			Size = UDim2.fromScale(1 / count, 1),
			Text = option.label,
			FontFace = Font.Bold,
			TextSize = props.textSize or 14,
			TextColor3 = Color.TextDim,
			ZIndex = 2,
			Parent = container,
		})
		buttons[option.id] = { button = button, index = index }
		button.Activated:Connect(function()
			if value ~= option.id then
				api.set(option.id)
				props.onChanged(option.id)
			end
		end)
	end

	api.set(value, true)
	return api
end

function Components.SectionLabel(text: string, layoutOrder: number): TextLabel
	return Create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 26),
		Text = text,
		FontFace = Font.Bold,
		TextSize = 11,
		TextColor3 = Color.TextFaint,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		LayoutOrder = layoutOrder,
	}, {
		Create.padding(0, 4, 4, 4),
	})
end

-- A card with a title, optional hint and a control on the right.
function Components.Row(props: {
	title: string,
	hint: string?,
	control: GuiObject?,
	controlWidth: number?,
	layoutOrder: number,
})
	local hasHint = props.hint ~= nil
	local reserved = (props.controlWidth or 0) + 10

	local row = Create("Frame", {
		Size = UDim2.new(1, 0, 0, if hasHint then 54 else 44),
		BackgroundColor3 = Color.Surface,
		LayoutOrder = props.layoutOrder,
	}, {
		Create.corner(12),
		Create.stroke(Color.White, 0.95),
		Create.padding(0, 12),
		Title = Create("TextLabel", {
			Position = UDim2.fromOffset(0, if hasHint then 9 else 0),
			Size = UDim2.new(1, -reserved, 0, if hasHint then 20 else 44),
			Text = props.title,
			FontFace = Font.SemiBold,
			TextSize = 14,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		Hint = if hasHint
			then Create("TextLabel", {
				Position = UDim2.fromOffset(0, 29),
				Size = UDim2.new(1, -reserved, 0, 16),
				Text = props.hint,
				FontFace = Font.Regular,
				TextSize = 12,
				TextColor3 = Color.TextDim,
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			else nil,
	})

	if props.control then
		props.control.AnchorPoint = Vector2.new(1, 0.5)
		props.control.Position = UDim2.fromScale(1, 0.5)
		props.control.Parent = row
	end

	return row
end

-- Wide secondary button.
function Components.Button(props: { text: string, layoutOrder: number, onActivated: () -> () })
	local button = Create("TextButton", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Color.White,
		BackgroundTransparency = 0.95,
		Text = props.text,
		FontFace = Font.SemiBold,
		TextSize = 14,
		TextColor3 = Color.Text,
		LayoutOrder = props.layoutOrder,
	}, {
		Create.corner(12),
		Create.stroke(Color.White, 0.9),
	})
	Components.pressable(button, 0.95, 0.88)
	button.Activated:Connect(props.onActivated)
	return { instance = button }
end

-- Small rounded label used for live readouts ("Fingers 2").
function Components.Chip(layoutOrder: number)
	local label = Create("TextLabel", {
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Color.SurfaceHigh,
		BackgroundTransparency = 0,
		FontFace = Font.Medium,
		TextSize = 12,
		TextColor3 = Color.TextDim,
		RichText = true,
		LayoutOrder = layoutOrder,
	}, {
		Create.corner(7),
		Create.padding(0, 8),
	})
	return label
end

return Components
