--!strict
-- F1: eggs and nests. Odds are per RARITY (see Config/Pets); a pet of the rolled rarity is then
-- picked with equal weight. Never read Odds here directly for display: use Odds.Egg(eggId, luck),
-- which is the exact table the server rolls with.
--
-- Price: Pricing.Egg(player, data, eggId) = max(minPrice, priceSeconds x milk/s x cash multiplier).

export type Egg = {
	id: string,
	name: string,
	priceSeconds: number, -- seconds of the player's income
	minPrice: number, -- floor when income is tiny
	hatchSeconds: number,
	rebirthsRequired: number,
	odds: { [string]: number }, -- rarity id -> weight (percent), sums to 100
	color: Color3,
}

local Eggs = {}

Eggs.FreeEggSeconds = 600 -- a free egg every 10 minutes (RequestClaimFreeEgg), never gated
Eggs.FreeEggId = "pasture"

-- Nests unlock with rebirths (highest matching row wins). Keys are "1".."MaxNests".
Eggs.NestSlots = {
	{ rebirths = 0, nests = 2 },
	{ rebirths = 1, nests = 3 },
	{ rebirths = 3, nests = 4 },
}
Eggs.MaxNests = 4

Eggs.List = {
	{
		id = "pasture",
		name = "Pasture Egg",
		priceSeconds = 120,
		minPrice = 100,
		hatchSeconds = 60,
		rebirthsRequired = 0,
		odds = { common = 65, uncommon = 25, rare = 8, epic = 1.8, legendary = 0.2 },
		color = Color3.fromRGB(150, 220, 120),
	},
	{
		id = "dairy",
		name = "Dairy Egg",
		priceSeconds = 600,
		minPrice = 1000,
		hatchSeconds = 300,
		rebirthsRequired = 0,
		odds = { common = 30, uncommon = 40, rare = 22, epic = 7, legendary = 1 },
		color = Color3.fromRGB(250, 245, 230),
	},
	{
		id = "cosmic",
		name = "Cosmic Cream Egg",
		priceSeconds = 1800,
		minPrice = 50000,
		hatchSeconds = 900,
		rebirthsRequired = 2,
		odds = { common = 0, uncommon = 20, rare = 45, epic = 28, legendary = 7 },
		color = Color3.fromRGB(140, 90, 230),
	},
} :: { Egg }

Eggs.ById = {} :: { [string]: Egg }
for _, e in Eggs.List do
	Eggs.ById[e.id] = e
end

function Eggs.NestsFor(rebirths: number): number
	local n = 0
	for _, row in Eggs.NestSlots do
		if rebirths >= row.rebirths then
			n = math.max(n, row.nests)
		end
	end
	return n
end

return Eggs
