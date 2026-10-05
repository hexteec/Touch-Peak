--[[
	Small static glyphs for the gesture legend, drawn with frames only.
	Camera moves use their axis colour (see Theme.GestureColor); selection
	gestures stay bone white.
]]

local Theme = require(script.Parent.Theme)
local Create = require(script.Parent.Create)

local Color = Theme.Color

local function canvas(): Frame
	return Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})
end

local function line(from: Vector2, to: Vector2, color: Color3, transparency: number?): Frame
	local offset = to - from
	local middle = (from + to) / 2
	return Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, middle.X, 0.5, middle.Y),
		Size = UDim2.fromOffset(offset.Magnitude, 2),
		Rotation = math.deg(math.atan2(offset.Y, offset.X)),
		BackgroundColor3 = color,
		BackgroundTransparency = transparency or 0,
	}, { Create.round() })
end

local function at(x: number, y: number): UDim2
	return UDim2.new(0.5, x, 0.5, y)
end

local Icons = {}

-- Drag: a finger travelling along an orbit.
function Icons.drag()
	local icon = canvas()
	Create.ring(20, Color.Green, 0.35, 2).Parent = icon
	Create.dot(7, Color.Green, at(7, -7)).Parent = icon
	return icon
end

-- Tap, then drag: the tap mark and the finger sliding away from it.
function Icons.tapDrag()
	local icon = canvas()
	Create.ring(9, Color.Red, 0.3, 1.5, at(-7, 0)).Parent = icon
	line(Vector2.new(-2, 0), Vector2.new(6, 0), Color.Red).Parent = icon
	Create.dot(7, Color.Red, at(8, 0)).Parent = icon
	return icon
end

-- The zoom strip at the screen edge, with its index notch.
function Icons.strip()
	local icon = canvas()
	Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = at(-2, 0),
		Size = UDim2.fromOffset(10, 22),
		BackgroundTransparency = 1,
		Parent = icon,
	}, {
		Create.corner(3),
		Create.stroke(Color.Blue, 0.3, 1.5),
	})
	for _, y in { -6, 0, 6 } do
		line(Vector2.new(-4, y), Vector2.new(0, y), Color.Blue, if y == 0 then 0 else 0.5).Parent = icon
	end
	line(Vector2.new(5, 0), Vector2.new(9, 0), Color.Blue).Parent = icon
	return icon
end

function Icons.tap()
	local icon = canvas()
	Create.ring(16, Color.Bone, 0.6, 1.5).Parent = icon
	Create.dot(6, Color.Bone).Parent = icon
	return icon
end

function Icons.doubleTap()
	local icon = canvas()
	Create.ring(22, Color.Bone, 0.75, 1.5).Parent = icon
	Create.ring(13, Color.Bone, 0.45, 1.5).Parent = icon
	Create.dot(6, Color.Bone).Parent = icon
	return icon
end

return Icons
