--!strict
-- Cash upgrades. Level 0 = not bought. Effect formulas are applied by the owning service.
-- Owner: Cow Economy session (A4) implements purchase; effects are read by A3 (tank, can,
-- pipe, sell, autoCollect) and by the character code (walkSpeed).

export type Upgrade = {
	id: string,
	name: string,
	description: string,
	maxLevel: number,
	baseCost: number,
	costGrowth: number, -- cost(level) = baseCost * costGrowth ^ level   (level = current level)
	perLevel: number, -- meaning depends on the upgrade, see description
}

local Upgrades = {}

Upgrades.List = {
	{
		id = "tankCapacity",
		name = "Bigger Tank",
		description = "+50% tank capacity per level",
		maxLevel = 25,
		baseCost = 50,
		costGrowth = 2.2,
		perLevel = 0.5,
	},
	{
		id = "pipeSpeed",
		name = "Faster Pipes",
		description = "+10% milk production per level",
		maxLevel = 25,
		baseCost = 75,
		costGrowth = 2.3,
		perLevel = 0.1,
	},
	{
		id = "canSize",
		name = "Bigger Milk Can",
		description = "+50% can capacity per level",
		maxLevel = 25,
		baseCost = 40,
		costGrowth = 2.1,
		perLevel = 0.5,
	},
	{
		id = "walkSpeed",
		name = "Running Boots",
		description = "+2 walk speed per level",
		maxLevel = 10,
		baseCost = 100,
		costGrowth = 2.5,
		perLevel = 2,
	},
	{
		id = "sellSpeed",
		name = "Faster Dairy",
		description = "+25% dairy sell speed per level",
		maxLevel = 25,
		baseCost = 60,
		costGrowth = 2.2,
		perLevel = 0.25,
	},
	{
		id = "autoCollect",
		name = "Auto Collect",
		description = "Auto-fills your can from the tank every (10 - level) seconds",
		maxLevel = 5,
		baseCost = 5000,
		costGrowth = 4,
		perLevel = 1,
	},
} :: { Upgrade }

Upgrades.ById = {} :: { [string]: Upgrade }
for _, u in Upgrades.List do
	Upgrades.ById[u.id] = u
end

function Upgrades.Cost(id: string, currentLevel: number): number
	local u = Upgrades.ById[id]
	return math.floor(u.baseCost * u.costGrowth ^ currentLevel)
end

return Upgrades
