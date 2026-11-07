--!strict
-- B4: Admin chat commands for fast testing. Only the place owner (game.CreatorId, or rank 255 in the
-- owning group) can use them, plus EVERYONE while running in Studio.
--
--   /cash N          set cash to N (supports 1e9, 2.5M, 3b ...). "/cash +N" adds N instead.
--   /cows tier n     give n cows of a tier (default n = 1)
--   /rebirths n      set the rebirth count
--   /crate n         give n unopened Mystery Milk Crates (default 1)
--   /reset           wipe your data back to a brand new player
--   /event id        start a timed event (DoublePrice, MilkFlood, GoldenRush, CrateRain); "/event off" ends it
--   /price x         lock the milk price to x for 5 minutes; "/price off" re-rolls it
--   /offline seconds simulate offline earnings as if you were away that long (popup included)
--   /truck           call the milk truck now (it arrives on the next DairyService tick)
--   /admin           list the commands
--
-- Uses TextChatService TextChatCommands. Falls back to Player.Chatted on the legacy chat.
-- Owns no player state: everything goes through DataService and the owning services' APIs.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Format = require(ReplicatedStorage.Shared.Format)
local Multipliers = require(ReplicatedStorage.Shared.Multipliers)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Cows = require(ReplicatedStorage.Shared.Config.Cows)
local Events = require(ReplicatedStorage.Shared.Config.Events)
local DataService = require(script.Parent.DataService)
local HerdUtil = require(script.Parent.HerdUtil)
local ProductionService = require(script.Parent.ProductionService)
local WalkSpeedService = require(script.Parent.WalkSpeedService)

local PRICE_LOCK_SECONDS = 5 * 60
local MAX_GIVE = 1e6 -- cows / crates per command, keeps typos from freezing anything

local AdminService = {}

type Handler = (player: Player, args: { string }) -> ()

local commands: { [string]: { usage: string, run: Handler } } = {}
local order: { string } = {}

----------------------------------------------------------------------------- helpers

local function notify(player: Player, text: string, kind: string?)
	Net.Event("Notify"):FireClient(player, text, kind or "info")
end

local SUFFIX: { [string]: number } = {
	k = 1e3,
	m = 1e6,
	b = 1e9,
	t = 1e12,
	qa = 1e15,
	qi = 1e18,
	sx = 1e21,
	sp = 1e24,
	oc = 1e27,
	no = 1e30,
	dc = 1e33,
}

-- "1e9" / "2.5M" / "300" / "1,000" -> number. nil when it is not a finite number.
local function parseNumber(s: string?): number?
	if not s then
		return nil
	end
	local text = string.lower((string.gsub(s, "[,_]", "")))
	local n = tonumber(text)
	if not n then
		local num, suffix = string.match(text, "^([%d%.eE%+%-]+)(%a+)$")
		local mult = suffix and SUFFIX[suffix]
		local base = num and tonumber(num)
		if base and mult then
			n = base * mult
		end
	end
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	return n
end

local function isAdmin(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	if game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = pcall(function()
			return player:GetRankInGroup(game.CreatorId)
		end)
		return ok and rank == 255
	end
	return false
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = deepCopy(v)
	end
	return out
end

local function replicateAll(player: Player, data: any)
	for key in data do
		DataService:Replicate(player, key)
	end
end

local function register(name: string, usage: string, run: Handler)
	commands[name] = { usage = usage, run = run }
	table.insert(order, name)
end

----------------------------------------------------------------------------- commands

register("cash", "/cash N  (1e9, 2.5M; +N adds)", function(player, args)
	local data = DataService:Get(player)
	local raw = args[1]
	if not data or not raw then
		notify(player, "Usage: /cash N", "error")
		return
	end
	local adding = string.sub(raw, 1, 1) == "+"
	local n = parseNumber(if adding then string.sub(raw, 2) else raw)
	if not n then
		notify(player, `Not a number: {raw}`, "error")
		return
	end
	-- AddCash is the only way cash goes up; a negative delta lowers it (AddCash skips stats for < 0)
	local delta = if adding then n else n - data.cash
	DataService:AddCash(player, delta)
	notify(player, `[Admin] cash = {Format.Cash(data.cash)}`, "success")
end)

register("cows", "/cows tier n", function(player, args)
	local tier = parseNumber(args[1])
	local n = parseNumber(args[2]) or 1
	if not tier or tier ~= math.floor(tier) or tier < 1 or tier > Cows.Count then
		notify(player, `Usage: /cows tier(1-{Cows.Count}) n`, "error")
		return
	end
	n = math.clamp(math.floor(n), 1, MAX_GIVE)
	HerdUtil.GiveCow(player, tier, n)
	local cow = Cows.Get(tier)
	notify(player, `[Admin] +{Format.Number(n)} {cow and cow.name or "?"} (tier {tier})`, "success")
end)

register("rebirths", "/rebirths n", function(player, args)
	local data = DataService:Get(player)
	local n = parseNumber(args[1])
	if not data or not n or n < 0 then
		notify(player, "Usage: /rebirths n", "error")
		return
	end
	data.rebirths = math.floor(n)
	DataService:Replicate(player, "rebirths")
	local mult = 1 + Economy.Rebirth.CashMultiplierPerRebirth * data.rebirths
	notify(player, `[Admin] rebirths = {data.rebirths} (cash x{Format.Number(mult)})`, "success")
end)

register("crate", "/crate n", function(player, args)
	local data = DataService:Get(player)
	if not data then
		return
	end
	local n = math.clamp(math.floor(parseNumber(args[1]) or 1), 1, MAX_GIVE)
	data.crates = (data.crates or 0) + n
	DataService:Replicate(player, "crates")
	notify(player, `[Admin] +{n} crates (now {data.crates})`, "success")
end)

register("reset", "/reset  (wipe your data)", function(player, _args)
	local data = DataService:Get(player)
	if not data then
		return
	end
	-- receipt ids must survive a reset, or a pending Robux retry could be granted twice
	local purchases = data.purchases
	-- the profile table must stay the same table (services hold references), so wipe it in place
	for key in table.clone(data) do
		data[key] = nil
	end
	for key, value in DataService.Template do
		data[key] = deepCopy(value)
	end
	data.cows = DataService:NewStartingCows()
	DataService:MarkStartingCowsDiscovered(data)
	data.purchases = purchases or {}
	data.firstJoin = os.time()
	data.lastOnline = os.time()
	replicateAll(player, data)
	WalkSpeedService:Apply(player)
	notify(player, "[Admin] data wiped. Rejoin for a fully clean start (plot, quests).", "success")
end)

register("event", "/event id | off", function(player, args)
	local id = args[1]
	if not id then
		local ids = {}
		for _, e in Events.List do
			table.insert(ids, e.id)
		end
		notify(player, `Usage: /event {table.concat(ids, " | ")} | off`, "error")
		return
	end
	if string.lower(id) == "off" then
		workspace:SetAttribute("EventId", "")
		workspace:SetAttribute("EventEndsAt", 0)
		workspace:SetAttribute("EventNextAt", os.time() + Events.EverySeconds)
		notify(player, "[Admin] event ended", "success")
		return
	end
	-- case-insensitive id match
	local ev: any = nil
	for _, e in Events.List do
		if string.lower(e.id) == string.lower(id) then
			ev = e
		end
	end
	if not ev then
		notify(player, `Unknown event: {id}`, "error")
		return
	end
	local endsAt = os.time() + ev.seconds
	workspace:SetAttribute("EventId", ev.id)
	workspace:SetAttribute("EventEndsAt", endsAt)
	workspace:SetAttribute("EventNextAt", endsAt + Events.EverySeconds)
	Net.Event("Notify"):FireAllClients(ev.name, "rare")
	-- If EventService (B2) is running it will end the event itself; this is the fallback.
	task.delay(ev.seconds, function()
		if workspace:GetAttribute("EventId") == ev.id and workspace:GetAttribute("EventEndsAt") == endsAt then
			workspace:SetAttribute("EventId", "")
		end
	end)
end)

register("price", "/price x | off", function(player, args)
	local raw = args[1]
	if raw and string.lower(raw) == "off" then
		-- DairyService re-rolls on its next tick once MilkPriceNextAt has passed
		workspace:SetAttribute("MilkPriceNextAt", 0)
		notify(player, "[Admin] milk price unlocked", "success")
		return
	end
	local x = parseNumber(raw)
	if not x or x <= 0 then
		notify(player, "Usage: /price x  (e.g. 1.5)", "error")
		return
	end
	workspace:SetAttribute("MilkPrice", x)
	workspace:SetAttribute("MilkPriceNextAt", os.time() + PRICE_LOCK_SECONDS)
	notify(player, `[Admin] milk price = {x}x for {PRICE_LOCK_SECONDS // 60} min`, "success")
end)

-- Same formula as ProductionService.applyOffline (keep in sync): milk into the tank at
-- Offline.Efficiency, capped by free tank space and Offline.MaxSeconds.
register("offline", "/offline seconds", function(player, args)
	local data = DataService:Get(player)
	local seconds = parseNumber(args[1])
	if not data or not seconds or seconds <= 0 then
		notify(player, "Usage: /offline seconds  (e.g. 3600)", "error")
		return
	end
	local elapsed = math.min(seconds, Economy.Offline.MaxSeconds)
	local mps = Multipliers.MilkPerSecond(player, data)
	local capacity = ProductionService:GetTankCapacity(player, data)
	local current = data.tankMilk or 0
	local milk = math.min(math.max(0, capacity - current), mps * elapsed * Economy.Offline.Efficiency)
	if milk <= 0 then
		notify(player, "[Admin] tank is already full, nothing to add", "info")
		return
	end
	data.tankMilk = current + milk
	DataService:Replicate(player, "tankMilk")
	Net.Event("OfflineEarnings"):FireClient(player, milk, elapsed)
	notify(player, `[Admin] offline {Format.Time(elapsed)}: +{Format.Number(milk)} milk`, "success")
end)

register("truck", "/truck", function(player, _args)
	if workspace:GetAttribute("TruckActive") then
		notify(player, "[Admin] the truck is already here", "info")
		return
	end
	workspace:SetAttribute("TruckNextAt", 0)
	notify(player, "[Admin] truck incoming", "success")
end)

register("admin", "/admin  (this list)", function(player, _args)
	local lines = {}
	for _, name in order do
		table.insert(lines, commands[name].usage)
	end
	notify(player, table.concat(lines, "\n"), "info")
end)

----------------------------------------------------------------------------- dispatch

local function run(player: Player, text: string)
	local words = string.split(text, " ")
	local args: { string } = {}
	for _, w in words do
		if w ~= "" then
			table.insert(args, w)
		end
	end
	local first = table.remove(args, 1)
	if not first or string.sub(first, 1, 1) ~= "/" then
		return
	end
	local cmd = commands[string.lower(string.sub(first, 2))]
	if not cmd then
		return
	end
	if not isAdmin(player) then
		return -- silent: normal players never learn the commands exist
	end
	if not DataService:Get(player) then
		notify(player, "[Admin] data not loaded yet", "error")
		return
	end
	local ok, err = pcall(cmd.run :: any, player, args)
	if not ok then
		warn(`[AdminService] {first} failed: {err}`)
		notify(player, `[Admin] {first} failed, see Output`, "error")
	end
end

AdminService.Run = run -- exposed for Studio command bar testing: AdminService.Run(player, "/cash 1e9")
AdminService.ParseNumber = parseNumber

function AdminService:Start()
	if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
		local folder = Instance.new("Folder")
		folder.Name = "AdminCommands"
		for _, name in order do
			local c = Instance.new("TextChatCommand")
			c.Name = "Admin_" .. name
			c.PrimaryAlias = "/" .. name
			c.Triggered:Connect(function(source: TextSource, text: string)
				local player = Players:GetPlayerByUserId(source.UserId)
				if player then
					run(player, text)
				end
			end)
			c.Parent = folder
		end
		folder.Parent = TextChatService
	else
		local function hook(player: Player)
			player.Chatted:Connect(function(message)
				run(player, message)
			end)
		end
		for _, p in Players:GetPlayers() do
			hook(p)
		end
		Players.PlayerAdded:Connect(hook)
	end
end

return AdminService
