--[[
	Wires everything together: settings, input, gestures, camera, selection
	and the on-screen UI.

	"Open" means the window is shown; "active" means touch controls are
	running (and the plugin holds Studio's mouse, so Studio's own select/drag
	tool does not also react to fingers). Opening the plugin activates it.
]]

local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Settings = require(script.Parent.Settings)
local Locale = require(script.Parent.Locale)
local Signal = require(script.Parent.Util.Signal)
local Maid = require(script.Parent.Util.Maid)
local GestureRecognizer = require(script.Parent.Input.GestureRecognizer)
local TouchInput = require(script.Parent.Input.TouchInput)
local CameraController = require(script.Parent.Camera.CameraController)
local SelectionController = require(script.Parent.Selection.SelectionController)
local Theme = require(script.Parent.UI.Theme)
local Overlay = require(script.Parent.UI.Overlay)
local Panel = require(script.Parent.UI.Panel)
local ZoomStrip = require(script.Parent.UI.ZoomStrip)

local STATS_REFRESH = 0.25 -- s between diagnostics updates
-- A tap followed by a drag is a zoom, not a selection: undo the tap's selection
-- if the drag starts within this time.
local TAP_UNDO_WINDOW = 1
-- Zoom strip: dragging this many pixels changes the distance to the target e times.
local STRIP_PIXELS_PER_E = 160

local App = {}
App.__index = App

local function describe(instances: { Instance }, locale): string
	if #instances == 1 then
		return instances[1].Name
	end
	return locale:t("toastSelectionItems", #instances)
end

function App.new(plugin: Plugin)
	local self = setmetatable({}, App)
	self._plugin = plugin
	self._maid = Maid.new()
	self._open = false
	self._active = false
	self._touchDetected = UserInputService.TouchEnabled
	self._beforeTap = nil -- { selection, time } saved by the last tap
	self._statsScheduled = false
	self._mouseOnlyHintShown = false

	self.OpenChanged = Signal.new()

	self.settings = Settings.new(plugin)
	self.locale = Locale.new(self.settings:Get("language"))
	self.recognizer = GestureRecognizer.new()
	self.recognizer:SetCombine(self.settings:Get("combineGestures"))
	self.camera = CameraController.new(self.settings)
	self.selection = SelectionController.new(self.settings)

	self.input = TouchInput.new(self.recognizer, {
		isBlocked = function(position)
			return (self.panel ~= nil and self.panel:ContainsPoint(position))
				or (self.zoomStrip ~= nil and self.zoomStrip:ContainsPoint(position))
		end,
		mouseEnabled = function()
			return self.settings:Get("mouseInput")
		end,
	})

	self:_bindGestures()
	self:_bindSettings()

	return self
end

-- Lifecycle --------------------------------------------------------------------------

function App:IsOpen(): boolean
	return self._open
end

function App:Toggle()
	if self._open then
		self:Close()
	else
		self:Open()
	end
end

function App:Open()
	if self._open then
		return
	end
	self._open = true
	self:_ensureGui()
	-- Opening always shows the full window; it can be collapsed from there.
	self.panel:SetCollapsed(false, true)
	self.panel:SetVisible(true)
	self:SetActive(true)
	self.OpenChanged:Fire(true)
end

function App:Close()
	if not self._open then
		return
	end
	self._open = false
	self:SetActive(false)
	if self.panel then
		self.panel:SetVisible(false)
	end
	self.OpenChanged:Fire(false)
end

function App:SetActive(active: boolean)
	if active == self._active then
		if self.panel then
			self.panel:SetActive(active)
		end
		return
	end
	self._active = active

	if active then
		-- Take over the mouse so Studio's select/drag tools do not react to the same touches.
		self._plugin:Activate(true)
		self.input:Start()
		self._heartbeat = RunService.Heartbeat:Connect(function(dt)
			self:_step(dt)
		end)
	else
		self.input:Stop()
		self.camera:Stop()
		if self._heartbeat then
			self._heartbeat:Disconnect()
			self._heartbeat = nil
		end
		if self.overlay then
			self.overlay:ClearTouches()
			self.overlay:ShowGesture(nil, nil)
		end
		pcall(function()
			if self._plugin:IsActivated() then
				self._plugin:Deactivate()
			end
		end)
	end

	if self.panel then
		self.panel:SetActive(active)
		self.panel:SetTouchCount(0)
		self.panel:SetGesture(nil)
	end
	self:_refreshZoomStrip()
end

-- Runs every frame while touch controls are active.
function App:_step(dt: number)
	-- Both fingers have reported by now: apply this frame's two-finger movement.
	self.recognizer:Flush()
	self.camera:Step(dt)
end

-- The zoom strip is only useful while touch controls are running.
function App:_refreshZoomStrip()
	local strip = self.zoomStrip
	if strip then
		strip:SetSide(self.settings:Get("zoomSide"))
		strip:SetVisible(self._open and self._active and self.settings:Get("showZoomStrip"))
	end
end

-- Shows a camera move in the window and on the viewport.
function App:_showGesture(gesture: string?)
	if self.panel then
		self.panel:SetGesture(gesture)
	end
	if self.overlay then
		local text = if gesture then self.locale:gesture(gesture) else nil
		self.overlay:ShowGesture(text, if gesture then Theme.GestureColor[gesture] else nil)
	end
end

-- Studio deactivates the plugin when the user picks another tool (Select, Move, ...).
function App:OnPluginDeactivated()
	if self._active and not self._plugin:IsActivated() then
		self:SetActive(false)
		if self.overlay then
			self.overlay:Toast(self.locale:t("toastPausedByTool"), Theme.Color.Amber)
		end
	end
end

function App:Destroy()
	self:SetActive(false)
	self:_destroyGui()
	self._maid:Clean()
	self.OpenChanged:DisconnectAll()
end

-- GUI ----------------------------------------------------------------------------------

function App:_ensureGui()
	if self.gui then
		return
	end

	-- A previous copy of the plugin (e.g. before a reload) may have left its UI behind.
	local leftover = CoreGui:FindFirstChild("TouchPeak")
	if leftover then
		leftover:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "TouchPeak"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 50
	gui.Archivable = false
	gui.Parent = CoreGui
	self.gui = gui

	self.overlay = Overlay.new(gui, self.settings)
	self:_createPanel()
	self:_createZoomStrip()
end

function App:_createZoomStrip()
	local strip = ZoomStrip.new({
		parent = self.gui,
		side = self.settings:Get("zoomSide"),
	})
	local function center(): Vector2
		local camera = Workspace.CurrentCamera
		return if camera then camera.ViewportSize / 2 else Vector2.zero
	end
	strip.Began:Connect(function()
		-- Zoom toward whatever is in the middle of the screen.
		self.camera:BeginInteraction()
		self.camera:AnchorAt(center())
		self:_showGesture("zoom")
	end)
	strip.Moved:Connect(function(dy)
		-- Finger up (negative dy) moves closer.
		self.camera:Zoom(math.exp(dy / STRIP_PIXELS_PER_E), center())
	end)
	strip.Ended:Connect(function()
		self:_showGesture(nil)
	end)
	self.zoomStrip = strip
	self:_refreshZoomStrip()
end

function App:_createPanel()
	self.panel = Panel.new({
		parent = self.gui,
		settings = self.settings,
		locale = self.locale,
		active = self._active,
		touchDetected = self._touchDetected,
		onActiveChanged = function(active)
			self:SetActive(active)
			if active and self.overlay then
				self.overlay:Toast(self.locale:t("toastResumed"), Theme.Color.Green)
			end
		end,
		onClose = function()
			self:Close()
		end,
	})
	self.panel:SetInputStats(self.input.Stats)
end

-- Rebuilds the window in place (used when the language changes).
function App:_rebuildPanel()
	if not self.panel then
		return
	end
	local wasVisible = self.panel:IsVisible()
	local wasCollapsed = self.panel:IsCollapsed()
	self.panel:Destroy()
	self:_createPanel()
	self.panel:SetCollapsed(wasCollapsed, true)
	self.panel:SetVisible(wasVisible, true)
	if self.zoomStrip then
		self.zoomStrip:Destroy()
		self:_createZoomStrip()
	end
end

function App:_destroyGui()
	if self.zoomStrip then
		self.zoomStrip:Destroy()
		self.zoomStrip = nil
	end
	if self.panel then
		self.panel:Destroy()
		self.panel = nil
	end
	if self.overlay then
		self.overlay:Destroy()
		self.overlay = nil
	end
	if self.gui then
		self.gui:Destroy()
		self.gui = nil
	end
end

-- Wiring -------------------------------------------------------------------------------

function App:_bindGestures()
	local recognizer = self.recognizer
	local camera = self.camera
	local maid = self._maid

	-- Visual feedback for real fingers.
	maid:Give(self.input.TouchBegan:Connect(function(id, position)
		if not self._touchDetected then
			self._touchDetected = true
			if self.panel then
				self.panel:SetTouchDetected(true)
			end
		end
		if self.overlay then
			self.overlay:TouchBegan(id, position)
		end
	end))
	maid:Give(self.input.TouchMoved:Connect(function(id, position)
		if self.overlay then
			self.overlay:TouchMoved(id, position)
		end
	end))
	maid:Give(self.input.TouchEnded:Connect(function(id)
		if self.overlay then
			self.overlay:TouchEnded(id)
		end
	end))

	-- Camera.
	maid:Give(recognizer.InteractionBegan:Connect(function()
		camera:BeginInteraction()
	end))
	maid:Give(recognizer.Rotate:Connect(function(delta)
		camera:Rotate(delta)
	end))
	maid:Give(recognizer.RotateEnded:Connect(function(velocity)
		camera:StartInertia("rotate", velocity)
	end))
	maid:Give(recognizer.AnchorBegan:Connect(function(centroid)
		camera:AnchorAt(centroid)
	end))
	maid:Give(recognizer.Pan:Connect(function(delta)
		camera:Pan(delta)
	end))
	maid:Give(recognizer.PanEnded:Connect(function(velocity)
		camera:StartInertia("pan", velocity)
	end))
	maid:Give(recognizer.Zoom:Connect(function(scale, centroid)
		camera:Zoom(scale, centroid)
	end))

	-- Roblox's own pinch event, used only when Studio does not report both fingers.
	maid:Give(self.input.PinchBegan:Connect(function(centroid)
		local viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.zero
		camera:AnchorAt(centroid or viewport / 2)
	end))
	maid:Give(self.input.Pinch:Connect(function(scale, centroid)
		camera:Zoom(scale, centroid)
	end))

	-- Selection.
	maid:Give(recognizer.Tap:Connect(function(position)
		self:_onTap(position)
	end))
	maid:Give(recognizer.DoubleTap:Connect(function(position)
		self:_onDoubleTap(position)
	end))
	maid:Give(recognizer.LongPress:Connect(function(position)
		self:_onLongPress(position)
	end))
	maid:Give(recognizer.TapDragBegan:Connect(function()
		self:_undoTapSelection()
	end))

	-- Status readouts.
	maid:Give(recognizer.GestureChanged:Connect(function(gesture)
		self:_showGesture(gesture)
		if gesture then
			self:_maybeExplainMouseOnly()
		end
	end))
	maid:Give(recognizer.TouchCountChanged:Connect(function(count)
		if self.panel then
			self.panel:SetTouchCount(count, self.input:IsMouseActive())
		end
	end))

	-- Diagnostics: refresh the counters a few times per second at most.
	maid:Give(self.input.StatsChanged:Connect(function()
		if self._statsScheduled then
			return
		end
		self._statsScheduled = true
		task.delay(STATS_REFRESH, function()
			self._statsScheduled = false
			if self.panel then
				self.panel:SetInputStats(self.input.Stats)
			end
		end)
	end))
end

-- On a touch screen where Studio only ever sends mouse events, point the user
-- at the mode bar once: pinch and two-finger pan cannot work there.
function App:_maybeExplainMouseOnly()
	if self._mouseOnlyHintShown or not self.input:IsMouseActive() then
		return
	end
	if not UserInputService.TouchEnabled or self.input.Stats.touchBegan > 0 then
		return
	end
	self._mouseOnlyHintShown = true
	if self.overlay then
		self.overlay:Toast(self.locale:t("toastMouseOnly"), Theme.Color.Amber)
	end
end

function App:_bindSettings()
	self._maid:Give(self.settings.Changed:Connect(function(key, value)
		if key == "combineGestures" then
			self.recognizer:SetCombine(value)
		elseif key == "language" then
			self.locale:SetLanguage(value)
			-- Defer so the language button finishes handling its click first.
			task.defer(function()
				self:_rebuildPanel()
			end)
		elseif key == "showTouches" and not value and self.overlay then
			self.overlay:ClearTouches()
		elseif key == "showZoomStrip" or key == "zoomSide" then
			self:_refreshZoomStrip()
		end
	end))
end

function App:_onTap(position: Vector2)
	self._beforeTap = { selection = self.selection:Get(), time = os.clock() }
	local target = self.selection:SelectAt(position)
	local overlay = self.overlay
	if not overlay then
		return
	end
	overlay:Ripple(position)
	if target then
		overlay:Toast(self.locale:t("toastSelected", target.Name))
	else
		overlay:Toast(self.locale:t("toastCleared"), Theme.Color.Ash)
	end
end

-- The tap that started a tap-and-drag zoom should not have changed the selection.
function App:_undoTapSelection()
	local saved = self._beforeTap
	self._beforeTap = nil
	if saved and os.clock() - saved.time <= TAP_UNDO_WINDOW then
		self.selection:Set(saved.selection)
		if self.overlay then
			self.overlay:HideToast()
		end
	end
end

function App:_onDoubleTap(position: Vector2)
	local target = self.selection:SelectAt(position)
	local focusOn = if target then { target } else self.selection:Get()
	local focused = #focusOn > 0 and self.camera:FocusOn(focusOn)

	local overlay = self.overlay
	if not overlay then
		return
	end
	overlay:Ripple(position)
	if focused then
		overlay:Toast(self.locale:t("toastFocused", describe(focusOn, self.locale)))
	else
		overlay:Toast(self.locale:t("toastNothingToFocus"), Theme.Color.Ash)
	end
end

function App:_onLongPress(position: Vector2)
	local target, added = self.selection:ToggleAt(position)
	local overlay = self.overlay
	if not overlay or not target then
		return
	end
	overlay:Ripple(position)
	local key = if added then "toastAdded" else "toastRemoved"
	overlay:Toast(self.locale:t(key, target.Name), if added then Theme.Color.Bone else Theme.Color.Ash)
end

return App
