--!strict
-- E1: Daily login rewards. A 7-day cycle that loops after day 7. Pure data + small shared helpers
-- (no Init/Start), used by server/Services/DailyService and client/UI/DailyPanel.
--
-- data.dailyStreak    days claimed in the current streak (0 = never / reset)
-- data.dailyLastClaim Multipliers.Now() of the last claim (0 = never)
--
-- A claim is available once ClaimCooldownSeconds have passed since the last claim. If
-- StreakResetSeconds have passed, the streak starts again at day 1.
--
-- reward.kind:
--   "cash"         productionSeconds of the player's current production (milk/s x cash multiplier),
--                  at least CashMinimum
--   "crates"       amount unopened Mystery Milk Crates
--   "boost"        boostKind "cash" | "production", mult, seconds
--   "premiumCrate" CrateService:GiveCrate(player, true) (opens right away with better odds)

export type DayReward = {
	kind: "cash" | "crates" | "boost" | "premiumCrate",
	productionSeconds: number?,
	amount: number?,
	boostKind: string?,
	mult: number?,
	seconds: number?,
	icon: string,
	label: string, -- short text for the 7-day strip
}

local Daily = {}

Daily.ClaimCooldownSeconds = 20 * 3600
Daily.StreakResetSeconds = 48 * 3600
Daily.CashMinimum = 250
Daily.RequestCooldownSeconds = 1 -- per player, between claim requests

Daily.Days = {
	{ kind = "cash", productionSeconds = 300, icon = "💵", label = "Cash" },
	{ kind = "crates", amount = 1, icon = "📦", label = "1 Crate" },
	{ kind = "boost", boostKind = "cash", mult = 2, seconds = 10 * 60, icon = "⚡", label = "2x Cash 10m" },
	{ kind = "cash", productionSeconds = 900, icon = "💰", label = "Big Cash" },
	{ kind = "crates", amount = 2, icon = "📦", label = "2 Crates" },
	{ kind = "boost", boostKind = "production", mult = 2, seconds = 15 * 60, icon = "🥛", label = "2x Milk 15m" },
	{ kind = "premiumCrate", icon = "🎁", label = "Premium Crate" },
} :: { DayReward }

local function num(v: any): number
	return if typeof(v) == "number" and v == v then v else 0
end

-- True when the player may claim now.
function Daily.CanClaim(data: any, now: number): boolean
	if not data then
		return false
	end
	local last = num(data.dailyLastClaim)
	return last <= 0 or now - last >= Daily.ClaimCooldownSeconds
end

-- True when the streak is broken (the next claim is day 1 again).
function Daily.StreakBroken(data: any, now: number): boolean
	local last = num(data and data.dailyLastClaim)
	return last <= 0 or now - last >= Daily.StreakResetSeconds
end

-- The streak count the next claim builds on (0 after a reset).
function Daily.EffectiveStreak(data: any, now: number): number
	if not data or Daily.StreakBroken(data, now) then
		return 0
	end
	return math.max(0, math.floor(num(data.dailyStreak)))
end

-- 1..#Days: the day the next claim gives (or the day just claimed + 1 while waiting).
function Daily.NextDay(data: any, now: number): number
	return Daily.EffectiveStreak(data, now) % #Daily.Days + 1
end

-- Seconds until the next claim is available (0 when available).
function Daily.SecondsUntilClaim(data: any, now: number): number
	if Daily.CanClaim(data, now) then
		return 0
	end
	return math.max(0, num(data.dailyLastClaim) + Daily.ClaimCooldownSeconds - now)
end

-- Cash amount for a "cash" reward, from milk/s and the cash multiplier.
function Daily.CashAmount(milkPerSecond: number, cashMultiplier: number, reward: DayReward): number
	local amount = milkPerSecond * (reward.productionSeconds or 0) * cashMultiplier
	if amount ~= amount or amount == math.huge then
		amount = 0
	end
	return math.floor(math.max(Daily.CashMinimum, amount))
end

return Daily
