--!strict
-- The ONE place where cash and production multipliers are combined.
-- Works on server and client (client uses it for display only).
--
-- Inputs (contract, see docs/CONTRACTS.md):
--   data                    the player's profile data (or the client mirror)
--   player attributes       Pass_DoubleCash (bool), FriendCount (number)
--   workspace attributes    EventId (string, "" when none)
--   data.boosts             { [boostId] = { kind = "cash" | "production", mult = number, expires = Multipliers.Now() + s } }

local Economy = require(script.Parent.Config.Economy)
local Upgrades = require(script.Parent.Config.Upgrades)
local Events = require(script.Parent.Config.Events)

local Multipliers = {}

-- The running server event (Config/Events entry) or nil. The ONE event lookup, server and client.
function Multipliers.ActiveEvent(): any
	local id = workspace:GetAttribute("EventId")
	if typeof(id) == "string" and id ~= "" then
		return Events.ById[id]
	end
	return nil
end

-- The ONE clock for boost expiry, server and client: workspace:GetServerTimeNow() (Unix seconds,
-- synced to the server on clients). Old saves used os.time(), which is the same scale.
function Multipliers.Now(): number
	return workspace:GetServerTimeNow()
end

local function boostMult(data: any, kind: string): number
	local m = 1
	local now = Multipliers.Now()
	if data.boosts then
		for _, b in data.boosts do
			if b.kind == kind and b.expires > now then
				m *= b.mult
			end
		end
	end
	return m
end

function Multipliers.Cash(player: Player, data: any): number
	local m = 1 + Economy.Rebirth.CashMultiplierPerRebirth * (data.rebirths or 0)
	if player:GetAttribute("Pass_DoubleCash") then
		m *= 2
	end
	local friends = player:GetAttribute("FriendCount")
	if typeof(friends) == "number" then
		m *= 1 + math.min(Economy.FriendBoost.Max, friends * Economy.FriendBoost.PerFriend)
	end
	local ev = Multipliers.ActiveEvent()
	if ev and ev.cashMultiplier then
		m *= ev.cashMultiplier
	end
	return m * boostMult(data, "cash")
end

function Multipliers.Production(_player: Player, data: any): number
	local lvl = (data.upgrades and data.upgrades.pipeSpeed) or 0
	local m = 1 + lvl * Upgrades.ById.pipeSpeed.perLevel
	local ev = Multipliers.ActiveEvent()
	if ev and ev.productionMultiplier then
		m *= ev.productionMultiplier
	end
	return m * boostMult(data, "production")
end

-- Base milk/sec of the herd before multipliers
function Multipliers.HerdMilkPerSecond(data: any): number
	local Cows = require(script.Parent.Config.Cows)
	local total = 0
	for tier, count in data.cows or {} do
		local t = Cows.Get(tonumber(tier) :: number)
		if t then
			total += t.milkPerSecond * count
		end
	end
	return total
end

function Multipliers.MilkPerSecond(player: Player, data: any): number
	return Multipliers.HerdMilkPerSecond(data) * Multipliers.Production(player, data)
end

-- Current server milk price including the truck bonus
function Multipliers.MilkPrice(): number
	local price = workspace:GetAttribute("MilkPrice")
	local p = if typeof(price) == "number" then price else 1
	if workspace:GetAttribute("TruckActive") then
		p *= Economy.Truck.PriceBonus
	end
	return p
end

return Multipliers
