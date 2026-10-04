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

	self.OpenChanged = Signal.new()

	self.settings = Settings.new(plugin)
	self.locale = Locale.new(self.settings:Get("language"))
	self.recognizer = GestureRecognizer.new()
	self.recognizer:SetCombine(self.settings:Get("combineGestures"))
	self.camera = CameraController.new(self.settings)
	self.selection = SelectionController.new(self.settings)

	self.input = TouchInput.new(self.recognizer, {
		isBlocked = function(position)
			return self.panel ~= nil and self.panel:ContainsPoint(position)
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
			-- Both fingers have reported by now: apply this frame's two-finger movement.
			self.recognizer:Flush()
			self.camera:Step(dt)
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
			self.overlay:ShowGesture(nil)
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
end

-- Studio deactivates the plugin when the user picks another tool (Select, Move, ...).
function App:OnPluginDeactivated()
	if self._active and not self._plugin:IsActivated() then
		self:SetActive(false)
		if self.overlay then
			self.overlay:Toast(self.locale:t("toastPausedByTool"), Theme.Color.Warning)
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
				self.overlay:Toast(self.locale:t("toastResumed"), Theme.Color.Success)
			end
		end,
		onClose = function()
			self:Close()
		end,
	})
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
end

function App:_destroyGui()
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
	maid:Give(recognizer.TwoFingerBegan:Connect(function(centroid)
		camera:BeginTwoFinger(centroid)
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

	-- Status readouts.
	maid:Give(recognizer.GestureChanged:Connect(function(gesture)
		if self.panel then
			self.panel:SetGesture(gesture)
		end
		if self.overlay then
			self.overlay:ShowGesture(if gesture then self.locale:gesture(gesture) else nil)
		end
	end))
	maid:Give(recognizer.TouchCountChanged:Connect(function(count)
		if self.panel then
			self.panel:SetTouchCount(count)
		end
	end))
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
		end
	end))
end

function App:_onTap(position: Vector2)
	local target = self.selection:SelectAt(position)
	local overlay = self.overlay
	if not overlay then
		return
	end
	overlay:Ripple(position, Theme.Color.Accent)
	if target then
		overlay:Toast(self.locale:t("toastSelected", target.Name), Theme.Color.Accent)
	else
		overlay:Toast(self.locale:t("toastCleared"), Theme.Color.TextDim)
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
	overlay:Ripple(position, Theme.Color.AccentAlt)
	if focused then
		overlay:Toast(self.locale:t("toastFocused", describe(focusOn, self.locale)), Theme.Color.AccentAlt)
	else
		overlay:Toast(self.locale:t("toastNothingToFocus"), Theme.Color.TextDim)
	end
end

function App:_onLongPress(position: Vector2)
	local target, added = self.selection:ToggleAt(position)
	local overlay = self.overlay
	if not overlay or not target then
		return
	end
	overlay:Ripple(position, Theme.Color.Success)
	local key = if added then "toastAdded" else "toastRemoved"
	overlay:Toast(self.locale:t(key, target.Name), if added then Theme.Color.Success else Theme.Color.Warning)
end

return App
