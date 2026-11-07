--!strict
-- Robux products. IDs are 0 until the user creates them in Creator Hub and pastes them here.
-- See docs/MONETIZATION_SETUP.md for the click-by-click guide.
-- Owner: Monetization session (B3). Shared so the UI (B1) can show names, prices and cash pack amounts.
--
-- UI usage (client):
--   MarketplaceService:PromptGamePassPurchase(player, Products.Passes.DoubleCash.id)
--   MarketplaceService:PromptProductPurchase(player, Products.DevProducts.CashSmall.id)
--   Only show / enable a buy button when its id ~= 0 (Products.IsConfigured(entry)).
--   Pass ownership: read the player attribute in `attribute` (e.g. Pass_DoubleCash).
--   Cash pack preview: Products.CashPackAmount(Multipliers.MilkPerSecond(p, data), Multipliers.Cash(p, data), entry)

export type Pass = { id: number, name: string, robux: number, attribute: string }
export type DevProduct = {
	id: number,
	name: string,
	robux: number,
	productionSeconds: number?,
	boostSeconds: number?,
}

local Products = {}

-- Gamepasses (one-time, permanent). `attribute` is the Player attribute MonetizationService sets.
Products.Passes = {
	DoubleCash = { id = 0, name = "2x Cash Forever", robux = 199, attribute = "Pass_DoubleCash" },
	AutoMerge = { id = 0, name = "Auto Merge", robux = 149, attribute = "Pass_AutoMerge" },
	AutoSell = { id = 0, name = "Auto Sell", robux = 249, attribute = "Pass_AutoSell" },
} :: { [string]: Pass }

-- Developer products (repeatable)
Products.DevProducts = {
	CashSmall = { id = 0, name = "Cash Pack S", robux = 25, productionSeconds = 600 },
	CashMedium = { id = 0, name = "Cash Pack M", robux = 99, productionSeconds = 3600 },
	CashLarge = { id = 0, name = "Cash Pack L", robux = 299, productionSeconds = 4 * 3600 },
	PremiumCrate = { id = 0, name = "Premium Milk Crate", robux = 49 },
	Boost3x = { id = 0, name = "3x Cash (15 min)", robux = 39, boostSeconds = 15 * 60 },
} :: { [string]: DevProduct }

-- Tuning
Products.CashPackMinimum = 1000 -- a cash pack always gives at least this much
Products.Boost3xMult = 3
Products.Boost3xKey = "robux3x" -- key inside data.boosts
Products.PurchaseIdCacheSize = 50 -- last N receipt PurchaseIds kept in data.purchases (idempotency)
Products.PassCheckRetries = 3

function Products.IsConfigured(entry: { id: number }): boolean
	return entry.id ~= 0
end

-- Same formula on server (grant) and client (preview): seconds of current production, cash multipliers applied.
function Products.CashPackAmount(milkPerSecond: number, cashMultiplier: number, entry: DevProduct): number
	local seconds = entry.productionSeconds or 0
	local amount = milkPerSecond * seconds * cashMultiplier
	if amount ~= amount or amount == math.huge then
		amount = 0
	end
	return math.floor(math.max(Products.CashPackMinimum, amount))
end

-- Reverse lookups by Roblox id -> key. Ids of 0 are skipped.
Products.PassKeyById = {} :: { [number]: string }
for key, pass in Products.Passes do
	if pass.id ~= 0 then
		Products.PassKeyById[pass.id] = key
	end
end
Products.ProductKeyById = {} :: { [number]: string }
for key, product in Products.DevProducts do
	if product.id ~= 0 then
		Products.ProductKeyById[product.id] = key
	end
end

return Products
