--!strict
-- A4: Buy pads. BuyPad1 / BuyPad5 / BuyPad25 on the owner's plot buy N tier-1 cows.
-- Price of the k-th cow bought this rebirth = BuyBasePrice * BuyPriceGrowth ^ k.
--
--   BuyService:Price(cowsBought, n) -> number   total price of the next n cows
--   BuyService:RefreshLabels(player)            update the pad labels on the player's plot

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Safe = require(ReplicatedStorage.Shared.Safe)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Format = require(ReplicatedStorage.Shared.Format)
local DataService = require(script.Parent.DataService)
local Pricing = require(ReplicatedStorage.Shared.Pricing)
local Notify = require(script.Parent.Parent.Util.Notify)
local PlotService = require(script.Parent.PlotService)
local Pads = require(script.Parent.Parent.Util.Pads)
local Rewards = require(script.Parent.Parent.Util.Rewards)

local AFFORD_COLOR = Color3.fromRGB(120, 255, 120)
local POOR_COLOR = Color3.fromRGB(255, 110, 110)

local BuyService = {}

function BuyService:Price(cowsBought: number, n: number): number
	return Pricing.Cows(cowsBought, n)
end

function BuyService:RefreshLabels(player: Player)
	local data = DataService:Get(player)
	local plot = PlotService:GetPlot(player)
	if not data or not plot then
		return
	end
	for _, n in Economy.BuyPads do
		local pad = plot:FindFirstChild("BuyPad" .. n)
		if pad then
			local price = BuyService:Price(data.cowsBought, n)
			local color = if data.cash >= price then AFFORD_COLOR else POOR_COLOR
			Pads.SetLabel(pad, `Buy x{n}\n{Format.Cash(price)}`, color)
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
		Notify.To(player, `Not enough cash! Need {Format.Cash(price)}`, "error")
		return
	end
	data.cowsBought += n
	DataService:Replicate(player, "cowsBought")
	Rewards.Cow(player, 1, n)
	Notify.To(player, `+{n} cow{if n == 1 then "" else "s"}!`, "success")
	BuyService:RefreshLabels(player)
end

function BuyService:Start()
	for _, n in Economy.BuyPads do
		Pads.BindPlotPad("BuyPad" .. n, function(player)
			buy(player, n)
		end)
	end
	-- live prices (cash changes constantly, so a cheap poll is simplest)
	while true do
		for _, player in Players:GetPlayers() do
			Safe.Run("BuyService labels", BuyService.RefreshLabels, BuyService, player)
		end
		task.wait(1)
	end
end

return BuyService
