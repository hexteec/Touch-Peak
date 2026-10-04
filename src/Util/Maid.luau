--[[
	Collects connections, instances, tweens and cleanup callbacks so they can
	be released together.
]]

local Maid = {}
Maid.__index = Maid

function Maid.new()
	return setmetatable({ _tasks = {} }, Maid)
end

function Maid:Give<T>(task: T): T
	table.insert(self._tasks, task)
	return task
end

local function cleanup(item)
	local kind = typeof(item)
	if kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "Instance" then
		if item:IsA("Tween") then
			item:Cancel()
		end
		item:Destroy()
	elseif kind == "function" then
		item()
	elseif kind == "thread" then
		pcall(task.cancel, item)
	elseif kind == "table" then
		if item.Disconnect then
			item:Disconnect()
		elseif item.Destroy then
			item:Destroy()
		end
	end
end

function Maid:Clean()
	local tasks = self._tasks
	self._tasks = {}
	-- Release in reverse order: things created last usually depend on things created first.
	for index = #tasks, 1, -1 do
		cleanup(tasks[index])
	end
end

Maid.Destroy = Maid.Clean

return Maid
