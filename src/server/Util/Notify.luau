--!strict
-- The ONE way the server shows a toast. Plain module (not auto-loaded).
--
--   Notify.To(player, text, kind?)   kind = "info" (default) | "success" | "error" | "rare"
--   Notify.All(text, kind?)          every player on the server

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local Notify = {}

function Notify.To(player: Player, text: string, kind: string?)
	Net.Event("Notify"):FireClient(player, text, kind or "info")
end

function Notify.All(text: string, kind: string?)
	Net.Event("Notify"):FireAllClients(text, kind or "info")
end

return Notify
