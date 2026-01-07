--!strict
-- DataService / Signal.lua
local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({
		_listeners = {}
	}, Signal)
end

function Signal:Connect(fn: (...any) -> ())
	local connection = {
		_fn = fn,
		Disconnect = function(self)
			for i, listener in ipairs(self._listeners) do
				if listener == self then
					table.remove(self._listeners, i)
					break
				end
			end
		end
	}
	table.insert(self._listeners, connection)
	return connection
end

function Signal:Fire(...)
	for _, listener in ipairs(self._listeners) do
		task.spawn(listener._fn, ...)
	end
end

return Signal
