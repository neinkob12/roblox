--!strict
-- Timed server events ("Next event in 08:54"). EventService (B2) picks one at random.
-- Effects are read by Shared/Multipliers and by the services named in each effect.

local Events = {}

Events.EverySeconds = 10 * 60 -- gap between the end of one event and the start of the next

-- STUDIO TESTING: set DebugFastInStudio = true to run events every 30s for 20s each.
-- Set it back to false before merging. (Only applies when RunService:IsStudio().)
Events.DebugFastInStudio = false
Events.DebugEverySeconds = 30
Events.DebugDurationSeconds = 20
Events.List = {
	{ id = "DoublePrice", name = "Milk Price Frenzy!", seconds = 180, cashMultiplier = 2 },
	{ id = "MilkFlood", name = "Milk Flood!", seconds = 180, productionMultiplier = 2 },
	{ id = "GoldenRush", name = "Golden Milk Rush!", seconds = 120, rareChanceMultiplier = 5 },
	{ id = "CrateRain", name = "Crate Rain!", seconds = 90, crateDropMultiplier = 10 },
}

Events.ById = {}
for _, e in Events.List do
	Events.ById[e.id] = e
end

return Events
