--!strict
-- Redeemable codes (B2 CodesService). Keys are UPPERCASE; players type them in any case.
-- Each player can redeem each code once (data.redeemedCodes[CODE] = true).
--
-- reward.kind: "cash" (amount) | "crates" (amount) | "boost" (boostKind "cash" | "production", mult, seconds)
-- expires: optional os.time() after which the code stops working (nil = never).
--   Tip: get a timestamp with os.time({year=2026, month=12, day=31, hour=23}) in the command bar.

local Codes = {}

export type Code = {
	reward: { [string]: any },
	expires: number?,
}

Codes.List = {
	MOOO = { reward = { kind = "boost", boostKind = "cash", mult = 2, seconds = 5 * 60 } },
	BRAINROT = { reward = { kind = "crates", amount = 1 } },
	RELEASE = { reward = { kind = "boost", boostKind = "cash", mult = 3, seconds = 10 * 60 } },
} :: { [string]: Code }

Codes.MaxLength = 32
Codes.CooldownSeconds = 1 -- per player, between redeem attempts

return Codes
