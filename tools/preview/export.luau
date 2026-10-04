--[[
	Builds the plugin UI inside the fake Studio from tests/lib/World and
	exports a few scenes as HTML pages (rendered by renderer.js), so the
	layout can be checked in a browser without Roblox Studio.

	Run from the repository root:
		lune run tools/preview/export
		tools/preview/screenshot.sh
]]

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local World = require("../../tests/lib/World")

local Vector2, Vector3, CFrame = World.Vector2, World.Vector3, World.CFrame

local OUT = "tools/preview/out"

-- Roblox defaults for properties the plugin does not always set.
local DEFAULTS = {
	BackgroundColor3 = { 163 / 255, 162 / 255, 165 / 255 },
	BackgroundTransparency = 0,
	TextColor3 = { 0, 0, 0 },
	TextTransparency = 0,
	TextSize = 14,
}

local function encode(value: any): any
	local kind = typeof(value)
	if kind == "UDim2" then
		return { xs = value.X.Scale, xo = value.X.Offset, ys = value.Y.Scale, yo = value.Y.Offset }
	elseif kind == "UDim" then
		return { s = value.Scale, o = value.Offset }
	elseif kind == "Vector2" then
		return { x = value.X, y = value.Y }
	elseif kind == "Color3" then
		return { value.R, value.G, value.B }
	elseif kind == "ColorSequence" then
		local out = {}
		for _, keypoint in value.Keypoints do
			table.insert(out, { t = keypoint.Time, c = { keypoint.Value.R, keypoint.Value.G, keypoint.Value.B } })
		end
		return out
	elseif kind == "NumberSequence" then
		local out = {}
		for _, keypoint in value.Keypoints do
			table.insert(out, { t = keypoint.Time, v = keypoint.Value })
		end
		return out
	elseif kind == "EnumItem" then
		return value.Name
	elseif kind == "Font" then
		return value.Weight.Name
	elseif kind == "number" or kind == "string" or kind == "boolean" then
		return value
	end
	return nil
end

local function export(world, instance)
	local data = world._data[instance]
	local props = {}
	for key, value in DEFAULTS do
		props[key] = value
	end
	for key, value in data.props do
		local encoded = encode(value)
		if encoded ~= nil then
			props[key] = encoded
		end
	end
	local children = {}
	for _, child in data.children do
		table.insert(children, export(world, child))
	end
	return { class = data.ClassName, props = props, children = children }
end

local renderer = fs.readFile("tools/preview/renderer.js")

local function writeScene(name: string, world, gui)
	local tree = export(world, gui)
	local html = string.format(
		[[<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;padding:0;background:#000}</style></head>
<body><div id="viewport"></div><script>const TREE = %s;
const SCREEN = { x: %d, y: %d };
%s</script></body></html>]],
		serde.encode("json", tree),
		World.ScreenSize.X,
		World.ScreenSize.Y,
		renderer
	)
	if not fs.isDir(OUT) then
		fs.writeDir(OUT)
	end
	fs.writeFile(`{OUT}/{name}.html`, html)
	print("wrote " .. name)
end

local function scene(setup: (any, any) -> ())
	local world = World.new()
	world.groundPlane = true
	world.services.LocalizationService.SystemLocaleId = "pl-pl"
	world.camera.CFrame = CFrame.lookAt(Vector3.new(0, 20, 40), Vector3.new(0, 0, 0))
	local App = world:require("App")
	local app = App.new(world:plugin())
	app:Open()
	setup(world, app)
	return world, world.coreGui.TouchPeak
end

-- Gestures tab while panning with tap-and-drag, the zoom strip partly scrolled.
writeScene(
	"gestures",
	scene(function(world, app)
		local Theme = world:require("UI/Theme")
		app.zoomStrip:_scrollBy(-17)
		app.overlay:TouchBegan("a", Vector2.new(560, 300))
		app.panel:SetTouchDetected(true)
		app.panel:SetGesture("pan")
		app.overlay:ShowGesture(app.locale:gesture("pan"), Theme.GestureColor.pan)
		app.overlay:Toast(app.locale:t("toastSelected", "Domek"))
	end)
)

-- Settings tab.
writeScene(
	"settings",
	scene(function(world, app)
		for _, button in world.coreGui.TouchPeak:GetDescendants() do
			if button:IsA("TextButton") and button.Text == "Ustawienia" then
				button.Activated:Fire()
			end
		end
		app.panel:SetTouchDetected(true)
	end)
)

-- Collapsed pill while rotating, and the paused state.
writeScene(
	"collapsed",
	scene(function(world, app)
		local Theme = world:require("UI/Theme")
		app.panel:SetCollapsed(true, true)
		app.panel:SetGesture("rotate")
		app.overlay:TouchBegan("a", Vector2.new(500, 420))
		app.overlay:ShowGesture(app.locale:gesture("rotate"), Theme.GestureColor.rotate)
	end)
)

-- Settings tab scrolled to the diagnostics, while a mouse-driven finger pans.
writeScene(
	"diagnostics",
	scene(function(world, app)
		for _, button in world.coreGui.TouchPeak:GetDescendants() do
			if button:IsA("TextButton") and button.Text == "Ustawienia" then
				button.Activated:Fire()
			end
		end
		app.panel:SetTouchCount(1, true)
		app.panel:SetGesture("pan")
		app.panel:SetInputStats({
			touchBegan = 0,
			touchChanged = 0,
			touchEnded = 0,
			touchFingers = 0,
			mouseDown = 14,
			mouseMoves = 512,
			wheel = 0,
			pinch = 0,
			pan = 0,
		})
		world.coreGui.TouchPeak.TouchPeakPanel.Body.Content.Pages.Settings.CanvasPosition = Vector2.new(0, 760)
		app.overlay:Toast(app.locale:t("toastMouseOnly"), world:require("UI/Theme").Color.Amber)
	end)
)

writeScene(
	"paused",
	scene(function(world, app)
		app:SetActive(false)
		app.overlay:Toast(app.locale:t("toastPausedByTool"), world:require("UI/Theme").Color.Amber)
	end)
)
