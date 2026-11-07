--!strict
-- B1: Rebirth panel. Shows current cash multiplier -> next, the cost, what resets, and a big
-- confirm button (two taps: "REBIRTH!" then "SURE?") that fires RequestRebirth.
-- Cost formula mirrors A4 RebirthService:Cost (Economy.Rebirth.BaseCost * CostGrowth ^ rebirths).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Format = require(ReplicatedStorage.Shared.Format)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Pricing = require(ReplicatedStorage.Shared.Pricing)
local Theme = require(script.Parent.Parent.Lib.Theme)
local C = require(script.Parent.Parent.Lib.UiKit)
local Panels = require(script.Parent.Components)
local DataController = require(script.Parent.Parent.Controllers.DataController)

local Colors = Theme.Colors

local RebirthPanel = {}

local multText: TextLabel
local costText: TextLabel
local progressFill: Frame
local confirm: TextButton
local confirmCaption: TextLabel
local armed = false
local armToken = 0

local function cost(rebirths: number): number
	return Pricing.Rebirth(rebirths)
end

local function mult(rebirths: number): number
	return 1 + Economy.Rebirth.CashMultiplierPerRebirth * rebirths
end

local function disarm()
	armed = false
	armToken += 1
	confirmCaption.Text = "REBIRTH!"
	C.SetButtonColor(confirm, Colors.Pink)
end

local function refresh()
	local data = DataController:Get()
	if not data then
		return
	end
	local r = if typeof(data.rebirths) == "number" then data.rebirths else 0
	local cash = if typeof(data.cash) == "number" then data.cash else 0
	local c = cost(r)
	multText.Text = `Cash x{Format.Number(mult(r))}  ➜  x{Format.Number(mult(r + 1))}`
	costText.Text = `Cost: {Format.Cash(c)}   (you have {Format.Cash(cash)})`
	C.Tween(progressFill, 0.3, { Size = UDim2.fromScale(math.clamp(cash / c, 0, 1), 1) })
	C.SetButtonEnabled(confirm, cash >= c)
	if cash < c and armed then
		disarm()
	end
end

function RebirthPanel:Init()
	local _, body = Panels.Panel("Rebirth", "REBIRTH", Vector2.new(480, 330), Colors.Pink)

	multText = C.Label(body, {
		name = "Multiplier",
		text = "Cash x1 ➜ x1.5",
		font = Theme.TitleFont,
		color = Colors.YellowDark,
		size = UDim2.new(1, 0, 0, 46),
		position = UDim2.fromOffset(0, 0),
		stroke = 3,
	})

	costText = C.Label(body, {
		name = "Cost",
		text = "Cost: $0",
		color = Colors.TextDark,
		size = UDim2.new(1, 0, 0, 26),
		position = UDim2.fromOffset(0, 52),
		stroke = 0,
	})

	local bar = Instance.new("Frame")
	bar.Name = "Progress"
	bar.BackgroundColor3 = Colors.PanelDark
	bar.Position = UDim2.new(0.5, 0, 0, 86)
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Size = UDim2.new(0.9, 0, 0, 18)
	bar.Parent = body
	C.Corner(bar, 9)
	C.Stroke(bar, 2, Colors.Stroke, true)
	progressFill = Instance.new("Frame")
	progressFill.Name = "Fill"
	progressFill.BackgroundColor3 = Colors.Pink
	progressFill.Size = UDim2.fromScale(0, 1)
	progressFill.Parent = bar
	C.Corner(progressFill, 9)

	C.Label(body, {
		name = "Resets",
		text = "Resets: cash, cows and upgrades.\nKeeps: crates, index, quests and boosts.",
		color = Colors.GreyDark,
		size = UDim2.new(1, 0, 0, 46),
		position = UDim2.fromOffset(0, 112),
		stroke = 0,
	})

	confirm, confirmCaption = C.Button(body, {
		name = "Confirm",
		text = "REBIRTH!",
		font = Theme.TitleFont,
		color = Colors.Pink,
		size = UDim2.fromOffset(260, 72),
		position = UDim2.new(0.5, 0, 1, -4),
		anchor = Vector2.new(0.5, 1),
		onClick = function()
			if not armed then
				armed = true
				armToken += 1
				local token = armToken
				confirmCaption.Text = "SURE? TAP AGAIN"
				C.SetButtonColor(confirm, Colors.Red)
				task.delay(3, function()
					if armed and armToken == token then
						disarm()
					end
				end)
				return
			end
			disarm()
			Net.Event("RequestRebirth"):FireServer()
			Panels.ClosePanel()
		end,
	})
end

function RebirthPanel:Start()
	DataController:OnChanged("cash", refresh)
	DataController:OnChanged("rebirths", refresh)
	Panels.OnPanelOpened("Rebirth", function()
		disarm()
		refresh()
	end)
	refresh()
end

return RebirthPanel
