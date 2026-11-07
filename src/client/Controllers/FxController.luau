--!strict
-- C5 Juice. Renders the server "Fx" remote (kind, payload) and a few effects derived from
-- data changes. Everything here is client-only and purely visual.
--
--   cash    coin burst CashPad -> player + big floating "+$X"
--   deposit milk splash + ring at DepositPad
--   merge   flash, sparkles and a pop-scale on the merged stall's cow + "MERGED!"
--   buy     tier-1 cows drop into Stall1 with a bounce + "+N cows"
--   rare    golden / diamond screen-edge glow + light camera shake (both skipped with reduceMotion)
--   crate   beam of light where the crate was picked up
--   pads    pads squish when the local player steps on them, labels pulse when ready
--
-- Performance: one Heartbeat loop drives every animation, coins / texts / shapes are pooled,
-- and at most Fx.MaxActiveEffects effects run at once (extra requests are dropped).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Fx = require(ReplicatedStorage.Shared.Fx)
local Format = require(ReplicatedStorage.Shared.Format)
local CowModels = require(ReplicatedStorage.Shared.CowModels)
local Theme = require(script.Parent.Parent.UI.Theme)
local DataController = require(script.Parent.DataController)
local Safe = require(ReplicatedStorage.Shared.Safe)

local player = Players.LocalPlayer

local FxController = {}

local PARK = CFrame.new(0, -10000, 0)
local FONT = Enum.Font.LuckiestGuy

local fxFolder: Folder
local glowFrames: { Frame } = {}

----------------------------------------------------------------------------- helpers

local function num(v: any, default: number): number
	if typeof(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then
		return v
	end
	return default
end

local function vec(v: any): Vector3?
	if typeof(v) == "Vector3" then
		return v
	end
	return nil
end

local function clamp01(t: number): number
	return math.clamp(t, 0, 1)
end

local function easeOutQuad(t: number): number
	return 1 - (1 - t) * (1 - t)
end

local function bounceOut(t: number): number
	local n, d = 7.5625, 2.75
	if t < 1 / d then
		return n * t * t
	elseif t < 2 / d then
		t -= 1.5 / d
		return n * t * t + 0.75
	elseif t < 2.5 / d then
		t -= 2.25 / d
		return n * t * t + 0.9375
	end
	t -= 2.625 / d
	return n * t * t + 0.984375
end

local function reducedMotion(): boolean
	local data = DataController:Get()
	if data and typeof(data.settings) == "table" and data.settings.reduceMotion == true then
		return true
	end
	local ok, value = pcall(function()
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and value == true
end

local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function getPlot(): Instance?
	local id = player:GetAttribute("PlotId")
	local plots = workspace:FindFirstChild("Plots")
	if typeof(id) ~= "number" or not plots then
		return nil
	end
	return plots:FindFirstChild("Plot" .. id)
end

local function plotPart(name: string): BasePart?
	local plot = getPlot()
	local p = plot and plot:FindFirstChild(name)
	if p and p:IsA("BasePart") then
		return p
	end
	return nil
end

local function dairyPart(name: string): BasePart?
	local dairy = workspace:FindFirstChild("Dairy")
	local p = dairy and dairy:FindFirstChild(name)
	if p and p:IsA("BasePart") then
		return p
	end
	return nil
end

local function getStall(tier: number): BasePart?
	local plot = getPlot()
	local stalls = plot and plot:FindFirstChild("Stalls")
	local stall = stalls and stalls:FindFirstChild("Stall" .. tier)
	if stall and stall:IsA("BasePart") then
		return stall
	end
	return nil
end

local function stallTop(stall: BasePart): Vector3
	local anchor = stall:FindFirstChild("CowAnchor")
	if anchor and anchor:IsA("Attachment") then
		return anchor.WorldPosition
	end
	return stall.Position + Vector3.new(0, stall.Size.Y / 2, 0)
end

local function nearCamera(pos: Vector3): boolean
	local camera = workspace.CurrentCamera
	if not camera then
		return true
	end
	return (camera.CFrame.Position - pos).Magnitude <= Fx.MaxDistance
end

local function fxPart(): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Transparency = 1
	p.CFrame = PARK
	return p
end

----------------------------------------------------------------------------- effect budget

local active = 0

-- Reserves one effect slot for `duration` seconds. Returns false when the budget is full.
local function begin(duration: number): boolean
	if active >= Fx.MaxActiveEffects then
		return false
	end
	active += 1
	task.delay(duration, function()
		active -= 1
	end)
	return true
end

----------------------------------------------------------------------------- frame loop

-- Each updater gets the frame time and returns false when it is finished.
local updaters: { (number) -> boolean } = {}

local function addUpdater(fn: (number) -> boolean)
	table.insert(updaters, fn)
end

local function step(dt: number)
	for i = #updaters, 1, -1 do
		local ok, alive = pcall(updaters[i], dt)
		if not ok then
			warn("[FxController] effect error: " .. tostring(alive))
		end
		if not ok or not alive then
			-- swap-remove (order does not matter)
			updaters[i] = updaters[#updaters]
			updaters[#updaters] = nil
		end
	end
end

-- Runs fn(t) every frame with t going 0 -> 1 over `duration`, then calls done().
local function animate(duration: number, fn: (number) -> (), done: (() -> ())?)
	local start = os.clock()
	addUpdater(function()
		local t = (os.clock() - start) / duration
		if t >= 1 then
			fn(1)
			if done then
				done()
			end
			return false
		end
		fn(t)
		return true
	end)
end

----------------------------------------------------------------------------- pools

local coinFree: { Part } = {}
local coinCount = 0

local function acquireCoin(): Part?
	local coin = table.remove(coinFree)
	if coin then
		return coin
	end
	if coinCount >= Fx.CoinPoolSize then
		return nil
	end
	coinCount += 1
	local p = fxPart()
	p.Name = "FxCoin"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Fx.Coins.Size
	p.Color = Fx.Coins.Color
	p.Material = Enum.Material.Metal
	p.Reflectance = 0.25
	p.Parent = fxFolder
	return p
end

local function releaseCoin(p: Part)
	p.Transparency = 1
	p.CFrame = PARK
	table.insert(coinFree, p)
end

local shapeFree: { Part } = {}

local function acquireShape(shape: Enum.PartType, color: Color3): Part
	local reused = table.remove(shapeFree)
	local part: Part
	if reused then
		part = reused
	else
		part = fxPart()
		part.Name = "FxShape"
		part.Parent = fxFolder
	end
	part.Shape = shape
	part.Color = color
	return part
end

local function releaseShape(p: Part)
	p.Transparency = 1
	p.CFrame = PARK
	if #shapeFree < 16 then
		table.insert(shapeFree, p)
	else
		p:Destroy()
	end
end

type TextItem = {
	part: Part,
	gui: BillboardGui,
	label: TextLabel,
	stroke: UIStroke,
	scale: UIScale,
}

local textFree: { TextItem } = {}
local textCount = 0

local function acquireText(): TextItem?
	local item = table.remove(textFree)
	if item then
		return item
	end
	if textCount >= Fx.TextPoolSize then
		return nil
	end
	textCount += 1
	local p = fxPart()
	p.Name = "FxText"
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Parent = fxFolder
	local gui = Instance.new("BillboardGui")
	gui.Name = "FxTextGui"
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = Fx.MaxDistance
	gui.ResetOnSpawn = false
	gui.Adornee = p
	gui.Enabled = false
	gui.Parent = p
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = FONT
	label.TextScaled = true
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Fx.Text.StrokeColor
	stroke.Parent = label
	local scale = Instance.new("UIScale")
	scale.Parent = label
	return { part = p, gui = gui, label = label, stroke = stroke, scale = scale }
end

local function releaseText(item: TextItem)
	item.gui.Enabled = false
	item.part.CFrame = PARK
	table.insert(textFree, item)
end

-- One emitter part per particle style; Emit() at a moved position (particles are world-space).
local sparkle: ParticleEmitter
local splash: ParticleEmitter

local function makeEmitter(name: string, props: { [string]: any }): ParticleEmitter
	local p = fxPart()
	p.Name = name
	p.Size = Vector3.new(1, 1, 1)
	p.Parent = fxFolder
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.LockedToPart = false
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = p
	return e
end

local function emitAt(e: ParticleEmitter, pos: Vector3, count: number, color: Color3?)
	local p = e.Parent
	if p and p:IsA("BasePart") then
		p.CFrame = CFrame.new(pos)
	end
	if color then
		e.Color = ColorSequence.new(color)
	end
	e:Emit(count)
end

----------------------------------------------------------------------------- building blocks

local function floatText(pos: Vector3, text: string, color: Color3, big: boolean?)
	local item = acquireText()
	if not item then
		return
	end
	item.label.Text = text
	item.label.TextColor3 = color
	item.label.TextTransparency = 0
	item.stroke.Transparency = 0
	item.scale.Scale = 0
	item.gui.Size = if big then Fx.Text.BigSize else Fx.Text.SmallSize
	item.part.CFrame = CFrame.new(pos)
	item.gui.Enabled = true
	local jitter = Vector3.new((math.random() - 0.5) * 1.5, 0, (math.random() - 0.5) * 1.5)
	animate(Fx.Text.Life, function(t)
		item.part.CFrame = CFrame.new(pos + jitter + Vector3.new(0, Fx.Text.Rise * easeOutQuad(t), 0))
		local s = if t < 0.12 then t / 0.12 * 1.25 elseif t < 0.22 then 1.25 - (t - 0.12) / 0.1 * 0.25 else 1
		item.scale.Scale = s
		local fade = if t > 0.6 then (t - 0.6) / 0.4 else 0
		item.label.TextTransparency = fade
		item.stroke.Transparency = fade
	end, function()
		releaseText(item)
	end)
end

-- Expanding, fading neon shape. `from`/`to` are sizes, cf is the shape's CFrame.
local function flash(cf: CFrame, shape: Enum.PartType, color: Color3, from: Vector3, to: Vector3, life: number)
	local p = acquireShape(shape, color)
	p.Size = from
	p.CFrame = cf
	p.Transparency = 0.2
	animate(life, function(t)
		local e = easeOutQuad(t)
		p.Size = from:Lerp(to, e)
		p.CFrame = cf
		p.Transparency = 0.2 + 0.8 * t
	end, function()
		releaseShape(p)
	end)
end

local function coinBurst(from: Vector3, count: number)
	local coins = Fx.Coins
	for i = 1, count do
		local coin = acquireCoin()
		if not coin then
			return
		end
		local c = coin :: Part
		local side = Vector3.new((math.random() - 0.5) * 8, 0, (math.random() - 0.5) * 8)
		local spin = (math.random() * 2 - 1) * 4 + 14
		task.delay((i - 1) * coins.Stagger, function()
			c.Transparency = 0
			local start = from + Vector3.new(0, 0.5, 0)
			local lastTarget = start
			animate(coins.Flight, function(t)
				local root = rootPart()
				local target = if root then root.Position else lastTarget
				lastTarget = target
				local ctrl = (start + target) / 2 + side + Vector3.new(0, coins.ArcHeight, 0)
				local a = start:Lerp(ctrl, t)
				local b = ctrl:Lerp(target, t)
				local pos = a:Lerp(b, t)
				local shrink = if t > 0.85 then 1 - (t - 0.85) / 0.15 else 1
				c.Size = coins.Size * math.max(shrink, 0.05)
				c.CFrame = CFrame.new(pos) * CFrame.Angles(0, t * spin, 0)
			end, function()
				c.Size = coins.Size
				releaseCoin(c)
			end)
		end)
	end
end

-- Pops a model's scale up and back (used on the merged stall's cow).
local function popScale(model: Model, amount: number, duration: number)
	local ok, base = pcall(function()
		return model:GetScale()
	end)
	if not ok or typeof(base) ~= "number" then
		return
	end
	animate(duration, function(t)
		if not model.Parent then
			return
		end
		local s = if t >= 1 then base else base * (1 + amount * math.sin(math.pi * t))
		pcall(function()
			model:ScaleTo(s)
		end)
	end)
end

----------------------------------------------------------------------------- effects

local lastCashFx = -math.huge

local function onCash(payload: any)
	lastCashFx = os.clock()
	local amount = num(payload and payload.amount, 0)
	local pad = dairyPart("CashPad")
	local root = rootPart()
	local from = if pad then pad.Position elseif root then root.Position else nil
	if not from or not nearCamera(from) or not begin(1.5) then
		return
	end
	local count = math.clamp(math.floor(math.log10(amount + 1) * 2.5), Fx.Coins.Min, Fx.Coins.Max)
	coinBurst(from, count)
	floatText(from + Vector3.new(0, 4, 0), "+" .. Format.Cash(amount), Fx.Text.CashColor, true)
	emitAt(sparkle, from + Vector3.new(0, 1, 0), 18, Fx.Coins.Color)
end

local function onDeposit(payload: any)
	local amount = num(payload and payload.amount, 0)
	local pad = dairyPart("DepositPad")
	if not pad or not nearCamera(pad.Position) or not begin(1.2) then
		return
	end
	local top = pad.Position + Vector3.new(0, pad.Size.Y / 2, 0)
	emitAt(splash, top + Vector3.new(0, 0.5, 0), 30)
	local ring = CFrame.new(top + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	flash(ring, Enum.PartType.Cylinder, Fx.Text.MilkColor, Vector3.new(0.2, 2, 2), Vector3.new(0.2, 13, 13), 0.5)
	if amount > 0 then
		floatText(top + Vector3.new(0, 3, 0), "+" .. Format.Number(amount) .. " milk", Fx.Text.MilkColor, false)
	end
end

local function onMerge(payload: any)
	local tier = math.floor(num(payload and payload.tier, 0))
	local count = math.floor(num(payload and payload.count, 0))
	local stall = if tier > 0 then getStall(tier) else nil
	local mergePad = plotPart("MergePad")
	local pos = if stall then stallTop(stall) elseif mergePad then mergePad.Position else nil
	if not pos or not nearCamera(pos) or not begin(1.4) then
		return
	end
	local p = pos :: Vector3
	if not reducedMotion() then
		flash(
			CFrame.new(p + Vector3.new(0, 2, 0)),
			Enum.PartType.Ball,
			Color3.new(1, 1, 1),
			Vector3.one,
			Vector3.one * 11,
			0.35
		)
	end
	emitAt(sparkle, p + Vector3.new(0, 2, 0), 40, Fx.Text.MergeColor)
	local text = if count > 1 then `MERGED! x{count}` else "MERGED!"
	floatText(p + Vector3.new(0, 6, 0), text, Fx.Text.MergeColor, true)
	-- the new tier's cow model may replicate a moment after this remote
	task.delay(0.15, function()
		local cow = stall and stall:FindFirstChild("Cow")
		if cow and cow:IsA("Model") then
			popScale(cow, 0.35, 0.4)
		end
	end)
	if mergePad then
		emitAt(sparkle, mergePad.Position + Vector3.new(0, 1, 0), 15, Fx.Text.MergeColor)
	end
end

local function prepClone(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		elseif d:IsA("Script") or d:IsA("LocalScript") or d:IsA("BillboardGui") then
			d:Destroy()
		end
	end
	-- keep CowAnimController and DiscoveryController away from the clone
	model:SetAttribute("CowTier", nil)
	model:SetAttribute("CowId", nil)
end

local function dropCow(source: Model?, land: Vector3, delay: number)
	task.delay(delay, function()
		local model: Model? = nil
		if source and source.Parent then
			model = source:Clone()
		else
			local ok, built = pcall(CowModels.Build, 1)
			if ok then
				model = built
			end
		end
		if not model or not model.PrimaryPart then
			if model then
				model:Destroy()
			end
			return
		end
		local m = model :: Model
		prepClone(m)
		local yaw = CFrame.Angles(0, math.random() * math.pi * 2, 0)
		local height = 14
		m:PivotTo(CFrame.new(land + Vector3.new(0, height, 0)) * yaw)
		m.Parent = fxFolder
		local okScale, base = pcall(function()
			return m:GetScale()
		end)
		local baseScale = if okScale and typeof(base) == "number" then base else 1
		local dropTime, holdTime, outTime = 0.55, 0.35, 0.25
		local total = dropTime + holdTime + outTime
		local landed = false
		animate(total, function(t)
			local s = t * total
			if s < dropTime then
				local y = height * (1 - bounceOut(s / dropTime))
				m:PivotTo(CFrame.new(land + Vector3.new(0, y, 0)) * yaw)
			elseif s < dropTime + holdTime then
				if not landed then
					landed = true
					m:PivotTo(CFrame.new(land) * yaw)
					emitAt(splash, land + Vector3.new(0, 0.3, 0), 6)
				end
			else
				local k = clamp01((s - dropTime - holdTime) / outTime)
				pcall(function()
					m:ScaleTo(baseScale * math.max(0.05, 1 - k))
				end)
			end
		end, function()
			m:Destroy()
		end)
	end)
end

local function onBuy(payload: any)
	local count = math.max(1, math.floor(num(payload and payload.count, 1)))
	local stall = getStall(1)
	local pad = plotPart("BuyPad" .. count) or plotPart("BuyPad1")
	if not stall then
		if pad then
			floatText(pad.Position + Vector3.new(0, 4, 0), `+{count} cows`, Fx.Text.CashColor, false)
		end
		return
	end
	local land = stallTop(stall)
	if not nearCamera(land) or not begin(1.8) then
		return
	end
	local source = stall:FindFirstChild("Cow")
	local sourceModel = if source and source:IsA("Model") then source else nil
	local drops = math.min(count, Fx.MaxDropCows)
	local spread = math.min(stall.Size.X, stall.Size.Z) * 0.3
	for i = 1, drops do
		local offset = if drops == 1
			then Vector3.zero
			else Vector3.new((math.random() - 0.5) * 2 * spread, 0, (math.random() - 0.5) * 2 * spread)
		dropCow(sourceModel, land + offset, (i - 1) * 0.08)
	end
	local text = if count == 1 then "+1 cow" else `+{count} cows`
	floatText(land + Vector3.new(0, 6, 0), text, Fx.Text.CashColor, true)
	if pad then
		emitAt(sparkle, pad.Position + Vector3.new(0, 1, 0), 12, Fx.Text.CashColor)
	end
end

-- camera shake: applied after the camera scripts every frame, never accumulates
local shakeStart = 0
local shakeTime = 0
local shakeDeg = 0
local shakeBound = false

local function shake(degrees: number, duration: number)
	if reducedMotion() then
		return
	end
	shakeStart = os.clock()
	shakeTime = duration
	shakeDeg = math.max(degrees, if shakeBound then shakeDeg else 0)
	if shakeBound then
		return
	end
	shakeBound = true
	RunService:BindToRenderStep("FxShake", Enum.RenderPriority.Camera.Value + 1, function()
		local t = (os.clock() - shakeStart) / shakeTime
		local camera = workspace.CurrentCamera
		if t >= 1 or not camera then
			shakeBound = false
			shakeDeg = 0
			RunService:UnbindFromRenderStep("FxShake")
			return
		end
		local now = os.clock() * 28
		local a = math.rad(shakeDeg * (1 - t))
		camera.CFrame = camera.CFrame
			* CFrame.Angles(math.noise(now, 0.3) * a, math.noise(now, 7.1) * a, math.noise(now, 13.7) * a * 0.5)
	end)
end

local glowToken = 0

local function glow(color: Color3, duration: number)
	glowToken += 1
	local token = glowToken
	for _, f in glowFrames do
		f.BackgroundColor3 = color
		f.Visible = true
	end
	local strength = Fx.Rare.GlowStrength
	animate(duration, function(t)
		if token ~= glowToken then
			return
		end
		-- quick in, slow pulse, fade out
		local a = if t < 0.1 then t / 0.1 elseif t < 0.7 then 0.85 + 0.15 * math.cos((t - 0.1) * 18) else (1 - t) / 0.3
		for _, f in glowFrames do
			f.BackgroundTransparency = 1 - strength * clamp01(a)
		end
	end, function()
		if token == glowToken then
			for _, f in glowFrames do
				f.Visible = false
			end
		end
	end)
end

local function onRare(payload: any)
	local kind = if payload and typeof(payload.kind) == "string" then payload.kind else "golden"
	local style = Fx.RareStyles[kind] or Fx.RareStyles.golden
	if not begin(Fx.Rare.GlowTime) then
		return
	end
	if not reducedMotion() then
		glow(style.color, Fx.Rare.GlowTime)
	end
	shake(style.shake, Fx.Rare.ShakeTime)
	local tank = getPlot()
	local tankModel = tank and tank:FindFirstChild("Tank")
	local root = rootPart()
	local pos: Vector3? = nil
	if tankModel and tankModel:IsA("Model") then
		pos = tankModel:GetPivot().Position + Vector3.new(0, 8, 0)
	elseif root then
		pos = root.Position + Vector3.new(0, 4, 0)
	end
	if pos and nearCamera(pos) then
		floatText(pos, style.label, style.color, true)
		emitAt(sparkle, pos, 30, style.color)
	end
end

local function onCrate(payload: any)
	local pos = vec(payload and payload.position)
	if not pos then
		local spawnPart = plotPart("CrateSpawn")
		pos = if spawnPart then spawnPart.Position else nil
	end
	if not pos or not nearCamera(pos) or not begin(1.2) then
		return
	end
	local p = pos :: Vector3
	local color = Color3.fromRGB(255, 230, 140)
	local height = 60
	local cf = CFrame.new(p + Vector3.new(0, height / 2 - 1, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	flash(cf, Enum.PartType.Cylinder, color, Vector3.new(height, 4, 4), Vector3.new(height, 0.3, 0.3), 1.0)
	local ring = CFrame.new(p + Vector3.new(0, -1, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	flash(ring, Enum.PartType.Cylinder, color, Vector3.new(0.2, 2, 2), Vector3.new(0.2, 10, 10), 0.5)
	emitAt(sparkle, p, 35, color)
	floatText(p + Vector3.new(0, 4, 0), "+1 crate", color, false)
end

local handlers: { [string]: (any) -> () } = {
	[Fx.Kind.Cash] = onCash,
	[Fx.Kind.Deposit] = onDeposit,
	[Fx.Kind.Merge] = onMerge,
	[Fx.Kind.Buy] = onBuy,
	[Fx.Kind.Rare] = onRare,
	[Fx.Kind.Crate] = onCrate,
}

-- Small "+$X" over the head for cash that did not come from the CashPad (codes, quests...).
local lastCash: number? = nil

local function onCashChanged(value: any)
	if typeof(value) ~= "number" then
		return
	end
	local previous = lastCash
	lastCash = value
	if not previous or value <= previous then
		return
	end
	local delta = value - previous
	local changedAt = os.clock()
	task.delay(Fx.DerivedCashWindow, function()
		if math.abs(lastCashFx - changedAt) <= Fx.DerivedCashWindow then
			return
		end
		local root = rootPart()
		if root and begin(Fx.Text.Life) then
			floatText(root.Position + Vector3.new(0, 4, 0), "+" .. Format.Cash(delta), Fx.Text.CashColor, false)
		end
	end)
end

----------------------------------------------------------------------------- pads

type PadState = { pad: BasePart, busy: boolean, last: number }

local padStates: { [BasePart]: PadState } = {}
local padConns: { RBXScriptConnection } = {}
type Pulse = { label: TextLabel, scale: UIScale }
local pulses: { Pulse } = {}

local function isReadyColor(c: Color3): boolean
	for _, ready in Fx.Pad.ReadyColors do
		if math.abs(c.R - ready.R) < 0.02 and math.abs(c.G - ready.G) < 0.02 and math.abs(c.B - ready.B) < 0.02 then
			return true
		end
	end
	return false
end

local function squish(state: PadState)
	local pad = state.pad
	local now = os.clock()
	if state.busy or now - state.last < Fx.Pad.Debounce or not pad.Parent then
		return
	end
	state.busy = true
	state.last = now
	-- a client-only jelly copy; the real pad never moves, so it never re-fires Touched
	local vis = Instance.new("Part")
	vis.Name = "FxPadSquish"
	vis.Anchored = true
	vis.CanCollide = false
	vis.CanTouch = false
	vis.CanQuery = false
	vis.CastShadow = false
	vis.Size = pad.Size
	vis.CFrame = pad.CFrame
	vis.Color = pad.Color
	vis.Material = pad.Material
	vis.Transparency = pad.Transparency
	if pad:IsA("Part") then
		vis.Shape = pad.Shape
	end
	vis.Parent = fxFolder
	pad.LocalTransparencyModifier = 1
	local size, cf = pad.Size, pad.CFrame
	local low = Fx.Pad.SquishScale
	local bright = pad.Color:Lerp(Color3.new(1, 1, 1), 0.35)
	animate(Fx.Pad.SquishTime, function(t)
		-- squeeze in during the first 40%, then a damped overshoot back to 1
		local k = if t < 0.4
			then 1 - (1 - low) * math.sin(t / 0.4 * math.pi / 2)
			else 1 + (1 - low) * 0.6 * math.sin((t - 0.4) / 0.6 * math.pi * 2) * (1 - t)
		local y = 1 + (1 - k) * 1.5
		vis.Size = Vector3.new(size.X * k, size.Y * y, size.Z * k)
		vis.CFrame = cf
		vis.Color = pad.Color:Lerp(bright, 1 - t)
	end, function()
		vis:Destroy()
		pad.LocalTransparencyModifier = 0
		state.busy = false
	end)
end

local function watchPad(pad: Instance?, pulse: boolean)
	if not pad or not pad:IsA("BasePart") then
		return
	end
	local state = padStates[pad]
	if not state then
		state = { pad = pad, busy = false, last = 0 }
		padStates[pad] = state
	end
	local s = state :: PadState
	table.insert(
		padConns,
		pad.Touched:Connect(function(hit)
			local character = player.Character
			if character and hit:IsDescendantOf(character) then
				squish(s)
			end
		end)
	)
	if pulse then
		local gui = pad:FindFirstChild("Label")
		local label = gui and gui:FindFirstChild("Text")
		if label and label:IsA("TextLabel") then
			local scale = label:FindFirstChild("FxPulse")
			if not scale then
				local created = Instance.new("UIScale")
				created.Name = "FxPulse"
				created.Parent = label
				scale = created
			end
			if scale and scale:IsA("UIScale") then
				table.insert(pulses, { label = label, scale = scale })
			end
		end
	end
end

local function bindPads()
	for _, c in padConns do
		c:Disconnect()
	end
	table.clear(padConns)
	for _, p in pulses do
		p.scale.Scale = 1
	end
	table.clear(pulses)
	for pad in padStates do
		if not pad.Parent then
			padStates[pad] = nil
		end
	end
	local plot = getPlot()
	if plot then
		for _, name in Fx.PlotPads do
			watchPad(plot:FindFirstChild(name), table.find(Fx.PulsePads, name) ~= nil)
		end
	end
	local dairy = workspace:FindFirstChild("Dairy")
	if dairy then
		for _, name in Fx.DairyPads do
			watchPad(dairy:FindFirstChild(name), false)
		end
	end
end

local function pulseStep(_dt: number): boolean
	local wave = math.sin(os.clock() * Fx.Pad.PulseSpeed)
	for _, p in pulses do
		if p.label.Parent and isReadyColor(p.label.TextColor3) then
			p.scale.Scale = 1 + Fx.Pad.PulseAmount * wave
		elseif p.scale.Scale ~= 1 then
			p.scale.Scale = 1
		end
	end
	return true
end

----------------------------------------------------------------------------- lifecycle

local function buildGlow()
	local gui = Instance.new("ScreenGui")
	gui.Name = "FxGlow"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- just under the HUD so buttons stay readable through the glow
	gui.DisplayOrder = Theme.Layers.Hud - 1
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- (size, position, gradient rotation) per screen edge; gradient goes opaque edge -> clear center
	type Edge = { size: UDim2, pos: UDim2, rot: number }
	local edges: { Edge } = {
		{ size = UDim2.fromScale(1, 0.22), pos = UDim2.fromScale(0, 0), rot = 90 },
		{ size = UDim2.fromScale(1, 0.22), pos = UDim2.fromScale(0, 0.78), rot = -90 },
		{ size = UDim2.fromScale(0.14, 1), pos = UDim2.fromScale(0, 0), rot = 0 },
		{ size = UDim2.fromScale(0.14, 1), pos = UDim2.fromScale(0.86, 0), rot = 180 },
	}
	for _, e in edges do
		local f = Instance.new("Frame")
		f.Size = e.size
		f.Position = e.pos
		f.BorderSizePixel = 0
		f.BackgroundTransparency = 1
		f.Visible = false
		f.Active = false
		local g = Instance.new("UIGradient")
		g.Rotation = e.rot
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = f
		f.Parent = gui
		table.insert(glowFrames, f)
	end
	gui.Parent = player:WaitForChild("PlayerGui")
end

function FxController:Init()
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "ClientFx"
	fxFolder.Parent = workspace

	sparkle = makeEmitter("FxSparkle", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Lifetime = NumberRange.new(0.5, 1),
		Speed = NumberRange.new(10, 18),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -25, 0),
		Drag = 2,
		LightEmission = 1,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.7),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
		RotSpeed = NumberRange.new(-200, 200),
	})
	splash = makeEmitter("FxSplash", {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(Fx.Text.MilkColor),
		Lifetime = NumberRange.new(0.4, 0.8),
		Speed = NumberRange.new(12, 22),
		SpreadAngle = Vector2.new(40, 40),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, -60, 0),
		LightEmission = 0.2,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.9),
			NumberSequenceKeypoint.new(1, 0.2),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.8, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
	})

	Net.Event("Fx").OnClientEvent:Connect(function(kind: any, payload: any)
		if typeof(kind) ~= "string" then
			return
		end
		local handler = handlers[kind]
		if not handler then
			return
		end
		local p = if typeof(payload) == "table" then payload else {}
		Safe.Run(`FxController {kind}`, handler, p)
	end)
end

function FxController:Start()
	buildGlow()
	addUpdater(pulseStep)
	RunService.Heartbeat:Connect(step)

	DataController:OnChanged("cash", onCashChanged)
	local data = DataController:Get()
	if data and typeof(data.cash) == "number" then
		lastCash = data.cash
	end

	player:GetAttributeChangedSignal("PlotId"):Connect(bindPads)
	workspace:WaitForChild("Dairy", 30)
	bindPads()
	-- plots and pads can be rebuilt; rebind cheaply if a watched pad disappeared
	while true do
		task.wait(3)
		local stale = #padConns == 0
		for pad in padStates do
			if not pad.Parent then
				stale = true
				break
			end
		end
		if stale then
			bindPads()
		end
	end
end

return FxController
