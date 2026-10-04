--[[
	The floating Touch Peak window drawn over the viewport.

	  * The header is a drag handle (mouse or finger) and shows whether touch
	    controls are active, with a pulsing status dot.
	  * The chevron collapses the window into a compact pill; tapping the pill
	    expands it again.
	  * "Gestures" lists every control with a small animation, "Settings"
	    holds sensitivities and options.
]]

local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Config = require(script.Parent.Parent.Config)
local Maid = require(script.Parent.Parent.Util.Maid)
local Settings = require(script.Parent.Parent.Settings)
local Theme = require(script.Parent.Theme)
local Create = require(script.Parent.Create)
local Components = require(script.Parent.Components)
local GestureIcons = require(script.Parent.GestureIcons)

local Color = Theme.Color
local Font = Theme.Font
local Size = Theme.Size

local DRAG_THRESHOLD = 6
local HEADER_BUTTONS_WIDTH = 100
local PAGES_TOP = 142
local FOOTER_HEIGHT = 34

local GESTURES = {
	{ icon = "rotate", title = "gestureRotate", hint = "gestureRotateHint" },
	{ icon = "zoom", title = "gestureZoom", hint = "gestureZoomHint" },
	{ icon = "pan", title = "gesturePan", hint = "gesturePanHint" },
	{ icon = "modes", title = "gestureModes", hint = "gestureModesHint" },
	{ icon = "tap", title = "gestureTap", hint = "gestureTapHint" },
	{ icon = "doubleTap", title = "gestureDoubleTap", hint = "gestureDoubleTapHint" },
	{ icon = "longPress", title = "gestureLongPress", hint = "gestureLongPressHint" },
}

local function toVector2(position: Vector3): Vector2
	return Vector2.new(position.X, position.Y)
end

local function isPointer(input: InputObject): boolean
	local inputType = input.UserInputType
	return inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch
end

local Panel = {}
Panel.__index = Panel

export type Params = {
	parent: GuiBase2d,
	settings: any,
	locale: any,
	active: boolean,
	touchDetected: boolean,
	onActiveChanged: (boolean) -> (),
	onClose: () -> (),
}

function Panel.new(params: Params)
	local self = setmetatable({}, Panel)
	self._params = params
	self._settings = params.settings
	self._locale = params.locale
	self._maid = Maid.new()
	self._loops = {}
	self._controls = {}
	self._visible = false
	self._visibleToken = 0
	self._collapseToken = 0
	self._collapsed = false
	self._active = params.active
	self._touchCount = 0
	self._viaMouse = false
	self._gesture = nil
	self._drag = nil
	self._tab = if self._settings:GetState("tab") == "settings" then "settings" else "gestures"

	self:_build()
	self:_buildGesturesPage()
	self:_buildSettingsPage()
	self:_bindDrag()
	self:_restorePosition()
	self:_selectTab(self._tab, true)
	self:SetTouchDetected(params.touchDetected)
	self:SetActive(params.active, true)
	self:_refreshChips()

	self._maid:Give(params.parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if not self._customPosition then
			self._position = self:_defaultPosition()
		end
		self:_applyLayout(true)
	end))
	self._maid:Give(self._settings.Changed:Connect(function(key, value)
		local control = self._controls[key]
		if control then
			control.set(value)
		end
	end))

	return self
end

function Panel:_t(key: string, ...: any): string
	return self._locale:t(key, ...)
end

-- Construction -------------------------------------------------------------------

function Panel:_build()
	-- Header ------------------------------------------------------------------
	local logo = Create("Frame", {
		Position = UDim2.fromOffset(14, 13),
		Size = UDim2.fromOffset(36, 36),
		BackgroundColor3 = Color.White,
	}, {
		Create.corner(11),
		Create.accentGradient(45),
		Ring = Create.ring(20, Color.White, 0.3, 2),
		Dot = Create.dot(8, Color.White),
	})

	local statusPulse = Create.dot(8, Color.Success, UDim2.new(0, 4, 0.5, 0))
	statusPulse.BackgroundTransparency = 0.4
	statusPulse.ZIndex = 1
	local statusDot = Create.dot(8, Color.Success, UDim2.new(0, 4, 0.5, 0))
	statusDot.ZIndex = 2
	local statusLabel = Create("TextLabel", {
		Position = UDim2.fromOffset(15, 0),
		Size = UDim2.new(1, -15, 1, 0),
		FontFace = Font.SemiBold,
		TextSize = 12,
		TextColor3 = Color.Success,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	local chevron = Components.ChevronGlyph()
	local collapseButton = Components.IconButton({
		glyph = chevron,
		onActivated = function()
			self:SetCollapsed(not self._collapsed)
		end,
	})
	collapseButton.instance.Position = UDim2.new(1, -54, 0.5, 0)

	local closeButton = Components.IconButton({
		glyph = Components.CloseGlyph(),
		onActivated = function()
			self._params.onClose()
		end,
	})
	closeButton.instance.Position = UDim2.new(1, -14, 0.5, 0)

	local dragHandle = Create("TextButton", {
		Size = UDim2.new(1, -HEADER_BUTTONS_WIDTH, 1, 0),
		ZIndex = 2,
	})

	local header = Create("Frame", {
		Size = UDim2.new(1, 0, 0, Size.Header),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, {
		Logo = logo,
		Title = Create("TextLabel", {
			Position = UDim2.fromOffset(62, 12),
			Size = UDim2.new(1, -62 - HEADER_BUTTONS_WIDTH + 8, 0, 20),
			Text = Config.ToolbarName,
			FontFace = Font.ExtraBold,
			TextSize = 17,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		Status = Create("Frame", {
			Position = UDim2.fromOffset(62, 34),
			Size = UDim2.new(1, -62 - HEADER_BUTTONS_WIDTH + 8, 0, 16),
			BackgroundTransparency = 1,
		}, {
			Pulse = statusPulse,
			Dot = statusDot,
			Label = statusLabel,
		}),
		DragHandle = dragHandle,
		Collapse = collapseButton.instance,
		Close = closeButton.instance,
	})

	-- Status card ---------------------------------------------------------------
	local toggle = Components.Toggle({
		value = self._active,
		onChanged = function(value)
			self._params.onActiveChanged(value)
		end,
	})
	toggle.instance.Position = UDim2.new(1, -14, 0.5, 0)

	local fingersChip = Components.Chip(1)
	local gestureChip = Components.Chip(2)

	local statusCard = Create("Frame", {
		Position = UDim2.fromOffset(Size.Padding, 12),
		Size = UDim2.new(1, -Size.Padding * 2, 0, 72),
		BackgroundColor3 = Color.Surface,
	}, {
		Create.corner(14),
		Create.stroke(Color.White, 0.93),
		Title = Create("TextLabel", {
			Position = UDim2.fromOffset(14, 12),
			Size = UDim2.new(1, -84, 0, 20),
			Text = self:_t("touchControl"),
			FontFace = Font.Bold,
			TextSize = 15,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		Chips = Create("Frame", {
			Position = UDim2.fromOffset(14, 38),
			Size = UDim2.new(1, -84, 0, 22),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
		}, {
			Create.list(6, Enum.FillDirection.Horizontal),
			Fingers = fingersChip,
			Gesture = gestureChip,
		}),
		Toggle = toggle.instance,
	})

	-- Tabs and pages -----------------------------------------------------------
	local tabs = Components.Segmented({
		options = {
			{ id = "gestures", label = self:_t("tabGestures") },
			{ id = "settings", label = self:_t("tabSettings") },
		},
		value = self._tab,
		size = UDim2.new(1, -Size.Padding * 2, 0, 36),
		onChanged = function(id)
			self:_selectTab(id)
		end,
	})
	tabs.instance.Position = UDim2.fromOffset(Size.Padding, 96)

	local function page(): ScrollingFrame
		return Create("ScrollingFrame", {
			Size = UDim2.fromScale(1, 1),
		}, {
			Create.padding(2, Size.Padding, 14, Size.Padding),
			Create.list(6),
		})
	end
	local gesturesPage = page()
	local settingsPage = page()

	local pages = Create("Frame", {
		Position = UDim2.fromOffset(0, PAGES_TOP),
		Size = UDim2.new(1, 0, 1, -PAGES_TOP - FOOTER_HEIGHT),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	}, {
		Gestures = gesturesPage,
		Settings = settingsPage,
	})

	local footer = Create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, Size.Padding, 1, 0),
		Size = UDim2.new(1, -Size.Padding * 2, 0, FOOTER_HEIGHT),
		BackgroundTransparency = 1,
	}, {
		Divider = Create("Frame", {
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Color.White,
			BackgroundTransparency = 0.93,
		}),
		Hint = Create("TextLabel", {
			Size = UDim2.new(1, -56, 1, 0),
			Text = self:_t("dragHint"),
			FontFace = Font.Regular,
			TextSize = 11,
			TextColor3 = Color.TextFaint,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		Version = Create("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, 56, 1, 0),
			Text = "v" .. Config.Version,
			FontFace = Font.SemiBold,
			TextSize = 11,
			TextColor3 = Color.TextFaint,
			TextXAlignment = Enum.TextXAlignment.Right,
		}),
	})

	local content = Create("Frame", {
		Position = UDim2.fromOffset(0, Size.Header),
		Size = UDim2.new(1, 0, 1, -Size.Header),
		BackgroundTransparency = 1,
	}, {
		Divider = Create("Frame", {
			Position = UDim2.fromOffset(Size.Padding, 0),
			Size = UDim2.new(1, -Size.Padding * 2, 0, 1),
			BackgroundColor3 = Color.White,
			BackgroundTransparency = 0.93,
		}),
		StatusCard = statusCard,
		Tabs = tabs.instance,
		Pages = pages,
		Footer = footer,
	})

	-- Body, shadow and root ----------------------------------------------------------
	local body = Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color.Background,
		BackgroundTransparency = 0.03,
		ClipsDescendants = true,
		ZIndex = 2,
	}, {
		Create.corner(18),
		Create.stroke(Color.White, 0.87),
		Glow = Create("Frame", {
			Size = UDim2.new(1, 0, 0, 160),
			BackgroundColor3 = Color.White,
		}, {
			Create.corner(18),
			Create("UIGradient", {
				Color = Theme.AccentGradient,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.83),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Rotation = 90,
			}),
		}),
		Header = header,
		Content = content,
	})

	local scale = Create("UIScale", { Scale = 1 })
	local root = Create("Frame", {
		Name = "TouchPeakPanel",
		Size = UDim2.fromOffset(Size.PanelWidth, Size.PanelHeight),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 10,
	}, {
		Scale = scale,
		Body = body,
	})

	-- Soft shadow: several very faint layers, each a little larger than the last.
	for index, layer in { { 2, 0.9 }, { 6, 0.94 }, { 12, 0.965 }, { 20, 0.98 } } do
		local spread, transparency = layer[1], layer[2]
		Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 2 + index),
			Size = UDim2.new(1, spread, 1, spread),
			BackgroundColor3 = Color.Black,
			BackgroundTransparency = transparency,
			ZIndex = 1,
			Parent = root,
		}, { Create.corner(18 + spread / 2) })
	end

	root.Parent = self._params.parent
	self._maid:Give(root)

	self._pulseTween = TweenService:Create(
		statusPulse,
		TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1),
		{ Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 1 }
	)
	self._maid:Give(self._pulseTween)

	self._root = root
	self._scale = scale
	self._body = body
	self._content = content
	self._chevron = chevron
	self._dragHandle = dragHandle
	self._statusDot = statusDot
	self._statusPulse = statusPulse
	self._statusLabel = statusLabel
	self._toggle = toggle
	self._fingersChip = fingersChip
	self._gestureChip = gestureChip
	self._tabs = tabs
	self._gesturesPage = gesturesPage
	self._settingsPage = settingsPage
end

function Panel:_buildGesturesPage()
	for index, gesture in GESTURES do
		local icon, tweens = GestureIcons[gesture.icon]()
		for _, tween in tweens do
			table.insert(self._loops, tween)
			self._maid:Give(tween)
		end

		Create("Frame", {
			Size = UDim2.new(1, 0, 0, 50),
			BackgroundColor3 = Color.Surface,
			LayoutOrder = index,
			Parent = self._gesturesPage,
		}, {
			Create.corner(13),
			Create.stroke(Color.White, 0.95),
			IconBox = Create("Frame", {
				Position = UDim2.fromOffset(7, 7),
				Size = UDim2.fromOffset(36, 36),
				BackgroundColor3 = Color.SurfaceHigh,
			}, {
				Create.corner(10),
				Icon = icon,
			}),
			Title = Create("TextLabel", {
				Position = UDim2.fromOffset(54, 7),
				Size = UDim2.new(1, -64, 0, 19),
				Text = self:_t(gesture.title),
				FontFace = Font.SemiBold,
				TextSize = 14,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}),
			Hint = Create("TextLabel", {
				Position = UDim2.fromOffset(54, 26),
				Size = UDim2.new(1, -64, 0, 16),
				Text = self:_t(gesture.hint),
				FontFace = Font.Regular,
				TextSize = 12,
				TextColor3 = Color.TextDim,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}),
		})
	end
end

function Panel:_buildSettingsPage()
	local settings = self._settings
	local page = self._settingsPage
	local order = 0

	local function add(instance: GuiObject)
		order += 1
		instance.LayoutOrder = order
		instance.Parent = page
	end

	local function section(key: string)
		add(Components.SectionLabel(self:_t(key), 0))
	end

	local function stepper(key: string, title: string)
		local control = Components.Stepper({
			value = settings:Get(key),
			min = Settings.SensitivityRange.min,
			max = Settings.SensitivityRange.max,
			step = 0.25,
			onChanged = function(value)
				settings:Set(key, value)
			end,
		})
		self._controls[key] = control
		add(Components.Row({ title = self:_t(title), control = control.instance, controlWidth = 112, layoutOrder = 0 }))
	end

	local function toggle(key: string, title: string, hint: string?)
		local control = Components.Toggle({
			value = settings:Get(key),
			onChanged = function(value)
				settings:Set(key, value)
			end,
		})
		self._controls[key] = control
		add(Components.Row({
			title = self:_t(title),
			hint = if hint then self:_t(hint) else nil,
			control = control.instance,
			controlWidth = 46,
			layoutOrder = 0,
		}))
	end

	local function choice(key: string, title: string, options, width: number)
		local control = Components.Segmented({
			options = options,
			value = settings:Get(key),
			size = UDim2.fromOffset(width, 30),
			textSize = 12,
			onChanged = function(id)
				settings:Set(key, id)
			end,
		})
		self._controls[key] = control
		add(
			Components.Row({ title = self:_t(title), control = control.instance, controlWidth = width, layoutOrder = 0 })
		)
	end

	section("sectionSensitivity")
	stepper("rotateSensitivity", "rotateSpeed")
	stepper("zoomSensitivity", "zoomSpeed")
	stepper("panSensitivity", "panSpeed")

	section("sectionCamera")
	choice("rotateMode", "rotateMode", {
		{ id = "orbit", label = self:_t("rotateModeOrbit") },
		{ id = "look", label = self:_t("rotateModeLook") },
	}, 150)
	toggle("inertia", "inertia", "inertiaHint")
	toggle("combineGestures", "combineGestures", "combineGesturesHint")
	toggle("invertRotate", "invertRotate", "invertRotateHint")
	toggle("invertPan", "invertPan", "invertPanHint")

	section("sectionSelection")
	toggle("selectModels", "selectModels", "selectModelsHint")
	toggle("showTouches", "showTouches", "showTouchesHint")
	toggle("mouseInput", "mouseInput", "mouseInputHint")
	toggle("showModeBar", "showModeBar", "showModeBarHint")
	choice("language", "language", {
		{ id = "auto", label = self:_t("languageAuto") },
		{ id = "pl", label = "PL" },
		{ id = "en", label = "EN" },
	}, 138)

	section("sectionInfo")
	local touchChip = Components.Chip(0)
	add(Components.Row({ title = self:_t("touchScreen"), control = touchChip, controlWidth = 110, layoutOrder = 0 }))
	self._touchChip = touchChip

	-- Live counters of what Studio actually delivers (touch vs. mouse).
	self._diagnostics = {}
	for _, key in { "diagTouch", "diagMouse", "diagGestures" } do
		local row = Components.Row({ title = self:_t(key), hint = "", layoutOrder = 0 })
		add(row)
		self._diagnostics[key] = row.Hint
	end
	self:SetInputStats(nil)

	local reset = Components.Button({
		text = self:_t("reset"),
		layoutOrder = 0,
		onActivated = function()
			settings:Reset()
		end,
	})
	add(reset.instance)
end

-- Dragging -----------------------------------------------------------------------

function Panel:_bindDrag()
	self._maid:Give(self._dragHandle.InputBegan:Connect(function(input)
		if self._drag or not isPointer(input) then
			return
		end
		self._drag = {
			input = input,
			isTouch = input.UserInputType == Enum.UserInputType.Touch,
			start = toVector2(input.Position),
			origin = self._position,
			moved = false,
		}
	end))

	self._maid:Give(UserInputService.InputChanged:Connect(function(input)
		local drag = self._drag
		if not drag then
			return
		end
		if drag.isTouch then
			if input ~= drag.input then
				return
			end
		elseif input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end

		local delta = toVector2(input.Position) - drag.start
		if not drag.moved and delta.Magnitude < DRAG_THRESHOLD then
			return
		end
		drag.moved = true
		self._position = self:_clamp(drag.origin + delta, self:_targetSize())
		self._root.Position = UDim2.fromOffset(self._position.X, self._position.Y)
	end))

	self._maid:Give(UserInputService.InputEnded:Connect(function(input)
		local drag = self._drag
		if not drag then
			return
		end
		local released = if drag.isTouch
			then input == drag.input
			else input.UserInputType == Enum.UserInputType.MouseButton1
		if not released then
			return
		end

		self._drag = nil
		if drag.moved then
			self._customPosition = true
			self._settings:SetState("position", { x = self._position.X, y = self._position.Y })
		elseif self._collapsed then
			-- A plain tap on the collapsed pill opens it again.
			self:SetCollapsed(false)
		end
	end))
end

-- Layout ---------------------------------------------------------------------------

function Panel:_screenSize(): Vector2
	return self._params.parent.AbsoluteSize
end

function Panel:_expandedHeight(): number
	local available = self:_screenSize().Y - Size.ScreenMargin * 2
	return math.max(Size.Header + 220, math.min(Size.PanelHeight, available))
end

function Panel:_targetSize(): Vector2
	if self._collapsed then
		return Vector2.new(Size.CollapsedWidth, Size.Header)
	end
	return Vector2.new(Size.PanelWidth, self:_expandedHeight())
end

function Panel:_clamp(position: Vector2, size: Vector2): Vector2
	local screen = self:_screenSize()
	local margin = Size.ScreenMargin
	local maxX = math.max(margin, screen.X - size.X - margin)
	local maxY = math.max(margin, screen.Y - size.Y - margin)
	return Vector2.new(math.clamp(position.X, margin, maxX), math.clamp(position.Y, margin, maxY))
end

-- Until the user drags the window it lives in the top-right corner of the viewport.
function Panel:_defaultPosition(): Vector2
	return Vector2.new(self:_screenSize().X - Size.PanelWidth - 24, 24)
end

function Panel:_restorePosition()
	local saved = self._settings:GetState("position")
	if type(saved) == "table" and type(saved.x) == "number" and type(saved.y) == "number" then
		self._customPosition = true
		self._position = Vector2.new(saved.x, saved.y)
	else
		self._customPosition = false
		self._position = self:_defaultPosition()
	end
	self:_applyLayout(true)
end

function Panel:_applyLayout(instant: boolean?)
	local size = self:_targetSize()
	self._position = self:_clamp(self._position, size)
	Create.animate(self._root, if instant then nil else Theme.Tween.Smooth, {
		Size = UDim2.fromOffset(size.X, size.Y),
		Position = UDim2.fromOffset(self._position.X, self._position.Y),
	})
end

function Panel:_selectTab(id: string, instant: boolean?)
	self._tab = id
	local info = if instant then nil else Theme.Tween.Smooth
	Create.animate(self._gesturesPage, info, {
		Position = UDim2.fromScale(if id == "gestures" then 0 else -1, 0),
	})
	Create.animate(self._settingsPage, info, {
		Position = UDim2.fromScale(if id == "settings" then 0 else 1, 0),
	})
	if instant then
		self._tabs.set(id, true)
	end
	self._settings:SetState("tab", id)
	self:_updateAnimations()
end

-- Public API -------------------------------------------------------------------------

function Panel:IsVisible(): boolean
	return self._visible
end

function Panel:IsCollapsed(): boolean
	return self._collapsed
end

function Panel:SetVisible(visible: boolean, instant: boolean?)
	if visible == self._visible then
		return
	end
	self._visible = visible
	self._visibleToken += 1
	self._drag = nil

	if visible then
		self._root.Visible = true
		if instant then
			self._scale.Scale = 1
		else
			self._scale.Scale = 0.9
			Create.tween(self._scale, Theme.Tween.Spring, { Scale = 1 })
		end
	elseif instant then
		self._root.Visible = false
	else
		local token = self._visibleToken
		Create.tween(self._scale, Theme.Tween.Close, { Scale = 0.9 })
		task.delay(Theme.Tween.Close.Time, function()
			if token == self._visibleToken then
				self._root.Visible = false
			end
		end)
	end

	self:_updateAnimations()
end

function Panel:SetCollapsed(collapsed: boolean, instant: boolean?)
	self._collapsed = collapsed
	self._collapseToken += 1
	local info = if instant then nil else Theme.Tween.Smooth

	Create.animate(self._chevron, info, { Rotation = if collapsed then 180 else 0 })

	if not collapsed then
		self._content.Visible = true
	elseif instant then
		self._content.Visible = false
	else
		-- Hide the content (and its inputs) once the window has shrunk.
		local token = self._collapseToken
		task.delay(Theme.Tween.Smooth.Time, function()
			if token == self._collapseToken then
				self._content.Visible = false
			end
		end)
	end

	self:_applyLayout(instant)
	self:_updateAnimations()
end

function Panel:SetActive(active: boolean, instant: boolean?)
	self._active = active
	self._toggle.set(active, instant)
	self:_refreshStatus()
	self:_updateAnimations()
end

-- `viaMouse` is true when the only "finger" is Studio's mouse pointer.
function Panel:SetTouchCount(count: number, viaMouse: boolean?)
	self._touchCount = count
	self._viaMouse = viaMouse == true and count > 0
	self:_refreshChips()
end

function Panel:SetInputStats(stats)
	local s = stats
		or {
			touchBegan = 0,
			touchChanged = 0,
			touchEnded = 0,
			touchFingers = 0,
			mouseDown = 0,
			mouseMoves = 0,
			wheel = 0,
			pinch = 0,
			pan = 0,
		}
	local rows = self._diagnostics
	rows.diagTouch.Text = self:_t("diagTouchValue", s.touchBegan + s.touchChanged + s.touchEnded, s.touchFingers)
	rows.diagTouch.TextColor3 = if s.touchFingers >= 2 then Color.Success else Color.TextDim
	rows.diagMouse.Text = self:_t("diagMouseValue", s.mouseDown, s.mouseMoves)
	rows.diagGestures.Text = self:_t("diagGesturesValue", s.pinch, s.pan, s.wheel)
end

function Panel:SetGesture(gesture: string?)
	self._gesture = gesture
	self:_refreshChips()
	self:_refreshStatus()
end

function Panel:SetTouchDetected(detected: boolean)
	local chip = self._touchChip
	chip.Text = self:_t(if detected then "detected" else "notDetected")
	chip.TextColor3 = if detected then Color.Success else Color.Warning
end

-- True when a screen point lies on the window (so it should not move the camera).
function Panel:ContainsPoint(point: Vector2): boolean
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

function Panel:_refreshStatus()
	local color = if self._active then Color.Success else Color.Warning
	local text = self:_t(if self._active then "statusActive" else "statusPaused")
	if self._active and self._gesture then
		text ..= " · " .. self._locale:gesture(self._gesture)
	end
	self._statusLabel.Text = text
	self._statusLabel.TextColor3 = color
	self._statusDot.BackgroundColor3 = color
	self._statusPulse.BackgroundColor3 = color
end

function Panel:_refreshChips()
	local highlight = '<font color="#EEF1F9">%s</font>'
	-- Studio's mouse pointer is shown as such: it can never be more than one finger.
	local label = self:_t(if self._viaMouse then "fingersMouse" else "fingers")
	self._fingersChip.Text = label .. "  " .. string.format(highlight, tostring(self._touchCount))
	self._gestureChip.Text = self:_t("gesture") .. "  " .. string.format(highlight, self._locale:gesture(self._gesture))
end

function Panel:_updateAnimations()
	local showIcons = self._visible and not self._collapsed and self._tab == "gestures"
	for _, tween in self._loops do
		if showIcons then
			tween:Play()
		else
			tween:Pause()
		end
	end

	local pulse = self._visible and self._active
	self._statusPulse.Visible = pulse
	if pulse then
		self._pulseTween:Play()
	else
		self._pulseTween:Pause()
	end
end

function Panel:Destroy()
	self._loops = {}
	self._maid:Clean()
end

return Panel
