--!strict
-- B1: Robux shop. Lists Config/Products gamepasses and dev products and prompts the purchase
-- with MarketplaceService. B3 MonetizationService grants the rewards on the server.
-- Owned passes (Player attribute Pass_<Key>) show "OWNED". Products whose id is still 0
-- show "Soon" and only toast instead of prompting.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)
local Products = require(ReplicatedStorage.Shared.Config.Products)
local Theme = require(script.Parent.Parent.Lib.Theme)
local C = require(script.Parent.Parent.Lib.UiKit)
local Panels = require(script.Parent.Components)
local Notifications = require(script.Parent.Notifications)

local player = Players.LocalPlayer
local Colors = Theme.Colors

local PASS_ORDER = { "DoubleCash", "AutoMerge", "AutoSell" }
local PRODUCT_ORDER = { "Boost3x", "PremiumCrate", "CashSmall", "CashMedium", "CashLarge" }

local PASS_INFO = {
	DoubleCash = { icon = "💰", text = "All cash x2, forever" },
	AutoMerge = { icon = "🧬", text = "Merges your cows automatically" },
	AutoSell = { icon = "🚚", text = "Your can sells itself from anywhere" },
}

local ShopPanel = {}

type PassRow = { key: string, buy: TextButton, caption: TextLabel, robux: number }
local passRows: { PassRow } = {}

local function productInfo(key: string, def: any): string
	if typeof(def.productionSeconds) == "number" then
		return `Cash worth {Format.Time(def.productionSeconds)} of production`
	elseif key == "PremiumCrate" then
		return "Opens instantly, better odds!"
	elseif typeof(def.boostSeconds) == "number" then
		return `Triple cash for {Format.Time(def.boostSeconds)}`
	end
	return ""
end

local function refreshPasses()
	for _, row in passRows do
		if player:GetAttribute("Pass_" .. row.key) then
			row.caption.Text = "OWNED"
			C.SetButtonEnabled(row.buy, false)
		else
			row.caption.Text = `R$ {row.robux}`
			C.SetButtonEnabled(row.buy, true)
		end
	end
end

local function prompt(kind: "pass" | "product", id: number)
	if id == 0 then
		Notifications.Show("This item is coming soon!", "info")
		return
	end
	local ok, err = pcall(function()
		if kind == "pass" then
			MarketplaceService:PromptGamePassPurchase(player, id)
		else
			MarketplaceService:PromptProductPurchase(player, id)
		end
	end)
	if not ok then
		warn(`[ShopPanel] prompt failed: {err}`)
	end
end

local function row(list: Instance, order: number, icon: string, name: string, info: string): Frame
	local card = C.Card(list, 74, order)
	C.Label(card, {
		name = "Icon",
		text = icon,
		size = UDim2.fromOffset(50, 50),
		position = UDim2.fromOffset(10, 10),
		stroke = 0,
	})
	C.Label(card, {
		name = "Name",
		text = name,
		color = Colors.TextDark,
		size = UDim2.new(1, -230, 0, 26),
		position = UDim2.fromOffset(70, 8),
		align = Enum.TextXAlignment.Left,
		stroke = 0,
	})
	C.Label(card, {
		name = "Info",
		text = info,
		color = Colors.GreyDark,
		size = UDim2.new(1, -230, 0, 22),
		position = UDim2.fromOffset(70, 40),
		align = Enum.TextXAlignment.Left,
		stroke = 0,
	})
	return card
end

local function header(list: Instance, order: number, text: string)
	local l = C.Label(list, {
		name = "Header",
		text = text,
		font = Theme.TitleFont,
		color = Colors.PurpleDark,
		size = UDim2.new(1, 0, 0, 28),
		align = Enum.TextXAlignment.Left,
		stroke = 0,
		order = order,
	})
	return l
end

function ShopPanel:Init()
	local _, body = Panels.Panel("Shop", "SHOP", Vector2.new(580, 370), Colors.Purple)
	local list = C.ScrollList(body, 8)
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	header(list, nextOrder(), "GAMEPASSES")
	local passes: any = Products.Passes
	for _, key in PASS_ORDER do
		local def = passes[key]
		if def then
			local info = PASS_INFO[key] or { icon = "⭐", text = "" }
			local card = row(list, nextOrder(), info.icon, def.name, info.text)
			local id: number = def.id
			local buy, caption = C.Button(card, {
				name = "Buy",
				text = `R$ {def.robux}`,
				color = Colors.Green,
				size = UDim2.fromOffset(140, Theme.MinTouch),
				position = UDim2.new(1, -10, 0.5, 0),
				anchor = Vector2.new(1, 0.5),
				onClick = function()
					prompt("pass", id)
				end,
			})
			table.insert(passRows, { key = key, buy = buy, caption = caption, robux = def.robux })
		end
	end

	header(list, nextOrder(), "BOOSTS & PACKS")
	local products: any = Products.DevProducts
	for _, key in PRODUCT_ORDER do
		local def = products[key]
		if def then
			local icon = if key == "PremiumCrate" then "📦" elseif key == "Boost3x" then "⚡" else "💵"
			local card = row(list, nextOrder(), icon, def.name, productInfo(key, def))
			local id: number = def.id
			C.Button(card, {
				name = "Buy",
				text = `R$ {def.robux}`,
				color = Colors.Green,
				size = UDim2.fromOffset(140, Theme.MinTouch),
				position = UDim2.new(1, -10, 0.5, 0),
				anchor = Vector2.new(1, 0.5),
				onClick = function()
					prompt("product", id)
				end,
			})
		end
	end
end

function ShopPanel:Start()
	for _, key in PASS_ORDER do
		player:GetAttributeChangedSignal("Pass_" .. key):Connect(refreshPasses)
	end
	Panels.OnPanelOpened("Shop", refreshPasses)
	refreshPasses()
end

return ShopPanel
