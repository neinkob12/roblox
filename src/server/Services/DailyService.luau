--!strict
-- E1 DailyService: the daily login reward (7-day cycle, see Config/Daily).
--
--   RequestDailyClaim (client -> server): ()
--     Allowed once Daily.ClaimCooldownSeconds (20h) have passed since data.dailyLastClaim.
--     After Daily.StreakResetSeconds (48h) the streak restarts at day 1.
--     Grants through Util/Rewards (premium crate through CrateService:GiveCrate(player, true)),
--     then sets data.dailyStreak += 1 and data.dailyLastClaim = Multipliers.Now().
--
--   DailyService:Claim(player) -> string?   same as the remote (no debounce), returns the toast text

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Format = require(ReplicatedStorage.Shared.Format)
local Multipliers = require(ReplicatedStorage.Shared.Multipliers)
local Daily = require(ReplicatedStorage.Shared.Config.Daily)
local DataService = require(script.Parent.DataService)
local CrateService = require(script.Parent.CrateService)
local Notify = require(script.Parent.Parent.Util.Notify)
local Debounce = require(script.Parent.Parent.Util.Debounce)
local Rewards = require(script.Parent.Parent.Util.Rewards)
local Safe = require(ReplicatedStorage.Shared.Safe)

local DailyService = {}

local function grant(player: Player, data: any, day: number, reward: Daily.DayReward): string?
	if reward.kind == "cash" then
		local amount = Daily.CashAmount(Multipliers.MilkPerSecond(player, data), Multipliers.Cash(player, data), reward)
		return Rewards.Grant(player, { kind = "cash", amount = amount }, `daily{day}`)
	elseif reward.kind == "crates" then
		return Rewards.Grant(player, { kind = "crates", amount = reward.amount }, `daily{day}`)
	elseif reward.kind == "boost" then
		return Rewards.Grant(player, {
			kind = "boost",
			boostKind = reward.boostKind,
			mult = reward.mult,
			seconds = reward.seconds,
		}, `daily{day}`)
	elseif reward.kind == "premiumCrate" then
		if CrateService:GiveCrate(player, true) then
			return "a Premium Milk Crate"
		end
	end
	return nil
end

function DailyService:Claim(player: Player): string?
	local data = DataService:Get(player)
	if not data then
		return nil
	end
	local now = Multipliers.Now()
	if not Daily.CanClaim(data, now) then
		local left = Daily.SecondsUntilClaim(data, now)
		Notify.To(player, `Next daily reward in {Format.Time(left)}`, "error")
		return nil
	end
	local streak = Daily.EffectiveStreak(data, now)
	local day = streak % #Daily.Days + 1
	local reward = Daily.Days[day]
	-- commit first so nothing below can be claimed twice, roll back if the grant failed
	local oldStreak, oldLast = data.dailyStreak, data.dailyLastClaim
	data.dailyStreak = streak + 1
	data.dailyLastClaim = now
	local text = reward and grant(player, data, day, reward)
	if not text then
		data.dailyStreak, data.dailyLastClaim = oldStreak, oldLast
		warn(`[DailyService] day {day} has an invalid reward`)
		return nil
	end
	DataService:Replicate(player, "dailyStreak")
	DataService:Replicate(player, "dailyLastClaim")
	Notify.To(player, `Day {day} reward: {text}`, "success")
	return text
end

function DailyService:Start()
	Net.Event("RequestDailyClaim").OnServerEvent:Connect(function(player: Player)
		if not Debounce.Try(player, "dailyClaim", Daily.RequestCooldownSeconds) then
			return
		end
		Safe.Run("DailyService.Claim", function()
			DailyService:Claim(player)
		end)
	end)
end

return DailyService
