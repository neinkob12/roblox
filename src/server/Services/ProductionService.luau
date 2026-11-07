--!strict
-- Milk production: cows -> pipes -> tank. Server tick every Economy.Tank.TickSeconds.
-- Owner: A3.
--
--   ProductionService:GetMilkPerSecond(player, data) -> number
--   Capacity.TankCapacity(player, data)  -> number
--   ProductionService:MarkTankDirty(player)            (replicate tankMilk on the next flush, max every 0.5s)
--
-- Player attributes set here: MilkPerSecond, TankCapacity (formulas in shared/Capacity).
-- Also: rare milk rolls (golden / diamond) and offline earnings on join.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Format = require(ReplicatedStorage.Shared.Format)
local Multipliers = require(ReplicatedStorage.Shared.Multipliers)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local DataService = require(script.Parent.DataService)
local Notify = require(script.Parent.Parent.Util.Notify)
local Capacity = require(ReplicatedStorage.Shared.Capacity)

local ProductionService = {}

local dirty: { [Player]: boolean } = {}
local rng = Random.new()

function ProductionService:MarkTankDirty(player: Player)
	dirty[player] = true
end

-- Returns the rare milk entry rolled this tick, or nil. Rarest is checked first.
local function rollRare(): any
	local ev = Multipliers.ActiveEvent()
	local mult = if ev and ev.rareChanceMultiplier then ev.rareChanceMultiplier else 1
	local list = table.clone(Economy.RareMilk)
	table.sort(list, function(a, b)
		return a.chance < b.chance
	end)
	for _, rare in list do
		if rng:NextNumber() < rare.chance * mult then
			return rare
		end
	end
	return nil
end

local function tickPlayer(player: Player, dt: number)
	local data = DataService:Get(player)
	if not data then
		return
	end
	local mps = Multipliers.MilkPerSecond(player, data)
	local capacity = Capacity.TankCapacity(player, data)
	player:SetAttribute("MilkPerSecond", mps)
	player:SetAttribute("TankCapacity", capacity)

	local current = data.tankMilk or 0
	if current >= capacity then
		-- full (capacity can also drop when an event ends; never delete milk, just stop filling)
		return
	end

	local add = mps * dt
	local rare = if mps > 0 then rollRare() else nil
	if rare then
		add += mps * dt * (rare.multiplier - 1)
	end
	local newValue = math.min(capacity, current + add)
	if newValue ~= current then
		data.tankMilk = newValue
		dirty[player] = true
	end
	if rare then
		local gained = newValue - current
		Notify.To(player, `{rare.name}! x{rare.multiplier} (+{Format.Number(gained)} milk)`, "rare")
	end
end

-- Adds `seconds` of offline milk to the tank and shows the welcome-back popup. Used on join and by /offline.
function ProductionService:GrantOffline(player: Player, data: any, seconds: number): (number, number)
	local milk, elapsed = Capacity.OfflineMilk(player, data, seconds)
	if milk <= 0 then
		return 0, elapsed
	end
	data.tankMilk = (data.tankMilk or 0) + milk
	DataService:Replicate(player, "tankMilk")
	Net.Event("OfflineEarnings"):FireClient(player, milk, elapsed)
	return milk, elapsed
end

function ProductionService:Init()
	DataService.PlayerLoaded:Connect(function(player: Player, data: any)
		local last = data.lastOnline or 0
		if last > 0 then
			ProductionService:GrantOffline(player, data, os.time() - last)
		end
		player:SetAttribute("MilkPerSecond", Multipliers.MilkPerSecond(player, data))
		player:SetAttribute("TankCapacity", Capacity.TankCapacity(player, data))
	end)
	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
	end)
end

function ProductionService:Start()
	-- replication flush loop (keeps network traffic bounded)
	task.spawn(function()
		while true do
			task.wait(Economy.Tank.ReplicateSeconds)
			for player in dirty do
				dirty[player] = nil
				if player.Parent == Players then
					DataService:Replicate(player, "tankMilk")
				end
			end
		end
	end)

	local last = os.clock()
	while true do
		task.wait(Economy.Tank.TickSeconds)
		local now = os.clock()
		-- clamp so a server hitch never grants a huge burst
		local dt = math.min(now - last, Economy.Tank.TickSeconds * 3)
		last = now
		for _, player in Players:GetPlayers() do
			local ok, err = pcall(tickPlayer :: any, player, dt)
			if not ok then
				warn(`[ProductionService] tick failed for {player.Name}: {err}`)
			end
		end
	end
end

return ProductionService
