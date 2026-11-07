--!nocheck
-- Boots the real game headless: builds the place from default.project.json, runs the server
-- entry script, and runs the client entry script once per fake player.
--
--   local H = require("../mock/Harness").new({ root = "." })
--   H:boot()                       -- server starts, world is built
--   local p = H:addPlayer("Alice") -- PlayerAdded, character, client scripts
--   H:advance(60)                  -- move the fake clock (task.wait, os.time, Heartbeat)
--   H:touch(part, p)               -- fire part.Touched with p's HumanoidRootPart
--   H:fireServer(p, "RequestBuyCrate")
--   H:serverModule("Services.DataService"):Get(p)

local S = require("./Scheduler")
local D = require("./Datatypes")
local Inst = require("./Instance")
local Services = require("./Services")
local Loader = require("./Loader")

local Harness = {}
Harness.__index = Harness

Harness.S = S
Harness.D = D
Harness.Inst = Inst
Harness.Services = Services

function Harness.new(opts)
	opts = opts or {}
	local self = setmetatable({}, Harness)
	self.projectRoot = opts.root or "."
	self.nextUserId = 1001
	self.players = {}
	self.clientLog = {} -- [Player] = { { name, args } }
	S.echo = opts.echo ~= false
	self.beforeStart = opts.beforeStart
	math.randomseed(opts.seed or 42)
	return self
end

function Harness:boot()
	local game = Services.newGame()
	self.game = game
	Loader.makeGlobals(game)
	Loader.buildPlace(game, self.projectRoot)
	if self.beforeStart then
		self.beforeStart(game)
	end
	self.server = Loader.newContext("server", true, nil)
	Services.state.server = self.server
	S.defaultCtx = self.server
	Services.removePlayer = function(player)
		self:removePlayer(player)
	end
	-- record every server -> client remote for assertions
	local remoteEvent = Inst.classes.RemoteEvent
	local fireClient = remoteEvent.methods.FireClient
	local harness = self
	Inst.extend("RemoteEvent", {
		methods = {
			FireClient = function(remote, player, ...)
				if Inst.is(player) and harness.clientLog[player] then
					table.insert(harness.clientLog[player], { name = remote.Name, args = table.pack(...), t = S.now })
				end
				return fireClient(remote, player, ...)
			end,
		},
	})
	local serverScript = game.ServerScriptService:FindFirstChild("Server")
	assert(serverScript, "ServerScriptService.Server missing (check default.project.json)")
	Loader.runScript(serverScript, self.server)
	S.flushDeferred()
	return self
end

-- frame: optional frame length (default 1/60). Use 0.1 for long soaks.
function Harness:advance(seconds, frame)
	S.advance(seconds, frame)
end

function Harness:step(n)
	for _ = 1, n or 1 do
		S.step()
	end
end

function Harness:waitUntil(cond, timeout)
	return S.waitUntil(cond, timeout)
end

-- Run fn(...) inside a context (server by default) and step frames until it finishes.
function Harness:run(fn, ctx, timeout)
	local results
	local co = S.spawnIn(ctx or self.server, function(...)
		results = table.pack(fn(...))
	end)
	if coroutine.status(co) ~= "dead" then
		S.waitUntil(function()
			return coroutine.status(co) == "dead"
		end, timeout or 30)
	end
	if not results then
		return nil
	end
	return table.unpack(results, 1, results.n)
end

-- Look up an instance by dotted path from game, e.g. "ServerScriptService.Server.Services.DataService"
function Harness:find(path)
	local x = self.game
	for part in string.gmatch(path, "[^%.]+") do
		x = x and x:FindFirstChild(part)
	end
	return x
end

-- Server-side module (same cache the game uses), path relative to ServerScriptService.Server
function Harness:serverModule(path)
	local inst = self:find("ServerScriptService.Server." .. path)
	assert(inst, "no server module " .. path)
	return Loader.requireIn(self.server, inst)
end

function Harness:sharedModule(path, ctx)
	local inst = self:find("ReplicatedStorage.Shared." .. path)
	assert(inst, "no shared module " .. path)
	return Loader.requireIn(ctx or self.server, inst)
end

function Harness:clientModule(player, path)
	local ctx = Services.state.clients[player]
	assert(ctx, "player has no client")
	local inst = player.PlayerScripts.Client
	for part in string.gmatch(path, "[^%.]+") do
		inst = inst:FindFirstChild(part)
	end
	assert(inst, "no client module " .. path)
	return Loader.requireIn(ctx, inst)
end

function Harness:addPlayer(name, opts)
	opts = opts or {}
	local game = self.game
	local userId = opts.userId or self.nextUserId
	self.nextUserId += 1
	local player = Inst.create("Player")
	player.Name = name
	Inst.rawSet(player, "UserId", userId)
	Inst.rawSet(player, "DisplayName", opts.displayName or name)
	local gui = Inst.create("PlayerGui")
	gui.Name = "PlayerGui"
	gui.Parent = player
	local backpack = Inst.create("Backpack")
	backpack.Name = "Backpack"
	backpack.Parent = player
	local ps = Inst.create("PlayerScripts")
	ps.Name = "PlayerScripts"
	ps.Parent = player
	self.clientLog[player] = {}
	table.insert(self.players, player)

	local ctx = Loader.newContext("client:" .. name, false, player)
	Services.state.clients[player] = ctx

	-- joining: Player parented to Players fires PlayerAdded on the server
	S.spawnIn(self.server, function()
		player.Parent = game.Players
		Inst.fire(game.Players, "PlayerAdded", player)
	end)
	S.flushDeferred()

	-- StarterGui and StarterPlayerScripts are copied for the player
	for _, c in game.StarterGui:GetChildren() do
		local copy = Inst.clone(c)
		if copy then
			copy.Parent = gui
		end
	end
	for _, c in game.StarterPlayer.StarterPlayerScripts:GetChildren() do
		local copy = Inst.clone(c)
		if copy then
			copy.Parent = ps
		end
	end

	-- character spawns shortly after joining
	if game.Players.CharacterAutoLoads and opts.character ~= false then
		S.spawnIn(self.server, function()
			S.task.wait(0.1)
			if player.Parent then
				Services.spawnCharacter(player)
			end
		end)
	end

	-- client scripts start once the client has the game loaded
	if opts.client ~= false then
		for _, x in ps:GetDescendants() do
			if Inst.I(x).className == "LocalScript" and not x.Disabled then
				Loader.runScript(x, ctx)
			end
		end
	end
	S.flushDeferred()
	return player
end

function Harness:removePlayer(player)
	if player.Parent == nil then
		return
	end
	local game = self.game
	local ctx = Services.state.clients[player]
	Inst.I(player).leaving = true
	S.spawnIn(self.server, function()
		Inst.fire(game.Players, "PlayerRemoving", player)
	end)
	S.flushDeferred()
	if ctx then
		ctx.dead = true
		Services.state.clients[player] = nil
	end
	S.spawnIn(self.server, function()
		local char = player.Character
		if char then
			char:Destroy()
		end
		player.Parent = nil
	end)
	S.flushDeferred()
end

function Harness:character(player)
	return player.Character
end

function Harness:root(player)
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function CFrame_on(part)
	return part.CFrame * D.CFrame.new(0, part.Size.Y / 2 + 3, 0)
end

-- Fire part.Touched as if the player's character touched it. Moves the character onto the
-- part first, so distance checks pass the way they would in a real game.
function Harness:touch(part, player, opts)
	assert(part, "touch: part is nil")
	local root = self:root(player)
	assert(root, `touch: {player.Name} has no character`)
	opts = opts or {}
	S.spawnIn(self.server, function()
		if opts.move ~= false then
			player.Character:PivotTo(CFrame_on(part))
		end
		Inst.getSignal(part, "Touched"):Fire(root)
	end)
	S.flushDeferred()
end

-- Client -> server remote, sent from the player's client context
function Harness:fireServer(player, remoteName, ...)
	local ctx = Services.state.clients[player]
	assert(ctx, "fireServer: player has no client")
	local net = self.game.ReplicatedStorage:FindFirstChild("Net")
	assert(net, "ReplicatedStorage.Net missing")
	local remote = net:FindFirstChild(remoteName)
	assert(remote, "unknown remote " .. remoteName)
	local args = table.pack(...)
	S.spawnIn(ctx, function()
		remote:FireServer(table.unpack(args, 1, args.n))
	end)
	S.flushDeferred()
	S.step() -- deliver
end

function Harness:invokeServer(player, remoteName, ...)
	local ctx = Services.state.clients[player]
	assert(ctx, "invokeServer: player has no client")
	local remote = self.game.ReplicatedStorage.Net:FindFirstChild(remoteName)
	assert(remote, "unknown remote " .. remoteName)
	local args = table.pack(...)
	return self:run(function()
		return remote:InvokeServer(table.unpack(args, 1, args.n))
	end, ctx)
end

-- Simulate a tap on a GuiButton in the player's client: fires Activated + MouseButton1Click.
function Harness:click(player, button)
	local ctx = Services.state.clients[player]
	assert(ctx, "click: player has no client")
	S.spawnIn(ctx, function()
		local input = Services.input({ UserInputType = D.Enum.UserInputType.Touch })
		Inst.getSignal(button, "Activated"):Fire(input, 1)
		Inst.getSignal(button, "MouseButton1Click"):Fire()
	end)
	S.flushDeferred()
end

-- Simulate a key press on the client (UserInputService.InputBegan / InputEnded).
function Harness:pressKey(player, keyName)
	local ctx = Services.state.clients[player]
	local uis = self.game:GetService("UserInputService")
	S.spawnIn(ctx, function()
		local key = D.Enum.KeyCode[keyName]
		local down = Services.input({
			UserInputType = D.Enum.UserInputType.Keyboard,
			UserInputState = D.Enum.UserInputState.Begin,
			KeyCode = key,
		})
		Inst.getSignal(uis, "InputBegan"):Fire(down, false)
		local up = Services.input({
			UserInputType = D.Enum.UserInputType.Keyboard,
			UserInputState = D.Enum.UserInputState.End,
			KeyCode = key,
		})
		Inst.getSignal(uis, "InputEnded"):Fire(up, false)
	end)
	S.flushDeferred()
end

-- Send a chat command as the player (TextChatService TextChatCommand.Triggered).
function Harness:chat(player, text)
	local alias = string.match(text, "^(%S+)")
	local found = false
	for _, x in self.game:GetService("TextChatService"):GetDescendants() do
		if Inst.I(x).className == "TextChatCommand" and (x.PrimaryAlias == alias or x.SecondaryAlias == alias) then
			found = true
			local source = Inst.create("TextSource")
			source.Name = player.Name
			Inst.rawSet(source, "UserId", player.UserId)
			S.spawnIn(self.server, function()
				Inst.getSignal(x, "Triggered"):Fire(source, text)
			end)
		end
	end
	S.flushDeferred()
	return found
end

-- Remote events the server sent this player, optionally filtered by remote name.
function Harness:received(player, name)
	local out = {}
	for _, e in self.clientLog[player] or {} do
		if name == nil or e.name == name then
			table.insert(out, e)
		end
	end
	return out
end

function Harness:clearReceived(player)
	self.clientLog[player] = {}
end

-- Add a ModuleScript with the given source (for self-tests).
function Harness.addModule(parent, name, source)
	local m = Inst.create("ModuleScript")
	m.Name = name
	Inst.I(m).source = source
	Inst.I(m).path = "selftest/" .. name
	m.Parent = parent
	return m
end

function Harness:errors()
	return S.errors
end

function Harness:output()
	return S.output
end

-- Warnings matching a Lua pattern (case-insensitive).
function Harness:warnings(pattern)
	local out = {}
	for _, o in S.output do
		if o.kind == "warn" and (pattern == nil or string.find(string.lower(o.text), string.lower(pattern))) then
			table.insert(out, o)
		end
	end
	return out
end

function Harness:shutdown()
	local state = Services.state
	for _, p in table.clone(self.players) do
		self:removePlayer(p)
	end
	for _, b in state.bindToClose do
		S.spawnIn(b.ctx, b.fn)
	end
	S.advance(1)
end

return Harness
