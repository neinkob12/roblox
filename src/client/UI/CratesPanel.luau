--!strict
-- B1: Mystery Milk Crates panel + spin animation.
--   Panel: crate count, OPEN (RequestOpenCrate), BUY (RequestBuyCrate) with the price shown.
--   Buy price mirrors A4 CrateService:BuyPrice = max(BuyBasePrice, MilkPerSecond * BuyPriceSecondsOfProduction)
--   (the MilkPerSecond player attribute already includes the multipliers).
--   Spin: on CrateOpened(tier, source) a reel of colored cow cards scrolls and lands on the
--   result, then the real cow model (CowModels.Build in a ViewportFrame) pops up.
--   Several results in a row are queued.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)
local Format = require(ReplicatedStorage.Shared.Format)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Cows = require(ReplicatedStorage.Shared.Config.Cows)
local CowModels = require(ReplicatedStorage.Shared.CowModels)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local Menu = require(script.Parent.Menu)
local DataController = require(script.Parent.Parent.Controllers.DataController)

local player = Players.LocalPlayer
local Colors = Theme.Colors

local CARD_W = 120
local CARD_H = 140
local CARD_GAP = 10
local REEL_CARDS = 34
local RESULT_INDEX = 29
local SPIN_TIME = 3.6

local CratesPanel = {}

local countText: TextLabel
local openBtn: TextButton
local buyBtn: TextButton
local buyCaption: TextLabel

local spinQueue: { { tier: number, source: string } } = {}
local spinning = false
local spinRoot: Frame

local function buyPrice(): number
	local mps = player:GetAttribute("MilkPerSecond")
	local n = if typeof(mps) == "number" then mps else 0
	return math.floor(math.max(Economy.Crate.BuyBasePrice, n * Economy.Crate.BuyPriceSecondsOfProduction))
end

local function refresh()
	local data = DataController:Get()
	if not data then
		return
	end
	local crates = if typeof(data.crates) == "number" then data.crates else 0
	local cash = if typeof(data.cash) == "number" then data.cash else 0
	countText.Text = `You have {Format.Number(crates)} crate{if crates == 1 then "" else "s"}`
	C.SetButtonEnabled(openBtn, crates > 0)
	local price = buyPrice()
	buyCaption.Text = `BUY {Format.Cash(price)}`
	C.SetButtonEnabled(buyBtn, cash >= price)
	Menu.SetBadge("Crates", crates)
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

local function cowViewport(parent: Instance, tier: number): RBXScriptConnection?
	local ok, model = pcall(CowModels.Build, tier)
	if not ok or not model then
		return nil
	end
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Cow"
	vp.BackgroundTransparency = 1
	vp.Size = UDim2.fromScale(1, 1)
	vp.Ambient = Color3.fromRGB(170, 170, 180)
	vp.LightColor = Color3.fromRGB(255, 250, 240)
	vp.LightDirection = Vector3.new(-1, -1.5, -1)
	vp.Parent = parent
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.Parent = vp
	vp.CurrentCamera = cam
	model:PivotTo(CFrame.identity)
	model.Parent = vp
	local boxCF, boxSize = model:GetBoundingBox()
	local center = boxCF.Position
	local dist = boxSize.Magnitude * 0.5 / math.tan(math.rad(cam.FieldOfView / 2)) * 1.05
	local start = os.clock()
	return RunService.RenderStepped:Connect(function()
		local a = (os.clock() - start) * 1.4
		cam.CFrame =
			CFrame.lookAt(center + Vector3.new(math.sin(a) * dist, boxSize.Y * 0.25, -math.cos(a) * dist), center)
	end)
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
	local spinConn = cowViewport(holder, tier)
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
		if spinConn then
			spinConn:Disconnect()
		end
		hint.Visible = false
		C.Tween(s, 0.2, { Scale = 0.5 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		C.Tween(overlay, 0.25, { BackgroundTransparency = 1 })
		task.wait(0.25)
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

local function pump()
	if spinning then
		return
	end
	spinning = true
	task.spawn(function()
		while #spinQueue > 0 do
			local item = table.remove(spinQueue, 1)
			if item then
				local ok, err = pcall(playSpin, item.tier, item.source)
				if not ok then
					warn(`[CratesPanel] spin failed: {err}`)
				end
			end
		end
		spinning = false
	end)
end

------------------------------------------------------------------------------ panel

function CratesPanel:Init()
	local _, body = C.Panel("Crates", "MYSTERY CRATES", Vector2.new(460, 300), Colors.Yellow)

	local icon = C.Label(body, {
		name = "Icon",
		text = "📦",
		size = UDim2.fromOffset(90, 90),
		position = UDim2.fromScale(0.5, 0),
		anchor = Vector2.new(0.5, 0),
		stroke = 0,
	})
	icon.Rotation = -6

	countText = C.Label(body, {
		name = "Count",
		text = "You have 0 crates",
		color = Colors.TextDark,
		size = UDim2.new(1, 0, 0, 30),
		position = UDim2.fromOffset(0, 96),
		stroke = 0,
	})

	C.Label(body, {
		name = "Info",
		text = "Each crate gives a cow near your best tier.\nCows drop crates on your farm too!",
		color = Colors.GreyDark,
		size = UDim2.new(1, 0, 0, 40),
		position = UDim2.fromOffset(0, 128),
		stroke = 0,
	})

	openBtn = C.Button(body, {
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
	buyBtn, buyCaption = C.Button(body, {
		name = "Buy",
		text = "BUY",
		font = Theme.TitleFont,
		color = Colors.Blue,
		size = UDim2.fromOffset(190, 64),
		position = UDim2.new(0.75, 0, 1, -4),
		anchor = Vector2.new(0.5, 1),
		onClick = function()
			Net.Event("RequestBuyCrate"):FireServer()
		end,
	})

	local _, root = C.Screen("CrateSpin", 110)
	spinRoot = root
end

function CratesPanel:Start()
	DataController:OnChanged("crates", refresh)
	DataController:OnChanged("cash", refresh)
	player:GetAttributeChangedSignal("MilkPerSecond"):Connect(refresh)
	C.OnPanelOpened("Crates", refresh)
	Net.Event("CrateOpened").OnClientEvent:Connect(function(tier: number, source: string)
		if typeof(tier) ~= "number" or not Cows.Get(tier) then
			return
		end
		table.insert(spinQueue, { tier = tier, source = if typeof(source) == "string" then source else "crate" })
		pump()
	end)
	refresh()
end

return CratesPanel
