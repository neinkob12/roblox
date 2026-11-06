--!strict
-- Minimal signal for in-process events between services/controllers.

export type Connection = { Disconnect: (self: Connection) -> () }

local Signal = {}
Signal.__index = Signal

export type Signal = typeof(setmetatable({} :: { _handlers: { [number]: (...any) -> () }, _nextId: number }, Signal))

function Signal.new(): Signal
	return setmetatable({ _handlers = {}, _nextId = 0 }, Signal)
end

function Signal.Connect(self: Signal, fn: (...any) -> ()): Connection
	self._nextId += 1
	local id = self._nextId
	self._handlers[id] = fn
	local handlers = self._handlers
	return {
		Disconnect = function(_)
			handlers[id] = nil
		end,
	} :: any
end

function Signal.Fire(self: Signal, ...: any)
	for _, fn in self._handlers do
		task.spawn(fn, ...)
	end
end

return Signal
