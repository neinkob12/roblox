--!strict
-- E1: Cow Index milestone rewards. Pure data + small shared helpers (no Init/Start), used by
-- server/Services/IndexRewardService, client/UI/IndexPanel and shared/Multipliers.
--
-- data.indexClaimed  list of claimed milestone counts, e.g. { 3, 6 }
--
-- Each milestone is claimable once `count` cow tiers are discovered (data.discovered).
-- rewards: a list of
--   { kind = "cash", productionSeconds }   productionSeconds of current production, at least CashMinimum
--   { kind = "crates", amount }
--   { kind = "premiumCrate" }              CrateService:GiveCrate(player, true)
-- cashBonus: PERMANENT extra cash multiplier once claimed (adds up: 3 x 0.05 = +15%).
--   Applied in Multipliers.Cash via IndexRewards.CashMultiplier(data). Survives rebirth.

export type Reward = {
	kind: "cash" | "crates" | "premiumCrate",
	productionSeconds: number?,
	amount: number?,
}

export type Milestone = {
	count: number,
	rewards: { Reward },
	cashBonus: number?,
	label: string, -- short text for the claim button
}

local IndexRewards = {}

IndexRewards.CashMinimum = 500
IndexRewards.RequestCooldownSeconds = 0.5

IndexRewards.Milestones = {
	{ count = 3, rewards = { { kind = "cash", productionSeconds = 600 } }, label = "Cash" },
	{ count = 6, rewards = { { kind = "crates", amount = 3 } }, label = "3 Crates" },
	{ count = 9, rewards = { { kind = "premiumCrate" } }, label = "Premium Crate" },
	{ count = 12, rewards = {}, cashBonus = 0.05, label = "+5% Cash" },
	{ count = 15, rewards = {}, cashBonus = 0.05, label = "+5% Cash" },
	{ count = 18, rewards = {}, cashBonus = 0.05, label = "+5% Cash" },
} :: { Milestone }

IndexRewards.ByCount = {} :: { [number]: Milestone }
for _, m in IndexRewards.Milestones do
	IndexRewards.ByCount[m.count] = m
end

function IndexRewards.DiscoveredCount(data: any): number
	local n = 0
	if data and typeof(data.discovered) == "table" then
		for _, v in data.discovered do
			if v == true then
				n += 1
			end
		end
	end
	return n
end

function IndexRewards.IsClaimed(data: any, count: number): boolean
	if not data or typeof(data.indexClaimed) ~= "table" then
		return false
	end
	return table.find(data.indexClaimed, count) ~= nil
end

-- Number of milestones that are reached but not claimed yet (for the menu badge).
function IndexRewards.ClaimableCount(data: any): number
	local found = IndexRewards.DiscoveredCount(data)
	local n = 0
	for _, m in IndexRewards.Milestones do
		if found >= m.count and not IndexRewards.IsClaimed(data, m.count) then
			n += 1
		end
	end
	return n
end

-- Permanent cash multiplier from claimed milestones (1 = none).
function IndexRewards.CashMultiplier(data: any): number
	if not data or typeof(data.indexClaimed) ~= "table" then
		return 1
	end
	local bonus = 0
	local seen: { [number]: boolean } = {}
	for _, count in data.indexClaimed do
		local m = IndexRewards.ByCount[count]
		if m and m.cashBonus and not seen[count] then
			seen[count] = true
			bonus += m.cashBonus
		end
	end
	return 1 + bonus
end

function IndexRewards.CashAmount(milkPerSecond: number, cashMultiplier: number, reward: Reward): number
	local amount = milkPerSecond * (reward.productionSeconds or 0) * cashMultiplier
	if amount ~= amount or amount == math.huge then
		amount = 0
	end
	return math.floor(math.max(IndexRewards.CashMinimum, amount))
end

return IndexRewards
