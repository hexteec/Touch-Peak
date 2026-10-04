--[[
	A fake Roblox Studio for running the plugin's modules under Lune.

	* Instances are validated against Roblox's real reflection database, so a
	  misspelled property name, a read-only property or a value of the wrong
	  type raises an error just like it would in Studio.
	* Workspace:Raycast intersects axis-aligned parts (and an optional ground
	  plane standing in for Terrain).
	* Cameras implement the projection helpers used by the plugin.
	* TweenService applies tween goals immediately.

	Every World is independent: `World.new()` gives a fresh DataModel and a
	fresh module cache for `world:require("Camera/CameraController")`.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local db = roblox.getReflectionDatabase()

local Vector2 = roblox.Vector2
local Vector3 = roblox.Vector3
local RealCFrame = roblox.CFrame
local Enum = roblox.Enum

local SCREEN_SIZE = Vector2.new(1280, 720)

-- Lune's CFrame.lookAt points the wrong way; build it from vectors instead.
local CFrame = setmetatable({
	lookAt = function(at: Vector3, target: Vector3, up: Vector3?)
		local look = (target - at).Unit
		local right = look:Cross(up or Vector3.yAxis)
		if right.Magnitude < 1e-6 then
			right = look:Cross(Vector3.xAxis)
		end
		right = right.Unit
		return RealCFrame.fromMatrix(at, right, right:Cross(look))
	end,
}, { __index = RealCFrame })

-- Signals ---------------------------------------------------------------------------

local connections = setmetatable({}, { __mode = "k" })

local function newSignal()
	local signal = { _handlers = {} }

	function signal:Connect(callback)
		local connection = { Connected = true }
		function connection.Disconnect(conn)
			conn.Connected = false
			local index = table.find(signal._handlers, conn)
			if index then
				table.remove(signal._handlers, index)
			end
		end
		connection._callback = callback
		connections[connection] = true
		table.insert(signal._handlers, connection)
		return connection
	end

	function signal:Fire(...)
		for _, connection in table.clone(signal._handlers) do
			if connection.Connected then
				connection._callback(...)
			end
		end
	end

	function signal:Count()
		return #signal._handlers
	end

	return signal
end

-- Reflection helpers ------------------------------------------------------------------

local chainCache = {}
local function classChain(className: string): { string }
	local cached = chainCache[className]
	if cached then
		return cached
	end
	local chain = {}
	local name = className
	while name do
		local class = db:GetClass(name)
		if not class then
			break
		end
		table.insert(chain, name)
		name = class.Superclass
	end
	chainCache[className] = chain
	return chain
end

local function findProperty(className: string, key: string)
	for _, name in classChain(className) do
		local property = db:GetClass(name).Properties[key]
		if property then
			return property
		end
	end
	return nil
end

local EVENTS = {
	Instance = { "ChildAdded", "ChildRemoved", "Destroying", "AncestryChanged", "Changed" },
	GuiObject = { "InputBegan", "InputChanged", "InputEnded", "MouseEnter", "MouseLeave" },
	GuiButton = { "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up" },
}

local function hasEvent(className: string, key: string): boolean
	for _, name in classChain(className) do
		local events = EVENTS[name]
		if events and table.find(events, key) then
			return true
		end
	end
	return false
end

local NUMBER_TYPES = { Float32 = true, Float64 = true, Int32 = true, Int64 = true }

local function checkType(className: string, key: string, datatype: string, value: any, isInstance)
	local ok
	if value == nil then
		ok = datatype == "Ref"
	elseif NUMBER_TYPES[datatype] then
		ok = type(value) == "number"
	elseif datatype == "Bool" then
		ok = type(value) == "boolean"
	elseif datatype == "String" or datatype == "Content" or datatype == "ContentId" then
		ok = type(value) == "string"
	elseif datatype == "Ref" then
		ok = isInstance(value)
	elseif string.sub(datatype, 1, 5) == "Enum." then
		ok = typeof(value) == "EnumItem" and tostring(value.EnumType) == datatype
	else
		ok = typeof(value) == datatype
	end
	if not ok then
		error(`Unable to assign property {key}. {datatype} expected, got {typeof(value)} ({className})`, 3)
	end
end

local DEFAULTS = {
	Visible = true,
	Enabled = true,
	Archivable = true,
	Locked = false,
	Transparency = 0,
	BackgroundTransparency = 0,
	Rotation = 0,
	Text = "",
	Size = roblox.UDim2.new(),
	Position = roblox.UDim2.new(),
	AnchorPoint = Vector2.zero,
	FieldOfView = 70,
}

-- Ray / box intersection (slab method). Returns distance along the unit direction.
local function rayBox(origin: Vector3, direction: Vector3, center: Vector3, size: Vector3): (number?, Vector3?)
	local half = size / 2
	local tMin, tMax = -math.huge, math.huge
	local normal = nil
	for _, axis in { "X", "Y", "Z" } do
		local o, d = origin[axis], direction[axis]
		local lo, hi = center[axis] - half[axis], center[axis] + half[axis]
		if math.abs(d) < 1e-9 then
			if o < lo or o > hi then
				return nil
			end
		else
			local t1, t2 = (lo - o) / d, (hi - o) / d
			local sign = -1
			if t1 > t2 then
				t1, t2 = t2, t1
				sign = 1
			end
			if t1 > tMin then
				tMin = t1
				normal = Vector3.new(axis == "X" and sign or 0, axis == "Y" and sign or 0, axis == "Z" and sign or 0)
			end
			tMax = math.min(tMax, t2)
			if tMin > tMax then
				return nil
			end
		end
	end
	if tMin < 0 then
		return nil -- starts inside or behind
	end
	return tMin, normal
end

-- World -------------------------------------------------------------------------------

local World = {}
World.__index = World

World.ScreenSize = SCREEN_SIZE
World.CFrame = CFrame
World.Vector2 = Vector2
World.Vector3 = Vector3
World.Enum = Enum

function World.new()
	local self = setmetatable({}, World)
	self._data = setmetatable({}, { __mode = "k" }) -- proxy -> data
	self._cache = {}
	self.groundPlane = false
	self.heartbeat = newSignal()

	local world = self

	-- Instances ---------------------------------------------------------------------

	local function isInstance(value)
		return world._data[value] ~= nil
	end
	self.isInstance = isInstance

	local methods = {}

	local function newInstance(className: string)
		if not db:GetClass(className) then
			error(`Unable to create an Instance of type "{className}"`, 2)
		end
		local data = {
			ClassName = className,
			props = { Name = className },
			children = {},
			events = {},
			propertySignals = {},
			destroyed = false,
		}
		local proxy = setmetatable({}, {
			__index = function(proxy, key)
				if key == "ClassName" then
					return className
				elseif key == "Parent" then
					return data.parent
				end
				local method = methods[key]
				if method then
					return method
				end
				if key == "AbsolutePosition" or key == "AbsoluteSize" then
					local position, size = world:_absolute(proxy)
					return if key == "AbsolutePosition" then position else size
				end
				if findProperty(className, key) then
					local value = data.props[key]
					if value == nil then
						value = DEFAULTS[key]
					end
					return value
				end
				if hasEvent(className, key) then
					data.events[key] = data.events[key] or newSignal()
					return data.events[key]
				end
				for _, child in data.children do
					if world._data[child].props.Name == key then
						return child
					end
				end
				error(`{key} is not a valid member of {className} "{data.props.Name}"`, 2)
			end,
			__newindex = function(proxy, key, value)
				if data.destroyed and key == "Parent" then
					error(`The Parent property of {data.props.Name} is locked`, 2)
				end
				if key == "Parent" then
					if value ~= nil and not isInstance(value) then
						error("Parent must be an Instance", 2)
					end
					local old = data.parent
					if old then
						local siblings = world._data[old].children
						table.remove(siblings, table.find(siblings, proxy))
					end
					data.parent = value
					if value then
						table.insert(world._data[value].children, proxy)
					end
					return
				end
				local property = findProperty(className, key)
				if not property then
					error(`{key} is not a valid member of {className}`, 2)
				end
				local scriptability = tostring(property.Scriptability)
				if scriptability ~= "ReadWrite" then
					error(`Unable to assign property {key}. Property is read only ({className})`, 2)
				end
				checkType(className, key, tostring(property.Datatype), value, isInstance)
				data.props[key] = value
				local signal = data.propertySignals[key]
				if signal then
					signal:Fire()
				end
			end,
			__tostring = function()
				return data.props.Name
			end,
		})
		world._data[proxy] = data
		return proxy
	end
	self.newInstance = newInstance

	local function descendants(instance, out)
		for _, child in world._data[instance].children do
			table.insert(out, child)
			descendants(child, out)
		end
		return out
	end

	function methods.IsA(instance, className)
		return table.find(classChain(world._data[instance].ClassName), className) ~= nil
	end
	function methods.Destroy(instance)
		local data = world._data[instance]
		if data.destroyed then
			return
		end
		for _, child in table.clone(data.children) do
			child:Destroy()
		end
		instance.Parent = nil
		data.destroyed = true
	end
	function methods.GetChildren(instance)
		return table.clone(world._data[instance].children)
	end
	function methods.GetDescendants(instance)
		return descendants(instance, {})
	end
	function methods.FindFirstChild(instance, name)
		for _, child in world._data[instance].children do
			if world._data[child].props.Name == name then
				return child
			end
		end
		return nil
	end
	function methods.IsDescendantOf(instance, ancestor)
		local current = world._data[instance].parent
		while current do
			if current == ancestor then
				return true
			end
			current = world._data[current].parent
		end
		return false
	end
	function methods.GetPropertyChangedSignal(instance, key)
		local data = world._data[instance]
		if key ~= "AbsoluteSize" and key ~= "AbsolutePosition" and not findProperty(data.ClassName, key) then
			error(`{key} is not a valid property name.`, 2)
		end
		data.propertySignals[key] = data.propertySignals[key] or newSignal()
		return data.propertySignals[key]
	end
	function methods.SetAttribute(instance, key, value)
		world._data[instance].attributes = world._data[instance].attributes or {}
		world._data[instance].attributes[key] = value
	end
	function methods.GetAttribute(instance, key)
		local attributes = world._data[instance].attributes
		return attributes and attributes[key]
	end
	function methods.GetBoundingBox(model)
		local min, max
		for _, part in descendants(model, {}) do
			if part:IsA("BasePart") then
				local center, half = part.CFrame.Position, part.Size / 2
				local lo, hi = center - half, center + half
				min = if min
					then Vector3.new(math.min(min.X, lo.X), math.min(min.Y, lo.Y), math.min(min.Z, lo.Z))
					else lo
				max = if max
					then Vector3.new(math.max(max.X, hi.X), math.max(max.Y, hi.Y), math.max(max.Z, hi.Z))
					else hi
			end
		end
		if not min then
			return RealCFrame.new(), Vector3.zero
		end
		return RealCFrame.new((min + max) / 2), max - min
	end

	-- Camera projection ---------------------------------------------------------------
	local function viewportRay(camera, x, y)
		local viewport = camera.ViewportSize
		local cframe = camera.CFrame
		local tanY = math.tan(math.rad(camera.FieldOfView) / 2)
		local nx = (2 * x / viewport.X - 1) * tanY * (viewport.X / viewport.Y)
		local ny = (1 - 2 * y / viewport.Y) * tanY
		local direction = (cframe.LookVector + cframe.RightVector * nx + cframe.UpVector * ny).Unit
		return roblox.Ray.new(cframe.Position, direction)
	end
	function methods.ViewportPointToRay(camera, x, y)
		return viewportRay(camera, x, y)
	end
	function methods.ScreenPointToRay(camera, x, y)
		return viewportRay(camera, x, y)
	end
	function methods.WorldToViewportPoint(camera, point)
		local viewport = camera.ViewportSize
		local cframe = camera.CFrame
		local relative = cframe:PointToObjectSpace(point)
		local depth = -relative.Z
		local tanY = math.tan(math.rad(camera.FieldOfView) / 2)
		local nx = relative.X / depth / (tanY * viewport.X / viewport.Y)
		local ny = relative.Y / depth / tanY
		return Vector3.new((nx + 1) / 2 * viewport.X, (1 - ny) / 2 * viewport.Y, depth), depth > 0
	end

	-- Raycasting against axis-aligned parts.
	function methods.Raycast(workspace, origin, direction, params)
		local length = direction.Magnitude
		local unit = direction.Unit
		local excluded = {}
		if params and params.FilterType == Enum.RaycastFilterType.Exclude then
			for _, instance in params.FilterDescendantsInstances do
				excluded[instance] = true
				for _, descendant in descendants(instance, {}) do
					excluded[descendant] = true
				end
			end
		end

		local best, bestDistance, bestNormal = nil, math.huge, nil
		for _, part in descendants(workspace, {}) do
			if part:IsA("BasePart") and not part:IsA("Terrain") and not excluded[part] then
				local distance, normal = rayBox(origin, unit, part.CFrame.Position, part.Size)
				if distance and distance <= length and distance < bestDistance then
					best, bestDistance, bestNormal = part, distance, normal
				end
			end
		end

		local terrain = workspace:FindFirstChild("Terrain")
		if world.groundPlane and terrain and not excluded[terrain] and math.abs(unit.Y) > 1e-9 then
			local distance = -origin.Y / unit.Y
			if distance >= 0 and distance <= length and distance < bestDistance then
				best, bestDistance, bestNormal = terrain, distance, Vector3.yAxis
			end
		end

		if not best then
			return nil
		end
		return {
			Instance = best,
			Position = origin + unit * bestDistance,
			Normal = bestNormal,
			Distance = bestDistance,
		}
	end

	-- Services ------------------------------------------------------------------------

	local workspace = newInstance("Workspace")
	local camera = newInstance("Camera")
	camera.Name = "Camera"
	camera.Parent = workspace
	world._data[camera].props.ViewportSize = SCREEN_SIZE
	camera.FieldOfView = 70
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 20, 40), Vector3.new(0, 0, 0))
	camera.Focus = RealCFrame.new()
	workspace.CurrentCamera = camera
	local terrain = newInstance("Terrain")
	terrain.Name = "Terrain"
	terrain.Parent = workspace

	local coreGui = newInstance("CoreGui")

	local selection = { _items = {}, SelectionChanged = newSignal() }
	function selection.Get(_)
		return table.clone(selection._items)
	end
	function selection.Set(_, items)
		for _, item in items do
			assert(isInstance(item), "Selection:Set expects Instances")
		end
		selection._items = table.clone(items)
		selection.SelectionChanged:Fire()
	end

	local userInputService = {
		TouchEnabled = true,
		InputBegan = newSignal(),
		InputChanged = newSignal(),
		InputEnded = newSignal(),
		TouchEnded = newSignal(),
		WindowFocusReleased = newSignal(),
	}
	function userInputService.GetMouseLocation(_)
		return Vector2.zero
	end

	local tweenService = {}
	function tweenService.Create(_, instance, info, goal)
		assert(isInstance(instance), "TweenService:Create expects an Instance")
		assert(type(info) == "table" and info.__TweenInfo, "TweenService:Create expects a TweenInfo")
		for key, value in goal do
			-- Validate the goal eagerly, like Roblox does.
			local property = findProperty(world._data[instance].ClassName, key)
			if not property then
				error(`No property named '{key}' for object '{instance.Name}'`, 2)
			end
		end
		local tween = newInstance("Tween")
		local state = { playing = false }
		world._data[tween].tweenState = state
		world._data[tween].tweenGoal = goal
		world._data[tween].tweenTarget = instance
		return tween
	end
	function methods.Play(tween)
		local data = world._data[tween]
		data.tweenState.playing = true
		for key, value in data.tweenGoal do
			data.tweenTarget[key] = value
		end
	end
	function methods.Pause(tween)
		world._data[tween].tweenState.playing = false
	end
	function methods.Cancel(tween)
		world._data[tween].tweenState.playing = false
	end

	local runService = { Heartbeat = self.heartbeat }
	function runService.IsEdit(_)
		return true
	end

	local services = {
		Workspace = workspace,
		CoreGui = coreGui,
		Selection = selection,
		UserInputService = userInputService,
		TweenService = tweenService,
		RunService = runService,
		StudioService = { StudioLocaleId = "en-us" },
		LocalizationService = { SystemLocaleId = "en-us" },
	}

	local game = {}
	function game.GetService(_, name)
		local service = services[name]
		if not service then
			error(`'{name}' is not a valid Service name`, 2)
		end
		return service
	end

	self.game = game
	self.services = services
	self.workspace = workspace
	self.camera = camera
	self.terrain = terrain
	self.coreGui = coreGui
	self.selection = selection
	self.userInputService = userInputService

	-- Globals visible to plugin modules.
	self.globals = {
		game = game,
		workspace = workspace,
		Instance = { new = newInstance },
		Vector2 = Vector2,
		Vector3 = Vector3,
		CFrame = CFrame,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Color3 = roblox.Color3,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		Font = roblox.Font,
		Enum = Enum,
		Ray = roblox.Ray,
		TweenInfo = {
			new = function(time, style, direction, repeatCount, reverses, delayTime)
				return {
					__TweenInfo = true,
					Time = time or 1,
					EasingStyle = style,
					EasingDirection = direction,
					RepeatCount = repeatCount or 0,
					Reverses = reverses or false,
					DelayTime = delayTime or 0,
				}
			end,
		},
		RaycastParams = {
			new = function()
				return { FilterType = Enum.RaycastFilterType.Exclude, FilterDescendantsInstances = {} }
			end,
		},
		task = task,
		typeof = function(value)
			if world._data[value] then
				return "Instance"
			elseif connections[value] then
				return "RBXScriptConnection"
			end
			return typeof(value)
		end,
	}

	return self
end

-- GUI layout (no UIScale/UIListLayout support; good enough for hit tests).
function World:_absolute(instance)
	local data = self._data[instance]
	if not data then
		return Vector2.zero, Vector2.zero
	end
	if instance:IsA("ScreenGui") or instance:IsA("CoreGui") then
		return Vector2.zero, SCREEN_SIZE
	end
	if not instance:IsA("GuiObject") then
		return Vector2.zero, Vector2.zero
	end
	local parentPosition, parentSize = self:_absolute(data.parent)
	local size = instance.Size
	local position = instance.Position
	local absoluteSize =
		Vector2.new(parentSize.X * size.X.Scale + size.X.Offset, parentSize.Y * size.Y.Scale + size.Y.Offset)
	local absolutePosition = parentPosition
		+ Vector2.new(
			parentSize.X * position.X.Scale + position.X.Offset,
			parentSize.Y * position.Y.Scale + position.Y.Offset
		)
		- absoluteSize * instance.AnchorPoint
	return absolutePosition, absoluteSize
end

function World:setReadOnly(instance, key: string, value: any)
	self._data[instance].props[key] = value
end

-- Adds an anchored, axis-aligned part to the workspace.
function World:part(props: { [string]: any })
	local part = self.newInstance("Part")
	for key, value in props do
		if key ~= "Parent" then
			part[key] = value
		end
	end
	part.Parent = props.Parent or self.workspace
	return part
end

function World:model(name: string, parent: any?)
	local model = self.newInstance("Model")
	model.Name = name
	model.Parent = parent or self.workspace
	return model
end

-- A fake InputObject.
function World:input(inputType: string, position: Vector2)
	return {
		UserInputType = Enum.UserInputType[inputType],
		UserInputState = Enum.UserInputState.Begin,
		Position = Vector3.new(position.X, position.Y, 0),
	}
end

-- Loads src/<path>.luau the way Rojo would lay it out in Studio.
local SRC = "src"

local function makeNode(world, name: string, parent)
	local node = { _name = name, _parent = parent, _children = {}, _source = nil, _path = nil }
	return setmetatable(node, {
		__index = function(_, key)
			if key == "Name" then
				return name
			elseif key == "Parent" then
				return parent
			end
			local child = node._children[key]
			if child then
				return child
			end
			error(`{key} is not a valid member of {name}`, 2)
		end,
	})
end

local function buildTree(world, directory: string, name: string, parent)
	local node = makeNode(world, name, parent)
	for _, entry in fs.readDir(directory) do
		local path = directory .. "/" .. entry
		if fs.isDir(path) then
			node._children[entry] = buildTree(world, path, entry, node)
		elseif string.match(entry, "%.luau$") then
			local base = string.gsub(entry, "%.luau$", "")
			if base == "init" or base == "init.server" then
				rawset(node, "_source", fs.readFile(path))
				rawset(node, "_path", path)
			else
				local child = makeNode(world, base, node)
				rawset(child, "_source", fs.readFile(path))
				rawset(child, "_path", path)
				node._children[base] = child
			end
		end
	end
	return node
end

function World:_loadNode(node)
	local cached = self._cache[node]
	if cached ~= nil then
		return cached.value
	end
	assert(node._source, `{node._name} is not a ModuleScript`)

	local env = table.clone(self.globals)
	env.script = node
	env.require = function(target)
		return self:_loadNode(target)
	end
	local chunk = luau.load(node._source, { debugName = node._path, environment = env })
	local value = chunk()
	self._cache[node] = { value = value }
	return value
end

function World:require(path: string)
	self._root = self._root or buildTree(self, SRC, "TouchPeak", nil)
	local node = self._root
	for part in string.gmatch(path, "[^/]+") do
		node = node._children[part] or error(`No module {path}`)
	end
	return self:_loadNode(node)
end

-- Runs src/init.server.luau as Studio would, with `plugin` as a global.
function World:runPlugin(plugin)
	self._root = self._root or buildTree(self, SRC, "TouchPeak", nil)
	local root = self._root
	local env = table.clone(self.globals)
	env.script = root
	env.plugin = plugin
	env.require = function(target)
		return self:_loadNode(target)
	end
	luau.load(root._source, { debugName = root._path, environment = env })()
end

-- A fake `plugin` object.
function World:plugin()
	local store = {}
	local plugin = { _activated = false, Deactivation = newSignal(), Unloading = newSignal(), toolbars = {} }
	function plugin.CreateToolbar(_, name)
		assert(type(name) == "string")
		local toolbar = { name = name, buttons = {} }
		function toolbar.CreateButton(_, id, tooltip, icon, text)
			assert(type(id) == "string" and type(tooltip) == "string" and type(icon) == "string")
			local button = { id = id, tooltip = tooltip, text = text, active = false, Click = newSignal() }
			function button.SetActive(_, active)
				button.active = active
			end
			table.insert(toolbar.buttons, button)
			return button
		end
		table.insert(plugin.toolbars, toolbar)
		return toolbar
	end
	function plugin.GetSetting(_, key)
		return store[key]
	end
	function plugin.SetSetting(_, key, value)
		store[key] = value
	end
	function plugin.Activate(_, exclusive)
		assert(type(exclusive) == "boolean")
		plugin._activated = true
	end
	function plugin.Deactivate(_)
		plugin._activated = false
		plugin.Deactivation:Fire()
	end
	function plugin.IsActivated(_)
		return plugin._activated
	end
	plugin._store = store
	return plugin
end

-- Runs every pending task.delay / task.defer callback that is due within `seconds`.
function World:wait(seconds: number)
	task.wait(seconds)
end

World.newSignal = newSignal

return World
