--[[
	Touch Peak – touch controls for the Roblox Studio camera.

	  1 finger ............ rotate the camera
	  2 fingers apart ..... zoom
	  2 fingers together .. pan
	  tap ................. select
	  double tap .......... focus the camera on an object
	  press and hold ...... add to / remove from the selection
]]

local RunService = game:GetService("RunService")

-- Plugins also run inside Play Solo sessions; only the edit session needs us.
if not plugin or not RunService:IsEdit() then
	return
end

local Config = require(script.Config)
local App = require(script.App)

local app = App.new(plugin)

local toolbar = plugin:CreateToolbar(Config.ToolbarName)
local button = toolbar:CreateButton(Config.ButtonId, app.locale:t("buttonTooltip"), Config.Icon, Config.ButtonText)
button.ClickableWhenViewportHidden = true

button.Click:Connect(function()
	app:Toggle()
end)

app.OpenChanged:Connect(function(open)
	button:SetActive(open)
end)

plugin.Deactivation:Connect(function()
	app:OnPluginDeactivated()
end)

plugin.Unloading:Connect(function()
	app:Destroy()
end)
