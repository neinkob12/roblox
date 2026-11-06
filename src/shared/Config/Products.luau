--!strict
-- Robux products. IDs are 0 until the user creates them in Creator Hub and pastes them here.
-- Owner: Monetization session (B3).

local Products = {}

-- Gamepasses (one-time, permanent)
Products.Passes = {
	DoubleCash = { id = 0, name = "2x Cash Forever", robux = 199 },
	AutoMerge = { id = 0, name = "Auto Merge", robux = 149 },
	AutoSell = { id = 0, name = "Auto Sell", robux = 249 },
}

-- Developer products (repeatable)
Products.DevProducts = {
	CashSmall = { id = 0, name = "Cash Pack S", robux = 25, productionSeconds = 600 },
	CashMedium = { id = 0, name = "Cash Pack M", robux = 99, productionSeconds = 3600 },
	CashLarge = { id = 0, name = "Cash Pack L", robux = 299, productionSeconds = 4 * 3600 },
	PremiumCrate = { id = 0, name = "Premium Milk Crate", robux = 49 },
	Boost3x = { id = 0, name = "3x Cash (15 min)", robux = 39, boostSeconds = 15 * 60 },
}

return Products
