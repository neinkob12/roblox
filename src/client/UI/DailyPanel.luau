--!strict
-- E1: Daily login reward popup (7-day strip + CLAIM button), see Config/Daily.
--   Shown once on join when a claim is available, never while the tutorial runs
--   (data.tutorialStep < Tutorial.Done). Also opened from the side Menu "Daily" button, which
--   shows a red badge while a claim is available.
--   Lives on its own ScreenGui at Theme.Layers.Popups (above Panels, below the Tutorial layer).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Format = require(ReplicatedStorage.Shared.Format)
local Daily = require(ReplicatedStorage.Shared.Config.Daily)
local Tutorial = require(ReplicatedStorage.Shared.Config.Tutorial)
local Theme = require(script.Parent.Parent.Lib.Theme)
local C = require(script.Parent.Parent.Lib.UiKit)
local Panels = require(script.Parent.Components)
local Menu = require(script.Parent.Menu)
local DataController = require(script.Parent.Parent.Controllers.DataController)

local Colors = Theme.Colors

local TILE_W = 78
local TILE_H = 112
local TILE_GAP = 8

local DailyPanel = {}

type Tile = { frame: Frame, day: TextLabel, check: TextLabel, stroke: UIStroke }

local dim: TextButton
local card: Frame
local cardScale: UIScale
local subtitle: TextLabel
local claimButton: TextButton
local claimCaption: TextLabel
local tiles: { Tile } = {}
local isOpen = false
local autoShown = false

local function tutorialDone(data: any): boolean
	return data ~= nil and typeof(data.tutorialStep) == "number" and data.tutorialStep >= Tutorial.Done
end

local function refresh()
	local data = DataController:Get()
	local now = C.Now()
	local can = data ~= nil and Daily.CanClaim(data, now)
	Menu.SetBadge("Daily", if can then 1 else 0)
	if not card or not data then
		return
	end
	local streak = Daily.EffectiveStreak(data, now)
	-- tiles already claimed in this 7-day cycle; while waiting, the day just claimed stays checked
	local claimed = if can then streak % #Daily.Days else (math.max(streak, 1) - 1) % #Daily.Days + 1
	for i, tile in tiles do
		local isToday = can and i == claimed + 1
		tile.check.Visible = i <= claimed
		tile.frame.BackgroundTransparency = if i <= claimed then 0.35 else 0
		tile.stroke.Color = if isToday then Colors.Yellow else Colors.Stroke
		tile.stroke.Thickness = if isToday then 4 else 2
		tile.day.Text = if isToday then "TODAY" else `Day {i}`
	end
	if can then
		subtitle.Text = if streak > 0
			then `{streak} day streak! Claim day {streak % #Daily.Days + 1}`
			else "Log in every day for bigger rewards!"
		claimCaption.Text = "CLAIM!"
		C.SetButtonEnabled(claimButton, true)
	else
		subtitle.Text = `{streak} day streak! Come back tomorrow`
		claimCaption.Text = `Next in {Format.Time(Daily.SecondsUntilClaim(data, now))}`
		C.SetButtonEnabled(claimButton, false)
	end
end

local function close()
	if not isOpen then
		return
	end
	isOpen = false
	C.Tween(cardScale, 0.15, { Scale = 0.6 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	C.Tween(dim, 0.18, { BackgroundTransparency = 1 }).Completed:Connect(function()
		if not isOpen then
			dim.Visible = false
		end
	end)
end

function DailyPanel.Open()
	if isOpen then
		return
	end
	isOpen = true
	Panels.ClosePanel()
	refresh()
	dim.Visible = true
	if C.ReduceMotion() then
		cardScale.Scale = 1
		dim.BackgroundTransparency = 0.45
	else
		cardScale.Scale = 0.5
		C.Tween(cardScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		C.Tween(dim, 0.2, { BackgroundTransparency = 0.45 })
	end
end

function DailyPanel.Toggle()
	if isOpen then
		close()
	else
		DailyPanel.Open()
	end
end

function DailyPanel:Init()
	local _, root = C.Screen("Daily", Theme.Layers.Popups)

	dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.Visible = false
	dim.Parent = root
	dim.Activated:Connect(close)

	local n = #Daily.Days
	local stripW = n * TILE_W + (n - 1) * TILE_GAP
	card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(stripW + 40, 320)
	card.BackgroundColor3 = Colors.Panel
	card.Active = true
	card.Parent = dim
	C.Corner(card, 18)
	C.Stroke(card, 4, Colors.Stroke, true)
	cardScale = Instance.new("UIScale")
	cardScale.Parent = card

	C.Label(card, {
		name = "Title",
		text = "DAILY REWARD",
		font = Theme.TitleFont,
		color = Colors.Yellow,
		size = UDim2.new(1, -150, 0, 44),
		position = UDim2.new(0.5, 0, 0, 10),
		anchor = Vector2.new(0.5, 0),
		stroke = 3,
	})
	subtitle = C.Label(card, {
		name = "Streak",
		text = "",
		color = Colors.TextDark,
		size = UDim2.new(1, -40, 0, 24),
		position = UDim2.new(0.5, 0, 0, 58),
		anchor = Vector2.new(0.5, 0),
		stroke = 0,
	})
	C.Button(card, {
		name = "Close",
		text = "X",
		color = Colors.Red,
		size = UDim2.fromOffset(Theme.MinTouch, Theme.MinTouch),
		position = UDim2.new(1, -8, 0, 8),
		anchor = Vector2.new(1, 0),
		onClick = close,
	})

	local strip = Instance.new("Frame")
	strip.Name = "Strip"
	strip.BackgroundTransparency = 1
	strip.AnchorPoint = Vector2.new(0.5, 0)
	strip.Position = UDim2.new(0.5, 0, 0, 90)
	strip.Size = UDim2.fromOffset(stripW, TILE_H)
	strip.Parent = card
	C.List(strip, TILE_GAP, true, Enum.HorizontalAlignment.Center)

	for i, reward in Daily.Days do
		local f = Instance.new("Frame")
		f.Name = "Day" .. i
		f.Size = UDim2.fromOffset(TILE_W, TILE_H)
		f.BackgroundColor3 = if i == n then Colors.Purple else Colors.Card
		f.LayoutOrder = i
		f.Parent = strip
		C.Corner(f, 12)
		local stroke = C.Stroke(f, 2, Colors.Stroke, true)
		local day = C.Label(f, {
			name = "Day",
			text = `Day {i}`,
			color = if i == n then Colors.Text else Colors.TextDark,
			size = UDim2.new(1, -8, 0, 20),
			position = UDim2.new(0.5, 0, 0, 4),
			anchor = Vector2.new(0.5, 0),
			stroke = if i == n then 2 else 0,
		})
		C.Label(f, {
			name = "Icon",
			text = reward.icon,
			size = UDim2.new(1, -16, 0, 44),
			position = UDim2.new(0.5, 0, 0, 26),
			anchor = Vector2.new(0.5, 0),
			stroke = 0,
		})
		C.Label(f, {
			name = "Reward",
			text = reward.label,
			size = UDim2.new(1, -8, 0, 34),
			position = UDim2.new(0.5, 0, 1, -4),
			anchor = Vector2.new(0.5, 1),
			stroke = 2,
		})
		local check = C.Label(f, {
			name = "Check",
			text = "✅",
			size = UDim2.fromOffset(30, 30),
			position = UDim2.new(1, 4, 0, -6),
			anchor = Vector2.new(1, 0),
			stroke = 0,
			zIndex = 3,
		})
		check.Visible = false
		tiles[i] = { frame = f, day = day, check = check, stroke = stroke }
	end

	local b, caption = C.Button(card, {
		name = "Claim",
		text = "CLAIM!",
		font = Theme.TitleFont,
		color = Colors.Green,
		size = UDim2.fromOffset(280, Theme.MinTouch),
		position = UDim2.new(0.5, 0, 1, -14),
		anchor = Vector2.new(0.5, 1),
		onClick = function()
			if Daily.CanClaim(DataController:Get(), C.Now()) then
				Net.Event("RequestDailyClaim"):FireServer()
			end
		end,
	})
	claimButton = b
	claimCaption = caption

	Menu.SetAction("Daily", DailyPanel.Toggle)
end

-- Show the popup once per session when a claim is available and the tutorial is finished.
-- Waits for the welcome-back popup (same layer) to be dismissed first.
local function tryAutoShow()
	if autoShown then
		return
	end
	local data = DataController:Get()
	if not tutorialDone(data) or not Daily.CanClaim(data, C.Now()) then
		return
	end
	autoShown = true
	task.spawn(function()
		task.wait(2)
		local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		local deadline = os.clock() + 120
		while pg and os.clock() < deadline do
			local popups = pg:FindFirstChild("Popups")
			local popupRoot = popups and popups:FindFirstChild("Root")
			if not (popupRoot and popupRoot:FindFirstChild("WelcomeBack")) then
				break
			end
			task.wait(0.5)
		end
		if Daily.CanClaim(DataController:Get(), C.Now()) then
			DailyPanel.Open()
		end
	end)
end

function DailyPanel:Start()
	DataController:OnChanged("dailyLastClaim", refresh)
	DataController:OnChanged("dailyStreak", refresh)
	DataController:OnChanged("tutorialStep", tryAutoShow)
	task.spawn(function()
		DataController:WaitForData()
		refresh()
		tryAutoShow()
		while true do
			task.wait(1)
			refresh()
		end
	end)
end

return DailyPanel
