--!strict
-- A4: Rebirth. Cost = Rebirth.BaseCost * Rebirth.CostGrowth ^ rebirths.
-- Resets cash (to StartingCash), cows (StartingCows), cowsBought, tank/can/queue/dairyCash and
-- upgrades, then rebirths += 1 (permanent +CashMultiplierPerRebirth cash, see Multipliers).
-- Keeps: discovered, crates, quests, codes, stats, boosts, purchases.
--
--   RebirthService:Cost(rebirths) -> number

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Format = require(ReplicatedStorage.Shared.Format)
local DataService = require(script.Parent.DataService)
local HerdUtil = require(script.Parent.HerdUtil)
local Pricing = require(ReplicatedStorage.Shared.Pricing)
local WalkSpeedService = require(script.Parent.WalkSpeedService)
local Notify = require(script.Parent.Parent.Util.Notify)

local RebirthService = {}

function RebirthService:Cost(rebirths: number): number
	return Pricing.Rebirth(rebirths)
end

local function onRequest(player: Player)
	if not HerdUtil.Debounce(player, "rebirth", 1) then
		return
	end
	local data = DataService:Get(player)
	if not data then
		return
	end
	local cost = RebirthService:Cost(data.rebirths)
	if data.cash < cost then
		Notify.To(player, `Rebirth needs {Format.Cash(cost)}`, "error")
		return
	end

	-- set directly: SpendCash(cash - StartingCash) loses precision above 2^53
	data.cash = Economy.StartingCash

	local cows = {}
	for tier, count in Economy.StartingCows do
		cows[tostring(tier)] = count
	end
	data.cows = cows
	data.cowsBought = 0
	data.cratesBought = 0
	data.tankMilk = 0
	data.canMilk = 0
	data.dairyQueue = 0
	data.dairyCash = 0
	local upgrades = {}
	for id in DataService.Template.upgrades do
		upgrades[id] = 0
	end
	data.upgrades = upgrades
	data.rebirths += 1

	for _, key in
		{
			"cash",
			"cows",
			"cowsBought",
			"cratesBought",
			"tankMilk",
			"canMilk",
			"dairyQueue",
			"dairyCash",
			"upgrades",
			"rebirths",
		}
	do
		DataService:Replicate(player, key)
	end
	WalkSpeedService:Apply(player)

	local mult = 1 + Economy.Rebirth.CashMultiplierPerRebirth * data.rebirths
	Notify.To(player, `REBIRTH {data.rebirths}! Cash x{Format.Number(mult)} forever`, "rare")
end

function RebirthService:Start()
	Net.Event("RequestRebirth").OnServerEvent:Connect(onRequest)
end

return RebirthService
