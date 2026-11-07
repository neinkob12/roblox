--!strict
-- E1 IndexRewardService: Cow Index milestone rewards (see Config/IndexRewards).
--
--   RequestIndexClaim (client -> server): (count: number)
--     `count` must be a milestone in IndexRewards.Milestones, the player must have discovered at
--     least that many tiers, and it must not be in data.indexClaimed yet. Grants every reward in
--     the milestone through Util/Rewards (premium crate through CrateService:GiveCrate(player, true)).
--     A milestone's cashBonus is permanent: Multipliers.Cash reads data.indexClaimed.
--
--   IndexRewardService:Claim(player, count) -> string?   same as the remote (no debounce)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Multipliers = require(ReplicatedStorage.Shared.Multipliers)
local IndexRewards = require(ReplicatedStorage.Shared.Config.IndexRewards)
local DataService = require(script.Parent.DataService)
local CrateService = require(script.Parent.CrateService)
local Notify = require(script.Parent.Parent.Util.Notify)
local Debounce = require(script.Parent.Parent.Util.Debounce)
local Rewards = require(script.Parent.Parent.Util.Rewards)
local Safe = require(ReplicatedStorage.Shared.Safe)

local IndexRewardService = {}

local function grantOne(player: Player, data: any, count: number, reward: IndexRewards.Reward): string?
	local source = `index{count}`
	if reward.kind == "cash" then
		local amount =
			IndexRewards.CashAmount(Multipliers.MilkPerSecond(player, data), Multipliers.Cash(player, data), reward)
		return Rewards.Grant(player, { kind = "cash", amount = amount }, source)
	elseif reward.kind == "crates" then
		return Rewards.Grant(player, { kind = "crates", amount = reward.amount }, source)
	elseif reward.kind == "premiumCrate" then
		if CrateService:GiveCrate(player, true) then
			return "a Premium Milk Crate"
		end
	end
	return nil
end

function IndexRewardService:Claim(player: Player, count: any): string?
	if typeof(count) ~= "number" or count ~= count then
		return nil
	end
	local milestone = IndexRewards.ByCount[count]
	local data = DataService:Get(player)
	if not milestone or not data then
		return nil
	end
	if typeof(data.indexClaimed) ~= "table" then
		data.indexClaimed = {}
	end
	if IndexRewards.IsClaimed(data, count) then
		return nil
	end
	if IndexRewards.DiscoveredCount(data) < count then
		Notify.To(player, `Discover {count} cows to claim this!`, "error")
		return nil
	end
	-- mark first so the permanent bonus and rewards can never be granted twice
	table.insert(data.indexClaimed, count)
	DataService:Replicate(player, "indexClaimed")
	local parts = {}
	for _, reward in milestone.rewards do
		local text = grantOne(player, data, count, reward)
		if text then
			table.insert(parts, text)
		else
			warn(`[IndexRewardService] milestone {count} has an invalid reward`)
		end
	end
	if milestone.cashBonus then
		table.insert(parts, `+{math.floor(milestone.cashBonus * 100 + 0.5)}% Cash forever`)
	end
	local text = if #parts > 0 then table.concat(parts, ", ") else "nothing"
	Notify.To(player, `Index {count} cows: {text}`, "success")
	return text
end

function IndexRewardService:Start()
	Net.Event("RequestIndexClaim").OnServerEvent:Connect(function(player: Player, count: any)
		if not Debounce.Try(player, "indexClaim", IndexRewards.RequestCooldownSeconds) then
			return
		end
		Safe.Run("IndexRewardService.Claim", function()
			IndexRewardService:Claim(player, count)
		end)
	end)
end

return IndexRewardService
