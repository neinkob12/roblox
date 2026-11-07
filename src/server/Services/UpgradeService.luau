--!strict
-- A4: Cash upgrades. RequestUpgrade(id) validates the id, maxLevel and cost, spends cash and
-- increments data.upgrades[id]. Effects are read by A3 (tank, can, pipe, sell, autoCollect)
-- and WalkSpeedService (walkSpeed).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local Format = require(ReplicatedStorage.Shared.Format)
local DataService = require(script.Parent.DataService)
local WalkSpeedService = require(script.Parent.WalkSpeedService)
local Notify = require(script.Parent.Parent.Util.Notify)
local Debounce = require(script.Parent.Parent.Util.Debounce)

local UpgradeService = {}

local function onRequest(player: Player, id: unknown)
	if typeof(id) ~= "string" then
		return
	end
	local upgrade = Upgrades.ById[id]
	if not upgrade then
		return
	end
	if not Debounce.Try(player, "upgrade", 0.15) then
		return
	end
	local data = DataService:Get(player)
	if not data then
		return
	end
	local level = data.upgrades[id] or 0
	if level >= upgrade.maxLevel then
		Notify.To(player, `{upgrade.name} is already maxed!`, "error")
		return
	end
	local cost = Upgrades.Cost(id, level)
	if not DataService:SpendCash(player, cost) then
		Notify.To(player, `Not enough cash! Need {Format.Cash(cost)}`, "error")
		return
	end
	data.upgrades[id] = level + 1
	DataService:Replicate(player, "upgrades")
	Notify.To(player, `{upgrade.name} upgraded to level {level + 1}!`, "success")
	if id == "walkSpeed" then
		WalkSpeedService:Apply(player)
	end
end

function UpgradeService:Start()
	Net.Event("RequestUpgrade").OnServerEvent:Connect(onRequest)
end

return UpgradeService
