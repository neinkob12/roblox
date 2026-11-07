--!strict
-- Player settings toggles (music, sfx, voice, reduceMotion).
-- Handles RequestSetting(name, value): only keys that exist in DataService.Template.settings,
-- only booleans. Owner: lead.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local DataService = require(script.Parent.DataService)

local MIN_INTERVAL = 0.2 -- seconds between requests per player

local SettingsService = {}

local lastRequest: { [Player]: number } = {}

function SettingsService:Start()
	Net.Event("RequestSetting").OnServerEvent:Connect(function(player: Player, name: unknown, value: unknown)
		if typeof(name) ~= "string" or typeof(value) ~= "boolean" then
			return
		end
		if typeof(DataService.Template.settings[name]) ~= "boolean" then
			return
		end
		local now = os.clock()
		if now - (lastRequest[player] or 0) < MIN_INTERVAL then
			return
		end
		lastRequest[player] = now

		local data = DataService:Get(player)
		if not data then
			return
		end
		data.settings[name] = value
		DataService:Replicate(player, "settings")
	end)

	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return SettingsService
