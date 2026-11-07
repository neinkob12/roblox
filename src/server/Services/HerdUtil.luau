--!strict
-- Shared helpers for the herd economy (A4). Not a service: no Init/Start.
--
--   HerdUtil.GiveCow(player, tier, n)          add n cows of a tier (marks discovered, fires CowDiscovered)
--   HerdUtil.AddCowsRaw(player, data, tier, n) same but does NOT replicate "cows" (for batch changes)
--   HerdUtil.BestTier(data) -> number           highest tier with count > 0 (1 if none)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Cows = require(ReplicatedStorage.Shared.Config.Cows)
local DataService = require(script.Parent.DataService)

local HerdUtil = {}

-- Adds cows without replicating "cows". Returns true if "discovered" changed.
function HerdUtil.AddCowsRaw(player: Player, data: any, tier: number, n: number): boolean
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

function HerdUtil.GiveCow(player: Player, tier: number, n: number)
	local data = DataService:Get(player)
	if not data then
		return
	end
	local newDiscovery = HerdUtil.AddCowsRaw(player, data, tier, n)
	DataService:Replicate(player, "cows")
	if newDiscovery then
		DataService:Replicate(player, "discovered")
	end
end

function HerdUtil.BestTier(data: any): number
	local best = 0
	for key, count in data.cows do
		local tier = tonumber(key)
		if tier and count > 0 and tier > best then
			best = tier
		end
	end
	return if best == 0 then 1 else best
end

return HerdUtil
