--!strict
-- Per-player cooldowns. Plain module (not auto-loaded). Cleans up on PlayerRemoving.
--
--   Debounce.Try(player, key, seconds) -> boolean   true = allowed now (and starts the cooldown)

local Players = game:GetService("Players")

local Debounce = {}

local last: { [Player]: { [string]: number } } = {}

Players.PlayerRemoving:Connect(function(player)
	last[player] = nil
end)

function Debounce.Try(player: Player, key: string, seconds: number): boolean
	local t = last[player]
	if not t then
		t = {}
		last[player] = t
	end
	local now = os.clock()
	local prev = t[key]
	if prev and now - prev < seconds then
		return false
	end
	t[key] = now
	return true
end

return Debounce
