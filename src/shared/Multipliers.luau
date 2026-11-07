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
local Pets = require(script.Parent.Config.Pets)
local IndexRewards = require(script.Parent.Config.IndexRewards)

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

-- F1 pets (added by F1, reviewed by lead) -------------------------------------------------
-- Summed bonus of the equipped pets for one kind ("milk" | "cash" | "speed" | "luck"), e.g. 0.25 =
-- +25%. Only the first Pets.SlotsFor(rebirths) equipped uids that are really owned count.
-- Caps: speed <= Pets.SpeedCap, luck <= Pets.LuckCap.
function Multipliers.PetBonus(data: any, kind: string): number
	local pets = data and data.pets
	local equipped = data and data.equippedPets
	if typeof(pets) ~= "table" or typeof(equipped) ~= "table" then
		return 0
	end
	local slots = Pets.SlotsFor(data.rebirths or 0)
	local total = 0
	for i, uid in equipped do
		if i > slots then
			break
		end
		local pet = pets[uid]
		if typeof(pet) == "table" then
			local k, value = Pets.Boost(pet.id, pet.variant)
			if k == kind then
				total += value
			end
		end
	end
	if kind == "speed" then
		total = math.min(total, Pets.SpeedCap)
	elseif kind == "luck" then
		total = math.min(total, Pets.LuckCap)
	end
	return total
end

-- Permanent pet index milk bonus: 1 + IndexMilkPerStep x floor(discovered entries / IndexStep)
function Multipliers.PetIndexMilk(data: any): number
	local index = data and data.petIndex
	if typeof(index) ~= "table" then
		return 1
	end
	local n = 0
	for key, v in index do
		if v == true and typeof(key) == "string" then
			n += 1
		end
	end
	return 1 + Pets.IndexMilkPerStep * (n // Pets.IndexStep)
end
-- end F1 pets ----------------------------------------------------------------------------

function Multipliers.Cash(player: Player, data: any): number
	local m = 1 + Economy.Rebirth.CashMultiplierPerRebirth * (data.rebirths or 0)
	m *= IndexRewards.CashMultiplier(data) -- E1: permanent bonus from claimed Index milestones
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
	m *= 1 + Multipliers.PetBonus(data, "cash") -- F1 pets
	return m * boostMult(data, "cash")
end

function Multipliers.Production(_player: Player, data: any): number
	local lvl = (data.upgrades and data.upgrades.pipeSpeed) or 0
	local m = 1 + lvl * Upgrades.ById.pipeSpeed.perLevel
	local ev = Multipliers.ActiveEvent()
	if ev and ev.productionMultiplier then
		m *= ev.productionMultiplier
	end
	m *= (1 + Multipliers.PetBonus(data, "milk")) * Multipliers.PetIndexMilk(data) -- F1 pets
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
