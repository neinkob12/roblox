--!strict
-- Source of truth for all 18 cow tiers, weakest to strongest.
-- Merge rule: 3 cows of tier N become 1 cow of tier N+1 (see Economy.MergeCost).
-- Owner: lead session. Other sessions READ this; propose changes in your PR description.
--
-- famous = true marks a cow-ified version of a known Italian-brainrot character.
-- Hard rule: NO Tung Tung Tung Sahur, NO Tralalero Tralala, NO Bombardiro Crocodilo
-- (active trademark litigation or offensive original audio). Each famous name must be
-- re-checked on USPTO TESS before going public (tracked in the Marketing/QA issue).

export type CowTier = {
	tier: number,
	id: string,
	name: string,
	famous: boolean,
	bodyColor: Color3,
	spotColor: Color3,
	milkColor: Color3,
	look: string, -- build notes for the Part-built model (CowModels.luau)
	milkPerSecond: number, -- base milk units per second per cow
}

local MILK_GROWTH = 3.5 -- each tier makes 3.5x the previous; > 3 so merging is always worth it

local list: { { any } } = {
	-- id, name, famous, body, spots, milk, look
	{
		"pappuccia",
		"Mucca Pappuccia",
		false,
		Color3.fromRGB(245, 240, 225),
		Color3.fromRGB(110, 75, 50),
		Color3.fromRGB(255, 255, 255),
		"Plain cream cow, brown spots, tiny gold bell",
	},
	{
		"panino",
		"Moolino Panino",
		false,
		Color3.fromRGB(215, 175, 120),
		Color3.fromRGB(160, 110, 60),
		Color3.fromRGB(255, 240, 170),
		"Two bread-slice parts on its back like a sandwich, lettuce edge",
	},
	{
		"patapim",
		"Brr Brr Patamoo",
		true,
		Color3.fromRGB(120, 160, 80),
		Color3.fromRGB(90, 60, 40),
		Color3.fromRGB(200, 255, 200),
		"Tree-trunk legs, leafy head, big nose (cow-ified Brr Brr Patapim)",
	},
	{
		"spaghettino",
		"Bovino Spaghettino",
		false,
		Color3.fromRGB(200, 50, 45),
		Color3.fromRGB(255, 220, 90),
		Color3.fromRGB(255, 150, 70),
		"Red cow, yellow noodle cylinders as tail and hair",
	},
	{
		"lirili",
		"Lirili Larilatte",
		true,
		Color3.fromRGB(150, 160, 170),
		Color3.fromRGB(70, 140, 70),
		Color3.fromRGB(210, 255, 210),
		"Grey elephant-ish cow, cactus parts on back, sandals (cow-ified Lirili Larila)",
	},
	{
		"biscottino",
		"Lattuccio Biscottino",
		false,
		Color3.fromRGB(150, 95, 55),
		Color3.fromRGB(70, 40, 20),
		Color3.fromRGB(120, 70, 40),
		"Cookie-brown body with chocolate chip spots",
	},
	{
		"bananini",
		"Chimpanzini Muuanini",
		true,
		Color3.fromRGB(255, 220, 60),
		Color3.fromRGB(120, 80, 40),
		Color3.fromRGB(255, 240, 120),
		"Banana-peel shell parts around a monkey-faced cow (cow-ified Chimpanzini Bananini)",
	},
	{
		"fragoletta",
		"Mammuccia Fragoletta",
		false,
		Color3.fromRGB(255, 120, 150),
		Color3.fromRGB(255, 240, 200),
		Color3.fromRGB(255, 170, 190),
		"Pink cow, seed dots, green leaf crown like a strawberry",
	},
	{
		"cappuccina",
		"Ballerina Cappumoocina",
		true,
		Color3.fromRGB(240, 220, 200),
		Color3.fromRGB(120, 80, 50),
		Color3.fromRGB(200, 160, 120),
		"Coffee-cup head, pink tutu ring, standing on tip-toes (cow-ified Ballerina Cappuccina)",
	},
	{
		"gelatino",
		"Gelatino Muccalino",
		false,
		Color3.fromRGB(180, 230, 255),
		Color3.fromRGB(255, 180, 220),
		Color3.fromRGB(255, 200, 240),
		"Pastel scoop spheres stacked on back, waffle-cone tail",
	},
	{
		"trippi",
		"Trippi Troppi Muuppi",
		true,
		Color3.fromRGB(255, 160, 60),
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(255, 200, 120),
		"Shrimp-tail cow with cat ears and whiskers (cow-ified Trippi Troppi)",
	},
	{
		"formaggiona",
		"Pizzavacca Formaggiona",
		false,
		Color3.fromRGB(255, 200, 80),
		Color3.fromRGB(190, 40, 40),
		Color3.fromRGB(255, 220, 100),
		"Wedge pizza body, pepperoni dots, cheese drip parts",
	},
	{
		"frigo",
		"Frigo Cammellatte",
		true,
		Color3.fromRGB(230, 235, 240),
		Color3.fromRGB(160, 120, 70),
		Color3.fromRGB(220, 245, 255),
		"Fridge-box body with a door handle, camel hump on top (cow-ified Frigo Camelo)",
	},
	{
		"robomucca",
		"Robomucca Bullonella",
		false,
		Color3.fromRGB(150, 155, 165),
		Color3.fromRGB(60, 65, 75),
		Color3.fromRGB(190, 255, 80),
		"Metal body, antenna, glowing Neon eyes",
	},
	{
		"lavalina",
		"Vulcanuccia Lavalina",
		false,
		Color3.fromRGB(45, 40, 40),
		Color3.fromRGB(255, 110, 20),
		Color3.fromRGB(255, 130, 40),
		"Dark stone body with orange Neon crack parts, smoke particles",
	},
	{
		"glorbo",
		"Glorbo Muuttodrillo",
		true,
		Color3.fromRGB(90, 170, 70),
		Color3.fromRGB(255, 110, 130),
		Color3.fromRGB(255, 140, 160),
		"Watermelon-shell body with crocodile snout (cow-ified Glorbo Fruttodrillo)",
	},
	{
		"arcobalena",
		"Arcobalena Muuuricca",
		false,
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(255, 80, 80),
		Color3.fromRGB(255, 120, 255),
		"Rainbow-striped body, cloud tail, sparkle particles",
	},
	{
		"saturnita",
		"La Vacca Saturno Saturnita",
		true,
		Color3.fromRGB(70, 60, 130),
		Color3.fromRGB(255, 210, 120),
		Color3.fromRGB(170, 120, 255),
		"Cow head on a Saturn planet body with orbit ring, human feet, star particles (top tier)",
	},
}

local Cows = {}
Cows.Count = #list
Cows.Tiers = {} :: { CowTier }
Cows.ById = {} :: { [string]: CowTier }

for i, row in list do
	local t: CowTier = {
		tier = i,
		id = row[1],
		name = row[2],
		famous = row[3],
		bodyColor = row[4],
		spotColor = row[5],
		milkColor = row[6],
		look = row[7],
		milkPerSecond = MILK_GROWTH ^ (i - 1),
	}
	Cows.Tiers[i] = t
	Cows.ById[t.id] = t
end

function Cows.Get(tier: number): CowTier?
	return Cows.Tiers[tier]
end

return Cows
