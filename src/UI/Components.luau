--[[
	Touch friendly controls in the plugin's monochrome style: recessed
	"wells" for tracks, raised "ridges" for whatever is selected, bone white
	for "on". Each constructor returns a table with `instance` plus a `set`
	function to update it from code.
]]

local TextService = game:GetService("TextService")

local Theme = require(script.Parent.Theme)
local Create = require(script.Parent.Create)

local Color = Theme.Color
local Font = Theme.Font
local Radius = Theme.Radius

local Components = {}

-- Width of a single line of Builder Sans Medium text.
local function textWidth(text: string, size: number): number
	local ok, bounds = pcall(function()
		return TextService:GetTextSize(text, size, Enum.Font.BuilderSansMedium, Vector2.new(1000, 100))
	end)
	if ok and typeof(bounds) == "Vector2" and bounds.X > 0 then
		return math.ceil(bounds.X)
	end
	return math.ceil((utf8.len(text) or #text) * size * 0.5)
end

local function isPointer(input: InputObject): boolean
	local inputType = input.UserInputType
	return inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch
end

-- Shows a button's background while hovered (mouse) or pressed (mouse or touch).
function Components.pressable(button: GuiButton, restTransparency: number, activeTransparency: number)
	local hovering = false
	local function refresh(pressed: boolean?)
		local goal = if pressed or hovering then activeTransparency else restTransparency
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
		if isPointer(input) then
			refresh(true)
		end
	end)
	button.InputEnded:Connect(function(input)
		if isPointer(input) then
			if input.UserInputType == Enum.UserInputType.Touch then
				hovering = false
			end
			refresh()
		end
	end)
end

local function bar(width: number, height: number, rotation: number?, position: UDim2?, color: Color3?): Frame
	return Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position or UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(width, height),
		Rotation = rotation or 0,
		BackgroundColor3 = color or Color.Ash,
	}, { Create.round() })
end
Components.bar = bar

local function glyphFrame(size: number, children): Frame
	return Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
	}, children)
end

function Components.CloseGlyph(): Frame
	return glyphFrame(14, {
		A = bar(13, 2, 45),
		B = bar(13, 2, -45),
	})
end

-- An upward chevron; rotate the returned frame 180 degrees to point it down.
function Components.ChevronGlyph(): Frame
	return glyphFrame(14, {
		Left = bar(8, 2, -45, UDim2.new(0.5, -2.5, 0.5, 0)),
		Right = bar(8, 2, 45, UDim2.new(0.5, 2.5, 0.5, 0)),
	})
end

-- A borderless square button that only shows a background when touched or hovered.
function Components.IconButton(props: { glyph: GuiObject, onActivated: () -> () })
	local button = Create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = Color.Ridge,
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, {
		Create.corner(Radius.Control),
		Glyph = props.glyph,
	})
	Components.pressable(button, 1, 0)
	button.Activated:Connect(props.onActivated)
	return { instance = button }
end

-- A slide switch. Off: knob in a dark well. On: the track fills with bone white.
function Components.Switch(props: { value: boolean, onChanged: (boolean) -> () })
	local value = props.value

	local knob = Create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = Color.Ash,
		ZIndex = 2,
	}, { Create.round() })

	local stroke = Create.stroke(Color.Bone, 0.86)
	local track = Create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(40, 22),
		BackgroundColor3 = Color.Well,
		BackgroundTransparency = 0,
	}, {
		Create.round(),
		Stroke = stroke,
		Knob = knob,
	})

	local api = { instance = track }

	function api.set(newValue: boolean, instant: boolean?)
		value = newValue
		local info = if instant then nil else Theme.Tween.Smooth
		Create.animate(track, info, { BackgroundColor3 = if value then Color.Bone else Color.Well })
		Create.animate(stroke, info, { Transparency = if value then 1 else 0.86 })
		Create.animate(knob, info, {
			Position = UDim2.new(0, if value then 21 else 3, 0.5, 0),
			BackgroundColor3 = if value then Color.Graphite else Color.Ash,
		})
	end

	track.Activated:Connect(function()
		api.set(not value)
		props.onChanged(value)
	end)

	api.set(value, true)
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

	local function stepButton(isPlus: boolean, anchor: Vector2, position: UDim2)
		local button = Create("TextButton", {
			AnchorPoint = anchor,
			Position = position,
			Size = UDim2.fromOffset(28, 28),
			BackgroundColor3 = Color.Ridge,
			BackgroundTransparency = 1,
		}, {
			Create.corner(Radius.Control),
			Glyph = glyphFrame(12, {
				H = bar(10, 2, 0, nil, Color.Bone),
				V = if isPlus then bar(2, 10, 0, nil, Color.Bone) else nil,
			}),
		})
		Components.pressable(button, 1, 0)
		return button
	end

	local minus = stepButton(false, Vector2.new(0, 0.5), UDim2.fromScale(0, 0.5))
	local plus = stepButton(true, Vector2.new(1, 0.5), UDim2.fromScale(1, 0.5))
	local label = Create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -56, 1, 0),
		FontFace = Font.SemiBold,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	local container = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(104, 28),
		BackgroundColor3 = Color.Well,
	}, {
		Create.corner(Radius.Control),
		Minus = minus,
		Plus = plus,
		Value = label,
	})

	local api = { instance = container }

	local function dim(button: GuiButton, disabled: boolean)
		for _, part in button.Glyph:GetChildren() do
			part.BackgroundColor3 = if disabled then Color.Dim else Color.Bone
		end
	end

	function api.set(newValue: number)
		value = math.clamp(newValue, props.min, props.max)
		label.Text = formatMultiplier(value)
		dim(minus, value <= props.min)
		dim(plus, value >= props.max)
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

-- A small choice control: the chosen option sits raised inside a dark well.
function Components.Segmented(props: {
	options: { { id: string, label: string } },
	value: string,
	onChanged: (string) -> (),
	width: number,
})
	local count = #props.options
	local value = props.value

	local highlight = Create("Frame", {
		Size = UDim2.new(1 / count, -4, 1, -4),
		BackgroundColor3 = Color.Ridge,
	}, { Create.corner(Radius.Control - 2) })

	local container = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(props.width, 28),
		BackgroundColor3 = Color.Well,
	}, {
		Create.corner(Radius.Control),
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
		Create.animate(highlight, info, { Position = UDim2.new((entry.index - 1) / count, 2, 0, 2) })
		for optionId, other in buttons do
			Create.animate(other.button, info, {
				TextColor3 = if optionId == id then Color.Bone else Color.Ash,
			})
		end
	end

	for index, option in props.options do
		local button = Create("TextButton", {
			Position = UDim2.fromScale((index - 1) / count, 0),
			Size = UDim2.fromScale(1 / count, 1),
			Text = option.label,
			FontFace = Font.Medium,
			TextSize = 13,
			TextColor3 = Color.Ash,
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

-- Text tabs with a short bone underline that slides to the chosen tab.
function Components.Tabs(props: {
	options: { { id: string, label: string } },
	value: string,
	onChanged: (string) -> (),
})
	local value = props.value
	local container = Create("Frame", {
		Size = UDim2.new(1, 0, 0, Theme.Size.Tabs),
		BackgroundTransparency = 1,
	})
	local underline = Create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Size = UDim2.fromOffset(0, 2),
		BackgroundColor3 = Color.Bone,
		Parent = container,
	}, { Create.round() })

	local api = { instance = container }
	local buttons = {}
	local x = 0

	function api.set(id: string, instant: boolean?)
		local entry = buttons[id]
		if not entry then
			return
		end
		value = id
		local info = if instant then nil else Theme.Tween.Smooth
		Create.animate(underline, info, {
			Position = UDim2.new(0, entry.x, 1, -1),
			Size = UDim2.fromOffset(entry.width, 2),
		})
		for optionId, other in buttons do
			Create.animate(other.button, info, {
				TextColor3 = if optionId == id then Color.Bone else Color.Ash,
			})
		end
	end

	for _, option in props.options do
		local width = textWidth(option.label, 15)
		local button = Create("TextButton", {
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.new(0, width, 1, -2),
			Text = option.label,
			FontFace = Font.Medium,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Color.Ash,
			Parent = container,
		})
		buttons[option.id] = { button = button, x = x, width = width }
		x += width + 20
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

-- Heading for a group of settings: sentence case, a touch heavier than rows.
function Components.GroupTitle(text: string): TextLabel
	return Create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 38),
		Text = text,
		FontFace = Font.SemiBold,
		TextSize = 13,
		TextColor3 = Color.Ash,
		TextYAlignment = Enum.TextYAlignment.Bottom,
	}, {
		Create.padding(0, 0, 8, 0),
	})
end

-- A list row: title, optional hint underneath, control on the right, hairline below.
function Components.Row(props: {
	title: string,
	hint: string?,
	control: GuiObject?,
	controlWidth: number?,
})
	local hasHint = props.hint ~= nil
	local reserved = (props.controlWidth or 0) + 12

	local row = Create("Frame", {
		Size = UDim2.new(1, 0, 0, if hasHint then 52 else 42),
		BackgroundTransparency = 1,
	}, {
		Title = Create("TextLabel", {
			Position = UDim2.fromOffset(0, if hasHint then 8 else 0),
			Size = UDim2.new(1, -reserved, 0, if hasHint then 20 else 42),
			Text = props.title,
			TextSize = 14,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		Hint = if hasHint
			then Create("TextLabel", {
				Position = UDim2.fromOffset(0, 28),
				Size = UDim2.new(1, -reserved, 0, 16),
				Text = props.hint,
				TextSize = 12,
				TextColor3 = Color.Ash,
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			else nil,
		Rule = Create("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Color.Bone,
			BackgroundTransparency = 0.94,
		}),
	})

	if props.control then
		props.control.AnchorPoint = Vector2.new(1, 0.5)
		props.control.Position = UDim2.fromScale(1, 0.5)
		props.control.Parent = row
	end

	return row
end

-- A read-only row with a value on the right (diagnostics).
function Components.ValueRow(title: string): (Frame, TextLabel)
	local value = Create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.45, 0, 1, 0),
		FontFace = Font.Medium,
		TextSize = 13,
		TextColor3 = Color.Bone,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local row = Create("Frame", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
	}, {
		Title = Create("TextLabel", {
			Size = UDim2.new(0.55, 0, 1, 0),
			Text = title,
			TextSize = 13,
			TextColor3 = Color.Ash,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		Value = value,
	})
	return row, value
end

function Components.Button(props: { text: string, onActivated: () -> () })
	local button = Create("TextButton", {
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = Color.Ridge,
		BackgroundTransparency = 0.3,
		Text = props.text,
		TextSize = 14,
	}, {
		Create.corner(Radius.Control),
	})
	Components.pressable(button, 0.3, 0)
	button.Activated:Connect(props.onActivated)
	return { instance = button }
end

return Components
