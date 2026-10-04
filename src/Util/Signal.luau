--[[
	Minimal synchronous signal.

	Handlers run immediately, in the order they were connected, which keeps the
	gesture pipeline deterministic (and easy to test outside of Roblox).
]]

local Connection = {}
Connection.__index = Connection

function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false

	local connections = self._signal._connections
	local index = table.find(connections, self)
	if index then
		table.remove(connections, index)
	end
end

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _connections = {} }, Signal)
end

function Signal:Connect(callback: (...any) -> ())
	local connection = setmetatable({
		Connected = true,
		_signal = self,
		_callback = callback,
	}, Connection)
	table.insert(self._connections, connection)
	return connection
end

function Signal:Fire(...)
	-- Iterate over a snapshot so handlers may connect/disconnect while firing.
	for _, connection in table.clone(self._connections) do
		if connection.Connected then
			connection._callback(...)
		end
	end
end

function Signal:DisconnectAll()
	for _, connection in self._connections do
		connection.Connected = false
	end
	table.clear(self._connections)
end

Signal.Destroy = Signal.DisconnectAll

return Signal
