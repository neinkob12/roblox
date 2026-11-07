--!strict
-- The ONE place that turns a random-reward table into concrete outcomes with percentages.
-- Roblox "paid random items" policy: every outcome must be shown as a number BEFORE purchase and
-- the shown numbers must sum to 100%. So the UI shows exactly what the server rolls with:
--   local outcomes = Odds.Crate(bestTier, shift)   -- { { tier = 7, chance = 0.65 }, ... } sums to 1
--   local tier = Odds.Roll(outcomes, rng)           -- server only
--   Odds.Percent(0.0123) -> "1.23%"
--
-- Generic form for other systems (eggs): Odds.Normalize({ { key = ..., weight = n }, ... }).
--
-- Luck (F1 pets): every function that builds a table takes an optional `luck` (0.5 = +50%,
-- Multipliers.PetBonus(data, "luck")). It multiplies the weight of every outcome ABOVE the lowest
-- one by (1 + luck) before normalizing, so the shown odds already include the player's luck.
--   Odds.Egg(eggId, luck?)  -- { { key = "mochi", chance = 0.2167 }, ... } sums to 1, keys = pet ids

local Economy = require(script.Parent.Config.Economy)
local Cows = require(script.Parent.Config.Cows)
local Pets = require(script.Parent.Config.Pets)
local Eggs = require(script.Parent.Config.Eggs)

export type Outcome = { key: any, chance: number }

local Odds = {}

-- weights -> chances (0..1) summing to exactly 1; zero-weight entries are dropped; equal keys merge
function Odds.Normalize(entries: { { key: any, weight: number } }): { Outcome }
	local total = 0
	for _, e in entries do
		if e.weight > 0 then
			total += e.weight
		end
	end
	local byKey: { [any]: number } = {}
	local order: { any } = {}
	for _, e in entries do
		if e.weight > 0 and total > 0 then
			if byKey[e.key] == nil then
				byKey[e.key] = 0
				table.insert(order, e.key)
			end
			byKey[e.key] += e.weight / total
		end
	end
	local out: { Outcome } = {}
	for _, key in order do
		table.insert(out, { key = key, chance = byKey[key] })
	end
	return out
end

-- F1: multiply every weight whose rank is above the lowest present rank by (1 + luck).
-- `rank(key)` orders outcomes (higher = better). Entries are changed in place.
local function applyLuck(entries: { { key: any, weight: number } }, luck: number?, rank: (any) -> number)
	local l = luck or 0
	if l <= 0 or l ~= l or l == math.huge then
		return
	end
	local lowest = math.huge
	for _, e in entries do
		if e.weight > 0 then
			lowest = math.min(lowest, rank(e.key))
		end
	end
	for _, e in entries do
		if e.weight > 0 and rank(e.key) > lowest then
			e.weight *= 1 + l
		end
	end
end

-- Crate outcomes for a player whose best owned tier is `bestTier`. `shift` = premium bonus.
-- Keys are cow tiers. Clamping (tier 1 floor, Crate.MaxTier ceiling) merges outcomes, so the
-- displayed list is exactly what can drop. `luck` (optional, F1) boosts every tier above the lowest.
function Odds.Crate(bestTier: number, shift: number, luck: number?): { Outcome }
	local crate = Economy.Crate
	local maxTier = math.min(crate.MaxTier or Cows.Count, Cows.Count)
	-- never roll above MaxTier, but never below what the best tier would give a low player
	local ceiling = math.max(maxTier, math.min(bestTier, Cows.Count))
	local entries = {}
	for _, o in crate.Odds do
		table.insert(entries, { key = math.clamp(bestTier + o.offset + shift, 1, ceiling), weight = o.weight })
	end
	applyLuck(entries, luck, function(key)
		return key
	end)
	local outcomes = Odds.Normalize(entries)
	table.sort(outcomes, function(a, b)
		return a.key < b.key
	end)
	return outcomes
end

-- F1: egg outcomes, keys are pet ids. The rarity is rolled with the egg's rarity weights (luck
-- applied per rarity), then a pet of that rarity with equal weight. Sorted rarest last.
-- Unknown egg id -> {}.
function Odds.Egg(eggId: string, luck: number?): { Outcome }
	local egg = Eggs.ById[eggId]
	if not egg then
		return {}
	end
	local rarityEntries = {}
	for _, r in Pets.Rarities do
		local w = egg.odds[r.id] or 0
		if w > 0 and #Pets.ByRarity[r.id] > 0 then
			table.insert(rarityEntries, { key = r.id, weight = w })
		end
	end
	applyLuck(rarityEntries, luck, function(key)
		return Pets.RarityById[key].order
	end)
	local entries = {}
	for _, e in rarityEntries do
		local list = Pets.ByRarity[e.key]
		for _, pet in list do
			table.insert(entries, { key = pet.id, weight = e.weight / #list })
		end
	end
	return Odds.Normalize(entries)
end

-- Server: pick one outcome key.
function Odds.Roll(outcomes: { Outcome }, rng: Random): any
	local pick = rng:NextNumber()
	for _, o in outcomes do
		pick -= o.chance
		if pick <= 0 then
			return o.key
		end
	end
	return outcomes[#outcomes].key -- float rounding fallback
end

-- "65%", "1.8%", "0.25%": up to 4 significant digits, as the policy allows with rounding
function Odds.Percent(chance: number): string
	local p = chance * 100
	local s = if p >= 10
		then string.format("%.1f", p)
		elseif p >= 1 then string.format("%.2f", p)
		else string.format("%.3f", p)
	s = (string.gsub(s, "0+$", ""))
	s = (string.gsub(s, "%.$", ""))
	return s .. "%"
end

return Odds
