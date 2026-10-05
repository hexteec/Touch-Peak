--[[
	The floating Touch Peak window drawn over the viewport.

	  * Header: the peak logo (its summit light shows whether touch controls
	    are on), the wordmark, collapse and close. Dragging the header moves
	    the window; when collapsed, tapping it opens the window again.
	  * Status line: on/paused, the camera move in progress (in its axis
	    colour) and the on/off switch.
	  * "Gestures" is a legend of what each touch does; "Settings" is a list.
]]

local UserInputService = game:GetService("UserInputService")

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
local Radius = Theme.Radius

local DRAG_THRESHOLD = 6
local HEADER_BUTTONS_WIDTH = 84
local CONTENT_TOP = Size.Header + Size.Status
local PAGES_TOP = Size.Tabs + 4

-- Gesture legend: what you do, and what it does (coloured like the camera move).
local LEGEND = {
	{ icon = "drag", action = "actDrag", effect = "effDrag", color = Color.Green },
	{ icon = "tapDrag", action = "actTapDrag", effect = "effTapDrag", color = Color.Red },
	{ icon = "strip", action = "actStrip", effect = "effStrip", color = Color.Blue },
	{ icon = "tap", action = "actTap", effect = "effTap" },
	{ icon = "doubleTap", action = "actDoubleTap", effect = "effDoubleTap" },
}

local EMPTY_STATS = {
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

local function toVector2(position: Vector3): Vector2
	return Vector2.new(position.X, position.Y)
end

local function isPointer(input: InputObject): boolean
	local inputType = input.UserInputType
	return inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch
end

local function hex(color: Color3): string
	local function byte(channel: number): number
		return math.floor(channel * 255 + 0.5)
	end
	return string.format("#%02X%02X%02X", byte(color.R), byte(color.G), byte(color.B))
end

-- The drawn logo: two peaks, the front one with a light on its summit.
local function peakLogo(): (Frame, Frame)
	-- Bars of a peak: `length` long at 60 degrees, meeting at `apex`.
	local function peak(apex: Vector2, length: number, color: Color3)
		local dx, dy = length * 0.25, length * 0.433 -- half of cos/sin 60
		return Components.bar(length, 2, -60, UDim2.fromOffset(apex.X - dx, apex.Y + dy), color),
			Components.bar(length, 2, 60, UDim2.fromOffset(apex.X + dx, apex.Y + dy), color)
	end
	local backLeft, backRight = peak(Vector2.new(17, 8), 8, Color.Dim)
	local frontLeft, frontRight = peak(Vector2.new(9, 3), 13, Color.Bone)
	local summit = Create.dot(5, Color.Green, UDim2.fromOffset(9, 0))

	local logo = Create("Frame", {
		Size = UDim2.fromOffset(24, 16),
		BackgroundTransparency = 1,
	}, {
		BackLeft = backLeft,
		BackRight = backRight,
		FrontLeft = frontLeft,
		FrontRight = frontRight,
		Summit = summit,
	})
	for _, part in { frontLeft, frontRight } do
		part.ZIndex = 2
	end
	summit.ZIndex = 3
	return logo, summit
end

-- The plugin's icon: your image from Config.Icon with a status light in its
-- corner, or the drawn peaks (whose summit is the light) when none is set.
local function makeIcon(size: number): (GuiObject, Frame)
	if Config.Icon == "" then
		local logo, summit = peakLogo()
		logo.AnchorPoint = Vector2.new(0, 0.5)
		return logo, summit
	end

	local light = Create.dot(8, Color.Green, UDim2.new(1, -1, 1, -1))
	light.ZIndex = 3
	Create.stroke(Color.Graphite, 0, 2).Parent = light
	local icon = Create("ImageLabel", {
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		Image = Config.Icon,
		ScaleType = Enum.ScaleType.Fit,
	}, {
		Create.corner(6),
		Light = light,
	})
	return icon, light
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
	self._controls = {}
	self._visible = false
	self._visibleToken = 0
	self._collapsed = false
	self._lights = {}
	self._rightReserve = 0
	self._active = params.active
	self._gesture = nil
	self._inputSource = nil
	self._drag = nil
	self._tab = if self._settings:GetState("tab") == "settings" then "settings" else "gestures"

	self:_build()
	self:_buildLegend()
	self:_buildSettings()
	self:_bindDrag()
	self:_restorePosition()
	self:_selectTab(self._tab, true)
	self:SetTouchDetected(params.touchDetected)
	self:SetInputStats(nil)
	self:SetActive(params.active, true)

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
	local inset = Size.Inset

	-- Header: logo, wordmark, collapse, close.
	local logo, headerLight = makeIcon(24)
	logo.Position = UDim2.new(0, inset, 0.5, 1)
	local collapseButton = Components.IconButton({
		glyph = Components.ChevronGlyph(),
		onActivated = function()
			self:SetCollapsed(not self._collapsed)
		end,
	})
	collapseButton.instance.Position = UDim2.new(1, -48, 0.5, 0)
	local closeButton = Components.IconButton({
		glyph = Components.CloseGlyph(),
		onActivated = function()
			self._params.onClose()
		end,
	})
	closeButton.instance.Position = UDim2.new(1, -12, 0.5, 0)

	local dragHandle = Create("TextButton", {
		Size = UDim2.new(1, -HEADER_BUTTONS_WIDTH, 1, 0),
		ZIndex = 4,
	})

	local header = Create("Frame", {
		Size = UDim2.new(1, 0, 0, Size.Header),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, {
		Grip = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 5),
			Size = UDim2.fromOffset(22, 3),
			BackgroundColor3 = Color.Dim,
			BackgroundTransparency = 0.3,
		}, { Create.round() }),
		Logo = logo,
		Wordmark = Create("TextLabel", {
			Position = UDim2.fromOffset(inset + 32, 0),
			Size = UDim2.new(1, -(inset + 32) - HEADER_BUTTONS_WIDTH, 1, 0),
			Text = "touch peak",
			FontFace = Font.Wordmark,
			TextSize = 13,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		DragHandle = dragHandle,
		Collapse = collapseButton.instance,
		Close = closeButton.instance,
	})

	-- Status line: state, current move, switch.
	local switch = Components.Switch({
		value = self._active,
		onChanged = function(value)
			self._params.onActiveChanged(value)
		end,
	})
	switch.instance.Position = UDim2.new(1, -inset, 0.5, 0)

	local statusLabel = Create("TextLabel", {
		Position = UDim2.fromOffset(inset, 0),
		Size = UDim2.new(1, -inset * 2 - 52, 1, 0),
		FontFace = Font.Medium,
		TextSize = 14,
		RichText = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	local status = Create("Frame", {
		Position = UDim2.fromOffset(0, Size.Header),
		Size = UDim2.new(1, 0, 0, Size.Status),
		BackgroundTransparency = 1,
	}, {
		Label = statusLabel,
		Switch = switch.instance,
	})

	-- Tabs and their pages.
	local tabs = Components.Tabs({
		options = {
			{ id = "gestures", label = self:_t("tabGestures") },
			{ id = "settings", label = self:_t("tabSettings") },
		},
		value = self._tab,
		onChanged = function(id)
			self:_selectTab(id)
		end,
	})
	tabs.instance.Position = UDim2.fromOffset(inset, 0)
	tabs.instance.Size = UDim2.new(1, -inset * 2, 0, Size.Tabs)

	local function page(): ScrollingFrame
		return Create("ScrollingFrame", {
			Size = UDim2.fromScale(1, 1),
		}, {
			Create.padding(4, inset, inset, inset),
			Create.list(0),
		})
	end
	local legendPage = page()
	local settingsPage = page()

	local pages = Create("Frame", {
		Position = UDim2.fromOffset(0, PAGES_TOP),
		Size = UDim2.new(1, 0, 1, -PAGES_TOP),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	}, {
		Gestures = legendPage,
		Settings = settingsPage,
	})

	local content = Create("Frame", {
		Position = UDim2.fromOffset(0, CONTENT_TOP),
		Size = UDim2.new(1, 0, 1, -CONTENT_TOP),
		BackgroundTransparency = 1,
	}, {
		Tabs = tabs.instance,
		Rule = Create("Frame", {
			Position = UDim2.fromOffset(inset, Size.Tabs),
			Size = UDim2.new(1, -inset * 2, 0, 1),
			BackgroundColor3 = Color.Bone,
			BackgroundTransparency = 0.92,
		}),
		Pages = pages,
	})

	-- Collapsed: just the icon (tap to open, drag to move) and the on/off switch.
	local pillIcon, pillLight = makeIcon(26)
	pillIcon.Position = UDim2.new(0, 14, 0.5, if Config.Icon == "" then 1 else 0)
	local pillSwitch = Components.Switch({
		value = self._active,
		onChanged = function(value)
			self._params.onActiveChanged(value)
		end,
	})
	pillSwitch.instance.Position = UDim2.new(1, -12, 0.5, 0)
	local pillHandle = Create("TextButton", {
		Size = UDim2.new(1, -60, 1, 0),
		ZIndex = 4,
	})
	local pill = Create("Frame", {
		Size = UDim2.new(1, 0, 0, Size.Header),
		BackgroundTransparency = 1,
		Visible = false,
	}, {
		Icon = pillIcon,
		Switch = pillSwitch.instance,
		Handle = pillHandle,
	})

	local corner = Create.corner(Radius.Panel)
	local body = Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color.Graphite,
		ClipsDescendants = true,
		ZIndex = 2,
	}, {
		Corner = corner,
		Create.stroke(Color.Bone, 0.9),
		Header = header,
		Status = status,
		Content = content,
		Pill = pill,
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

	self._shadowCorners = {}
	for index, layer in { { 2, 0.8 }, { 12, 0.92 } } do
		local spread, transparency = layer[1], layer[2]
		local shadowCorner = Create.corner(Radius.Panel + spread / 2)
		self._shadowCorners[shadowCorner] = spread
		Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 2 + index * 2),
			Size = UDim2.new(1, spread, 1, spread),
			BackgroundColor3 = Color.Black,
			BackgroundTransparency = transparency,
			ZIndex = 1,
			Parent = root,
		}, { shadowCorner })
	end

	root.Parent = self._params.parent
	self._maid:Give(root)

	self._root = root
	self._scale = scale
	self._body = body
	self._header = header
	self._status = status
	self._content = content
	self._pill = pill
	self._corner = corner
	self._dragHandles = { dragHandle, pillHandle }
	self._lights = { headerLight, pillLight }
	self._statusLabel = statusLabel
	self._switches = { switch, pillSwitch }
	self._tabs = tabs
	self._legendPage = legendPage
	self._settingsPage = settingsPage
end

function Panel:_buildLegend()
	for index, entry in LEGEND do
		Create("Frame", {
			Size = UDim2.new(1, 0, 0, 50),
			BackgroundTransparency = 1,
			LayoutOrder = index,
			Parent = self._legendPage,
		}, {
			Glyph = Create("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0, 0.5),
				Size = UDim2.fromOffset(28, 28),
				BackgroundTransparency = 1,
			}, { Icon = GestureIcons[entry.icon]() }),
			Action = Create("TextLabel", {
				Position = UDim2.fromOffset(44, 8),
				Size = UDim2.new(1, -44, 0, 18),
				Text = self:_t(entry.action),
				FontFace = Font.Medium,
				TextSize = 14,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}),
			Effect = Create("TextLabel", {
				Position = UDim2.fromOffset(44, 27),
				Size = UDim2.new(1, -44, 0, 16),
				Text = self:_t(entry.effect),
				TextSize = 13,
				TextColor3 = entry.color or Color.Ash,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}),
		})
	end
end

function Panel:_buildSettings()
	local settings = self._settings
	local page = self._settingsPage
	local order = 0

	local function add(instance: GuiObject)
		order += 1
		instance.LayoutOrder = order
		instance.Parent = page
	end

	local function group(key: string)
		add(Components.GroupTitle(self:_t(key)))
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
		add(Components.Row({ title = self:_t(title), control = control.instance, controlWidth = 104 }))
	end

	local function switch(key: string, title: string, hint: string?)
		local control = Components.Switch({
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
			controlWidth = 40,
		}))
	end

	local function choice(key: string, title: string, options, width: number)
		local control = Components.Segmented({
			options = options,
			value = settings:Get(key),
			width = width,
			onChanged = function(id)
				settings:Set(key, id)
			end,
		})
		self._controls[key] = control
		add(Components.Row({ title = self:_t(title), control = control.instance, controlWidth = width }))
	end

	group("groupSensitivity")
	stepper("rotateSensitivity", "rotateSpeed")
	stepper("zoomSensitivity", "zoomSpeed")
	stepper("panSensitivity", "panSpeed")

	group("groupCamera")
	choice("rotateMode", "rotateMode", {
		{ id = "orbit", label = self:_t("rotateModeOrbit") },
		{ id = "look", label = self:_t("rotateModeLook") },
	}, 150)
	switch("inertia", "inertia", "inertiaHint")
	switch("invertRotate", "invertRotate", "invertRotateHint")
	switch("invertPan", "invertPan", "invertPanHint")

	group("groupZoom")
	switch("showZoomStrip", "showZoomStrip", "showZoomStripHint")
	choice("zoomSide", "zoomSide", {
		{ id = "left", label = self:_t("zoomSideLeft") },
		{ id = "right", label = self:_t("zoomSideRight") },
	}, 124)

	group("groupSelection")
	switch("selectModels", "selectModels", "selectModelsHint")
	switch("showTouches", "showTouches", "showTouchesHint")
	switch("mouseInput", "mouseInput", "mouseInputHint")
	choice("language", "language", {
		{ id = "auto", label = self:_t("languageAuto") },
		{ id = "pl", label = "PL" },
		{ id = "en", label = "EN" },
	}, 138)

	group("groupDiagnostics")
	self._diagnostics = {}
	for _, key in
		{
			"touchScreen",
			"diagInput",
			"diagTouchEvents",
			"diagTouchFingers",
			"diagMouseClicks",
			"diagMouseMoves",
			"diagPinch",
			"version",
		}
	do
		local row, value = Components.ValueRow(self:_t(key))
		add(row)
		self._diagnostics[key] = value
	end
	self._diagnostics.version.Text = Config.Version

	local spacer = Create("Frame", { Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1 })
	add(spacer)
	local reset = Components.Button({
		text = self:_t("reset"),
		onActivated = function()
			settings:Reset()
		end,
	})
	add(reset.instance)
end

-- Dragging -----------------------------------------------------------------------

function Panel:_bindDrag()
	-- Both the header and the collapsed pill's icon move the window.
	for _, handle in self._dragHandles do
		self._maid:Give(handle.InputBegan:Connect(function(input)
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
	end

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
			-- A plain tap on the collapsed pill opens the window again.
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
	return math.max(CONTENT_TOP + 200, math.min(Size.PanelHeight, available))
end

function Panel:_targetSize(): Vector2
	if self._collapsed then
		return Vector2.new(Size.PillWidth, Size.Header)
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

-- Until the user drags the window it lives in the top-right corner of the
-- viewport, left of anything reserved along the right edge (the zoom strip).
function Panel:_defaultPosition(): Vector2
	local width = self:_targetSize().X
	return Vector2.new(self:_screenSize().X - width - 20 - self._rightReserve, 20)
end

-- Keeps the default position clear of `pixels` along the right edge of the screen.
function Panel:SetRightReserve(pixels: number)
	self._rightReserve = pixels
	if not self._customPosition then
		self._position = self:_defaultPosition()
		self:_applyLayout(true)
	end
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
	Create.animate(self._legendPage, info, {
		Position = UDim2.fromScale(if id == "gestures" then 0 else -1, 0),
	})
	Create.animate(self._settingsPage, info, {
		Position = UDim2.fromScale(if id == "settings" then 0 else 1, 0),
	})
	if instant then
		self._tabs.set(id, true)
	end
	self._settings:SetState("tab", id)
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
			self._scale.Scale = 0.96
			Create.tween(self._scale, Theme.Tween.Smooth, { Scale = 1 })
		end
	elseif instant then
		self._root.Visible = false
	else
		local token = self._visibleToken
		Create.tween(self._scale, Theme.Tween.Close, { Scale = 0.96 })
		task.delay(Theme.Tween.Close.Time, function()
			if token == self._visibleToken then
				self._root.Visible = false
			end
		end)
	end
end

function Panel:SetCollapsed(collapsed: boolean, instant: boolean?)
	local before = self:_targetSize()
	self._collapsed = collapsed
	local after = self:_targetSize()

	-- A window on the right half of the screen shrinks toward its right edge.
	if self._position.X + before.X / 2 > self:_screenSize().X / 2 then
		self._position += Vector2.new(before.X - after.X, 0)
	end

	self._header.Visible = not collapsed
	self._status.Visible = not collapsed
	self._content.Visible = not collapsed
	self._pill.Visible = collapsed

	local info = if instant then nil else Theme.Tween.Smooth
	local radius = if collapsed then Size.Header / 2 else Radius.Panel
	Create.animate(self._corner, info, { CornerRadius = UDim.new(0, radius) })
	for shadowCorner, spread in self._shadowCorners do
		Create.animate(shadowCorner, info, { CornerRadius = UDim.new(0, radius + spread / 2) })
	end

	self:_applyLayout(instant)
end

function Panel:SetActive(active: boolean, instant: boolean?)
	self._active = active
	for _, switch in self._switches do
		switch.set(active, instant)
	end
	self:_refreshStatus()
end

-- `viaMouse` is true when the only "finger" is Studio's mouse pointer.
function Panel:SetTouchCount(count: number, viaMouse: boolean?)
	if count > 0 then
		self._inputSource = if viaMouse then "inputMouse" else "inputTouch"
		self._diagnostics.diagInput.Text = self:_t(self._inputSource)
	end
end

function Panel:SetInputStats(stats)
	local s = stats or EMPTY_STATS
	local rows = self._diagnostics
	rows.diagTouchEvents.Text = tostring(s.touchBegan + s.touchChanged + s.touchEnded)
	rows.diagTouchFingers.Text = tostring(s.touchFingers)
	rows.diagTouchFingers.TextColor3 = if s.touchFingers >= 2 then Color.Green else Color.Bone
	rows.diagMouseClicks.Text = tostring(s.mouseDown)
	rows.diagMouseMoves.Text = tostring(s.mouseMoves)
	rows.diagPinch.Text = tostring(s.pinch)
	if not self._inputSource then
		rows.diagInput.Text = self:_t("inputNone")
	end
end

function Panel:SetGesture(gesture: string?)
	self._gesture = gesture
	self:_refreshStatus()
end

function Panel:SetTouchDetected(detected: boolean)
	local label = self._diagnostics.touchScreen
	label.Text = self:_t(if detected then "detected" else "notDetected")
	label.TextColor3 = if detected then Color.Bone else Color.Amber
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
	local active = self._active
	for _, light in self._lights do
		light.BackgroundColor3 = if active then Color.Green else Color.Amber
	end

	local text = self:_t(if active then "statusOn" else "statusPaused")
	self._statusLabel.TextColor3 = if active then Color.Bone else Color.Amber
	local gesture = self._gesture
	if active and gesture then
		local color = Theme.GestureColor[gesture] or Color.Bone
		text ..= `   <font color="{hex(color)}">{self._locale:gesture(gesture)}</font>`
	end
	self._statusLabel.Text = text
end

function Panel:Destroy()
	self._maid:Clean()
end

return Panel
