--!strict
-- The ONE place for tank, can and dairy sizes. Server services use it for gameplay, the client
-- uses it for display, so they can never drift apart. Pure functions, no state.
--
--   Capacity.TankCapacity(player, data) -> number
--   Capacity.CanCapacity(player, data) -> number
--   Capacity.SellPerSecond(player, data) -> number         dairy queue value sold per second
--   Capacity.AutoCollectInterval(level) -> number           seconds between Auto Collect fills
--   Capacity.OfflineMilk(player, data, seconds) -> (milk, elapsed)
--       milk earned while away for `seconds` (capped by Offline.MaxSeconds and free tank space)

local Economy = require(script.Parent.Config.Economy)
local Upgrades = require(script.Parent.Config.Upgrades)
local Multipliers = require(script.Parent.Multipliers)

local Capacity = {}

local function level(data: any, id: string): number
	return (data.upgrades and data.upgrades[id]) or 0
end

function Capacity.TankCapacity(player: Player, data: any): number
	local mps = Multipliers.MilkPerSecond(player, data)
	local base = math.max(Economy.Tank.MinCapacity, mps * Economy.Tank.BaseSeconds)
	return base * (1 + level(data, "tankCapacity") * Upgrades.ById.tankCapacity.perLevel)
end

function Capacity.CanCapacity(player: Player, data: any): number
	local mps = Multipliers.MilkPerSecond(player, data)
	local base = math.max(Economy.Can.MinCapacity, mps * Economy.Can.BaseSeconds)
	return base * (1 + level(data, "canSize") * Upgrades.ById.canSize.perLevel)
end

function Capacity.SellPerSecond(player: Player, data: any): number
	local mps = Multipliers.MilkPerSecond(player, data)
	local rate = mps * Economy.Dairy.BaseSellFactor * (1 + level(data, "sellSpeed") * Upgrades.ById.sellSpeed.perLevel)
	return math.max(Economy.Dairy.MinSellPerSecond, rate)
end

function Capacity.AutoCollectInterval(lvl: number): number
	return math.max(
		Economy.Can.AutoCollectMinSeconds,
		Economy.Can.AutoCollectBaseSeconds - lvl * Upgrades.ById.autoCollect.perLevel
	)
end

function Capacity.OfflineMilk(player: Player, data: any, seconds: number): (number, number)
	local elapsed = math.min(seconds, Economy.Offline.MaxSeconds)
	if elapsed <= 0 then
		return 0, 0
	end
	local room = math.max(0, Capacity.TankCapacity(player, data) - (data.tankMilk or 0))
	local milk = math.min(room, Multipliers.MilkPerSecond(player, data) * elapsed * Economy.Offline.Efficiency)
	return math.max(0, milk), elapsed
end

return Capacity
