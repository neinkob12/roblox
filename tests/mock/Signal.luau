--!nocheck
-- RBXScriptSignal / RBXScriptConnection stand-in. Handlers run in the context that connected
-- them (server or a specific client), each in its own thread, like Roblox.

local S = require("./Scheduler")

local SignalMT = { __type = "RBXScriptSignal" }
SignalMT.__index = SignalMT
local ConnMT = { __type = "RBXScriptConnection" }
ConnMT.__index = ConnMT

local Signal = {}

-- opts.filter(conn, ...) -> bool decides per connection whether it receives a Fire.
-- opts.name for diagnostics.
function Signal.new(name: string?, opts: any?)
	return setmetatable({ _conns = {}, _waiting = {}, _name = name or "Signal", _opts = opts or {} }, SignalMT)
end

function ConnMT:Disconnect()
	if not self.Connected then
		return
	end
	rawset(self, "Connected", false)
	local list = self._signal._conns
	for i, c in list do
		if c == self then
			table.remove(list, i)
			break
		end
	end
end

function SignalMT:Connect(fn)
	assert(type(fn) == "function", `Attempt to connect failed: Passed value is not a function ({self._name})`)
	local conn = setmetatable({ Connected = true, _fn = fn, _ctx = S.current(), _signal = self }, ConnMT)
	table.insert(self._conns, conn)
	if self._opts.onConnect then
		self._opts.onConnect(conn)
	end
	return conn
end
SignalMT.ConnectParallel = SignalMT.Connect
SignalMT.connect = SignalMT.Connect

function SignalMT:Once(fn)
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

function SignalMT:Wait()
	local co = coroutine.running()
	table.insert(self._waiting, { co = co, ctx = S.current() })
	return S.yield()
end
SignalMT.wait = SignalMT.Wait

-- Not a Roblox API: the mock (and tests) fire signals with this.
function SignalMT:Fire(...)
	local filter = self._opts.filter
	local snapshot = table.clone(self._conns)
	for _, conn in snapshot do
		if conn.Connected and (not filter or filter(conn._ctx, ...)) then
			S.spawnIn(conn._ctx, conn._fn, ...)
		end
	end
	if #self._waiting > 0 then
		local waiting = self._waiting
		self._waiting = {}
		for _, w in waiting do
			if not filter or filter(w.ctx, ...) then
				S.resume(w.co, ...)
			else
				table.insert(self._waiting, w)
			end
		end
	end
end

function SignalMT:ConnectionCount()
	return #self._conns
end

function Signal.is(v)
	return getmetatable(v) == SignalMT
end

return Signal
