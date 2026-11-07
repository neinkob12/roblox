--!strict
-- Roblox policy checks per player (paid random items, trading). Owner: lead.
-- https://create.roblox.com/docs/production/monetization/paid-random-items
--
-- Sets player attributes on join (default = restricted until the check succeeds):
--   PaidRandomRestricted : boolean  true -> this player must NOT access random rewards that are paid
--                                   directly or indirectly with Robux (cash can be bought with Robux,
--                                   so buying crates/eggs with cash counts). Free, earned crates/eggs
--                                   (drops, quests, codes, daily) stay allowed.
--   PaidTradingAllowed   : boolean
--
--   ComplianceService:IsPaidRandomRestricted(player) -> boolean   (server gate for every paid roll)

local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local RunService = game:GetService("RunService")

local Safe = require(game:GetService("ReplicatedStorage").Shared.Safe)

local RETRIES = 3

local ComplianceService = {}

local function check(player: Player)
	-- safe default while the check runs or if it keeps failing
	player:SetAttribute("PaidRandomRestricted", true)
	player:SetAttribute("PaidTradingAllowed", false)
	for attempt = 1, RETRIES do
		local ok, info = pcall(function()
			return PolicyService:GetPolicyInfoForPlayerAsync(player)
		end)
		if ok and typeof(info) == "table" then
			player:SetAttribute("PaidRandomRestricted", info.ArePaidRandomItemsRestricted == true)
			player:SetAttribute("PaidTradingAllowed", info.IsPaidItemTradingAllowed == true)
			return
		end
		if player.Parent ~= Players then
			return
		end
		task.wait(2 * attempt)
	end
	if RunService:IsStudio() then
		-- PolicyService often fails in Studio; don't lock the developer out of testing
		player:SetAttribute("PaidRandomRestricted", false)
		warn("[ComplianceService] policy check failed in Studio; treating as unrestricted for testing")
	else
		warn(`[ComplianceService] policy check failed for {player.Name}; keeping paid random items restricted`)
	end
end

function ComplianceService:IsPaidRandomRestricted(player: Player): boolean
	return player:GetAttribute("PaidRandomRestricted") ~= false
end

function ComplianceService:Start()
	for _, player in Players:GetPlayers() do
		task.spawn(Safe.Run, "ComplianceService check", check, player)
	end
	Players.PlayerAdded:Connect(function(player)
		Safe.Run("ComplianceService check", check, player)
	end)
end

return ComplianceService
