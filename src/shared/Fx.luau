--!strict
-- C5 Juice: shared kinds, payload types and tuning for the "Fx" remote.
-- Server fires:  Net.Event("Fx"):FireClient(player, kind, payload)
-- Client renders it in src/client/Controllers/FxController.luau.
--
-- Kinds and payloads (every field is optional, the client falls back to world part names):
--   "cash"    { amount: number }               collected dairy cash at Dairy.CashPad
--   "deposit" { amount: number }               milk deposited at Dairy.DepositPad
--   "merge"   { count: number, tier: number }  merges done, highest new tier (stall to pop)
--   "buy"     { count: number }                tier-1 cows bought (drop into Stall1)
--   "rare"    { kind: string }                 "golden" | "diamond" rare milk
--   "crate"   { position: Vector3 }            mystery crate picked up at this position

export type CashPayload = { amount: number? }
export type DepositPayload = { amount: number? }
export type MergePayload = { count: number?, tier: number? }
export type BuyPayload = { count: number? }
export type RarePayload = { kind: string? }
export type CratePayload = { position: Vector3? }

local Fx = {}

Fx.Kind = {
	Cash = "cash",
	Deposit = "deposit",
	Merge = "merge",
	Buy = "buy",
	Rare = "rare",
	Crate = "crate",
}

-- Performance caps (keep it smooth on phones)
Fx.MaxActiveEffects = 12 -- concurrent effect "jobs"; extra requests are dropped
Fx.CoinPoolSize = 48 -- total coin Parts ever created
Fx.TextPoolSize = 8 -- floating BillboardGuis ever created
Fx.MaxDropCows = 5 -- cow clones per "buy" drop-in
Fx.MaxDistance = 220 -- skip world effects farther than this from the camera

-- Coin burst (cash)
Fx.Coins = {
	Min = 4,
	Max = 16,
	Flight = 0.7, -- seconds pad -> player
	Stagger = 0.035, -- seconds between coins
	ArcHeight = 7,
	Size = Vector3.new(0.25, 1.3, 1.3),
	Color = Color3.fromRGB(255, 205, 50),
}

-- Floating "+$X" text
Fx.Text = {
	Rise = 5, -- studs
	Life = 1.3, -- seconds
	BigSize = UDim2.fromOffset(320, 90),
	SmallSize = UDim2.fromOffset(200, 56),
	CashColor = Color3.fromRGB(120, 255, 120),
	MilkColor = Color3.fromRGB(240, 250, 255),
	MergeColor = Color3.fromRGB(255, 220, 80),
	StrokeColor = Color3.fromRGB(30, 20, 10),
}

-- data.settings.reduceMotion: shake, screen glow, merge flash and cow pop are skipped, and
-- these keep the rest calm (no spin or wide arcs, no bounce or overshoot)
Fx.Calm = {
	CoinArcScale = 0.25,
	DropHeight = 3,
}

-- Rare milk screen-edge glow + camera shake
export type RareStyle = { color: Color3, shake: number, label: string }

-- keyed by Economy.RareMilk[].id; shake = max camera wobble in degrees
Fx.RareStyles = {
	golden = { color = Color3.fromRGB(255, 200, 40), shake = 0.8, label = "GOLDEN MILK!" },
	diamond = { color = Color3.fromRGB(110, 230, 255), shake = 1.3, label = "DIAMOND MILK!" },
} :: { [string]: RareStyle }

Fx.Rare = {
	GlowTime = 1.6,
	ShakeTime = 0.45,
	GlowStrength = 0.55, -- 0..1, opacity at the screen edge
}

-- Pads
Fx.Pad = {
	-- Pads are thin slabs, so the squish is a client-only jelly copy (X/Z squeeze + overshoot).
	-- The real pad is hidden with LocalTransparencyModifier and never moves (no extra touches).
	SquishScale = 0.84, -- X/Z size factor at the bottom of the squish
	SquishTime = 0.32, -- whole animation, seconds
	Debounce = 0.4,
	PulseSpeed = 5, -- radians per second
	PulseAmount = 0.07, -- +-7% text scale
	-- label colors that mean "you can use this now" (set by A4 BuyService / MergeService)
	ReadyColors = {
		Color3.fromRGB(120, 255, 120), -- BuyService AFFORD_COLOR
		Color3.fromRGB(255, 220, 80), -- MergeService "n ready!"
	},
}

-- Plot pads that squish, plus Dairy pads (found by name, see CONTRACTS section 6)
Fx.PlotPads = { "BuyPad1", "BuyPad5", "BuyPad25", "MergePad", "TankTap" }
Fx.PulsePads = { "BuyPad1", "BuyPad5", "BuyPad25", "MergePad" }
Fx.DairyPads = { "DepositPad", "CashPad" }

-- A cash increase with no "cash" Fx within this window gets a small derived "+$X" pop
Fx.DerivedCashWindow = 0.35

return Fx
