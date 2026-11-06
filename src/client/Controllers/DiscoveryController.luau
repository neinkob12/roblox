--!strict
-- Full-screen "NEW COW!" reveal when the server fires Net.Event("CowDiscovered") (tier).
-- Owner: A2.
--
-- Sequence: white flash -> dark backdrop + spinning sunburst -> "NEW COW!" banner drops in ->
-- rotating cow model (ViewportFrame) pops up -> huge cow name slams in -> confetti burst.
-- Tap/click anywhere to close (after a short delay) or it closes itself after AUTO_CLOSE seconds.
-- Several discoveries in a row (merge-all) are queued and shown one after another.
--
-- Public: DiscoveryController:Show(tier) queues a reveal (for the index UI, admin, trailer).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Cows = require(ReplicatedStorage.Shared.Config.Cows)
local CowModels = require(ReplicatedStorage.Shared.CowModels)
local Format = require(ReplicatedStorage.Shared.Format)
local Net = require(ReplicatedStorage.Shared.Net)

local AUTO_CLOSE = 7
local CLOSE_UNLOCK = 1.0
local RAY_COUNT = 14
local CONFETTI_COUNT = 70
local CONFETTI_COLORS = {
	Color3.fromRGB(255, 80, 120),
	Color3.fromRGB(255, 210, 60),
	Color3.fromRGB(90, 220, 120),
	Color3.fromRGB(80, 170, 255),
	Color3.fromRGB(200, 110, 255),
	Color3.fromRGB(255, 255, 255),
}

local DiscoveryController = {}

local queue: { number } = {}
local playing = false

local function tween(
	inst: Instance,
	time: number,
	props: { [string]: any },
	style: Enum.EasingStyle?,
	dir: Enum.EasingDirection?
): Tween
	local t = TweenService:Create(
		inst,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		props
	)
	t:Play()
	return t
end

local function stroke(parent: GuiObject, thickness: number, color: Color3?)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color or Color3.fromRGB(20, 10, 30)
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = parent
end

local function label(parent: Instance, name: string, text: string, size: UDim2, pos: UDim2): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Text = text
	l.Size = size
	l.Position = pos
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Parent = parent
	return l
end

local function lighten(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), amount)
end

local function buildGui(cow: Cows.CowTier)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "DiscoveryReveal"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 100
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- whole screen is the close button (big touch target on phones)
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(15, 8, 30)
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.ZIndex = 1
	backdrop.Parent = gui
	local bgGrad = Instance.new("UIGradient")
	bgGrad.Color = ColorSequence.new(cow.bodyColor:Lerp(Color3.new(0, 0, 0), 0.55), Color3.fromRGB(10, 5, 20))
	bgGrad.Rotation = 90
	bgGrad.Parent = backdrop

	-- content area kept square-ish and centered so it fits landscape phones and PCs alike
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.Size = UDim2.fromScale(1, 1)
	content.ZIndex = 2
	content.Parent = gui
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.25
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = content
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = content

	-- sunburst rays (rotated individually each frame)
	local rays: { Frame } = {}
	local rayColor = lighten(cow.milkColor, 0.3)
	for i = 1, RAY_COUNT do
		local ray = Instance.new("Frame")
		ray.Name = "Ray"
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.48)
		ray.Size = UDim2.fromScale(0.09, 1.6)
		ray.BackgroundColor3 = rayColor
		ray.BackgroundTransparency = 1
		ray.BorderSizePixel = 0
		ray.Rotation = (i - 1) * (180 / RAY_COUNT)
		ray.ZIndex = 2
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = ray
		ray.Parent = content
		table.insert(rays, ray)
	end

	-- glow disc behind the cow
	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.48)
	glow.Size = UDim2.fromScale(0.5, 0.62)
	glow.BackgroundColor3 = lighten(cow.milkColor, 0.5)
	glow.BackgroundTransparency = 1
	glow.ZIndex = 3
	glow.Parent = content
	local glowCorner = Instance.new("UICorner")
	glowCorner.CornerRadius = UDim.new(0.5, 0)
	glowCorner.Parent = glow
	local glowGrad = Instance.new("UIGradient")
	glowGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 0.9),
	})
	glowGrad.Parent = glow

	-- the cow, spinning in a viewport
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Cow"
	vp.AnchorPoint = Vector2.new(0.5, 0.5)
	vp.Position = UDim2.fromScale(0.5, 0.47)
	vp.Size = UDim2.fromScale(0.6, 0.6)
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(170, 170, 180)
	vp.LightColor = Color3.fromRGB(255, 250, 240)
	vp.LightDirection = Vector3.new(-1, -1.5, -1)
	vp.ZIndex = 4
	vp.Parent = content
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.Parent = vp
	vp.CurrentCamera = cam
	local model = CowModels.Build(cow.tier)
	model:PivotTo(CFrame.identity)
	model.Parent = vp
	local boxCF, boxSize = model:GetBoundingBox()
	local center = boxCF.Position
	local radius = boxSize.Magnitude * 0.5
	local camDist = radius / math.tan(math.rad(cam.FieldOfView / 2)) * 1.05

	-- banner
	local banner = label(content, "Banner", "NEW COW!", UDim2.fromScale(0.85, 0.16), UDim2.fromScale(0.5, -0.2))
	banner.TextColor3 = Color3.fromRGB(255, 225, 60)
	banner.Rotation = -4
	banner.ZIndex = 6
	stroke(banner, 5)
	local bannerGrad = Instance.new("UIGradient")
	bannerGrad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 160), Color3.fromRGB(255, 160, 30))
	bannerGrad.Rotation = 90
	bannerGrad.Parent = banner

	-- cow name
	local name = label(content, "CowName", cow.name, UDim2.fromScale(0.95, 0.14), UDim2.fromScale(0.5, 0.82))
	name.ZIndex = 6
	name.TextTransparency = 1
	stroke(name, 5)
	local nameGrad = Instance.new("UIGradient")
	nameGrad.Color = ColorSequence.new(Color3.new(1, 1, 1), lighten(cow.milkColor, 0.2))
	nameGrad.Rotation = 90
	nameGrad.Parent = name
	local nameScale = Instance.new("UIScale")
	nameScale.Scale = 2.5
	nameScale.Parent = name

	local sub = label(
		content,
		"Tier",
		`Tier {cow.tier} / {Cows.Count}  ·  {Format.Number(cow.milkPerSecond)} milk/s`,
		UDim2.fromScale(0.7, 0.06),
		UDim2.fromScale(0.5, 0.92)
	)
	sub.ZIndex = 6
	sub.TextTransparency = 1
	sub.TextColor3 = Color3.fromRGB(255, 240, 200)
	stroke(sub, 3)

	local hint = label(gui, "Hint", "Tap to continue", UDim2.fromScale(0.4, 0.045), UDim2.fromScale(0.5, 0.965))
	hint.ZIndex = 7
	hint.TextTransparency = 1
	hint.TextColor3 = Color3.fromRGB(220, 220, 230)
	stroke(hint, 2)
	local hintSize = Instance.new("UITextSizeConstraint")
	hintSize.MinTextSize = 14
	hintSize.MaxTextSize = 28
	hintSize.Parent = hint

	-- confetti layer
	local confettiLayer = Instance.new("Frame")
	confettiLayer.Name = "Confetti"
	confettiLayer.BackgroundTransparency = 1
	confettiLayer.Size = UDim2.fromScale(1, 1)
	confettiLayer.ZIndex = 8
	confettiLayer.Parent = gui

	-- white flash
	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 0
	flash.BorderSizePixel = 0
	flash.ZIndex = 9
	flash.Parent = gui

	gui.Parent = playerGui

	return {
		gui = gui,
		backdrop = backdrop,
		content = content,
		scale = scale,
		rays = rays,
		glow = glow,
		cam = cam,
		center = center,
		camDist = camDist,
		boxHeight = boxSize.Y,
		banner = banner,
		name = name,
		nameScale = nameScale,
		sub = sub,
		hint = hint,
		confettiLayer = confettiLayer,
		flash = flash,
	}
end

type Confetti = { f: Frame, x: number, y: number, vx: number, vy: number, spin: number, wobble: number }

local function spawnConfetti(layer: Frame): { Confetti }
	local rng = Random.new()
	local list: { Confetti } = {}
	for _ = 1, CONFETTI_COUNT do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = CONFETTI_COLORS[rng:NextInteger(1, #CONFETTI_COLORS)]
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		-- size relative to screen height so it looks the same on phone and PC
		local w = rng:NextNumber(0.012, 0.022)
		f.Size = UDim2.fromScale(w * 0.6, w * (if rng:NextNumber() < 0.5 then 1.6 else 0.8))
		local ar = Instance.new("UIAspectRatioConstraint")
		ar.AspectRatio = rng:NextNumber(0.4, 1.2)
		ar.DominantAxis = Enum.DominantAxis.Height
		ar.Parent = f
		f.ZIndex = 8
		f.Parent = layer
		-- burst from the center, then fall
		local angle = rng:NextNumber(math.rad(200), math.rad(340))
		local speed = rng:NextNumber(0.5, 1.3)
		table.insert(list, {
			f = f,
			x = 0.5 + rng:NextNumber(-0.05, 0.05),
			y = 0.45,
			vx = math.cos(angle) * speed * 0.6,
			vy = math.sin(angle) * speed,
			spin = rng:NextNumber(-540, 540),
			wobble = rng:NextNumber(0, math.pi * 2),
		})
	end
	return list
end

local function play(tier: number)
	local cow = Cows.Get(tier)
	if not cow then
		return
	end
	local ui = buildGui(cow)
	local start = os.clock()
	local confetti: { Confetti } = {}
	local closed = false
	local canClose = false

	-- intro
	tween(ui.flash, 0.5, { BackgroundTransparency = 1 })
	tween(ui.backdrop, 0.35, { BackgroundTransparency = 0.15 })
	tween(ui.scale, 0.55, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(ui.glow, 0.6, { BackgroundTransparency = 0 })
	for _, ray in ui.rays do
		tween(ray, 0.6, { BackgroundTransparency = 0 })
	end
	tween(ui.banner, 0.6, { Position = UDim2.fromScale(0.5, 0.09) }, Enum.EasingStyle.Bounce)
	task.delay(0.35, function()
		if closed then
			return
		end
		tween(ui.name, 0.25, { TextTransparency = 0 })
		tween(ui.nameScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
		confetti = spawnConfetti(ui.confettiLayer)
	end)
	task.delay(0.7, function()
		if not closed then
			tween(ui.sub, 0.3, { TextTransparency = 0 })
		end
	end)
	task.delay(CLOSE_UNLOCK, function()
		canClose = true
		if not closed then
			tween(ui.hint, 0.3, { TextTransparency = 0.1 })
		end
	end)

	local conn = RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - start
		-- spin the cow (slight bob of the camera too)
		local a = t * 1.3
		local camPos = ui.center
			+ Vector3.new(
				math.sin(a) * ui.camDist,
				ui.boxHeight * 0.25 + math.sin(t * 2) * 0.2,
				-math.cos(a) * ui.camDist
			)
		ui.cam.CFrame = CFrame.lookAt(camPos, ui.center)
		-- sunburst
		for i, ray in ui.rays do
			ray.Rotation = (i - 1) * (180 / RAY_COUNT) + t * 25
		end
		-- banner pulse
		ui.banner.Rotation = -4 + math.sin(t * 3) * 2
		-- hint blink
		if canClose then
			ui.hint.TextTransparency = 0.25 + math.sin(t * 4) * 0.25
		end
		-- confetti physics (screen-space scale units)
		for _, c in confetti do
			c.vy += 1.4 * dt
			c.vx *= (1 - 0.8 * dt)
			c.x += (c.vx + math.sin(t * 5 + c.wobble) * 0.05) * dt
			c.y += c.vy * dt
			c.f.Position = UDim2.fromScale(c.x, c.y)
			c.f.Rotation += c.spin * dt
		end
	end)

	local done = Instance.new("BindableEvent")
	local function close()
		if closed then
			return
		end
		closed = true
		tween(ui.scale, 0.25, { Scale = 0.6 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		tween(ui.backdrop, 0.3, { BackgroundTransparency = 1 })
		for _, ray in ui.rays do
			tween(ray, 0.25, { BackgroundTransparency = 1 })
		end
		tween(ui.glow, 0.25, { BackgroundTransparency = 1 })
		tween(ui.name, 0.25, { TextTransparency = 1 })
		tween(ui.sub, 0.25, { TextTransparency = 1 })
		tween(ui.banner, 0.25, { TextTransparency = 1 })
		ui.hint.Visible = false
		task.delay(0.32, function()
			conn:Disconnect()
			ui.gui:Destroy()
			done:Fire()
		end)
	end

	ui.backdrop.Activated:Connect(function()
		if canClose then
			close()
		end
	end)
	task.delay(AUTO_CLOSE, close)
	done.Event:Wait()
	done:Destroy()
end

local function pump()
	if playing then
		return
	end
	playing = true
	task.spawn(function()
		while #queue > 0 do
			local tier = table.remove(queue, 1) :: number
			local ok, err = pcall(play, tier)
			if not ok then
				warn(`[DiscoveryController] reveal failed: {err}`)
			end
			task.wait(0.15)
		end
		playing = false
	end)
end

function DiscoveryController:Show(tier: number)
	if type(tier) ~= "number" or not Cows.Get(tier) then
		return
	end
	table.insert(queue, tier)
	pump()
end

function DiscoveryController:Init()
	Net.Event("CowDiscovered").OnClientEvent:Connect(function(tier: number)
		DiscoveryController:Show(tier)
	end)
end

return DiscoveryController
