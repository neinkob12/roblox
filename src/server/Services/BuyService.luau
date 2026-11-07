--!strict
-- A4: Buy pads. BuyPad1 / BuyPad5 / BuyPad25 on the owner's plot buy N tier-1 cows.
-- Price of the k-th cow bought this rebirth = BuyBasePrice * BuyPriceGrowth ^ k.
--
--   BuyService:Price(cowsBought, n) -> number   total price of the next n cows
--   BuyService:RefreshLabels(player)            update the pad labels on the player's plot

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Format = require(ReplicatedStorage.Shared.Format)
local DataService = require(script.Parent.DataService)
local HerdUtil = require(script.Parent.HerdUtil)
local Pricing = require(ReplicatedStorage.Shared.Pricing)

local AFFORD_COLOR = Color3.fromRGB(120, 255, 120)
local POOR_COLOR = Color3.fromRGB(255, 110, 110)

local BuyService = {}

function BuyService:Price(cowsBought: number, n: number): number
	return Pricing.Cows(cowsBought, n)
end

function BuyService:RefreshLabels(player: Player)
	local data = DataService:Get(player)
	local plot = HerdUtil.GetPlot(player)
	if not data or not plot then
		return
	end
	for _, n in Economy.BuyPads do
		local pad = plot:FindFirstChild("BuyPad" .. n)
		if pad then
			local price = BuyService:Price(data.cowsBought, n)
			local color = if data.cash >= price then AFFORD_COLOR else POOR_COLOR
			HerdUtil.SetLabel(pad, `Buy x{n}\n{Format.Cash(price)}`, color)
		end
	end
end

local function buy(player: Player, n: number)
	local data = DataService:Get(player)
	if not data then
		return
	end
	local price = BuyService:Price(data.cowsBought, n)
	if not DataService:SpendCash(player, price) then
		HerdUtil.Notify(player, `Not enough cash! Need {Format.Cash(price)}`, "error")
		return
	end
	data.cowsBought += n
	DataService:Replicate(player, "cowsBought")
	HerdUtil.GiveCow(player, 1, n)
	HerdUtil.Notify(player, `+{n} cow{if n == 1 then "" else "s"}!`, "success")
	require(ReplicatedStorage.Shared.Net).Event("Fx"):FireClient(player, "buy", { count = n })
	BuyService:RefreshLabels(player)
end

function BuyService:Start()
	for _, n in Economy.BuyPads do
		HerdUtil.BindPad("BuyPad" .. n, function(player)
			buy(player, n)
		end)
	end
	-- live prices (cash changes constantly, so a cheap poll is simplest)
	while true do
		for _, player in Players:GetPlayers() do
			local ok, err = (pcall :: any)(BuyService.RefreshLabels, BuyService, player)
			if not ok then
				warn(`[BuyService] label refresh failed for {player.Name}: {err}`)
			end
		end
		task.wait(1)
	end
end

return BuyService
