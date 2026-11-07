--!strict
-- Milk production: cows -> pipes -> tank. Server tick every Economy.Tank.TickSeconds.
-- Owner: A3.
--
--   ProductionService:GetMilkPerSecond(player, data) -> number
--   ProductionService:GetTankCapacity(player, data)  -> number
--   ProductionService:MarkTankDirty(player)            (replicate tankMilk on the next flush, max every 0.5s)
--
-- Player attributes set here: MilkPerSecond, TankCapacity.
-- Also: rare milk rolls (golden / diamond) and offline earnings on join.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Format = require(ReplicatedStorage.Shared.Format)
local Multipliers = require(ReplicatedStorage.Shared.Multipliers)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local Events = require(ReplicatedStorage.Shared.Config.Events)
local DataService = require(script.Parent.DataService)

local ProductionService = {}

local dirty: { [Player]: boolean } = {}
local rng = Random.new()

function ProductionService:GetMilkPerSecond(player: Player, data: any): number
	return Multipliers.MilkPerSecond(player, data)
end

function ProductionService:GetTankCapacity(player: Player, data: any): number
	local mps = Multipliers.MilkPerSecond(player, data)
	local lvl = (data.upgrades and data.upgrades.tankCapacity) or 0
	local base = math.max(Economy.Tank.MinCapacity, mps * Economy.Tank.BaseSeconds)
	return base * (1 + lvl * Upgrades.ById.tankCapacity.perLevel)
end

function ProductionService:MarkTankDirty(player: Player)
	dirty[player] = true
end

local function rareChanceMultiplier(): number
	local id = workspace:GetAttribute("EventId")
	if typeof(id) == "string" and id ~= "" then
		local ev: any = Events.ById[id]
		if ev and ev.rareChanceMultiplier then
			return ev.rareChanceMultiplier
		end
	end
	return 1
end

-- Returns the rare milk entry rolled this tick, or nil. Rarest is checked first.
local function rollRare(): any
	local mult = rareChanceMultiplier()
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
	local capacity = ProductionService:GetTankCapacity(player, data)
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
		Net.Event("Notify")
			:FireClient(player, `{rare.name}! x{rare.multiplier} (+{Format.Number(gained)} milk)`, "rare")
		Net.Event("Fx"):FireClient(player, "rare", { kind = rare.id })
	end
end

local function applyOffline(player: Player, data: any)
	local last = data.lastOnline or 0
	if last == 0 then
		return
	end
	local elapsed = math.min(os.time() - last, Economy.Offline.MaxSeconds)
	if elapsed <= 0 then
		return
	end
	local mps = Multipliers.MilkPerSecond(player, data)
	local capacity = ProductionService:GetTankCapacity(player, data)
	local current = data.tankMilk or 0
	local room = math.max(0, capacity - current)
	local milk = math.min(room, mps * elapsed * Economy.Offline.Efficiency)
	if milk <= 0 then
		return
	end
	data.tankMilk = current + milk
	DataService:Replicate(player, "tankMilk")
	Net.Event("OfflineEarnings"):FireClient(player, milk, elapsed)
end

function ProductionService:Init()
	DataService.PlayerLoaded:Connect(function(player: Player, data: any)
		applyOffline(player, data)
		player:SetAttribute("MilkPerSecond", Multipliers.MilkPerSecond(player, data))
		player:SetAttribute("TankCapacity", ProductionService:GetTankCapacity(player, data))
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
			local ok, err = pcall(tickPlayer, player, dt)
			if not ok then
				warn(`[ProductionService] tick failed for {player.Name}: {err}`)
			end
		end
	end
end

return ProductionService
