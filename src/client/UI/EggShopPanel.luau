--!strict
-- F2: Egg Shop panel ("EggShop"). Opened from the EggStand at the dairy, an empty nest, or the
-- Pets panel.
--   One card per egg (Config/Eggs): egg model, price (Pricing.Egg, the formula the server charges),
--   hatch time, Rebirth gate, BUY (RequestBuyEgg) and an "Odds" TEXT button.
--   Odds view: every pet the egg can give with its percentage from shared/Odds (Odds.Egg), the
--   exact table the server rolls with, INCLUDING the player's current luck (policy rule 1 + 4).
--   Free egg button with a cooldown timer (RequestClaimFreeEgg), never gated.
--   Player attribute PaidRandomRestricted = true: every BUY button is disabled and the panel says
--   "Not available in your region. Claim the free egg!" (policy rule 3). The free egg stays.
--
-- Public: EggShopPanel.Open(), EggShopPanel.ShowOdds(eggId)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Eggs = require(ReplicatedStorage.Shared.Config.Eggs)
local Pets = require(ReplicatedStorage.Shared.Config.Pets)
local Odds = require(ReplicatedStorage.Shared.Odds)
local Format = require(ReplicatedStorage.Shared.Format)
local Pricing = require(ReplicatedStorage.Shared.Pricing)
local Multipliers = require(ReplicatedStorage.Shared.Multipliers)
local PetModels = require(ReplicatedStorage.Shared.PetModels)
local C = require(script.Parent.Parent.Lib.UiKit)
local PetViewport = require(script.Parent.Parent.Lib.PetViewport)
local Panels = require(script.Parent.Components)
local DataController = require(script.Parent.Parent.Controllers.DataController)

local player = Players.LocalPlayer
local Colors = C.Colors
local Theme = C.Theme

local PANEL = Vector2.new(700, 372)
local CARD_W = 214
local CARD_H = 200
local RESTRICTED_TEXT = "Not available in your region. Claim the free egg!"

type Card = {
	egg: Eggs.Egg,
	buy: TextButton,
	buyCaption: TextLabel,
	info: TextLabel,
}

local EggShopPanel = {}

local cards: { Card } = {}
local freeBtn: TextButton
local freeCaption: TextLabel
local notice: TextLabel
local oddsView: Frame
local oddsTitle: TextLabel
local oddsList: ScrollingFrame
local oddsEggId: string? = nil

local function restricted(): boolean
	-- ComplianceService defaults to true until the policy check succeeds
	return player:GetAttribute("PaidRandomRestricted") ~= false
end

local function luck(): number
	return Multipliers.PetBonus(DataController:Get(), "luck")
end

------------------------------------------------------------------------------ odds

local function renderOdds()
	local eggId = oddsEggId
	if not eggId then
		return
	end
	local egg = Eggs.ById[eggId]
	for _, child in oddsList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local l = luck()
	oddsTitle.Text = `{if egg then egg.name else "Egg"} odds`
		.. (if l > 0 then ` (with your +{PetViewport.Percent(l)} luck)` else " (luck +0%)")
	local outcomes = Odds.Egg(eggId, l)
	-- rarest last, like the server table; show rarity groups in order
	table.sort(outcomes, function(a, b)
		local pa, pb = Pets.ById[a.key], Pets.ById[b.key]
		local ra = if pa then Pets.RarityById[pa.rarity].order else 0
		local rb = if pb then Pets.RarityById[pb.rarity].order else 0
		if ra ~= rb then
			return ra < rb
		end
		return tostring(a.key) < tostring(b.key)
	end)
	for i, o in outcomes do
		local pet = Pets.ById[o.key]
		local rarity = pet and Pets.RarityById[pet.rarity]
		local row = C.Card(oddsList, 34, i)
		local chip = Instance.new("Frame")
		chip.Name = "Rarity"
		chip.Size = UDim2.fromOffset(10, 22)
		chip.Position = UDim2.new(0, 8, 0.5, 0)
		chip.AnchorPoint = Vector2.new(0, 0.5)
		chip.BackgroundColor3 = if rarity then rarity.color else Colors.Grey
		chip.ZIndex = 3
		C.Corner(chip, 4)
		chip.Parent = row
		C.Label(row, {
			name = "Name",
			text = if pet then pet.name else tostring(o.key),
			color = Colors.TextDark,
			size = UDim2.new(0.5, -24, 1, -8),
			position = UDim2.new(0, 24, 0.5, 0),
			anchor = Vector2.new(0, 0.5),
			align = Enum.TextXAlignment.Left,
			stroke = 0,
			zIndex = 3,
		})
		C.Label(row, {
			name = "RarityName",
			text = if rarity then rarity.name else "",
			color = if rarity then C.Darken(rarity.color, 0.2) else Colors.GreyDark,
			size = UDim2.new(0.25, 0, 1, -10),
			position = UDim2.fromScale(0.55, 0.5),
			anchor = Vector2.new(0, 0.5),
			align = Enum.TextXAlignment.Left,
			stroke = 0,
			zIndex = 3,
		})
		C.Label(row, {
			name = "Chance",
			text = Odds.Percent(o.chance),
			color = Colors.TextDark,
			size = UDim2.new(0.2, -10, 1, -8),
			position = UDim2.new(1, -10, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			align = Enum.TextXAlignment.Right,
			stroke = 0,
			zIndex = 3,
		})
	end
end

function EggShopPanel.ShowOdds(eggId: string)
	if not Eggs.ById[eggId] then
		return
	end
	oddsEggId = eggId
	oddsView.Visible = true
	renderOdds()
end

local function hideOdds()
	oddsEggId = nil
	oddsView.Visible = false
end

------------------------------------------------------------------------------ refresh

local function refresh()
	local data = DataController:Get()
	local cash = if data and typeof(data.cash) == "number" then data.cash else 0
	local reb = if data and typeof(data.rebirths) == "number" then data.rebirths else 0
	local locked = restricted()
	for _, card in cards do
		local egg = card.egg
		local price = Pricing.Egg(player, data, egg.id)
		local gateText = if egg.rebirthsRequired > 0 then ` · Rebirth {egg.rebirthsRequired}` else ""
		card.info.Text = `Hatch {Format.Time(egg.hatchSeconds)}{gateText}`
		if locked then
			card.buyCaption.Text = "Not available in your region"
			C.SetButtonEnabled(card.buy, false)
		elseif reb < egg.rebirthsRequired then
			card.buyCaption.Text = `Rebirth {egg.rebirthsRequired}`
			C.SetButtonEnabled(card.buy, false)
		else
			card.buyCaption.Text = `BUY {Format.Cash(price)}`
			C.SetButtonEnabled(card.buy, cash >= price)
		end
	end
	notice.Visible = locked

	local last = if data and typeof(data.lastFreeEgg) == "number" then data.lastFreeEgg else 0
	local left = last + Eggs.FreeEggSeconds - Multipliers.Now()
	if left <= 0 then
		freeCaption.Text = "🎁 CLAIM FREE EGG"
		C.SetButtonEnabled(freeBtn, true)
	else
		freeCaption.Text = `Free egg in {Format.Time(math.ceil(left))}`
		C.SetButtonEnabled(freeBtn, false)
	end
	if oddsEggId then
		renderOdds()
	end
end

------------------------------------------------------------------------------ build

local function eggIcon(parent: Instance, eggId: string)
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Egg"
	vp.BackgroundTransparency = 1
	vp.Size = UDim2.new(1, 0, 0, 64)
	vp.Position = UDim2.fromOffset(0, 6)
	vp.Ambient = Color3.fromRGB(170, 170, 180)
	vp.LightColor = Color3.fromRGB(255, 250, 240)
	vp.ZIndex = 3
	vp.Parent = parent
	local ok, model = pcall(PetModels.BuildEgg, eggId)
	if not ok or not model then
		return
	end
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.Parent = vp
	vp.CurrentCamera = cam
	model:PivotTo(CFrame.identity)
	model.Parent = vp
	cam.CFrame = CFrame.lookAt(Vector3.new(-1.2, 2, -5.2), Vector3.new(0, 1.1, 0))
end

local function buildCard(parent: Instance, egg: Eggs.Egg, order: number): Card
	local f = Instance.new("Frame")
	f.Name = "Egg_" .. egg.id
	f.Size = UDim2.fromOffset(CARD_W, CARD_H)
	f.BackgroundColor3 = Colors.Card
	f.LayoutOrder = order
	f.ZIndex = 2
	C.Corner(f, 14)
	C.Stroke(f, 3, C.Darken(egg.color, 0.25), true)
	f.Parent = parent
	eggIcon(f, egg.id)
	C.Label(f, {
		name = "Name",
		text = egg.name,
		font = Theme.TitleFont,
		color = C.Darken(egg.color, 0.35),
		size = UDim2.new(1, -12, 0, 26),
		position = UDim2.fromOffset(6, 72),
		stroke = 0,
		zIndex = 3,
	})
	local info = C.Label(f, {
		name = "Info",
		text = "",
		color = Colors.GreyDark,
		size = UDim2.new(1, -12, 0, 22),
		position = UDim2.fromOffset(6, 100),
		stroke = 0,
		zIndex = 3,
	})
	local oddsW = 78
	local buy, buyCaption = C.Button(f, {
		name = "Buy",
		text = "BUY",
		color = Colors.Green,
		size = UDim2.fromOffset(CARD_W - 18 - oddsW, Theme.MinTouch),
		position = UDim2.new(0, 6, 1, -6),
		anchor = Vector2.new(0, 1),
		zIndex = 3,
		onClick = function()
			if restricted() then
				return
			end
			Net.Event("RequestBuyEgg"):FireServer(egg.id)
		end,
	})
	-- policy: the odds button has a TEXT label ("Odds"), not just an icon
	C.Button(f, {
		name = "Odds",
		text = "Odds",
		color = Colors.Blue,
		size = UDim2.fromOffset(oddsW, Theme.MinTouch),
		position = UDim2.new(1, -6, 1, -6),
		anchor = Vector2.new(1, 1),
		zIndex = 3,
		onClick = function()
			EggShopPanel.ShowOdds(egg.id)
		end,
	})
	return { egg = egg, buy = buy, buyCaption = buyCaption, info = info }
end

function EggShopPanel.Open()
	Panels.OpenPanel("EggShop")
end

function EggShopPanel:Init()
	local _, body = Panels.Panel("EggShop", "EGG SHOP", PANEL, Colors.Orange)

	local row = Instance.new("Frame")
	row.Name = "Eggs"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, CARD_H)
	row.ZIndex = 2
	row.Parent = body
	local layout = C.List(row, 12, true)
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	for i, egg in Eggs.List do
		table.insert(cards, buildCard(row, egg, i))
	end

	freeBtn, freeCaption = C.Button(body, {
		name = "FreeEgg",
		text = "🎁 CLAIM FREE EGG",
		font = Theme.TitleFont,
		color = Colors.Pink,
		size = UDim2.fromOffset(300, Theme.MinTouch),
		position = UDim2.fromScale(0, 1),
		anchor = Vector2.new(0, 1),
		zIndex = 3,
		onClick = function()
			Net.Event("RequestClaimFreeEgg"):FireServer()
		end,
	})
	notice = C.Label(body, {
		name = "Restricted",
		text = RESTRICTED_TEXT,
		color = Colors.RedDark,
		size = UDim2.new(1, -316, 0, 48),
		position = UDim2.new(1, 0, 1, -8),
		anchor = Vector2.new(1, 1),
		align = Enum.TextXAlignment.Left,
		stroke = 0,
		zIndex = 3,
	})
	notice.Visible = false

	-- odds overlay (covers the body)
	local ov = Instance.new("Frame")
	ov.Name = "OddsView"
	ov.Size = UDim2.fromScale(1, 1)
	ov.BackgroundColor3 = Colors.Panel
	ov.ZIndex = 6
	ov.Visible = false
	ov.Active = true
	ov.Parent = body
	oddsView = ov
	oddsTitle = C.Label(ov, {
		name = "Title",
		text = "Odds",
		color = Colors.TextDark,
		size = UDim2.new(1, -150, 0, 32),
		position = UDim2.fromOffset(0, 4),
		align = Enum.TextXAlignment.Left,
		stroke = 0,
		zIndex = 7,
	})
	C.Button(ov, {
		name = "Back",
		text = "Back",
		color = Colors.Red,
		size = UDim2.fromOffset(130, Theme.MinTouch),
		position = UDim2.fromScale(1, 0),
		anchor = Vector2.new(1, 0),
		zIndex = 7,
		onClick = hideOdds,
	})
	local listHolder = Instance.new("Frame")
	listHolder.Name = "ListHolder"
	listHolder.BackgroundTransparency = 1
	listHolder.Position = UDim2.fromOffset(0, Theme.MinTouch + 6)
	listHolder.Size = UDim2.new(1, 0, 1, -(Theme.MinTouch + 6))
	listHolder.ZIndex = 7
	listHolder.Parent = ov
	oddsList = C.ScrollList(listHolder, 4)
	oddsList.ZIndex = 7
end

function EggShopPanel:Start()
	for _, key in { "cash", "rebirths", "lastFreeEgg", "pets", "equippedPets", "nests" } do
		DataController:OnChanged(key, refresh)
	end
	player:GetAttributeChangedSignal("PaidRandomRestricted"):Connect(refresh)
	player:GetAttributeChangedSignal("MilkPerSecond"):Connect(refresh)
	Panels.OnPanelOpened("EggShop", function()
		hideOdds()
		refresh()
	end)

	-- the EggStand at the dairy opens the shop
	game:GetService("ProximityPromptService").PromptTriggered:Connect(function(p: ProximityPrompt, who: Player)
		local dairy = workspace:FindFirstChild("Dairy")
		local stand = dairy and dairy:FindFirstChild("EggStand")
		if who == player and stand and p.Parent == stand then
			EggShopPanel.Open()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			if Panels.IsOpen("EggShop") then
				refresh()
			end
		end
	end)
	refresh()
end

return EggShopPanel
