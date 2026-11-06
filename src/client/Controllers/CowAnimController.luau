--!strict
-- Client-only idle animation for every cow model in workspace.Plots (keeps the server cheap).
-- Owner: A2.
--
-- Each cow (a Model with attribute CowTier, built by CowModels) gets:
--   * a soft bob + side wiggle on its Root (all other parts are welded to Root)
--   * a random head turn every few seconds via the "Neck" Motor6D
--   * a little "pop" hop when it first appears (new tier in a stall)
-- Driven by one Heartbeat loop with sine waves instead of thousands of Tween objects.
-- Cows farther than ANIM_DISTANCE from the camera are skipped.

local RunService = game:GetService("RunService")

local ANIM_DISTANCE = 140
local BOB_HEIGHT = 0.12
local WIGGLE_DEG = 3
local HOP_TIME = 0.45
local HOP_HEIGHT = 1.6
local TURN_TIME = 0.35

type CowAnim = {
	model: Model,
	root: BasePart,
	baseCF: CFrame,
	neck: Motor6D?,
	neckBase: CFrame,
	phase: number,
	speed: number,
	born: number,
	turnFrom: Vector2, -- (yaw, pitch) in radians
	turnTo: Vector2,
	turnStart: number,
	nextTurn: number,
}

local CowAnimController = {}

local cows: { [Model]: CowAnim } = {}
local rng = Random.new()

local function easeInOut(t: number): number
	return t * t * (3 - 2 * t)
end

local function register(model: Model)
	if cows[model] then
		return
	end
	local root = model:WaitForChild("Root", 10)
	if not root or not root:IsA("BasePart") or not model.Parent then
		return
	end
	local head = model:FindFirstChild("Head")
	local neck = head and head:FindFirstChild("Neck")
	local motor: Motor6D? = if neck and neck:IsA("Motor6D") then neck else nil
	local now = os.clock()
	cows[model] = {
		model = model,
		root = root,
		baseCF = root.CFrame,
		neck = motor,
		neckBase = if motor then motor.C0 else CFrame.identity,
		phase = rng:NextNumber(0, math.pi * 2),
		speed = rng:NextNumber(1.6, 2.4),
		born = now,
		turnFrom = Vector2.zero,
		turnTo = Vector2.zero,
		turnStart = now,
		nextTurn = now + rng:NextNumber(1, 4),
	}
end

local function onDescendant(inst: Instance)
	if inst:IsA("Model") and inst:GetAttribute("CowTier") ~= nil then
		task.spawn(register, inst)
	end
end

local function step()
	local camera = workspace.CurrentCamera
	local camPos = if camera then camera.CFrame.Position else Vector3.zero
	local now = os.clock()
	for model, c in cows do
		if not model.Parent or not c.root.Parent then
			cows[model] = nil
			continue
		end
		if (c.baseCF.Position - camPos).Magnitude > ANIM_DISTANCE then
			continue
		end
		local t = now * c.speed + c.phase
		local bob = math.abs(math.sin(t)) * BOB_HEIGHT
		local roll = math.sin(t) * math.rad(WIGGLE_DEG)
		local yaw = math.sin(t * 0.5) * math.rad(WIGGLE_DEG)

		local age = now - c.born
		if age < HOP_TIME then
			local k = age / HOP_TIME
			bob += math.sin(math.pi * k) * HOP_HEIGHT
			roll = 0
		end
		c.root.CFrame = c.baseCF * CFrame.new(0, bob, 0) * CFrame.Angles(0, yaw, roll)

		local neck = c.neck
		if neck and neck.Parent then
			if now >= c.nextTurn then
				c.turnFrom = c.turnTo
				-- sometimes look straight ahead, otherwise look around
				if rng:NextNumber() < 0.3 then
					c.turnTo = Vector2.zero
				else
					c.turnTo = Vector2.new(math.rad(rng:NextNumber(-40, 40)), math.rad(rng:NextNumber(-12, 15)))
				end
				c.turnStart = now
				c.nextTurn = now + rng:NextNumber(1.8, 5)
			end
			local k = easeInOut(math.clamp((now - c.turnStart) / TURN_TIME, 0, 1))
			local cur = c.turnFrom:Lerp(c.turnTo, k)
			neck.C0 = c.neckBase * CFrame.Angles(cur.Y, cur.X, 0)
		end
	end
end

function CowAnimController:Start()
	local plots = workspace:WaitForChild("Plots", 60)
	if not plots then
		return
	end
	for _, d in plots:GetDescendants() do
		onDescendant(d)
	end
	plots.DescendantAdded:Connect(onDescendant)
	RunService.Heartbeat:Connect(step)
end

return CowAnimController
