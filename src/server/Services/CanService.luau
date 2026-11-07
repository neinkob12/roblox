--!strict
-- Milk can: touch your own plot's TankTap to pour tank milk into the can you carry.
-- Owner: A3.
--
--   CanService:GetCanCapacity(player, data) -> number
--   CanService:FillCan(player) -> number      (milk moved; used by the tap and autoCollect)
--
-- Player attribute set here: CanCapacity.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Safe = require(ReplicatedStorage.Shared.Safe)
local Format = require(ReplicatedStorage.Shared.Format)
local Multipliers = require(ReplicatedStorage.Shared.Multipliers)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local ProductionService = require(script.Parent.ProductionService)
local Notify = require(script.Parent.Parent.Util.Notify)

local CanService = {}

local DEBOUNCE = 1
local lastTouch: { [Player]: number } = {}
local lastAuto: { [Player]: number } = {}
local hookedTaps: { [BasePart]: boolean } = {}

function CanService:GetCanCapacity(player: Player, data: any): number
	local mps = Multipliers.MilkPerSecond(player, data)
	local lvl = (data.upgrades and data.upgrades.canSize) or 0
	local base = math.max(Economy.Can.MinCapacity, mps * Economy.Can.BaseSeconds)
	return base * (1 + lvl * Upgrades.ById.canSize.perLevel)
end

function CanService:FillCan(player: Player): number
	local data = DataService:Get(player)
	if not data then
		return 0
	end
	local capacity = CanService:GetCanCapacity(player, data)
	player:SetAttribute("CanCapacity", capacity)
	local tank = data.tankMilk or 0
	local can = data.canMilk or 0
	local move = math.min(tank, math.max(0, capacity - can))
	if move <= 0 then
		return 0
	end
	data.tankMilk = tank - move
	data.canMilk = can + move
	ProductionService:MarkTankDirty(player)
	DataService:Replicate(player, "canMilk")
	return move
end

local function onTapTouched(plot: Model, hit: BasePart)
	local player = PlotService:IsOwnerTouch(plot, hit)
	if not player then
		return
	end
	local now = os.clock()
	if lastTouch[player] and now - lastTouch[player] < DEBOUNCE then
		return
	end
	lastTouch[player] = now
	local data = DataService:Get(player)
	if not data then
		return
	end
	local moved = CanService:FillCan(player)
	if moved > 0 then
		Notify.To(player, `+{Format.Number(moved)} milk in your can`, "success")
	elseif (data.tankMilk or 0) <= 0 then
		Notify.To(player, "Your tank is empty, wait for the cows!", "info")
	else
		Notify.To(player, "Your can is full! Sell it at the Dairy", "info")
	end
end

local function hookPlot(plot: Instance)
	if not plot:IsA("Model") then
		return
	end
	local tap = plot:FindFirstChild("TankTap") or plot:WaitForChild("TankTap", 10)
	if not tap or not tap:IsA("BasePart") or hookedTaps[tap] then
		if not tap then
			warn(`[CanService] {plot.Name} has no TankTap`)
		end
		return
	end
	hookedTaps[tap] = true
	tap.Touched:Connect(function(hit)
		onTapTouched(plot, hit)
	end)
end

function CanService:Init()
	Players.PlayerRemoving:Connect(function(player)
		lastTouch[player] = nil
		lastAuto[player] = nil
	end)
	DataService.PlayerLoaded:Connect(function(player: Player, data: any)
		player:SetAttribute("CanCapacity", CanService:GetCanCapacity(player, data))
	end)
end

function CanService:Start()
	task.spawn(function()
		local plots = workspace:WaitForChild("Plots", 30)
		if not plots then
			warn("[CanService] workspace.Plots not found")
			return
		end
		for _, plot in plots:GetChildren() do
			task.spawn(hookPlot, plot)
		end
		plots.ChildAdded:Connect(hookPlot)
	end)

	-- capacity attribute + autoCollect upgrade
	while true do
		task.wait(1)
		local now = os.clock()
		for _, player in Players:GetPlayers() do
			local data = DataService:Get(player)
			if data then
				Safe.Run("CanService tick", function()
					player:SetAttribute("CanCapacity", CanService:GetCanCapacity(player, data))
					local lvl = (data.upgrades and data.upgrades.autoCollect) or 0
					if lvl > 0 then
						local interval = math.max(
							Economy.Can.AutoCollectMinSeconds,
							Economy.Can.AutoCollectBaseSeconds - lvl * Upgrades.ById.autoCollect.perLevel
						)
						if not lastAuto[player] or now - lastAuto[player] >= interval then
							lastAuto[player] = now
							CanService:FillCan(player)
						end
					end
				end)
			end
		end
	end
end

return CanService
