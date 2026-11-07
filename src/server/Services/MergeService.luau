--!strict
-- A4: Merge pad. Every MergeCost cows of tier N become 1 cow of tier N+1, bottom-up and
-- cascading (new tier-2 cows can immediately merge into tier 3, and so on).
-- Players with the Pass_AutoMerge attribute get an automatic merge every AutoMergeSeconds.
--
--   MergeService:MergeAll(player, silent?) -> number   merges done (0 = nothing to merge)
--   MergeService:CountMerges(cows) -> number            merges that MergeAll would do

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Safe = require(ReplicatedStorage.Shared.Safe)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Cows = require(ReplicatedStorage.Shared.Config.Cows)
local DataService = require(script.Parent.DataService)
local HerdUtil = require(script.Parent.HerdUtil)
local Notify = require(script.Parent.Parent.Util.Notify)
local PlotService = require(script.Parent.PlotService)
local Pads = require(script.Parent.Parent.Util.Pads)

local MergeService = {}

-- Pure simulation on a copy, used for the pad label.
function MergeService:CountMerges(cows: { [string]: number }): number
	local cost = Economy.MergeCost
	local carry = 0
	local total = 0
	for tier = 1, Cows.Count - 1 do
		local have = (cows[tostring(tier)] or 0) + carry
		local n = have // cost
		total += n
		carry = n
	end
	return total
end

function MergeService:MergeAll(player: Player, silent: boolean?): number
	local data = DataService:Get(player)
	if not data then
		return 0
	end
	local cost = Economy.MergeCost
	local total = 0
	local highestNew = 0
	local discoveredChanged = false
	for tier = 1, Cows.Count - 1 do
		local key = tostring(tier)
		local have = data.cows[key] or 0
		local n = have // cost
		if n > 0 then
			local left = have - n * cost
			data.cows[key] = if left > 0 then left else nil
			if HerdUtil.AddCowsRaw(player, data, tier + 1, n) then
				discoveredChanged = true
			end
			total += n
			highestNew = tier + 1
		end
	end
	if total == 0 then
		if not silent then
			Notify.To(player, `Need {cost} cows of the same tier to merge`, "error")
		end
		return 0
	end
	data.stats.merges += total
	DataService:Replicate(player, "cows")
	DataService:Replicate(player, "stats")
	if discoveredChanged then
		DataService:Replicate(player, "discovered")
	end
	local best = Cows.Get(highestNew)
	local bestName = if best then best.name else "?"
	Notify.To(player, `MERGED! x{total} (up to {bestName})`, "success")
	return total
end

local function refreshLabel(player: Player)
	local data = DataService:Get(player)
	local plot = PlotService:GetPlot(player)
	local pad = plot and plot:FindFirstChild("MergePad")
	if not data or not pad then
		return
	end
	local n = MergeService:CountMerges(data.cows)
	if n > 0 then
		Pads.SetLabel(pad, `MERGE\n{n} ready!`, Color3.fromRGB(255, 220, 80))
	else
		Pads.SetLabel(pad, `MERGE\n{Economy.MergeCost} -> 1`, Color3.fromRGB(255, 255, 255))
	end
end

function MergeService:Start()
	Pads.BindPlotPad("MergePad", function(player)
		MergeService:MergeAll(player)
		refreshLabel(player)
	end)
	local elapsed = 0
	while true do
		task.wait(1)
		elapsed += 1
		local autoTick = elapsed % Economy.AutoMergeSeconds == 0
		for _, player in Players:GetPlayers() do
			Safe.Run("MergeService tick", function()
				if autoTick and player:GetAttribute("Pass_AutoMerge") == true then
					MergeService:MergeAll(player, true)
				end
				refreshLabel(player)
			end)
		end
	end
end

return MergeService
