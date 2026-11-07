--!strict
-- The ONE place that hands things to a player. Plain module (not auto-loaded).
-- Every function validates first and changes nothing when the input is bad.
--
--   Rewards.Cash(player, amount, countsAsEarned?) -> boolean
--       countsAsEarned = false keeps it out of totalCashEarned (leaderboard + "earn cash" quests),
--       used for Robux cash packs.
--   Rewards.Crates(player, n) -> boolean                 unopened Mystery Milk Crates
--   Rewards.Boost(player, id, kind, mult, seconds) -> number?   returns the new expiry (Multipliers.Now)
--       kind = "cash" | "production". Expired boosts are pruned. The same id with the same kind and
--       mult stacks time. A different kind/mult under an active id is stored next to it
--       (key "id:kind:mult") instead of silently overwriting it.
--   Rewards.Cow(player, tier, n) -> boolean              marks discovered, fires CowDiscovered
--   Rewards.AddCowsRaw(player, data, tier, n) -> boolean same, without replicating (batch changes);
--                                                        returns true when "discovered" changed
--   Rewards.Grant(player, reward, sourceId) -> string?   a Config reward table (Codes, Quests):
--       { kind = "cash", amount } | { kind = "crates", amount } | { kind = "boost", boostKind, mult, seconds }
--       Returns a short text for the toast, nil when nothing was given.
--
-- Boost clock: expiry is Multipliers.Now() (workspace:GetServerTimeNow()), the same clock the client
-- reads, so boost timers in the UI match the server exactly.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Format = require(ReplicatedStorage.Shared.Format)
local Cows = require(ReplicatedStorage.Shared.Config.Cows)
local Multipliers = require(ReplicatedStorage.Shared.Multipliers)
local DataService = require(script.Parent.Parent.Services.DataService)

local Rewards = {}

local function positive(n: any): boolean
	return typeof(n) == "number" and n == n and n > 0 and n ~= math.huge
end

function Rewards.Cash(player: Player, amount: number, countsAsEarned: boolean?): boolean
	if not positive(amount) or not DataService:Get(player) then
		return false
	end
	DataService:AddCash(player, amount, countsAsEarned)
	return true
end

function Rewards.Crates(player: Player, n: number): boolean
	local data = DataService:Get(player)
	if not data or not positive(n) or n ~= math.floor(n) then
		return false
	end
	data.crates = (data.crates or 0) + n
	DataService:Replicate(player, "crates")
	return true
end

function Rewards.Boost(player: Player, id: string, kind: string, mult: number, seconds: number): number?
	local data = DataService:Get(player)
	if not data or id == "" or (kind ~= "cash" and kind ~= "production") or not positive(mult) then
		return nil
	end
	if not positive(seconds) then
		return nil
	end
	data.boosts = data.boosts or {}
	local now = Multipliers.Now()
	for key, b in data.boosts do
		if typeof(b) ~= "table" or typeof(b.expires) ~= "number" or b.expires <= now then
			data.boosts[key] = nil
		end
	end
	local key = id
	local existing = data.boosts[key]
	if existing and (existing.kind ~= kind or existing.mult ~= mult) then
		key = `{id}:{kind}:{mult}`
		existing = data.boosts[key]
	end
	local expires: number
	if existing then
		existing.expires += seconds
		expires = existing.expires
	else
		expires = now + seconds
		data.boosts[key] = { kind = kind, mult = mult, expires = expires }
	end
	DataService:Replicate(player, "boosts")
	return expires
end

function Rewards.AddCowsRaw(player: Player, data: any, tier: number, n: number): boolean
	if n <= 0 or tier < 1 or tier > Cows.Count or tier ~= math.floor(tier) then
		return false
	end
	local key = tostring(tier)
	data.cows[key] = (data.cows[key] or 0) + n
	if not data.discovered[key] then
		data.discovered[key] = true
		Net.Event("CowDiscovered"):FireClient(player, tier)
		return true
	end
	return false
end

function Rewards.Cow(player: Player, tier: number, n: number): boolean
	local data = DataService:Get(player)
	if not data or not positive(n) or tier < 1 or tier > Cows.Count or tier ~= math.floor(tier) then
		return false
	end
	local newDiscovery = Rewards.AddCowsRaw(player, data, tier, n)
	DataService:Replicate(player, "cows")
	if newDiscovery then
		DataService:Replicate(player, "discovered")
	end
	return true
end

function Rewards.Grant(player: Player, reward: { [string]: any }, sourceId: string): string?
	if reward.kind == "cash" then
		local amount = tonumber(reward.amount) or 0
		if Rewards.Cash(player, amount) then
			return `+{Format.Cash(amount)}`
		end
	elseif reward.kind == "crates" then
		local amount = math.floor(tonumber(reward.amount) or 0)
		if Rewards.Crates(player, amount) then
			return `+{amount} Mystery Milk Crate{if amount == 1 then "" else "s"}`
		end
	elseif reward.kind == "boost" then
		local kind = reward.boostKind
		local mult = tonumber(reward.mult) or 0
		local seconds = tonumber(reward.seconds) or 0
		if typeof(kind) == "string" and Rewards.Boost(player, sourceId, kind, mult, seconds) then
			local what = if kind == "cash" then "Cash" else "Milk"
			return `{Format.Number(mult)}x {what} for {Format.Time(seconds)}`
		end
	end
	return nil
end

return Rewards
