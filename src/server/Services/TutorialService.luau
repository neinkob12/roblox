--!strict
-- C4: Server side of the onboarding tutorial.
--
-- Handles RequestTutorialStep(step). Accepts only:
--   step == current + 1   when the CURRENT step's condition holds (Config/Tutorial), or the
--                         current step's target part does not exist (graceful skip)
--   step == Tutorial.Done the skip button (always allowed, still forward only)
-- Saves data.tutorialStep via DataService. Veterans (played before the tutorial) skip it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Tutorial = require(ReplicatedStorage.Shared.Config.Tutorial)
local DataService = require(script.Parent.DataService)

local TutorialService = {}

type Ctx = {
	step: number,
	startedAt: number,
	baseEarned: number?,
	collected: boolean?,
}

local ctxs: { [Player]: Ctx } = {}
local lastRequest: { [Player]: number } = {}

-- Per-step context, rebuilt whenever data.tutorialStep changed (also after /reset).
local function getCtx(player: Player, data: any): Ctx
	local step = data.tutorialStep or 0
	local ctx = ctxs[player]
	if ctx == nil or ctx.step ~= step then
		local baseEarned = data.totalCashEarned or 0
		local def = Tutorial.Steps[step]
		if def and def.carryCollect and ctx and ctx.step == step - 1 and ctx.baseEarned then
			baseEarned = ctx.baseEarned -- keep counting from the start of the previous step
		end
		local fresh: Ctx = {
			step = step,
			startedAt = os.clock(),
			baseEarned = baseEarned,
		}
		ctxs[player] = fresh
		return fresh
	end
	return ctx
end

local function stepFinished(player: Player, data: any, index: number): boolean
	local step = Tutorial.Steps[index]
	if step == nil then
		return true
	end
	if Tutorial.FindTarget(player, step) == nil then
		return true -- target missing: never block the player
	end
	local ctx = getCtx(player, data)
	if step.done(data, ctx) then
		return true
	end
	local auto = step.autoSeconds
	if auto and os.clock() - ctx.startedAt >= auto - Tutorial.TimedSlackSeconds then
		return true
	end
	return false
end

local function setStep(player: Player, step: number)
	DataService:Set(player, "tutorialStep", step)
	local data = DataService:Get(player)
	if data then
		getCtx(player, data) -- start the new step's context now (baseline for "collect")
	end
end

local function onRequest(player: Player, step: any)
	if typeof(step) ~= "number" or step ~= step then
		return
	end
	step = math.floor(step)
	local now = os.clock()
	if now - (lastRequest[player] or 0) < Tutorial.RequestCooldown then
		return
	end
	lastRequest[player] = now

	local data = DataService:Get(player)
	if not data then
		return
	end
	local current = data.tutorialStep or 0
	if current >= Tutorial.Done then
		return
	end
	if step == Tutorial.Done then
		setStep(player, Tutorial.Done) -- skip button, or the last (info) step ending
		return
	end
	if step ~= current + 1 then
		return
	end
	if current == 0 or stepFinished(player, data, current) then
		setStep(player, step)
	end
end

local function onLoaded(player: Player, data: any)
	if (data.tutorialStep or 0) < Tutorial.Done and Tutorial.IsVeteran(data) then
		DataService:Set(player, "tutorialStep", Tutorial.Done)
		return
	end
	getCtx(player, data)
end

function TutorialService:Init()
	DataService.PlayerLoaded:Connect(onLoaded)
	Players.PlayerRemoving:Connect(function(player)
		ctxs[player] = nil
		lastRequest[player] = nil
	end)
end

function TutorialService:Start()
	Net.Event("RequestTutorialStep").OnServerEvent:Connect(onRequest)
	for _, player in Players:GetPlayers() do
		local data = DataService:Get(player)
		if data then
			onLoaded(player, data)
		end
	end
end

return TutorialService
