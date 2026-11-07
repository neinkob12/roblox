--!strict
-- B2 QuestService: 3 rotating quests per player.
--
-- Progress is tracked by DIFFING data counters every Quests.TrackSeconds, so no other
-- service needs to call us:
--   merge_n        -> data.stats.merges
--   sell_milk_n    -> data.stats.milkSold      (raw milk deposited at the dairy)
--   open_crates_n  -> data.stats.cratesOpened
--   collect_cash_n -> data.totalCashEarned     (quest cash rewards are NOT counted)
--   buy_cows_n     -> data.cowsBought          (resets on rebirth; drops are ignored)
--
-- Remote: RequestClaimQuest(questId: string). Server checks progress >= target, grants the
-- reward, and replaces that slot with a new random quest.
--
-- ===== data.quests shape (for the UI, B1) =====  replicated as key "quests"
--
--   data.quests = {
--     version = 1,
--     nextId = number,                 -- internal counter
--     active = {                       -- dense array, always Quests.ActiveCount (3) entries
--       {
--         id = "q12",                  -- pass this to RequestClaimQuest
--         type = "merge_n",            -- one of the 5 types above
--         text = "Merge 10 cows",      -- ready-to-show description
--         target = 10,                 -- number
--         progress = 4,                -- number, clamped to target (progress == target -> claimable)
--         reward = {                   -- same shape as Config/Quests rewards, cash amount resolved:
--           kind = "cash", amount = 1200,                                   -- or
--           kind = "crates", amount = 1,                                    -- or
--           kind = "boost", boostKind = "cash" | "production", mult = 2, seconds = 120,
--         },
--         rewardText = "+$1.2K",       -- ready-to-show reward label
--       },
--       ...
--     },
--   }
--
-- UI tip: show a "CLAIM" button when quest.progress >= quest.target, fire
-- Net.Event("RequestClaimQuest"):FireServer(quest.id). Progress bar = progress / target.
-- A Notify("Quest complete: ...", "success") fires the moment a quest finishes.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Format = require(ReplicatedStorage.Shared.Format)
local Multipliers = require(ReplicatedStorage.Shared.Multipliers)
local Quests = require(ReplicatedStorage.Shared.Config.Quests)
local DataService = require(script.Parent.DataService)
local HerdUtil = require(script.Parent.HerdUtil)
local CodesService = require(script.Parent.CodesService)

local QuestService = {}

local DATA_VERSION = 1
local EASY = Quests.DebugEasyInStudio and RunService:IsStudio()

-- last seen counter values per player (in memory: progress made offline never counts)
local baselines: { [Player]: { [string]: number } } = {}

local function readCounters(data: any): { [string]: number }
	local stats = data.stats or {}
	return {
		merge_n = stats.merges or 0,
		sell_milk_n = stats.milkSold or 0,
		open_crates_n = stats.cratesOpened or 0,
		collect_cash_n = data.totalCashEarned or 0,
		buy_cows_n = data.cowsBought or 0,
	}
end

-- 2 significant digits so targets look clean (1234 -> 1200)
local function roundNice(n: number): number
	if n < 10 then
		return math.max(1, math.floor(n + 0.5))
	end
	local mag = 10 ^ (math.floor(math.log10(n)) - 1)
	return math.floor(n / mag + 0.5) * mag
end

local function milkPerSecond(player: Player, data: any): number
	local ok, mps = pcall(Multipliers.MilkPerSecond, player, data)
	if ok and typeof(mps) == "number" and mps == mps and mps > 0 then
		return mps
	end
	return 1
end

local function pick<T>(list: { T }): T
	return list[math.random(1, #list)]
end

local function newQuest(player: Player, data: any, exclude: { [string]: boolean }): any
	local choices = {}
	for _, def in Quests.Types do
		if not exclude[def.type] then
			table.insert(choices, def)
		end
	end
	if #choices == 0 then
		choices = Quests.Types
	end
	local def = pick(choices)
	local mps = milkPerSecond(player, data)

	local target: number
	if def.targets then
		target = pick(def.targets)
	else
		local seconds = pick(def.targetSeconds or { 60 })
		local floor = if def.type == "collect_cash_n" then Quests.MinCash else Quests.MinMilk
		target = roundNice(math.max(floor, mps * seconds))
	end
	if EASY then
		target = 1
	end

	local template = pick(def.rewards)
	local reward = table.clone(template)
	if reward.kind == "cash" then
		reward.amount = roundNice(math.max(Quests.MinCash, mps * (template.cashSeconds or 60)))
		reward.cashSeconds = nil
	end

	data.quests.nextId = (data.quests.nextId or 0) + 1
	local text = string.gsub(def.text, "{n}", Format.Number(target))
	local rewardText = "Reward"
	if reward.kind == "cash" then
		rewardText = "+" .. Format.Cash(reward.amount)
	elseif reward.kind == "crates" then
		rewardText = `+{reward.amount} Crate{if reward.amount == 1 then "" else "s"}`
	elseif reward.kind == "boost" then
		local what = if reward.boostKind == "cash" then "Cash" else "Milk"
		rewardText = `{Format.Number(reward.mult)}x {what} {Format.Time(reward.seconds)}`
	end
	return {
		id = "q" .. data.quests.nextId,
		type = def.type,
		text = text,
		target = target,
		progress = 0,
		reward = reward,
		rewardText = rewardText,
	}
end

local function activeTypes(data: any, skipIndex: number?): { [string]: boolean }
	local set = {}
	for i, q in data.quests.active do
		if i ~= skipIndex then
			set[q.type] = true
		end
	end
	return set
end

-- Makes sure data.quests is valid and has ActiveCount quests. Returns true if it changed.
local function ensureQuests(player: Player, data: any): boolean
	local changed = false
	if
		typeof(data.quests) ~= "table"
		or data.quests.version ~= DATA_VERSION
		or typeof(data.quests.active) ~= "table"
	then
		data.quests = { version = DATA_VERSION, nextId = 0, active = {} }
		changed = true
	end
	local active = data.quests.active
	-- drop quests whose type no longer exists in config
	for i = #active, 1, -1 do
		if typeof(active[i]) ~= "table" or not Quests.ByType[active[i].type] then
			table.remove(active, i)
			changed = true
		end
	end
	while #active > Quests.ActiveCount do
		table.remove(active)
		changed = true
	end
	while #active < Quests.ActiveCount do
		table.insert(active, newQuest(player, data, activeTypes(data)))
		changed = true
	end
	return changed
end

local function track(player: Player)
	local data = DataService:Get(player)
	if not data then
		return
	end
	local changed = ensureQuests(player, data)
	local current = readCounters(data)
	local last = baselines[player]
	baselines[player] = current
	if last then
		for _, q in data.quests.active do
			if q.progress < q.target then
				local delta = (current[q.type] or 0) - (last[q.type] or 0)
				if delta > 0 then
					q.progress = math.min(q.target, q.progress + delta)
					changed = true
					if q.progress >= q.target then
						HerdUtil.Notify(player, `Quest complete: {q.text}! Claim your reward`, "success")
					end
				end
			end
		end
	end
	if changed then
		DataService:Replicate(player, "quests")
	end
end

local function claim(player: Player, questId: any)
	if typeof(questId) ~= "string" or #questId > 20 then
		return
	end
	if not HerdUtil.Debounce(player, "claimQuest", 0.3) then
		return
	end
	local data = DataService:Get(player)
	if not data or typeof(data.quests) ~= "table" or typeof(data.quests.active) ~= "table" then
		return
	end
	local index: number? = nil
	for i, q in data.quests.active do
		if q.id == questId then
			index = i
			break
		end
	end
	if not index then
		return
	end
	local q = data.quests.active[index]
	if q.progress < q.target then
		HerdUtil.Notify(player, "That quest isn't finished yet!", "error")
		return
	end
	-- replace first, then grant: a second claim with the same id can never pay twice
	data.quests.active[index] = newQuest(player, data, activeTypes(data, index))
	local text = CodesService:GrantReward(player, q.reward, "quest_" .. (q.reward.boostKind or "x"))
	if q.reward.kind == "cash" then
		-- quest cash must not count toward "Earn N cash" quests
		local b = baselines[player]
		if b and text then
			b.collect_cash_n += q.reward.amount
		end
	end
	DataService:Replicate(player, "quests")
	HerdUtil.Notify(player, `Quest reward: {text or q.rewardText}`, "success")
end

function QuestService:Start()
	Net.Event("RequestClaimQuest").OnServerEvent:Connect(claim)
	DataService.PlayerLoaded:Connect(function(player: Player, data: any)
		if ensureQuests(player, data) then
			DataService:Replicate(player, "quests")
		end
		baselines[player] = readCounters(data)
	end)
	Players.PlayerRemoving:Connect(function(player)
		baselines[player] = nil
	end)
	while true do
		task.wait(Quests.TrackSeconds)
		for _, player in Players:GetPlayers() do
			local ok, err = pcall(track :: any, player)
			if not ok then
				warn(`[QuestService] track failed for {player.Name}: {err}`)
			end
		end
	end
end

return QuestService
