--!strict
-- F1: every pet, rarity and variant. Server (PetService/EggService) and client (F2 UI) read this.
-- Boost math lives in shared/Multipliers.luau (PetBonus); odds in shared/Odds.luau (Egg).
--
-- A pet's boost = rarity.boost (or SpeedBoost for speed pets, half for luck pets) x variant.mult.
-- Totals: each kind is capped (SpeedCap, LuckCap, MilkCap, CashCap) so pets can't break rebirth pacing.

export type BoostKind = "milk" | "cash" | "speed" | "luck"
export type Rarity = { id: string, name: string, order: number, boost: number, speedBoost: number, color: Color3 }
export type Variant = { id: string, name: string, mult: number, order: number }
export type Pet = { id: string, name: string, rarity: string, boost: BoostKind }

local Pets = {}

Pets.MaxInventory = 50 -- pets owned (eggs waiting in nests count toward it when buying)
Pets.MergeCount = 5 -- identical pets merged into 1 of the next variant
Pets.MaxReleasePerRequest = 50 -- RequestReleasePets array limit. Releasing gives NO refund (no cash loop)
Pets.SpeedCap = 0.3 -- total walk speed bonus (+30%)
Pets.LuckCap = 1.0 -- total luck (+100%)
Pets.MilkCap = 3.0 -- total milk bonus (+300%); milk and cash multiply, so pets give at most x16 income
Pets.CashCap = 3.0 -- total cash bonus (+300%)
Pets.LuckFactor = 0.5 -- luck pets give half the rarity's boost
Pets.IndexMilkPerStep = 0.02 -- permanent +2% milk ...
Pets.IndexStep = 5 -- ... for every 5 pet index entries discovered

-- Equip slots unlock with rebirths (highest matching row wins)
Pets.EquipSlots = {
	{ rebirths = 0, slots = 3 },
	{ rebirths = 2, slots = 4 },
	{ rebirths = 4, slots = 5 },
}
Pets.MaxEquipSlots = 5

Pets.Rarities = {
	{
		id = "common",
		name = "Common",
		order = 1,
		boost = 0.05,
		speedBoost = 0.02,
		color = Color3.fromRGB(170, 170, 170),
	},
	{
		id = "uncommon",
		name = "Uncommon",
		order = 2,
		boost = 0.10,
		speedBoost = 0.03,
		color = Color3.fromRGB(90, 200, 90),
	},
	{ id = "rare", name = "Rare", order = 3, boost = 0.20, speedBoost = 0.05, color = Color3.fromRGB(70, 140, 255) },
	{ id = "epic", name = "Epic", order = 4, boost = 0.40, speedBoost = 0.07, color = Color3.fromRGB(170, 80, 230) },
	{
		id = "legendary",
		name = "Legendary",
		order = 5,
		boost = 0.80,
		speedBoost = 0.10,
		color = Color3.fromRGB(255, 190, 40),
	},
} :: { Rarity }

Pets.Variants = {
	{ id = "normal", name = "Normal", mult = 1, order = 1 },
	{ id = "golden", name = "Golden", mult = 2.5, order = 2 },
	{ id = "rainbow", name = "Rainbow", mult = 6, order = 3 },
} :: { Variant }

-- what 5 of a variant merge into (nil = can't merge further)
Pets.NextVariant = { normal = "golden", golden = "rainbow" } :: { [string]: string }

Pets.List = {
	{ id = "mochi", name = "Moo-Moo Mochi", rarity = "common", boost = "milk" },
	{ id = "cheddarino", name = "Sir Cheddarino", rarity = "common", boost = "cash" },
	{ id = "calfetto", name = "Zoomy Calfetto", rarity = "common", boost = "speed" },
	{ id = "butterbun", name = "Butterbun Bovelli", rarity = "uncommon", boost = "milk" },
	{ id = "latte", name = "Latte Lamarino", rarity = "uncommon", boost = "cash" },
	{ id = "clover", name = "Clover Clompy", rarity = "uncommon", boost = "luck" },
	{ id = "sprinkle", name = "Sprinkle Udderini", rarity = "rare", boost = "milk" },
	{ id = "moozzarella", name = "Moozzarella Twirlo", rarity = "rare", boost = "cash" },
	{ id = "turbo", name = "Turbo Hoofino", rarity = "rare", boost = "speed" },
	{ id = "galacto", name = "Galacto Gelato", rarity = "epic", boost = "milk" },
	{ id = "bubbletea", name = "Bubbletea Bullwinko", rarity = "epic", boost = "luck" },
	{ id = "creamquake", name = "Creamquake Cowboni", rarity = "epic", boost = "cash" },
	{ id = "churnado", name = "Cosmic Churnado", rarity = "legendary", boost = "milk" },
	{ id = "yogurtron", name = "King Yogurtron", rarity = "legendary", boost = "cash" },
	{ id = "moonmilk", name = "Lucky Moonmilk", rarity = "legendary", boost = "luck" },
} :: { Pet }

Pets.ById = {} :: { [string]: Pet }
Pets.RarityById = {} :: { [string]: Rarity }
Pets.VariantById = {} :: { [string]: Variant }
Pets.ByRarity = {} :: { [string]: { Pet } } -- rarity id -> pets, in List order

for _, r in Pets.Rarities do
	Pets.RarityById[r.id] = r
	Pets.ByRarity[r.id] = {}
end
for _, v in Pets.Variants do
	Pets.VariantById[v.id] = v
end
for _, p in Pets.List do
	Pets.ById[p.id] = p
	table.insert(Pets.ByRarity[p.rarity], p)
end

-- Index entries: 15 pets x 3 variants = 45. Key format "petId:variant".
Pets.IndexSize = #Pets.List * #Pets.Variants

function Pets.IndexKey(petId: string, variant: string): string
	return petId .. ":" .. variant
end

-- Boost of one pet: kind and value (0.05 = +5%). nil for unknown ids.
function Pets.Boost(petId: string, variant: string): (BoostKind?, number)
	local pet = Pets.ById[petId]
	local v = Pets.VariantById[variant]
	if not pet or not v then
		return nil, 0
	end
	local r = Pets.RarityById[pet.rarity]
	local base = r.boost
	if pet.boost == "speed" then
		base = r.speedBoost
	elseif pet.boost == "luck" then
		base = r.boost * Pets.LuckFactor
	end
	return pet.boost, base * v.mult
end

function Pets.SlotsFor(rebirths: number): number
	local slots = 0
	for _, row in Pets.EquipSlots do
		if rebirths >= row.rebirths then
			slots = math.max(slots, row.slots)
		end
	end
	return slots
end

return Pets
