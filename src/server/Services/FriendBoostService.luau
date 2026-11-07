--!strict
-- B2 FriendBoostService: sets the Player attribute FriendCount = number of OTHER players in
-- this server who are Roblox friends with them. Multipliers turns it into the cash bonus
-- (Economy.FriendBoost: +10% per friend, max +50%).
--
-- player:IsFriendsWith yields and can fail, so every pair is checked once (pcall, cached) and
-- counts are recomputed on every join/leave.

local Players = game:GetService("Players")

local FriendBoostService = {}

-- cache["small_big"] = true/false (userIds sorted so each pair has one key)
local cache: { [string]: boolean } = {}
-- players inside PlayerRemoving are still parented to Players, so skip them explicitly
local leaving: { [Player]: boolean } = {}

local function pairKey(a: number, b: number): string
	if a > b then
		a, b = b, a
	end
	return `{a}_{b}`
end

local function areFriends(a: Player, b: Player): boolean
	local key = pairKey(a.UserId, b.UserId)
	local cached = cache[key]
	if cached ~= nil then
		return cached
	end
	local ok, result = pcall(function()
		return a:IsFriendsWith(b.UserId)
	end)
	if not ok then
		return false -- don't cache failures, try again next recompute
	end
	cache[key] = result == true
	return result == true
end

local function recompute()
	local players = {}
	for _, p in Players:GetPlayers() do
		if not leaving[p] then
			table.insert(players, p)
		end
	end
	for _, p in players do
		if p.Parent == Players and not leaving[p] then
			local count = 0
			for _, other in players do
				if other ~= p and not leaving[other] and areFriends(p, other) then
					count += 1
				end
			end
			if p.Parent == Players and p:GetAttribute("FriendCount") ~= count then
				p:SetAttribute("FriendCount", count)
			end
		end
	end
end

-- serialize recomputes: joins/leaves in quick succession just schedule one more pass
local running = false
local dirty = false
local function schedule()
	dirty = true
	if running then
		return
	end
	running = true
	task.spawn(function()
		while dirty do
			dirty = false
			local ok, err = pcall(recompute)
			if not ok then
				warn(`[FriendBoostService] {err}`)
			end
		end
		running = false
	end)
end

function FriendBoostService:Start()
	Players.PlayerAdded:Connect(function(player)
		player:SetAttribute("FriendCount", 0)
		schedule()
	end)
	Players.PlayerRemoving:Connect(function(player)
		leaving[player] = true
		task.delay(5, function()
			leaving[player] = nil
		end)
		local id = player.UserId
		for key in cache do
			local a, b = string.match(key, "^(%-?%d+)_(%-?%d+)$")
			if tonumber(a) == id or tonumber(b) == id then
				cache[key] = nil
			end
		end
		schedule()
	end)
	for _, player in Players:GetPlayers() do
		player:SetAttribute("FriendCount", 0)
	end
	schedule()
end

return FriendBoostService
