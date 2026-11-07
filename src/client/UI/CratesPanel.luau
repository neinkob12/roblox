--!strict
-- B1: Mystery Milk Crates panel + spin animation.
--   Panel: crate count, OPEN (RequestOpenCrate), BUY (RequestBuyCrate) with the price shown.
--   Buy price mirrors A4 CrateService:BuyPrice = max(BuyBasePrice, MilkPerSecond * BuyPriceSecondsOfProduction)
--   (the MilkPerSecond player attribute already includes the multipliers).
--   Spin: on CrateOpened(tier, source) a reel of colored cow cards scrolls and lands on the
--   result, then the real cow model (Lib/CowViewport) pops up.
--   Several results in a row are queued in the shared RevealQueue (C6), so a "NEW COW!"
--   discovery from the same crate plays after the spin instead of on top of it.
--
-- G0 compliance (docs/CONTRACTS.md section 11, Roblox "paid random items" policy):
--   * The odds of every outcome are always visible in the panel (summary line) and in full in the
--     "ODDS" list, computed with shared/Odds (the exact table the server rolls with), live with the
--     best tier. The list also has a Premium Crate tab (shift = Economy.Crate.PremiumOddsShift).
--   * Restricted players (attribute PaidRandomRestricted ~= false) cannot buy: BUY is disabled with
--     a note pointing to the free sources. Opening crates they already own stays allowed.
--   CratesPanel.ShowOdds(premium) -> opens the odds list (ShopPanel uses it for the Premium Crate).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Format = require(ReplicatedStorage.Shared.Format)
local Pricing = require(ReplicatedStorage.Shared.Pricing)
local Odds = require(ReplicatedStorage.Shared.Odds)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Cows = require(ReplicatedStorage.Shared.Config.Cows)
local Theme = require(script.Parent.Parent.Lib.Theme)
local RevealQueue = require(script.Parent.Parent.Lib.RevealQueue)
local C = require(script.Parent.Parent.Lib.UiKit)
local Panels = require(script.Parent.Components)
local Menu = require(script.Parent.Menu)
local DataController = require(script.Parent.Parent.Controllers.DataController)
local CowViewport = require(script.Parent.Parent.Lib.CowViewport)
local SoundController = require(script.Parent.Parent.Controllers.SoundController)

local player = Players.LocalPlayer
local Colors = Theme.Colors

local CARD_W = 120
local CARD_H = 140
local CARD_GAP = 10
local REEL_CARDS = 34
local RESULT_INDEX = 29
local SPIN_TIME = 3.6

local RESTRICTED_TEXT = "Not available in your region. Earn crates from drops, quests and codes!"
local ODDS_ROW_H = 46

local CratesPanel = {}

local mainFrame: Frame
local countText: TextLabel
local oddsSummary: TextLabel
local openBtn: TextButton
local buyBtn: TextButton
local buyCaption: TextLabel

local oddsFrame: Frame
local oddsTitle: TextLabel
local oddsList: ScrollingFrame
local oddsFooter: TextLabel
local premiumTab: TextButton
local normalTab: TextButton
local oddsPremium = false

local spinRoot: Frame

local function buyPrice(): number
	-- same formula the server charges (shared/Pricing), so the button never lies
	return Pricing.Crate(player, DataController:Get())
end

local function isRestricted(): boolean
	-- same rule as ComplianceService:IsPaidRandomRestricted (nil = check not done yet = restricted)
	return player:GetAttribute("PaidRandomRestricted") ~= false
end

-- same as CrateService bestTier: highest tier with count > 0 (1 if none)
local function bestTier(data: any): number
	local best = 1
	local cows = if data and typeof(data.cows) == "table" then data.cows else {}
	for key, count in cows do
		local tier = tonumber(key)
		if tier and typeof(count) == "number" and count > 0 and tier > best then
			best = tier
		end
	end
	return best
end

local function outcomes(premium: boolean): { Odds.Outcome }
	local shift = if premium then Economy.Crate.PremiumOddsShift else 0
	return Odds.Crate(bestTier(DataController:Get()), shift)
end

local function cowName(tier: number): string
	local cow = Cows.Get(tier)
	return if cow then cow.name else `Tier {tier}`
end

------------------------------------------------------------------------------ odds list

local function renderOdds()
	if not oddsFrame or not oddsFrame.Visible then
		return
	end
	local restricted = isRestricted()
	if restricted then
		-- restricted players never see the Robux Premium Crate (ShopPanel hides it too)
		oddsPremium = false
	end
	premiumTab.Visible = not restricted
	C.SetButtonEnabled(normalTab, oddsPremium)
	C.SetButtonEnabled(premiumTab, not oddsPremium)
	oddsTitle.Text = if oddsPremium then "PREMIUM CRATE ODDS" else "MYSTERY CRATE ODDS"
	for _, child in oddsList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local list = outcomes(oddsPremium)
	local total = 0
	for i, o in list do
		local tier: number = o.key
		total += o.chance
		local cow = Cows.Get(tier)
		local card = C.Card(oddsList, ODDS_ROW_H, i)
		card.Name = "Odds" .. tier
		local chip = Instance.new("Frame")
		chip.Name = "Chip"
		chip.Size = UDim2.fromOffset(36, 36)
		chip.Position = UDim2.new(0, 6, 0.5, 0)
		chip.AnchorPoint = Vector2.new(0, 0.5)
		chip.BackgroundColor3 = if cow then cow.bodyColor else Colors.Grey
		chip.ZIndex = 3
		C.Corner(chip, 10)
		C.Stroke(chip, 2, Colors.Stroke, true)
		chip.Parent = card
		C.Label(chip, {
			name = "Tier",
			text = tostring(tier),
			font = Theme.TitleFont,
			size = UDim2.fromScale(0.8, 0.8),
			position = UDim2.fromScale(0.5, 0.5),
			anchor = Vector2.new(0.5, 0.5),
			stroke = 2,
			zIndex = 4,
		})
		C.Label(card, {
			name = "Name",
			text = `{cowName(tier)}  (Tier {tier})`,
			color = Colors.TextDark,
			size = UDim2.new(1, -150, 0, 28),
			position = UDim2.new(0, 50, 0.5, 0),
			anchor = Vector2.new(0, 0.5),
			align = Enum.TextXAlignment.Left,
			stroke = 0,
			zIndex = 3,
		})
		C.Label(card, {
			name = "Percent",
			text = Odds.Percent(o.chance),
			font = Theme.TitleFont,
			color = Colors.TextDark,
			size = UDim2.fromOffset(90, 30),
			position = UDim2.new(1, -8, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			align = Enum.TextXAlignment.Right,
			stroke = 0,
			zIndex = 3,
		})
	end
	oddsFooter.Text = `Based on your best cow (Tier {bestTier(DataController:Get())}). Total: {Odds.Percent(total)}`
end

local function showOdds(premium: boolean)
	oddsPremium = premium and not isRestricted()
	mainFrame.Visible = false
	oddsFrame.Visible = true
	renderOdds()
end

local function hideOdds()
	oddsFrame.Visible = false
	mainFrame.Visible = true
end

-- Opens the Crates panel on the odds list (premium = Premium Crate odds). Used by ShopPanel.
function CratesPanel.ShowOdds(premium: boolean)
	if not Panels.IsOpen("Crates") then
		Panels.OpenPanel("Crates")
	end
	showOdds(premium)
end

------------------------------------------------------------------------------ main view

local function refresh()
	local data = DataController:Get()
	if not data then
		return
	end
	local crates = if typeof(data.crates) == "number" then data.crates else 0
	local cash = if typeof(data.cash) == "number" then data.cash else 0
	countText.Text = `You have {Format.Number(crates)} crate{if crates == 1 then "" else "s"}`
	-- opening owned crates (earned for free) is allowed for everyone
	C.SetButtonEnabled(openBtn, crates > 0)

	local parts = {}
	for _, o in outcomes(false) do
		table.insert(parts, `{cowName(o.key)} {Odds.Percent(o.chance)}`)
	end
	oddsSummary.Text = "Odds: " .. table.concat(parts, "  |  ")

	if isRestricted() then
		buyCaption.Text = RESTRICTED_TEXT
		buyCaption.TextWrapped = true
		C.SetButtonEnabled(buyBtn, false)
	else
		local price = buyPrice()
		buyCaption.Text = `BUY {Format.Cash(price)}`
		buyCaption.TextWrapped = false
		C.SetButtonEnabled(buyBtn, cash >= price)
	end
	Menu.SetBadge("Crates", crates)
	renderOdds()
end

------------------------------------------------------------------------------ spin

local function cowCard(parent: Instance, tier: number, w: number, h: number): Frame
	local cow = Cows.Get(tier)
	local card = Instance.new("Frame")
	card.Name = "Card" .. tier
	card.Size = UDim2.fromOffset(w, h)
	card.BackgroundColor3 = if cow then cow.bodyColor else Colors.Grey
	C.Corner(card, 14)
	C.Stroke(card, 4, Colors.Stroke, true)
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170))
	grad.Parent = card
	local spot = Instance.new("Frame")
	spot.Name = "Spot"
	spot.AnchorPoint = Vector2.new(0.5, 0.5)
	spot.Position = UDim2.fromScale(0.5, 0.38)
	spot.Size = UDim2.fromOffset(w * 0.45, w * 0.45)
	spot.BackgroundColor3 = if cow then cow.spotColor else Colors.GreyDark
	C.Corner(spot, math.floor(w * 0.225))
	C.Stroke(spot, 3, Colors.Stroke, true)
	spot.Parent = card
	C.Label(spot, {
		name = "Tier",
		text = tostring(tier),
		font = Theme.TitleFont,
		size = UDim2.fromScale(0.7, 0.7),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		stroke = 3,
	})
	C.Label(card, {
		name = "Name",
		text = if cow then cow.name else "?",
		size = UDim2.new(1, -12, 0, 36),
		position = UDim2.new(0.5, 0, 1, -8),
		anchor = Vector2.new(0.5, 1),
		stroke = 2,
	})
	card.Parent = parent
	return card
end

local function playSpin(tier: number, source: string)
	local rng = Random.new()
	local overlay = Instance.new("TextButton")
	overlay.Name = "Spin"
	overlay.Text = ""
	overlay.AutoButtonColor = false
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(15, 8, 30)
	overlay.BackgroundTransparency = 1
	overlay.Parent = spinRoot
	C.Tween(overlay, 0.25, { BackgroundTransparency = 0.25 })

	local title = C.Label(overlay, {
		name = "Title",
		text = if source == "premium" then "PREMIUM MILK CRATE!" else "MYSTERY MILK CRATE!",
		font = Theme.TitleFont,
		color = if source == "premium" then Colors.Purple else Colors.Yellow,
		size = UDim2.fromOffset(600, 54),
		position = UDim2.fromScale(0.5, 0.12),
		anchor = Vector2.new(0.5, 0.5),
		stroke = 4,
	})

	-- reel window
	local window = Instance.new("Frame")
	window.Name = "Window"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromOffset(640, CARD_H + 30)
	window.BackgroundColor3 = Colors.Chip
	window.ClipsDescendants = true
	window.Parent = overlay
	C.Corner(window, 18)
	C.Stroke(window, 5, Colors.Yellow, true)

	local strip = Instance.new("Frame")
	strip.Name = "Strip"
	strip.BackgroundTransparency = 1
	strip.AnchorPoint = Vector2.new(0, 0.5)
	strip.Size = UDim2.fromOffset(REEL_CARDS * (CARD_W + CARD_GAP), CARD_H)
	strip.Parent = window
	C.List(strip, CARD_GAP, true, Enum.HorizontalAlignment.Left)

	for i = 1, REEL_CARDS do
		local t = if i == RESULT_INDEX then tier else math.clamp(tier + rng:NextInteger(-2, 2), 1, Cows.Count)
		local card = cowCard(strip, t, CARD_W, CARD_H)
		card.LayoutOrder = i
	end

	-- center marker
	local marker = Instance.new("Frame")
	marker.Name = "Marker"
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Position = UDim2.fromScale(0.5, 0.5)
	marker.Size = UDim2.new(0, 6, 1, 0)
	marker.BackgroundColor3 = Colors.Yellow
	marker.ZIndex = 5
	marker.Parent = window
	C.Stroke(marker, 2, Colors.Stroke, true)

	-- x of the strip so that card i's center sits at the window center
	local function stripX(i: number, jitter: number): number
		local cardCenter = (i - 1) * (CARD_W + CARD_GAP) + CARD_W / 2 + jitter
		return 320 - cardCenter
	end
	strip.Position = UDim2.new(0, stripX(3, 0), 0.5, 0)
	local landing = stripX(RESULT_INDEX, rng:NextNumber(-CARD_W * 0.35, CARD_W * 0.35))
	C.Tween(strip, SPIN_TIME, { Position = UDim2.new(0, landing, 0.5, 0) }, Enum.EasingStyle.Quint)
	task.wait(SPIN_TIME + 0.15)
	if not overlay.Parent then
		return
	end

	-- reveal
	SoundController:Play("CrateReveal")
	C.Tween(window, 0.2, { Size = UDim2.fromOffset(640, 0) })
	task.wait(0.2)
	window:Destroy()
	local cow = Cows.Get(tier)
	local reveal = cowCard(overlay, tier, 260, 300)
	reveal.AnchorPoint = Vector2.new(0.5, 0.5)
	reveal.Position = UDim2.fromScale(0.5, 0.53)
	local spot = reveal:FindFirstChild("Spot")
	if spot then
		spot:Destroy()
	end
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 1, -50)
	holder.Parent = reveal
	local stopCow = CowViewport.Mount(holder, tier, { spin = 1.4 })
	local s = Instance.new("UIScale")
	s.Scale = 0.3
	s.Parent = reveal
	C.Tween(s, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	local border = reveal:FindFirstChildOfClass("UIStroke")
	if border then
		-- UIGradient multiplies the stroke color, so the base must be white
		border.Color = Color3.new(1, 1, 1)
		border.Thickness = 6
		C.Rainbow(border)
	end
	title.Text = `YOU GOT {string.upper(if cow then cow.name else "A COW")}!`
	local hint = C.Label(overlay, {
		name = "Hint",
		text = "Tap to continue",
		size = UDim2.fromOffset(240, 24),
		position = UDim2.fromScale(0.5, 0.95),
		anchor = Vector2.new(0.5, 0.5),
		color = Color3.fromRGB(220, 220, 230),
	})

	local done = false
	local function close()
		if done then
			return
		end
		done = true
		hint.Visible = false
		C.Tween(s, 0.2, { Scale = 0.5 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		C.Tween(overlay, 0.25, { BackgroundTransparency = 1 })
		task.wait(0.25)
		stopCow()
		overlay:Destroy()
	end
	local unlocked = false
	task.delay(0.6, function()
		unlocked = true
	end)
	overlay.Activated:Connect(function()
		if unlocked then
			task.spawn(close)
		end
	end)
	local t0 = os.clock()
	while not done and os.clock() - t0 < 4 do
		task.wait(0.1)
	end
	close()
end

------------------------------------------------------------------------------ panel

function CratesPanel:Init()
	local _, body = Panels.Panel("Crates", "MYSTERY CRATES", Vector2.new(460, 340), Colors.Yellow)

	-------------------------------------------------------------------- main view
	local main = Instance.new("Frame")
	main.Name = "Main"
	main.BackgroundTransparency = 1
	main.Size = UDim2.fromScale(1, 1)
	main.ZIndex = 2
	main.Parent = body
	mainFrame = main

	local icon = C.Label(main, {
		name = "Icon",
		text = "📦",
		size = UDim2.fromOffset(64, 64),
		position = UDim2.fromScale(0.5, 0),
		anchor = Vector2.new(0.5, 0),
		stroke = 0,
	})
	icon.Rotation = -6

	-- the odds are one tap away BEFORE buying (policy: text label, not just an icon)
	C.Button(main, {
		name = "OddsButton",
		text = "ODDS",
		font = Theme.TitleFont,
		color = Colors.Purple,
		size = UDim2.fromOffset(110, Theme.MinTouch),
		position = UDim2.fromScale(1, 0),
		anchor = Vector2.new(1, 0),
		onClick = function()
			showOdds(false)
		end,
	})

	countText = C.Label(main, {
		name = "Count",
		text = "You have 0 crates",
		color = Colors.TextDark,
		size = UDim2.new(1, -240, 0, 28),
		position = UDim2.new(0.5, 0, 0, 68),
		anchor = Vector2.new(0.5, 0),
		stroke = 0,
	})

	oddsSummary = C.Label(main, {
		name = "OddsSummary",
		text = "Odds:",
		color = Colors.TextDark,
		size = UDim2.new(1, 0, 0, 26),
		position = UDim2.fromOffset(0, 100),
		stroke = 0,
	})

	C.Label(main, {
		name = "Info",
		text = "Each crate gives a cow near your best tier.\nCows drop crates on your farm too!",
		color = Colors.GreyDark,
		size = UDim2.new(1, 0, 0, 40),
		position = UDim2.fromOffset(0, 130),
		stroke = 0,
	})

	openBtn = C.Button(main, {
		name = "Open",
		text = "OPEN",
		font = Theme.TitleFont,
		color = Colors.Green,
		size = UDim2.fromOffset(190, 64),
		position = UDim2.new(0.25, 0, 1, -4),
		anchor = Vector2.new(0.5, 1),
		onClick = function()
			Net.Event("RequestOpenCrate"):FireServer()
		end,
	})
	buyBtn, buyCaption = C.Button(main, {
		name = "Buy",
		text = "BUY",
		font = Theme.TitleFont,
		color = Colors.Blue,
		size = UDim2.fromOffset(190, 64),
		position = UDim2.new(0.75, 0, 1, -4),
		anchor = Vector2.new(0.5, 1),
		onClick = function()
			if isRestricted() then
				return -- the server refuses too (CrateService)
			end
			Net.Event("RequestBuyCrate"):FireServer()
		end,
	})

	-------------------------------------------------------------------- odds view
	local odds = Instance.new("Frame")
	odds.Name = "OddsView"
	odds.BackgroundTransparency = 1
	odds.Size = UDim2.fromScale(1, 1)
	odds.Visible = false
	odds.ZIndex = 2
	odds.Parent = body
	oddsFrame = odds

	oddsTitle = C.Label(odds, {
		name = "OddsTitle",
		text = "MYSTERY CRATE ODDS",
		font = Theme.TitleFont,
		color = Colors.PurpleDark,
		size = UDim2.new(1, -250, 0, 30),
		position = UDim2.fromOffset(0, 4),
		align = Enum.TextXAlignment.Left,
		stroke = 0,
	})
	normalTab = C.Button(odds, {
		name = "MysteryTab",
		text = "MYSTERY",
		color = Colors.Yellow,
		size = UDim2.fromOffset(120, Theme.MinTouch),
		position = UDim2.new(1, -126, 0, -6),
		anchor = Vector2.new(1, 0),
		onClick = function()
			oddsPremium = false
			renderOdds()
		end,
	})
	premiumTab = C.Button(odds, {
		name = "PremiumTab",
		text = "PREMIUM",
		color = Colors.Purple,
		size = UDim2.fromOffset(120, Theme.MinTouch),
		position = UDim2.new(1, 0, 0, -6),
		anchor = Vector2.new(1, 0),
		onClick = function()
			if not isRestricted() then
				oddsPremium = true
				renderOdds()
			end
		end,
	})

	local listHolder = Instance.new("Frame")
	listHolder.Name = "ListHolder"
	listHolder.BackgroundTransparency = 1
	listHolder.Position = UDim2.fromOffset(0, 62)
	listHolder.Size = UDim2.new(1, 0, 1, -62 - 96)
	listHolder.ZIndex = 2
	listHolder.Parent = odds
	oddsList = C.ScrollList(listHolder, 6)

	oddsFooter = C.Label(odds, {
		name = "Footer",
		text = "",
		color = Colors.GreyDark,
		size = UDim2.new(1, 0, 0, 24),
		position = UDim2.new(0, 0, 1, -90),
		stroke = 0,
	})
	C.Button(odds, {
		name = "Back",
		text = "BACK",
		font = Theme.TitleFont,
		color = Colors.Blue,
		size = UDim2.fromOffset(190, Theme.MinTouch),
		position = UDim2.new(0.5, 0, 1, -4),
		anchor = Vector2.new(0.5, 1),
		onClick = hideOdds,
	})

	local _, root = C.Screen("CrateSpin", Theme.Layers.Reveal)
	spinRoot = root
end

function CratesPanel:Start()
	DataController:OnChanged("crates", refresh)
	DataController:OnChanged("cash", refresh)
	DataController:OnChanged("cratesBought", refresh)
	DataController:OnChanged("cows", refresh) -- best tier -> odds update live
	player:GetAttributeChangedSignal("MilkPerSecond"):Connect(refresh)
	player:GetAttributeChangedSignal("PaidRandomRestricted"):Connect(refresh)
	Panels.OnPanelOpened("Crates", function()
		hideOdds() -- every open starts on the main view (ShowOdds switches after opening)
		refresh()
	end)
	Net.Event("CrateOpened").OnClientEvent:Connect(function(tier: number, source: string)
		if typeof(tier) ~= "number" or not Cows.Get(tier) then
			return
		end
		local src = if typeof(source) == "string" then source else "crate"
		RevealQueue.Push(function()
			SoundController:Play("CrateSpin")
			playSpin(tier, src)
		end, 0)
	end)
	refresh()
end

return CratesPanel
