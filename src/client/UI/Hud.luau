--!strict
-- B1: Always-on HUD.
--   bottom-left   Cash (count-up tween + floating "+$123"), Rebirths, Milk/sec
--   bottom-center Milk can (canMilk / CanCapacity attribute) + "Selling: $X" / "Collect: $X"
--   top-left      Milk price chip (MilkPrice, countdown to MilkPriceNextAt, green >= 1, red < 1)
--                 + active boosts with timers
--   top-center    "Next event in mm:ss" or active event banner, truck banner when TruckActive
-- Reads data ONLY through DataController. Timers use workspace:GetServerTimeNow().

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Format = require(ReplicatedStorage.Shared.Format)
local Multipliers = require(ReplicatedStorage.Shared.Multipliers)
local Events = require(ReplicatedStorage.Shared.Config.Events)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local TopStack = require(script.Parent.TopStack)
local DataController = require(script.Parent.Parent.Controllers.DataController)

local player = Players.LocalPlayer
local Colors = Theme.Colors

local Hud = {}

local root: Frame
local cashLabel: TextLabel
local cashFrame: Frame
local rebirthLabel: TextLabel
local mpsLabel: TextLabel
local canFill: Frame
local canText: TextLabel
local sellChip: Frame
local sellText: TextLabel
local priceChip: Frame
local priceText: TextLabel
local priceTimer: TextLabel
local eventChip: Frame
local eventText: TextLabel
local truckBanner: Frame
local truckText: TextLabel
local boostList: Frame

local lastCash: number? = nil

local function chip(parent: Instance, name: string, size: Vector2, color: Color3?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = UDim2.fromOffset(size.X, size.Y)
	f.BackgroundColor3 = color or Colors.Chip
	f.BackgroundTransparency = 0.15
	f.Active = false
	C.Corner(f, 12)
	C.Stroke(f, 3, Colors.Stroke, true)
	f.Parent = parent
	return f
end

------------------------------------------------------------------------------- build

local function buildCash()
	-- On touch devices the thumbstick lives bottom-left, so lift the cash block above it.
	local lift = if UserInputService.TouchEnabled then 120 else 10
	cashFrame = Instance.new("Frame")
	cashFrame.Name = "CashBlock"
	cashFrame.BackgroundTransparency = 1
	cashFrame.AnchorPoint = Vector2.new(0, 1)
	cashFrame.Position = UDim2.new(0, 12, 1, -lift)
	cashFrame.Size = UDim2.fromOffset(250, 104)
	cashFrame.Active = false
	cashFrame.Parent = root

	cashLabel = C.Label(cashFrame, {
		name = "Cash",
		text = "$0",
		font = Theme.TitleFont,
		color = Colors.Cash,
		size = UDim2.fromOffset(250, 50),
		position = UDim2.fromOffset(0, 0),
		align = Enum.TextXAlignment.Left,
		stroke = 4,
	})

	rebirthLabel = C.Label(cashFrame, {
		name = "Rebirths",
		text = "Rebirths: 0",
		color = Colors.Pink,
		size = UDim2.fromOffset(200, 24),
		position = UDim2.fromOffset(2, 52),
		align = Enum.TextXAlignment.Left,
		stroke = 2,
	})

	mpsLabel = C.Label(cashFrame, {
		name = "MilkPerSecond",
		text = "0 milk/s",
		color = Colors.Milk,
		size = UDim2.fromOffset(200, 24),
		position = UDim2.fromOffset(2, 78),
		align = Enum.TextXAlignment.Left,
		stroke = 2,
	})
end

local function buildCan()
	local can = chip(root, "MilkCan", Vector2.new(190, 58))
	can.AnchorPoint = Vector2.new(0.5, 1)
	can.Position = UDim2.new(0.5, 0, 1, -8)

	C.Label(can, {
		name = "Icon",
		text = "🥛",
		size = UDim2.fromOffset(44, 44),
		position = UDim2.fromOffset(6, 7),
		stroke = 0,
	})

	local barBg = Instance.new("Frame")
	barBg.Name = "Bar"
	barBg.BackgroundColor3 = Color3.fromRGB(60, 55, 80)
	barBg.Position = UDim2.fromOffset(54, 32)
	barBg.Size = UDim2.new(1, -64, 0, 16)
	barBg.Parent = can
	C.Corner(barBg, 8)
	canFill = Instance.new("Frame")
	canFill.Name = "Fill"
	canFill.BackgroundColor3 = Colors.Milk
	canFill.Size = UDim2.fromScale(0, 1)
	canFill.Parent = barBg
	C.Corner(canFill, 8)

	canText = C.Label(can, {
		name = "Amount",
		text = "Milk 0 / 0",
		size = UDim2.new(1, -64, 0, 22),
		position = UDim2.fromOffset(54, 6),
		align = Enum.TextXAlignment.Left,
	})

	sellChip = chip(root, "Selling", Vector2.new(190, 26), Colors.GreenDark)
	sellChip.AnchorPoint = Vector2.new(0.5, 1)
	sellChip.Position = UDim2.new(0.5, 0, 1, -72)
	sellChip.Visible = false
	sellText = C.Label(sellChip, {
		name = "Text",
		text = "",
		size = UDim2.new(1, -12, 1, -4),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
	})
end

local function buildTop()
	priceChip = chip(root, "MilkPrice", Vector2.new(170, 50))
	priceChip.Position = UDim2.fromOffset(12, 8)
	priceText = C.Label(priceChip, {
		name = "Price",
		text = "Milk x1.00",
		size = UDim2.new(1, -14, 0, 26),
		position = UDim2.fromOffset(8, 3),
		align = Enum.TextXAlignment.Left,
		color = Colors.Green,
	})
	priceTimer = C.Label(priceChip, {
		name = "Timer",
		text = "new price in 0:30",
		size = UDim2.new(1, -14, 0, 16),
		position = UDim2.fromOffset(8, 30),
		align = Enum.TextXAlignment.Left,
		color = Color3.fromRGB(210, 210, 225),
		stroke = 1,
	})

	boostList = Instance.new("Frame")
	boostList.Name = "Boosts"
	boostList.BackgroundTransparency = 1
	boostList.Position = UDim2.fromOffset(12, 64)
	boostList.Size = UDim2.fromOffset(170, 120)
	boostList.Active = false
	boostList.Parent = root
	local l = C.List(boostList, 4, false, Enum.HorizontalAlignment.Left)
	l.VerticalAlignment = Enum.VerticalAlignment.Top

	-- event + truck share the reserved top-center stack (C6) so they never overlap
	eventChip = chip(root, "Event", Vector2.new(260, 34))
	eventChip.Visible = false
	TopStack.Add(eventChip, 10)
	eventText = C.Label(eventChip, {
		name = "Text",
		text = "",
		size = UDim2.new(1, -14, 1, -6),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
	})

	truckBanner = chip(root, "Truck", Vector2.new(300, 34), Colors.Orange)
	truckBanner.Visible = false
	TopStack.Add(truckBanner, 20)
	truckText = C.Label(truckBanner, {
		name = "Text",
		text = "",
		size = UDim2.new(1, -14, 1, -6),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
	})
end

------------------------------------------------------------------------------ update

-- "08:54" style countdown (Format.Time gives "8:54")
local function mmss(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	if s >= 3600 then
		return Format.Time(s)
	end
	return string.format("%02d:%02d", s // 60, s % 60)
end

local function cashPopup(amount: number)
	local pop = C.Label(root, {
		name = "CashPopup",
		text = "+" .. Format.Cash(amount),
		font = Theme.TitleFont,
		color = Colors.Yellow,
		size = UDim2.fromOffset(200, 36),
		stroke = 3,
		zIndex = 5,
	})
	local base = cashFrame.Position
	local x = math.random(150, 230)
	pop.Position = base + UDim2.fromOffset(x - 60, -40)
	pop.AnchorPoint = Vector2.new(0, 1)
	local s = Instance.new("UIScale")
	s.Scale = 0.4
	s.Parent = pop
	C.Tween(s, 0.25, { Scale = 1.1 }, Enum.EasingStyle.Back)
	C.Tween(pop, 1.2, { Position = pop.Position + UDim2.fromOffset(0, -70) }, Enum.EasingStyle.Quad)
	task.delay(0.7, function()
		C.Tween(pop, 0.5, { TextTransparency = 1 })
		local st = pop:FindFirstChildOfClass("UIStroke")
		if st then
			C.Tween(st, 0.5, { Transparency = 1 })
		end
	end)
	task.delay(1.25, function()
		pop:Destroy()
	end)
end

local function onCash(cash: number)
	if typeof(cash) ~= "number" then
		return
	end
	C.CountUp(cashLabel, cash, Format.Cash)
	if lastCash and cash > lastCash then
		cashPopup(cash - lastCash)
		local s = cashLabel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		s.Parent = cashLabel
		s.Scale = 1.15
		C.Tween(s, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	lastCash = cash
end

local function updateCan()
	local data = DataController:Get()
	local milk = if data and typeof(data.canMilk) == "number" then data.canMilk else 0
	local capAttr = player:GetAttribute("CanCapacity")
	local cap = if typeof(capAttr) == "number" then capAttr else Economy.Can.MinCapacity
	canText.Text = `Milk {Format.Number(math.floor(milk))} / {Format.Number(math.floor(cap))}`
	local ratio = if cap > 0 then math.clamp(milk / cap, 0, 1) else 0
	C.Tween(canFill, 0.25, { Size = UDim2.fromScale(ratio, 1) })
	canFill.BackgroundColor3 = if ratio >= 1 then Colors.Yellow else Colors.Milk
end

local function updateSelling()
	local data = DataController:Get()
	if not data then
		sellChip.Visible = false
		return
	end
	local queue = if typeof(data.dairyQueue) == "number" then data.dairyQueue else 0
	local ready = if typeof(data.dairyCash) == "number" then data.dairyCash else 0
	if ready > 0 then
		sellChip.Visible = true
		sellChip.BackgroundColor3 = Colors.YellowDark
		sellText.Text = `Collect: {Format.Cash(ready)} at the dairy!`
	elseif queue > 0 then
		sellChip.Visible = true
		sellChip.BackgroundColor3 = Colors.GreenDark
		-- dairyQueue holds milk VALUE (milk * price), cash multipliers apply when sold
		sellText.Text = `Selling: {Format.Cash(queue * Multipliers.Cash(player, data))}`
	else
		sellChip.Visible = false
	end
end

local function updateMps()
	local mps = player:GetAttribute("MilkPerSecond")
	local n = if typeof(mps) == "number" then mps else 0
	mpsLabel.Text = `{Format.Number(n)} milk/s`
end

local boostRows: { [string]: Frame } = {}

local function updateBoosts(now: number)
	local data = DataController:Get()
	local boosts = if data and typeof(data.boosts) == "table" then data.boosts else {}
	local seen: { [string]: boolean } = {}
	for id, b in boosts do
		if typeof(b) == "table" and typeof(b.expires) == "number" and b.expires > now then
			local key = tostring(id)
			seen[key] = true
			local row = boostRows[key]
			if not row then
				row = chip(boostList, "Boost_" .. key, Vector2.new(170, 26), Colors.PurpleDark)
				C.Label(row, {
					name = "Text",
					size = UDim2.new(1, -10, 1, -4),
					position = UDim2.fromScale(0.5, 0.5),
					anchor = Vector2.new(0.5, 0.5),
				})
				boostRows[key] = row
			end
			local kind = if b.kind == "production" then "Milk" else "Cash"
			local mult = if typeof(b.mult) == "number" then b.mult else 1
			local text = row:FindFirstChild("Text") :: TextLabel
			text.Text = `x{Format.Number(mult)} {kind}  {Format.Time(b.expires - now)}`
		end
	end
	for key, row in boostRows do
		if not seen[key] then
			row:Destroy()
			boostRows[key] = nil
		end
	end
end

local function updateTimers()
	local now = C.Now()

	-- milk price
	local price = Multipliers.MilkPrice()
	priceText.Text = `Milk x{string.format("%.2f", price)}`
	priceText.TextColor3 = if price >= 1 then Colors.Green else Colors.Red
	local nextAt = workspace:GetAttribute("MilkPriceNextAt")
	if typeof(nextAt) == "number" then
		priceTimer.Text = `new price in {Format.Time(nextAt - now)}`
	else
		priceTimer.Text = ""
	end

	-- truck
	if workspace:GetAttribute("TruckActive") then
		truckBanner.Visible = true
		local leaves = workspace:GetAttribute("TruckLeavesAt")
		local left = if typeof(leaves) == "number" then Format.Time(leaves - now) else ""
		truckText.Text = `🚚 MILK TRUCK! x{Economy.Truck.PriceBonus} price  {left}`
	else
		truckBanner.Visible = false
	end

	-- events
	local id = workspace:GetAttribute("EventId")
	local ev = if typeof(id) == "string" and id ~= "" then Events.ById[id] else nil
	if ev then
		eventChip.Visible = true
		eventChip.BackgroundColor3 = Colors.PinkDark
		local ends = workspace:GetAttribute("EventEndsAt")
		local left = if typeof(ends) == "number" then mmss(ends - now) else ""
		eventText.Text = `{ev.name} {left}`
	else
		local nextEv = workspace:GetAttribute("EventNextAt")
		if typeof(nextEv) == "number" and nextEv > now then
			eventChip.Visible = true
			eventChip.BackgroundColor3 = Colors.Chip
			eventText.Text = `Next event in {mmss(nextEv - now)}`
		else
			eventChip.Visible = false
		end
	end

	updateBoosts(now)
end

function Hud:Init()
	local _, r = C.Screen("Hud", 5)
	root = r
	buildCash()
	buildCan()
	buildTop()
end

function Hud:Start()
	DataController:OnChanged("cash", onCash)
	DataController:OnChanged("rebirths", function(n)
		if typeof(n) == "number" then
			rebirthLabel.Text = `Rebirths: {Format.Number(n)}`
		end
	end)
	DataController:OnChanged("canMilk", function()
		updateCan()
	end)
	DataController:OnChanged("dairyQueue", function()
		updateSelling()
	end)
	DataController:OnChanged("dairyCash", function()
		updateSelling()
	end)
	player:GetAttributeChangedSignal("CanCapacity"):Connect(updateCan)
	player:GetAttributeChangedSignal("MilkPerSecond"):Connect(updateMps)
	updateCan()
	updateMps()
	updateSelling()

	while true do
		local ok, err = pcall(updateTimers)
		if not ok then
			warn(`[Hud] {err}`)
		end
		task.wait(0.25)
	end
end

return Hud
