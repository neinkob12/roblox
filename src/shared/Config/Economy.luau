--!strict
-- All economy tuning numbers live here so balancing never touches gameplay code.
-- Owner: Production & Dairy session (A3) and Cow Economy session (A4) may TUNE values.
-- Do not rename keys without updating docs/CONTRACTS.md.
--
-- Units:
--   milk  = abstract milk units (cows produce milk units/sec; Config/Cows.milkPerSecond)
--   cash  = $ (1 milk unit sells for $1 * price * cash multipliers)
-- Capacities that must stay meaningful as production explodes are expressed in
-- "seconds of current production" with a flat minimum.

local Economy = {}

Economy.StartingCash = 10
Economy.StartingCows = { [1] = 1 } -- tier -> count for brand new players

-- Buy pads (always buy tier 1 cows). Price of the n-th cow ever bought this rebirth:
--   BuyBasePrice * BuyPriceGrowth ^ cowsBought
Economy.BuyPads = { 1, 5, 25 }
Economy.BuyBasePrice = 5
Economy.BuyPriceGrowth = 1.035

-- Merge: MergeCost cows of tier N -> 1 cow of tier N+1
Economy.MergeCost = 3

-- Tank: fills from pipes, stops when full
Economy.Tank = {
	MinCapacity = 50,
	BaseSeconds = 60, -- capacity = max(MinCapacity, production/sec * seconds) * (1 + tankCapacity lvl * perLevel)
	TickSeconds = 1, -- production tick
	ReplicateSeconds = 0.5, -- tankMilk is sent to the client at most this often
}

-- Milk can (carried by the player, filled at the tank tap)
Economy.Can = {
	MinCapacity = 25,
	BaseSeconds = 30, -- capacity = max(MinCapacity, production/sec * seconds) * (1 + canSize lvl * perLevel)
	AutoCollectBaseSeconds = 10, -- autoCollect upgrade fills the can every (this - level) seconds
	AutoCollectMinSeconds = 2,
}

-- Dairy: deposited milk is sold over time, cash waits on the collect pad
Economy.Dairy = {
	MinSellPerSecond = 5,
	BaseSellFactor = 2, -- sells (production/sec * factor) milk per second, * (1 + sellSpeed lvl * perLevel)
	TickSeconds = 0.5, -- how often the queue sells
	AutoSellSeconds = 5, -- Auto Sell gamepass deposits the can this often
}

-- Milk price board: random multiplier, re-rolled every interval, same for whole server
Economy.MilkPrice = {
	Min = 0.5,
	Max = 1.5,
	IntervalSeconds = 30,
}

-- Milk truck: occasional bonus buyer at the dairy
Economy.Truck = {
	EverySeconds = 300,
	StaysSeconds = 45,
	PriceBonus = 1.5, -- multiplies the current milk price while the truck is there
	DriveSeconds = 4, -- drive in / drive out animation
	DriveDistance = 80, -- studs the truck travels to reach TruckStop
}

-- Rare milk: chance per production tick that a cow's milk becomes rare
Economy.RareMilk = {
	{ id = "golden", name = "Golden Milk", multiplier = 5, chance = 0.01 },
	{ id = "diamond", name = "Diamond Milk", multiplier = 10, chance = 0.002 },
}

-- Rebirth: resets cash, cows, cowsBought, tank/can/dairy milk AND upgrades.
-- Keeps: rebirths, discovered (index), quests progress, codes, purchases, stats.
Economy.Rebirth = {
	CashMultiplierPerRebirth = 0.5, -- total = 1 + 0.5 * rebirths
	BaseCost = 1e6,
	CostGrowth = 6, -- cost = BaseCost * CostGrowth ^ rebirths
}

-- Offline earnings: cows keep filling the tank (respecting capacity) up to a cap
Economy.Offline = {
	MaxSeconds = 8 * 60 * 60,
	Efficiency = 0.5, -- offline production is 50% of online
}

-- Friend boost: +10% per friend in server, capped
Economy.FriendBoost = {
	PerFriend = 0.1,
	Max = 0.5,
}

-- Lucky crates ("Mystery Milk Crate")
Economy.Crate = {
	DropChancePerCowPerMinute = 0.002,
	BuyBasePrice = 250,
	BuyPriceSecondsOfProduction = 120, -- price = max(BuyBasePrice, production/sec * this)
	-- Odds are relative to the player's highest tier owned (best):
	-- offset 0 = same tier as best, +1 = one above, etc. Weights must sum to 100.
	Odds = {
		{ offset = -1, weight = 60 },
		{ offset = 0, weight = 30 },
		{ offset = 1, weight = 9 },
		{ offset = 2, weight = 1 },
	},
}

return Economy
