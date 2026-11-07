--!nocheck
-- Builds the place tree from default.project.json using Rojo's file rules, and runs scripts
-- with a Roblox-like global environment. Each context (server, each client) has its own
-- require cache, like separate Roblox peers.

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local luau = require("@lune/luau")

local S = require("./Scheduler")
local D = require("./Datatypes")
local Inst = require("./Instance")
local Services = require("./Services")

local L = {}

---------------------------------------------------------------- Rojo tree
local function stripExt(name: string): (string, string?)
	for _, suffix in { ".server.luau", ".server.lua", ".client.luau", ".client.lua", ".luau", ".lua" } do
		if string.sub(name, -#suffix) == suffix then
			local base = string.sub(name, 1, #name - #suffix)
			local kind = if string.find(suffix, "server")
				then "Script"
				elseif string.find(suffix, "client") then "LocalScript"
				else "ModuleScript"
			return base, kind
		end
	end
	return name, nil
end

local function makeScript(className: string, name: string, path: string)
	local inst = Inst.create(className)
	inst.Name = name
	local d = Inst.I(inst)
	d.source = fs.readFile(path)
	d.path = path
	return inst
end

local function buildPath(path: string, name: string)
	if fs.isFile(path) then
		local file = string.match(path, "[^/]+$")
		local _, kind = stripExt(file)
		if kind then
			return makeScript(kind, name, path)
		elseif string.sub(file, -5) == ".json" and not string.find(file, "%.meta%.json$") then
			local inst = Inst.create("ModuleScript")
			inst.Name = name
			Inst.I(inst).source = "return game:GetService('HttpService'):JSONDecode([==[" .. fs.readFile(path) .. "]==])"
			Inst.I(inst).path = path
			return inst
		elseif string.sub(file, -4) == ".txt" then
			local inst = Inst.create("StringValue")
			inst.Name = name
			inst.Value = fs.readFile(path)
			return inst
		end
		return nil
	end
	-- directory
	local entries = fs.readDir(path)
	table.sort(entries)
	local container
	for _, initName in { "init.server.luau", "init.server.lua", "init.client.luau", "init.client.lua", "init.luau", "init.lua" } do
		if table.find(entries, initName) then
			local _, kind = stripExt(initName)
			container = makeScript(kind, name, path .. "/" .. initName)
			break
		end
	end
	if not container then
		container = Inst.create("Folder")
		container.Name = name
	end
	for _, entry in entries do
		if not string.match(entry, "^init%.") and not string.match(entry, "^%.") then
			local full = path .. "/" .. entry
			local childName = entry
			if fs.isFile(full) then
				local base, kind = stripExt(entry)
				if kind then
					childName = base
				elseif string.sub(entry, -5) == ".json" then
					childName = string.sub(entry, 1, -6)
				elseif string.sub(entry, -4) == ".txt" then
					childName = string.sub(entry, 1, -5)
				end
			end
			local child = buildPath(full, childName)
			if child then
				child.Parent = container
			end
		end
	end
	return container
end

local function applyProps(inst, props)
	if not props then
		return
	end
	for k, v in props do
		if type(v) == "table" then
			-- Rojo explicit value: { "Vector3": [x, y, z] } etc. Only simple ones are needed here.
			local typ, val = next(v)
			if typ == "Vector3" then
				v = D.Vector3.new(val[1], val[2], val[3])
			elseif typ == "Color3" then
				v = D.Color3.new(val[1], val[2], val[3])
			elseif typ == "Enum" then
				v = val
			else
				v = val
			end
		end
		inst[k] = v
	end
end

local function buildNode(node, name: string, parent, root: string)
	local inst
	if node["$path"] then
		inst = buildPath(root .. "/" .. node["$path"], name)
		if not inst then
			error(`[loader] $path {node["$path"]} produced nothing`)
		end
	elseif node["$className"] then
		local cls = node["$className"]
		if Services.serviceClasses[cls] and parent and Inst.I(parent).className == "DataModel" then
			inst = parent:GetService(cls)
		else
			inst = Inst.create(cls)
			inst.Name = name
		end
	else
		-- no className: must be an existing child (e.g. StarterPlayerScripts)
		inst = parent:FindFirstChild(name)
		if not inst then
			error(`[loader] node {name} has no $className and does not exist`)
		end
	end
	applyProps(inst, node["$properties"])
	if inst.Parent == nil and parent and Inst.I(inst).className ~= "DataModel" then
		inst.Parent = parent
	end
	for key, child in node do
		if string.sub(key, 1, 1) ~= "$" then
			buildNode(child, key, inst, root)
		end
	end
	return inst
end

function L.buildPlace(game, root: string)
	local project = serde.decode("json", fs.readFile(root .. "/default.project.json"))
	local tree = project.tree
	assert(tree["$className"] == "DataModel", "project root must be a DataModel")
	applyProps(game, tree["$properties"])
	for key, child in tree do
		if string.sub(key, 1, 1) ~= "$" then
			buildNode(child, key, game, root)
		end
	end
	return project
end

---------------------------------------------------------------- contexts & environment
function L.newContext(name: string, isServer: boolean, player)
	return {
		name = name,
		isServer = isServer,
		isClient = not isServer,
		player = player,
		modules = {}, -- [ModuleScript] = { state = "loading" | "ok" | "error", value }
		shared = {},
		G = {},
	}
end

local fakeOs = S.makeOs()
local fakeCoroutine = S.makeCoroutine()

local function fmtArgs(...)
	local n = select("#", ...)
	local parts = table.create(n)
	for i = 1, n do
		parts[i] = tostring((select(i, ...)))
	end
	return table.concat(parts, " ")
end

local game -- set by L.makeGlobals
local baseGlobals = {}

function L.makeGlobals(g)
	game = g
	local Instance = {
		new = function(className, parent)
			if type(className) ~= "string" then
				error("Instance.new: className must be a string", 2)
			end
			local ok, res = pcall(Inst.new, className, parent)
			if not ok then
				error(res, 2)
			end
			return res
		end,
		fromExisting = function(inst)
			return Inst.clone(inst)
		end,
	}
	baseGlobals = {
		math = math,
		string = string,
		table = table,
		utf8 = utf8,
		bit32 = bit32,
		buffer = buffer,
		debug = debug,
		vector = vector,
		select = select,
		type = type,
		tostring = tostring,
		tonumber = tonumber,
		pairs = pairs,
		ipairs = ipairs,
		next = next,
		pcall = pcall,
		xpcall = xpcall,
		error = error,
		assert = assert,
		setmetatable = setmetatable,
		getmetatable = getmetatable,
		rawget = rawget,
		rawset = rawset,
		rawequal = rawequal,
		rawlen = rawlen,
		unpack = table.unpack,
		newproxy = newproxy,
		gcinfo = gcinfo,
		game = g,
		Game = g,
		workspace = g.Workspace,
		Workspace = g.Workspace,
		Instance = Instance,
		task = S.task,
		os = fakeOs,
		coroutine = fakeCoroutine,
		typeof = D.typeof,
		print = function(...)
			S.log("print", S.current(), fmtArgs(...))
		end,
		warn = function(...)
			S.log("warn", S.current(), fmtArgs(...))
		end,
		tick = function()
			return S.epoch + S.now
		end,
		time = function()
			return S.now
		end,
		elapsedTime = function()
			return S.now
		end,
		wait = function(t)
			local dt = S.task.wait(t or 0.03)
			return dt, S.now
		end,
		delay = function(t, f)
			S.task.delay(t, f)
		end,
		spawn = function(f)
			S.task.defer(f)
		end,
		settings = function()
			return {
				Rendering = { QualityLevel = D.Enum.QualityLevel.Automatic },
				Physics = {},
				Network = {},
			}
		end,
		UserSettings = function()
			return {
				GetService = function(_, name)
					return {
						SavedQualityLevel = D.Enum.SavedQualitySetting.Automatic,
						GetCameraYInverted = function()
							return false
						end,
						IsUserFeatureEnabled = function()
							return false
						end,
					}
				end,
			}
		end,
		Vector3 = D.Vector3,
		Vector2 = D.Vector2,
		CFrame = D.CFrame,
		Color3 = D.Color3,
		UDim = D.UDim,
		UDim2 = D.UDim2,
		TweenInfo = D.TweenInfo,
		NumberRange = D.NumberRange,
		NumberSequence = D.NumberSequence,
		NumberSequenceKeypoint = D.NumberSequenceKeypoint,
		ColorSequence = D.ColorSequence,
		ColorSequenceKeypoint = D.ColorSequenceKeypoint,
		Random = D.Random,
		Rect = D.Rect,
		PhysicalProperties = D.PhysicalProperties,
		Ray = D.Ray,
		BrickColor = D.BrickColor,
		Font = D.Font,
		Enum = D.Enum,
		RaycastParams = {
			new = function()
				return {
					FilterDescendantsInstances = {},
					FilterType = D.Enum.RaycastFilterType.Exclude,
					IgnoreWater = false,
					CollisionGroup = "Default",
					AddToFilter = function() end,
				}
			end,
		},
		OverlapParams = {
			new = function()
				return {
					FilterDescendantsInstances = {},
					FilterType = D.Enum.RaycastFilterType.Exclude,
					MaxParts = 0,
					CollisionGroup = "Default",
					AddToFilter = function() end,
				}
			end,
		},
		DateTime = {
			now = function()
				local ms = math.floor((S.epoch + S.now) * 1000)
				return { UnixTimestamp = math.floor(ms / 1000), UnixTimestampMillis = ms }
			end,
			fromUnixTimestamp = function(t)
				return { UnixTimestamp = t, UnixTimestampMillis = t * 1000 }
			end,
			fromUnixTimestampMillis = function(t)
				return { UnixTimestamp = math.floor(t / 1000), UnixTimestampMillis = t }
			end,
		},
	}
	return baseGlobals
end

-- Roblox-style require bound to a context.
local function makeRequire(ctx)
	local function req(target)
		if type(target) == "number" then
			error("require(assetId) is not allowed (no Toolbox/free models)", 2)
		end
		if not Inst.is(target) then
			error(`Attempted to call require with invalid argument(s).`, 2)
		end
		local d = Inst.I(target)
		if d.className ~= "ModuleScript" then
			error(`Attempted to call require with invalid argument(s). ({d.className})`, 2)
		end
		local entry = ctx.modules[target]
		if entry then
			if entry.state == "ok" then
				return entry.value
			elseif entry.state == "loading" then
				error(`Requested module was required recursively ({Inst.fullName(target)})`, 2)
			else
				error(`Requested module experienced an error while loading ({Inst.fullName(target)})`, 2)
			end
		end
		entry = { state = "loading" }
		ctx.modules[target] = entry
		local chunk = L.compile(target, ctx)
		local res = table.pack(pcall(chunk))
		if not res[1] then
			entry.state = "error"
			-- Roblox prints the module's own error, then the require errors
			error(res[2], 0)
		end
		if res.n - 1 ~= 1 then
			entry.state = "error"
			error(`Module code did not return exactly one value ({Inst.fullName(target)})`, 2)
		end
		entry.state = "ok"
		entry.value = res[2]
		return res[2]
	end
	return req
end

function L.compile(scriptInst, ctx)
	local d = Inst.I(scriptInst)
	ctx.require = ctx.require or makeRequire(ctx)
	local env = setmetatable({
		script = scriptInst,
		require = ctx.require,
		shared = ctx.shared,
		_G = ctx.G,
	}, { __index = baseGlobals })
	local debugName = d.path or Inst.fullName(scriptInst)
	local ok, fn = pcall(luau.load, d.source or "", { debugName = debugName, environment = env, injectGlobals = false })
	if not ok then
		error(`[compile] {debugName}: {fn}`, 0)
	end
	return fn
end

-- Run a Script/LocalScript in its own thread for ctx.
function L.runScript(scriptInst, ctx)
	local fn = L.compile(scriptInst, ctx)
	return S.spawnIn(ctx, fn)
end

-- For the harness: require a module by instance inside ctx (in a thread of that ctx).
function L.requireIn(ctx, moduleInst)
	ctx.require = ctx.require or makeRequire(ctx)
	local result
	local co = S.spawnIn(ctx, function()
		result = ctx.require(moduleInst)
	end)
	if coroutine.status(co) ~= "dead" then
		-- module yielded during load; finish it by stepping frames
		S.waitUntil(function()
			return coroutine.status(co) == "dead"
		end, 30)
	end
	return result
end

return L
