--!strict
-- A4: Humanoid.WalkSpeed = (BASE + walkSpeed upgrade level * perLevel) x (1 + pet speed bonus).
-- Applied on spawn, on data load, and whenever UpgradeService / RebirthService call Apply.
--
--   WalkSpeedService:Apply(player)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local Multipliers = require(ReplicatedStorage.Shared.Multipliers)
local DataService = require(script.Parent.DataService)

local BASE_WALK_SPEED = 16

local WalkSpeedService = {}

function WalkSpeedService:Apply(player: Player)
	local data = DataService:Get(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not data or not humanoid then
		return
	end
	local level = (data.upgrades and data.upgrades.walkSpeed) or 0
	local speed = BASE_WALK_SPEED + level * Upgrades.ById.walkSpeed.perLevel
	humanoid.WalkSpeed = speed * (1 + Multipliers.PetBonus(data, "speed")) -- F1 speed pets
end

local function onCharacter(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end
	DataService:WaitFor(player)
	WalkSpeedService:Apply(player)
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

function WalkSpeedService:Start()
	DataService.PlayerLoaded:Connect(function(player)
		WalkSpeedService:Apply(player)
	end)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
end

return WalkSpeedService
