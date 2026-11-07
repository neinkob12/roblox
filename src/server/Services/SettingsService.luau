--!strict
-- Player settings toggles (music, sfx, voice, reduceMotion).
-- Handles RequestSetting(name, value): only keys that exist in DataService.Template.settings,
-- only booleans. No rate limit on purpose: dropping a fast double tap desyncs the toggle UI,
-- and a boolean whitelist is cheap to apply. Owner: lead.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local DataService = require(script.Parent.DataService)

local SettingsService = {}

function SettingsService:Start()
	Net.Event("RequestSetting").OnServerEvent:Connect(function(player: Player, name: unknown, value: unknown)
		if typeof(name) ~= "string" or typeof(value) ~= "boolean" then
			return
		end
		if typeof(DataService.Template.settings[name]) ~= "boolean" then
			return
		end

		local data = DataService:Get(player)
		if not data then
			return
		end
		data.settings[name] = value
		DataService:Replicate(player, "settings")
	end)
end

return SettingsService
