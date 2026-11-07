--!strict
-- B1: Upgrades panel. One row per Config/Upgrades entry: name, level, effect, cost.
-- Buy fires RequestUpgrade(id); the button is grey when you can't afford it or it's maxed.
-- The server (A4 UpgradeService) validates everything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Format = require(ReplicatedStorage.Shared.Format)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local Theme = require(script.Parent.Parent.Lib.Theme)
local C = require(script.Parent.Parent.Lib.UiKit)
local Panels = require(script.Parent.Components)
local DataController = require(script.Parent.Parent.Controllers.DataController)
local Capacity = require(ReplicatedStorage.Shared.Capacity)

local Colors = Theme.Colors

local UpgradesPanel = {}

type Row = { level: TextLabel, effect: TextLabel, buy: TextButton, caption: TextLabel }
local rows: { [string]: Row } = {}

-- Human readable total effect at a level (matches the descriptions in Config/Upgrades).
local function effectText(u: Upgrades.Upgrade, level: number): string
	if u.id == "walkSpeed" then
		return `+{Format.Number(level * u.perLevel)} walk speed`
	elseif u.id == "autoCollect" then
		if level <= 0 then
			return "Off"
		end
		local secs = Capacity.AutoCollectInterval(level)
		return `Fills can every {secs}s`
	end
	return `+{Format.Number(level * u.perLevel * 100)}%`
end

local function refresh()
	local data = DataController:Get()
	if not data then
		return
	end
	local cash = if typeof(data.cash) == "number" then data.cash else 0
	local levels = if typeof(data.upgrades) == "table" then data.upgrades else {}
	for _, u in Upgrades.List do
		local row = rows[u.id]
		if row then
			local level = levels[u.id] or 0
			row.level.Text = `Lv {level}/{u.maxLevel}`
			row.effect.Text = `{u.description}\nNow: {effectText(u, level)}`
			if level >= u.maxLevel then
				row.caption.Text = "MAX"
				C.SetButtonEnabled(row.buy, false)
			else
				local cost = Upgrades.Cost(u.id, level)
				row.caption.Text = Format.Cash(cost)
				C.SetButtonEnabled(row.buy, cash >= cost)
			end
		end
	end
end

function UpgradesPanel:Init()
	local _, body = Panels.Panel("Upgrades", "UPGRADES", Vector2.new(560, 360), Colors.Green)
	local list = C.ScrollList(body, 8)
	for i, u in Upgrades.List do
		local card = C.Card(list, 84, i)
		C.Label(card, {
			name = "Name",
			text = u.name,
			color = Colors.TextDark,
			size = UDim2.fromOffset(220, 26),
			position = UDim2.fromOffset(12, 6),
			align = Enum.TextXAlignment.Left,
			stroke = 0,
		})
		local level = C.Label(card, {
			name = "Level",
			text = "Lv 0",
			color = Colors.BlueDark,
			size = UDim2.fromOffset(90, 22),
			position = UDim2.fromOffset(236, 8),
			align = Enum.TextXAlignment.Left,
			stroke = 0,
		})
		local effect = C.Label(card, {
			name = "Effect",
			text = u.description,
			color = Colors.GreyDark,
			size = UDim2.new(1, -170, 0, 44),
			position = UDim2.fromOffset(12, 34),
			align = Enum.TextXAlignment.Left,
			stroke = 0,
		})
		local buy, caption = C.Button(card, {
			name = "Buy",
			text = "$0",
			color = Colors.Green,
			size = UDim2.fromOffset(140, Theme.MinTouch),
			position = UDim2.new(1, -10, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			onClick = function()
				Net.Event("RequestUpgrade"):FireServer(u.id)
			end,
		})
		rows[u.id] = { level = level, effect = effect, buy = buy, caption = caption }
	end
end

function UpgradesPanel:Start()
	DataController:OnChanged("cash", refresh)
	DataController:OnChanged("upgrades", refresh)
	Panels.OnPanelOpened("Upgrades", refresh)
	refresh()
end

return UpgradesPanel
