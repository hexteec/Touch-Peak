--[[
	Tiny declarative instance builder:

		Create("Frame", { Size = ... }, {
			Create.corner(12),
			Label = Create("TextLabel", { Text = "Hi" }),
		})

	String keys in the children table become the child's Name.
]]

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local DEFAULTS = {
	Frame = { BorderSizePixel = 0 },
	ScrollingFrame = {
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Theme.Color.Bone,
		ScrollBarImageTransparency = 0.8,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ElasticBehavior = Enum.ElasticBehavior.Always,
	},
	TextLabel = {
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
		FontFace = Theme.Font.Regular,
		TextColor3 = Theme.Color.Bone,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
	},
	TextButton = {
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		FontFace = Theme.Font.Medium,
		TextColor3 = Theme.Color.Bone,
		TextSize = 14,
		Text = "",
	},
}

local Create = {}

local function create(className: string, props: { [string]: any }?, children: { [any]: Instance }?): Instance
	local instance = Instance.new(className)

	local defaults = DEFAULTS[className]
	if defaults then
		for key, value in defaults do
			instance[key] = value
		end
	end

	local parent = nil
	for key, value in props or {} do
		if key == "Parent" then
			parent = value
		else
			instance[key] = value
		end
	end

	for key, child in children or {} do
		if type(key) == "string" then
			child.Name = key
		end
		child.Parent = instance
	end

	if parent then
		instance.Parent = parent
	end
	return instance
end

setmetatable(Create, {
	__call = function(_, className, props, children)
		return create(className, props, children)
	end,
})

function Create.corner(radius: number): UICorner
	return create("UICorner", { CornerRadius = UDim.new(0, radius) })
end

function Create.round(): UICorner
	return create("UICorner", { CornerRadius = UDim.new(1, 0) })
end

function Create.stroke(color: Color3?, transparency: number?, thickness: number?): UIStroke
	return create("UIStroke", {
		Color = color or Theme.Color.Bone,
		Transparency = transparency or 0.9,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Create.padding(top: number, right: number?, bottom: number?, left: number?): UIPadding
	right = right or top
	return create("UIPadding", {
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right),
		PaddingBottom = UDim.new(0, bottom or top),
		PaddingLeft = UDim.new(0, left or right),
	})
end

function Create.list(padding: number, direction: Enum.FillDirection?): UIListLayout
	return create("UIListLayout", {
		Padding = UDim.new(0, padding),
		FillDirection = direction or Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Top,
	})
end

-- A filled circle centred on `position`.
function Create.dot(size: number, color: Color3, position: UDim2?): Frame
	return create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position or UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color,
	}, { Create.round() })
end

-- An outlined circle centred on `position`.
function Create.ring(size: number, color: Color3, transparency: number, thickness: number, position: UDim2?): Frame
	return create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position or UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
	}, {
		Create.round(),
		Stroke = Create.stroke(color, transparency, thickness),
	})
end

function Create.tween(instance: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local tween = TweenService:Create(instance, info, goal)
	tween:Play()
	return tween
end

-- Tweens to `goal`, or applies it immediately when `info` is nil.
function Create.animate(instance: Instance, info: TweenInfo?, goal: { [string]: any })
	if info then
		Create.tween(instance, info, goal)
	else
		for key, value in goal do
			instance[key] = value
		end
	end
end

return Create
