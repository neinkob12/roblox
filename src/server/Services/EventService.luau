--!strict
-- B2 EventService: timed server events (Config/Events).
--
-- workspace attributes (contract section 5):
--   EventId      string  "" when no event is running, else an Events.List id
--   EventEndsAt  number  os.time() when the running event ends (0 when none)
--   EventNextAt  number  os.time() when the next event starts (0 while one is running)
--
-- Loop: wait EverySeconds -> pick a random event (never the same one twice in a row) ->
-- Notify everyone -> wait its seconds -> clear -> repeat.
-- Effects are applied by their readers: Multipliers (cash/production), ProductionService
-- (rareChanceMultiplier), CrateService (crateDropMultiplier).
--
--   The running event is read with Multipliers.ActiveEvent() (server and client).
--
-- STUDIO TESTING: Config/Events.DebugFastInStudio = true (events every 30s, 20s long).

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)
local Events = require(ReplicatedStorage.Shared.Config.Events)
local Notify = require(script.Parent.Parent.Util.Notify)

local EventService = {}

local FAST = Events.DebugFastInStudio and RunService:IsStudio()
local GAP = if FAST then Events.DebugEverySeconds else Events.EverySeconds

local lastId: string? = nil

local function pickEvent(): any
	local choices = {}
	for _, e in Events.List do
		if e.id ~= lastId then
			table.insert(choices, e)
		end
	end
	if #choices == 0 then
		choices = Events.List
	end
	return choices[math.random(1, #choices)]
end

local function runOne()
	local ev = pickEvent()
	if not ev then
		return
	end
	lastId = ev.id
	local seconds = if FAST then Events.DebugDurationSeconds else ev.seconds
	workspace:SetAttribute("EventNextAt", 0)
	workspace:SetAttribute("EventEndsAt", os.time() + seconds)
	workspace:SetAttribute("EventId", ev.id)
	Notify.All(`EVENT: {ev.name} ({Format.Time(seconds)})`, "rare")
	task.wait(seconds)
	workspace:SetAttribute("EventId", "")
	workspace:SetAttribute("EventEndsAt", 0)
	Notify.All(`{ev.name} is over! Next event in {Format.Time(GAP)}`, "info")
end

function EventService:Init()
	workspace:SetAttribute("EventId", "")
	workspace:SetAttribute("EventEndsAt", 0)
	workspace:SetAttribute("EventNextAt", os.time() + GAP)
end

function EventService:Start()
	while true do
		workspace:SetAttribute("EventNextAt", os.time() + GAP)
		task.wait(GAP)
		local ok, err = pcall(runOne :: any)
		if not ok then
			warn(`[EventService] event failed: {err}`)
			workspace:SetAttribute("EventId", "")
			workspace:SetAttribute("EventEndsAt", 0)
		end
	end
end

return EventService
