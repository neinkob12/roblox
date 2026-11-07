--!strict
-- C4: Onboarding tutorial for brand-new players. Pure data + small shared helpers (no Init/Start).
--
-- data.tutorialStep meaning:
--   0            not started (client asks for step 1 on join)
--   1 .. #Steps  that step is currently shown
--   Tutorial.Done (7) finished or skipped, never shown again
--
-- Each step has a `done(data, ctx)` check that BOTH sides run:
--   client: TutorialController polls it and sends RequestTutorialStep(current + 1)
--   server: TutorialService re-checks it before accepting the request
-- ctx is per side and per step: { startedAt = os.clock() when the step began,
--   baseEarned = server only, data.totalCashEarned when the step began,
--   collected = client only, true once dairyCash dropped from > 0 to 0 }

export type Ctx = {
	startedAt: number,
	baseEarned: number?,
	collected: boolean?,
}

export type Target = {
	scope: "plot" | "dairy",
	name: string,
}

export type Step = {
	id: string,
	text: string,
	target: Target,
	done: (data: any, ctx: Ctx) -> boolean,
	autoSeconds: number?, -- info steps: advance after this many seconds
}

local Tutorial = {}

Tutorial.Done = 7

-- Players who already played before the tutorial existed skip it automatically.
Tutorial.VeteranCashEarned = 5000
-- How long the client waits for a target part to exist before asking to skip the step.
Tutorial.TargetWaitSeconds = 12
-- Client polling interval for step conditions, and how long to wait before resending a request.
Tutorial.PollSeconds = 0.25
Tutorial.ResendSeconds = 3
-- Server: minimum seconds between two accepted requests from one player.
Tutorial.RequestCooldown = 0.2
-- Server: slack for timed (info) steps, since the client starts its timer a bit later.
Tutorial.TimedSlackSeconds = 1.5

-- 3D arrow + beam look
Tutorial.ArrowHeight = 4 -- studs above the top of the target part
Tutorial.ArrowBounce = 0.8 -- studs
Tutorial.ArrowBounceSpeed = 3 -- radians per second
Tutorial.ArrowSpinSpeed = 1.5 -- radians per second
Tutorial.ArrowColor = Color3.fromRGB(255, 215, 60)

-- Info steps (no action needed) advance on their own after this long.
local INFO_SECONDS = 8

local function ownsTier2Plus(data: any): boolean
	local cows = data.cows
	if type(cows) ~= "table" then
		return false
	end
	for key, count in cows do
		local tier = tonumber(key)
		if tier and tier >= 2 and type(count) == "number" and count > 0 then
			return true
		end
	end
	return false
end

Tutorial.Steps = {
	{
		id = "fill",
		text = "Fill your milk can at the tank!",
		target = { scope = "plot", name = "TankTap" },
		done = function(data, _ctx)
			return (data.canMilk or 0) > 0
		end,
	},
	{
		id = "deposit",
		text = "Bring the milk to the Dairy! (high Milk x = more cash)",
		target = { scope = "dairy", name = "DepositPad" },
		done = function(data, _ctx)
			-- the queue can sell out fast, so already-sold cash also counts
			return (data.canMilk or 0) <= 0 and ((data.dairyQueue or 0) > 0 or (data.dairyCash or 0) > 0)
		end,
	},
	{
		id = "collect",
		text = "Collect your cash!",
		target = { scope = "dairy", name = "CashPad" },
		done = function(data, ctx)
			if ctx.collected then
				return true
			end
			local base = ctx.baseEarned
			return base ~= nil and (data.totalCashEarned or 0) > base
		end,
	},
	{
		id = "buy",
		text = "Buy 2 more cows! (Need cash? Sell more milk!)",
		target = { scope = "plot", name = "BuyPad1" },
		done = function(data, _ctx)
			return (data.cowsBought or 0) >= 2
		end,
	},
	{
		id = "merge",
		text = "Merge 3 cows into a new one!",
		target = { scope = "plot", name = "MergePad" },
		done = function(data, _ctx)
			return ownsTier2Plus(data)
		end,
	},
	{
		id = "price",
		text = "Keep going: fill, sell, buy, merge! Open Quests for rewards",
		target = { scope = "plot", name = "TankTap" },
		autoSeconds = INFO_SECONDS,
		done = function(_data, ctx)
			return os.clock() - ctx.startedAt >= INFO_SECONDS
		end,
	},
} :: { Step }

-- The player's plot Model, found by the PlotId attribute (works on client and server).
function Tutorial.FindPlot(player: Player): Instance?
	local plotId = player:GetAttribute("PlotId")
	local plots = workspace:FindFirstChild("Plots")
	if type(plotId) ~= "number" or not plots then
		return nil
	end
	for _, plot in plots:GetChildren() do
		if plot:GetAttribute("PlotId") == plotId then
			return plot
		end
	end
	return nil
end

-- The BasePart a step points at, or nil if it doesn't exist (yet).
function Tutorial.FindTarget(player: Player, step: Step): BasePart?
	local parent: Instance? = nil
	if step.target.scope == "dairy" then
		parent = workspace:FindFirstChild("Dairy")
	else
		parent = Tutorial.FindPlot(player)
	end
	if not parent then
		return nil
	end
	local inst = parent:FindFirstChild(step.target.name)
	if inst and inst:IsA("BasePart") then
		return inst
	end
	return nil
end

-- Did the player already play before the tutorial existed?
function Tutorial.IsVeteran(data: any): boolean
	return (data.rebirths or 0) > 0 or (data.totalCashEarned or 0) >= Tutorial.VeteranCashEarned
end

return Tutorial
