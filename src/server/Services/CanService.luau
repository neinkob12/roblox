--!strict
-- Milk can: touch your own plot's TankTap to pour tank milk into the can you carry.
-- Owner: A3.
--
--   Capacity.CanCapacity(player, data) -> number
--   CanService:FillCan(player) -> number      (milk moved; used by the tap and autoCollect)
--
-- Player attribute set here: CanCapacity (formula in shared/Capacity).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Safe = require(ReplicatedStorage.Shared.Safe)
local Format = require(ReplicatedStorage.Shared.Format)
local DataService = require(script.Parent.DataService)
local ProductionService = require(script.Parent.ProductionService)
local Notify = require(script.Parent.Parent.Util.Notify)
local Debounce = require(script.Parent.Parent.Util.Debounce)
local Pads = require(script.Parent.Parent.Util.Pads)
local Capacity = require(ReplicatedStorage.Shared.Capacity)

local CanService = {}

function CanService:FillCan(player: Player): number
	local data = DataService:Get(player)
	if not data then
		return 0
	end
	local capacity = Capacity.CanCapacity(player, data)
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

local function onTap(player: Player)
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

function CanService:Init()
	DataService.PlayerLoaded:Connect(function(player: Player, data: any)
		player:SetAttribute("CanCapacity", Capacity.CanCapacity(player, data))
	end)
end

function CanService:Start()
	Pads.BindPlotPad("TankTap", function(player)
		onTap(player)
	end)

	-- capacity attribute + autoCollect upgrade
	while true do
		task.wait(1)
		for _, player in Players:GetPlayers() do
			local data = DataService:Get(player)
			if data then
				Safe.Run("CanService tick", function()
					player:SetAttribute("CanCapacity", Capacity.CanCapacity(player, data))
					local lvl = (data.upgrades and data.upgrades.autoCollect) or 0
					if lvl > 0 then
						if Debounce.Try(player, "autoCollect", Capacity.AutoCollectInterval(lvl)) then
							CanService:FillCan(player)
						end
					end
				end)
			end
		end
	end
end

return CanService
