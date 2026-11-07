--!nocheck
-- Fake-clock scheduler. Every game thread is a coroutine we own, tagged with a "context"
-- (the server, or one fake client). task.* and os.time/os.clock are driven by S.now, which
-- only moves when the test calls S.advance(seconds).

local S = {}

S.now = 0 -- seconds since boot (os.clock, time())
S.epoch = 1800000000 -- os.time() at boot
S.frame = 1 / 60
S.frameCount = 0

S.errors = {} -- { { ctx, message, traceback } }
S.output = {} -- { { kind, ctx, text } }
S.echo = true -- print game output to stdout
S.frameHooks = {} -- functions(dt) called every frame (RunService signals)

local ctxOf: { [thread]: any } = setmetatable({}, { __mode = "k" })
local token: { [thread]: number } = setmetatable({}, { __mode = "k" })
local sleeping = {} -- { co, wake, start, token, args? }
local deferred = {} -- { co, args }
local seq = 0

S.defaultCtx = { name = "harness", isServer = true, isClient = false }

function S.current()
	local co = coroutine.running()
	return (co and ctxOf[co]) or S.defaultCtx
end

function S.setCtx(co: thread, ctx)
	ctxOf[co] = ctx
end

function S.ctxOf(co: thread)
	return ctxOf[co]
end

function S.log(kind: string, ctx, text: string)
	local name = ctx and ctx.name or "?"
	table.insert(S.output, { kind = kind, ctx = name, text = text, t = S.now })
	if S.echo then
		local prefix = if kind == "print" then "" elseif kind == "warn" then "WARN " else "ERROR "
		print(string.format("[%7.2f][%s] %s%s", S.now, name, prefix, text))
	end
end

function S.reportError(ctx, message, trace)
	local msg = tostring(message)
	table.insert(S.errors, { ctx = ctx and ctx.name or "?", message = msg, traceback = trace or "" })
	S.log("error", ctx, msg .. (if trace and trace ~= "" then "\n" .. trace else ""))
end

-- Resume a thread and report errors the way Roblox prints "Script error".
function S.resume(co: thread, ...)
	if coroutine.status(co) ~= "suspended" then
		return
	end
	local c = ctxOf[co]
	if c and c.dead then
		-- the client this thread belonged to has left the game
		coroutine.close(co)
		return
	end
	token[co] = (token[co] or 0) + 1
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		S.reportError(ctxOf[co], err, debug.traceback(co))
	end
end

function S.newThread(fn, ctx)
	local co = coroutine.create(fn)
	ctxOf[co] = ctx or S.current()
	return co
end

-- Run fn(...) now in a new thread with the given context.
function S.spawnIn(ctx, fn, ...)
	local co = S.newThread(fn, ctx)
	S.resume(co, ...)
	return co
end

local function schedule(co, wake, args)
	seq += 1
	table.insert(sleeping, { co = co, wake = wake, start = S.now, token = (token[co] or 0), args = args, seq = seq })
end

---------------------------------------------------------------- task library
local task = {}

function task.spawn(f, ...)
	local co
	if type(f) == "thread" then
		co = f
	else
		co = S.newThread(f)
	end
	S.resume(co, ...)
	return co
end

function task.defer(f, ...)
	local co
	if type(f) == "thread" then
		co = f
	else
		co = S.newThread(f)
	end
	table.insert(deferred, { co = co, args = table.pack(...), token = token[co] or 0 })
	return co
end

function task.delay(t, f, ...)
	local co
	if type(f) == "thread" then
		co = f
	else
		co = S.newThread(f)
	end
	-- the thread has not started, so its token is 0 or its current token
	schedule(co, S.now + math.max(tonumber(t) or 0, 0), table.pack(...))
	return co
end

function task.wait(t)
	local co = coroutine.running()
	if not co or not coroutine.isyieldable() then
		error("task.wait called from a non-yieldable thread", 2)
	end
	local dt = math.max(tonumber(t) or 0, 0)
	-- Roblox resumes on the first frame at or after now + dt (always at least one frame)
	schedule(co, S.now + dt, nil)
	return coroutine.yield()
end

function task.cancel(co)
	for i = #sleeping, 1, -1 do
		if sleeping[i].co == co then
			table.remove(sleeping, i)
		end
	end
	for i = #deferred, 1, -1 do
		if deferred[i].co == co then
			table.remove(deferred, i)
		end
	end
	if coroutine.status(co) == "suspended" then
		coroutine.close(co)
	end
end

function task.synchronize() end
function task.desynchronize() end

S.task = task

-- Yield the current thread until S.resume is called on it again (used by Signal:Wait, Invoke...).
function S.yield()
	local co = coroutine.running()
	if not co or not coroutine.isyieldable() then
		error("attempt to yield from a non-yieldable thread", 3)
	end
	return coroutine.yield()
end

---------------------------------------------------------------- frame loop
function S.flushDeferred()
	local guard = 0
	while #deferred > 0 do
		guard += 1
		if guard > 100000 then
			S.reportError(S.defaultCtx, "deferred queue never drained (infinite task.defer loop?)", "")
			table.clear(deferred)
			return
		end
		local item = table.remove(deferred, 1)
		if (token[item.co] or 0) == item.token then
			S.resume(item.co, table.unpack(item.args, 1, item.args.n))
		end
	end
end

-- Queue a plain function to run (in ctx) at the next flush. Used by remotes.
function S.deferIn(ctx, fn, ...)
	local co = S.newThread(fn, ctx)
	table.insert(deferred, { co = co, args = table.pack(...), token = 0 })
end

function S.step()
	S.now += S.frame
	S.frameCount += 1
	-- wake due sleepers, oldest wake first
	local due = {}
	local i = 1
	while i <= #sleeping do
		local e = sleeping[i]
		if e.wake <= S.now + 1e-9 then
			table.insert(due, e)
			sleeping[i] = sleeping[#sleeping]
			sleeping[#sleeping] = nil
		else
			i += 1
		end
	end
	table.sort(due, function(a, b)
		if a.wake ~= b.wake then
			return a.wake < b.wake
		end
		return a.seq < b.seq
	end)
	for _, e in due do
		if (token[e.co] or 0) == e.token and coroutine.status(e.co) == "suspended" then
			if e.args then
				S.resume(e.co, table.unpack(e.args, 1, e.args.n))
			else
				S.resume(e.co, S.now - e.start)
			end
		end
	end
	S.flushDeferred()
	for _, hook in S.frameHooks do
		hook(S.frame)
	end
	S.flushDeferred()
end

function S.advance(seconds: number)
	local target = S.now + seconds
	while S.now + 1e-9 < target do
		S.step()
	end
end

-- Step frames until cond() is true or the timeout (seconds) passes. Returns cond's result.
function S.waitUntil(cond, timeout)
	local target = S.now + (timeout or 10)
	while true do
		local v = cond()
		if v then
			return v
		end
		if S.now >= target then
			return nil
		end
		S.step()
	end
end

function S.sleepingCount()
	return #sleeping
end

---------------------------------------------------------------- clock-driven os
function S.makeOs()
	local fakeOs = table.clone(os)
	fakeOs.time = function(t)
		if t ~= nil then
			return os.time(t)
		end
		return math.floor(S.epoch + S.now)
	end
	fakeOs.clock = function()
		return S.now
	end
	return fakeOs
end

-- coroutine library that tags new coroutines with the creating context
function S.makeCoroutine()
	local c = table.clone(coroutine)
	c.create = function(fn)
		return S.newThread(fn)
	end
	c.wrap = function(fn)
		local co = S.newThread(fn)
		return function(...)
			local res = table.pack(coroutine.resume(co, ...))
			if not res[1] then
				error(res[2], 2)
			end
			return table.unpack(res, 2, res.n)
		end
	end
	return c
end

return S
