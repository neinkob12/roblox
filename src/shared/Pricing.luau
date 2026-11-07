--!strict
-- The ONE place for every price formula. Server services charge with it, the client UI shows it,
-- so displayed prices can never drift from what the server charges again.

local Economy = require(script.Parent.Config.Economy)
local Eggs = require(script.Parent.Config.Eggs)
local Multipliers = require(script.Parent.Multipliers)

local Pricing = {}

-- Total price of the next `n` tier-1 cows, given how many were bought this rebirth.
function Pricing.Cows(cowsBought: number, n: number): number
	local base = Economy.BuyBasePrice
	local g = Economy.BuyPriceGrowth
	local total = if g == 1 then base * n else base * g ^ cowsBought * (g ^ n - 1) / (g - 1) -- geometric series
	return math.floor(total + 0.5)
end

-- Price of one Mystery Milk Crate for this player.
function Pricing.Crate(player: Player, data: any): number
	local c = Economy.Crate
	if not data then
		return c.BuyBasePrice
	end
	local mps = Multipliers.MilkPerSecond(player, data)
	if c.PriceUsesCashMultiplier then
		mps *= Multipliers.Cash(player, data)
	end
	local price = math.max(c.BuyBasePrice, mps * c.BuyPriceSecondsOfProduction)
	return math.floor(price * (c.BuyPriceGrowth or 1) ^ (data.cratesBought or 0))
end

-- F1: price of one egg = max(minPrice, priceSeconds x milk/s x cash multiplier). 0 for unknown ids.
function Pricing.Egg(player: Player, data: any, eggId: string): number
	local egg = Eggs.ById[eggId]
	if not egg then
		return 0
	end
	if not data then
		return egg.minPrice
	end
	local income = Multipliers.MilkPerSecond(player, data) * Multipliers.Cash(player, data)
	return math.floor(math.max(egg.minPrice, income * egg.priceSeconds))
end

-- Cash needed for the next rebirth.
function Pricing.Rebirth(rebirths: number): number
	return math.floor(Economy.Rebirth.BaseCost * Economy.Rebirth.CostGrowth ^ rebirths)
end

return Pricing
