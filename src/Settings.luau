--[[
	Persistent plugin settings backed by plugin:GetSetting / plugin:SetSetting.

	`store` is anything with GetSetting/SetSetting (the plugin object in Studio,
	or nil for an in-memory store in tests).
]]

local Signal = require(script.Parent.Util.Signal)

local PREFIX = "TouchPeak_"

local DEFAULTS = {
	rotateSensitivity = 1,
	zoomSensitivity = 1,
	panSensitivity = 1,
	rotateMode = "orbit", -- "orbit" around what you look at, or "look" around in place
	inertia = true,
	combineGestures = false,
	invertRotate = false,
	invertPan = false,
	selectModels = true,
	showTouches = true,
	mouseInput = true,
	showNavigator = true,
	language = "auto", -- "auto" | "pl" | "en"
}

local CHOICES = {
	rotateMode = { orbit = true, look = true },
	language = { auto = true, pl = true, en = true },
}

local SENSITIVITY_RANGE = { min = 0.25, max = 3 }

local Settings = {}
Settings.__index = Settings

Settings.Defaults = DEFAULTS
Settings.SensitivityRange = SENSITIVITY_RANGE

local function sanitize(key: string, value: any): any
	local default = DEFAULTS[key]
	if value == nil or typeof(value) ~= typeof(default) then
		return default
	end
	if CHOICES[key] and not CHOICES[key][value] then
		return default
	end
	if typeof(default) == "number" then
		if value ~= value then -- NaN
			return default
		end
		return math.clamp(value, SENSITIVITY_RANGE.min, SENSITIVITY_RANGE.max)
	end
	return value
end

function Settings.new(store)
	local self = setmetatable({}, Settings)
	self._store = store
	self._values = {}
	self.Changed = Signal.new()

	for key in DEFAULTS do
		self._values[key] = sanitize(key, self:_read(key))
	end

	return self
end

function Settings:_read(key: string): any
	if not self._store then
		return nil
	end
	local ok, value = pcall(self._store.GetSetting, self._store, PREFIX .. key)
	return if ok then value else nil
end

function Settings:_write(key: string, value: any)
	if self._store then
		pcall(self._store.SetSetting, self._store, PREFIX .. key, value)
	end
end

function Settings:Get(key: string): any
	assert(DEFAULTS[key] ~= nil, `Unknown setting "{key}"`)
	return self._values[key]
end

function Settings:Set(key: string, value: any)
	assert(DEFAULTS[key] ~= nil, `Unknown setting "{key}"`)
	value = sanitize(key, value)
	if self._values[key] == value then
		return
	end
	self._values[key] = value
	self:_write(key, value)
	self.Changed:Fire(key, value)
end

function Settings:Reset()
	for key, default in DEFAULTS do
		self:Set(key, default)
	end
end

-- UI state (panel position, last tab, ...) that is remembered but is not a user preference.
function Settings:GetState(key: string): any
	return self:_read("State_" .. key)
end

function Settings:SetState(key: string, value: any)
	self:_write("State_" .. key, value)
end

return Settings
