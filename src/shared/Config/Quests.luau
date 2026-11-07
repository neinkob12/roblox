--!strict
-- Rotating quests (B2 QuestService). Every player always has `ActiveCount` quests.
-- Claiming a finished quest replaces it with a new random one (never two of the same type).
--
-- Targets: `targets` is a list of fixed counts (one picked at random), OR `targetSeconds`
-- means "N seconds of your current milk/sec" (so quests scale with your herd).
-- Rewards: kind = "cash" (cashSeconds x your milk/sec, at least MinCash),
--          "crates" (amount crates), "boost" (boostKind "cash" | "production", mult, seconds).
--
-- STUDIO TESTING: set `DebugEasyInStudio = true` to make every target 1 (or 1 second of milk)
-- so any single merge / sale / crate / buy completes a quest. Set it back to false before merging.

local Quests = {}

Quests.ActiveCount = 3
Quests.TrackSeconds = 2 -- how often counters are diffed
Quests.MinCash = 150 -- floor for cash rewards and cash-scaled targets
Quests.MinMilk = 50 -- floor for milk-scaled targets
Quests.DebugEasyInStudio = false

export type QuestDef = {
	type: string,
	text: string, -- "{n}" is replaced with the formatted target
	targets: { number }?,
	targetSeconds: { number }?,
	rewards: { { [string]: any } },
}

Quests.Types = {
	{
		type = "merge_n",
		text = "Merge {n} cows",
		targets = { 3, 6, 10, 15 },
		rewards = {
			{ kind = "cash", cashSeconds = 120 },
			{ kind = "crates", amount = 1 },
		},
	},
	{
		type = "sell_milk_n",
		text = "Sell {n} milk at the dairy",
		targetSeconds = { 60, 120, 240 },
		rewards = {
			{ kind = "cash", cashSeconds = 150 },
			{ kind = "boost", boostKind = "production", mult = 2, seconds = 120 },
		},
	},
	{
		type = "open_crates_n",
		text = "Open {n} Mystery Milk Crates",
		targets = { 1, 2, 3 },
		rewards = {
			{ kind = "cash", cashSeconds = 180 },
			{ kind = "boost", boostKind = "cash", mult = 2, seconds = 120 },
		},
	},
	{
		type = "collect_cash_n",
		text = "Earn {n} cash",
		targetSeconds = { 90, 180, 300 },
		rewards = {
			{ kind = "crates", amount = 1 },
			{ kind = "boost", boostKind = "cash", mult = 2, seconds = 180 },
		},
	},
	{
		type = "buy_cows_n",
		text = "Buy {n} cows",
		targets = { 3, 5, 10, 25 },
		rewards = {
			{ kind = "cash", cashSeconds = 120 },
			{ kind = "crates", amount = 1 },
		},
	},
} :: { QuestDef }

Quests.ByType = {} :: { [string]: QuestDef }
for _, q in Quests.Types do
	Quests.ByType[q.type] = q
end

return Quests
