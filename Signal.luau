--!strict
-- DataService / Signal.lua
local Signal = {}
Signal.__index = Signal

export type Connection = {
	Disconnect: (Connection) -> (),
	_fn: (...any) -> (),
	_signal: any,
}

function Signal.new()
	return setmetatable({
		_listeners = {}
	}, Signal)
end

-- [CONNECT] - Adiciona um ouvinte
function Signal:Connect(fn: (...any) -> ()): Connection
	local connection = {
		_fn = fn,
		_signal = self,
		Disconnect = function(self)
			local listeners = self._signal._listeners
			local index = table.find(listeners, self)
			if index then
				table.remove(listeners, index)
			end
		end
	}
	table.insert(self._listeners, connection)
	return connection
end

-- [FIRE] - Dispara o evento
function Signal:Fire(...)
	for _, listener in ipairs(self._listeners) do
		task.spawn(listener._fn, ...)
	end
end

-- [WAIT] - Pausa a execução até o sinal ser disparado (Crucial para o Load)
function Signal:Wait(): ...any
	local thread = coroutine.running()
	local connection: Connection
	
	connection = self:Connect(function(...)
		connection:Disconnect()
		task.spawn(thread, ...)
	end)
	
	return coroutine.yield()
end

-- [DESTROY] - Limpa tudo para evitar memory leak
function Signal:Destroy()
	table.clear(self._listeners)
end

return Signal

