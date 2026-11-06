--!strict
-- Builds the 18 brainrot cows from plain Parts (no meshes, no Toolbox).
-- Owner: A2. Used by StallService (server), DiscoveryController (client), and free for the UI
-- (index, crate spin) and the trailer camera to reuse.
--
--   CowModels.Build(tier: number): Model
--
-- Model layout (contract for anyone reusing it):
--   * PrimaryPart "Root": invisible, Anchored, sits at the cow's FEET (ground level), centered.
--     Model:PivotTo(cframe) puts the cow's feet at `cframe`, facing cframe.LookVector.
--   * Every other part is unanchored, massless, non-colliding and welded (Weld) to Root,
--     so moving Root moves the whole cow.
--   * "Head" is jointed to Root by a Motor6D named "Neck" (parented to Head), so the client
--     can turn the head by changing Neck.C0. Head decorations are welded to Head.
--   * Attributes: CowTier (number), CowId (string).
--   * ~4 studs tall (tier 18 ~5), at most ~40 parts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cows = require(ReplicatedStorage.Shared.Config.Cows)

local MAX_PARTS = 40

-- Base proportions in "cow space": origin at the feet, front of the cow faces -Z.
local LEG_H = 1.2
local BODY_SIZE = Vector3.new(2.2, 1.6, 3.2)
local BODY_Y = LEG_H + BODY_SIZE.Y / 2 -- 2.0
local HEAD_SIZE = Vector3.new(1.5, 1.35, 1.25)
local HEAD_CF = CFrame.new(0, 2.75, -2.05)

local PINK = Color3.fromRGB(255, 165, 175)
local BLACK = Color3.fromRGB(25, 25, 30)
local WHITE = Color3.fromRGB(250, 250, 250)
local HORN = Color3.fromRGB(240, 230, 200)

local PARTICLE_SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local PARTICLE_SMOKE = "rbxasset://textures/particles/smoke_main.dds"

export type PartOpts = {
	material: Enum.Material?,
	shape: Enum.PartType?,
	class: string?, -- "Part" (default) or "WedgePart"
	transparency: number?,
	onHead: boolean?, -- weld to Head instead of Root; cf is then relative to the head
	reflectance: number?,
}

type Builder = {
	model: Model,
	root: Part,
	head: Part,
	scale: number,
	count: number,
	cow: Cows.CowTier,
	parts: { [string]: BasePart },
}

local CowModels = {}

local function weldTo(part0: BasePart, part1: BasePart)
	local weld = Instance.new("Weld")
	weld.Name = "Weld"
	weld.Part0 = part0
	weld.Part1 = part1
	weld.C0 = part0.CFrame:Inverse() * part1.CFrame
	weld.C1 = CFrame.identity
	weld.Parent = part1
end

local function styleBase(part: BasePart)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

-- Scales a cow-space CFrame (position only) by the builder's scale.
local function scaled(b: Builder, cf: CFrame): CFrame
	return cf - cf.Position + cf.Position * b.scale
end

-- Adds one part. `cf` is in cow space (or head space when opts.onHead).
local function add(b: Builder, name: string, size: Vector3, cf: CFrame, color: Color3, opts: PartOpts?): BasePart
	local o: PartOpts = opts or {}
	local part: BasePart
	if o.class == "WedgePart" then
		part = Instance.new("WedgePart")
	else
		local p = Instance.new("Part")
		if o.shape then
			p.Shape = o.shape
		end
		part = p
	end
	styleBase(part)
	part.Name = name
	part.Size = size * b.scale
	local world = if o.onHead then b.head.CFrame * scaled(b, cf) else scaled(b, cf)
	part.CFrame = world
	part.Color = color
	part.Material = o.material or Enum.Material.SmoothPlastic
	part.Transparency = o.transparency or 0
	part.Reflectance = o.reflectance or 0
	weldTo(if o.onHead then b.head else b.root, part)
	part.Parent = b.model
	b.count += 1
	b.parts[name] = part
	return part
end

local function remove(b: Builder, name: string)
	local p = b.parts[name]
	if p then
		p:Destroy()
		b.parts[name] = nil
		b.count -= 1
	end
end

local function recolor(b: Builder, names: { string }, color: Color3, material: Enum.Material?)
	for _, n in names do
		local p = b.parts[n]
		if p then
			p.Color = color
			if material then
				p.Material = material
			end
		end
	end
end

local function resize(b: Builder, name: string, size: Vector3, cf: CFrame?)
	local p = b.parts[name]
	if not p then
		return
	end
	p.Size = size * b.scale
	if cf then
		local weld = p:FindFirstChild("Weld") :: Weld?
		local onHead = weld ~= nil and weld.Part0 == b.head
		local world = if onHead then b.head.CFrame * scaled(b, cf) else scaled(b, cf)
		p.CFrame = world
		if weld and weld.Part0 then
			weld.C0 = weld.Part0.CFrame:Inverse() * world
		end
	end
end

local LEGS = { "LegFL", "LegFR", "LegBL", "LegBR" }
local LEG_POS = {
	LegFL = Vector3.new(-0.65, 0, -1.05),
	LegFR = Vector3.new(0.65, 0, -1.05),
	LegBL = Vector3.new(-0.65, 0, 1.05),
	LegBR = Vector3.new(0.65, 0, 1.05),
}

local function setLegs(b: Builder, width: number, height: number, color: Color3, material: Enum.Material?)
	for _, n in LEGS do
		local pos = LEG_POS[n]
		resize(b, n, Vector3.new(width, height, width), CFrame.new(pos.X, height / 2, pos.Z))
		recolor(b, { n }, color, material)
	end
end

local function addLight(b: Builder, color: Color3, range: number, brightness: number)
	local body = b.parts.Body or b.root
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = body
end

local function addParticles(
	b: Builder,
	texture: string,
	color: Color3,
	rate: number,
	size: number,
	speed: number,
	lifetime: number,
	parentName: string?
)
	local parent = (parentName and b.parts[parentName]) or b.parts.Body or b.root
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = texture
	pe.Color = ColorSequence.new(color)
	pe.Rate = rate
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size * 0.4),
		NumberSequenceKeypoint.new(0.3, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Speed = NumberRange.new(speed * 0.5, speed)
	pe.Lifetime = NumberRange.new(lifetime * 0.6, lifetime)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.LightEmission = 0.6
	pe.RotSpeed = NumberRange.new(-90, 90)
	pe.Parent = parent
end

-- The shared cow every tier starts from.
local function buildBase(b: Builder)
	local cow = b.cow
	local body = cow.bodyColor
	local spot = cow.spotColor

	add(b, "Body", BODY_SIZE, CFrame.new(0, BODY_Y, 0), body)
	for _, n in LEGS do
		local pos = LEG_POS[n]
		add(b, n, Vector3.new(0.6, LEG_H, 0.6), CFrame.new(pos.X, LEG_H / 2, pos.Z), body)
	end
	add(b, "Udder", Vector3.new(0.8, 0.35, 0.8), CFrame.new(0, LEG_H - 0.05, 0.55), PINK)
	add(
		b,
		"Tail",
		Vector3.new(0.2, 1.2, 0.2),
		CFrame.new(0, BODY_Y + 0.1, BODY_SIZE.Z / 2 + 0.25) * CFrame.Angles(math.rad(-25), 0, 0),
		body
	)
	add(b, "TailTip", Vector3.new(0.32, 0.4, 0.32), CFrame.new(0, BODY_Y - 0.45, BODY_SIZE.Z / 2 + 0.5), spot)

	-- spots: flat patches that stick out a little from the body sides / top
	add(b, "Spot1", Vector3.new(0.1, 0.8, 1.0), CFrame.new(-1.11, BODY_Y + 0.2, -0.4), spot)
	add(b, "Spot2", Vector3.new(0.1, 0.6, 0.7), CFrame.new(1.11, BODY_Y - 0.1, 0.6), spot)
	add(b, "Spot3", Vector3.new(0.9, 0.1, 0.8), CFrame.new(0.35, BODY_Y + 0.81, 0.7), spot)
	add(b, "Spot4", Vector3.new(0.1, 0.5, 0.6), CFrame.new(1.11, BODY_Y + 0.35, -0.9), spot)

	-- head: its own part, jointed to Root by a Motor6D so the client can turn it
	local head = add(b, "Head", HEAD_SIZE, HEAD_CF, body) :: Part
	local oldWeld = head:FindFirstChild("Weld")
	if oldWeld then
		oldWeld:Destroy()
	end
	local neck = Instance.new("Motor6D")
	neck.Name = "Neck"
	neck.Part0 = b.root
	neck.Part1 = head
	neck.C0 = b.root.CFrame:Inverse() * head.CFrame
	neck.C1 = CFrame.identity
	neck.Parent = head
	b.head = head

	local hz = -HEAD_SIZE.Z / 2 -- front face of the head (head space)
	add(b, "Snout", Vector3.new(1.15, 0.6, 0.35), CFrame.new(0, -0.3, hz - 0.15), PINK, { onHead = true })
	add(b, "NostrilL", Vector3.new(0.14, 0.14, 0.06), CFrame.new(-0.25, -0.25, hz - 0.34), BLACK, { onHead = true })
	add(b, "NostrilR", Vector3.new(0.14, 0.14, 0.06), CFrame.new(0.25, -0.25, hz - 0.34), BLACK, { onHead = true })
	add(b, "EyeL", Vector3.new(0.36, 0.36, 0.08), CFrame.new(-0.38, 0.2, hz - 0.03), WHITE, { onHead = true })
	add(b, "EyeR", Vector3.new(0.36, 0.36, 0.08), CFrame.new(0.38, 0.2, hz - 0.03), WHITE, { onHead = true })
	add(b, "PupilL", Vector3.new(0.18, 0.2, 0.06), CFrame.new(-0.36, 0.18, hz - 0.09), BLACK, { onHead = true })
	add(b, "PupilR", Vector3.new(0.18, 0.2, 0.06), CFrame.new(0.36, 0.18, hz - 0.09), BLACK, { onHead = true })
	add(
		b,
		"HornL",
		Vector3.new(0.2, 0.55, 0.2),
		CFrame.new(-0.45, 0.85, 0) * CFrame.Angles(0, 0, math.rad(15)),
		HORN,
		{ onHead = true }
	)
	add(
		b,
		"HornR",
		Vector3.new(0.2, 0.55, 0.2),
		CFrame.new(0.45, 0.85, 0) * CFrame.Angles(0, 0, math.rad(-15)),
		HORN,
		{ onHead = true }
	)
	add(
		b,
		"EarL",
		Vector3.new(0.55, 0.22, 0.32),
		CFrame.new(-0.95, 0.3, 0.1) * CFrame.Angles(0, 0, math.rad(-20)),
		body,
		{ onHead = true }
	)
	add(
		b,
		"EarR",
		Vector3.new(0.55, 0.22, 0.32),
		CFrame.new(0.95, 0.3, 0.1) * CFrame.Angles(0, 0, math.rad(20)),
		body,
		{ onHead = true }
	)
end

local function headCylinderUp(): CFrame
	-- Cylinder parts run along X; rotate so they stand upright.
	return CFrame.Angles(0, 0, math.rad(90))
end

-- Per-tier accessories, keyed by Cows id. Each follows the `look` notes in Config/Cows.
local EXTRAS: { [string]: (Builder) -> () } = {}

EXTRAS.pappuccia = function(b)
	-- tiny gold bell on a red collar
	add(b, "Collar", Vector3.new(1.0, 0.18, 0.5), CFrame.new(0, 2.0, -1.75), Color3.fromRGB(200, 40, 40))
	add(
		b,
		"Bell",
		Vector3.new(0.45, 0.45, 0.45),
		CFrame.new(0, 1.75, -1.95),
		Color3.fromRGB(255, 200, 40),
		{ shape = Enum.PartType.Ball, material = Enum.Material.Metal, reflectance = 0.2 }
	)
end

EXTRAS.panino = function(b)
	local bread = Color3.fromRGB(235, 190, 120)
	local crust = Color3.fromRGB(170, 105, 50)
	add(b, "Lettuce", Vector3.new(2.6, 0.12, 3.6), CFrame.new(0, BODY_Y + 0.86, 0), Color3.fromRGB(110, 200, 70), {
		material = Enum.Material.Grass,
	})
	add(b, "BreadTop", Vector3.new(2.4, 0.4, 3.4), CFrame.new(0, BODY_Y + 1.12, 0), bread, {
		material = Enum.Material.Sand,
	})
	add(b, "CrustTop", Vector3.new(2.5, 0.12, 3.5), CFrame.new(0, BODY_Y + 1.36, 0), crust)
	add(b, "BreadBottom", Vector3.new(2.4, 0.35, 3.4), CFrame.new(0, LEG_H + 0.1, 0), bread, {
		material = Enum.Material.Sand,
	})
	add(b, "Tomato", Vector3.new(2.45, 0.1, 3.45), CFrame.new(0, BODY_Y + 0.95, 0), Color3.fromRGB(220, 50, 40))
end

EXTRAS.patapim = function(b)
	local bark = Color3.fromRGB(110, 75, 45)
	setLegs(b, 0.85, LEG_H, bark, Enum.Material.Wood)
	-- big nose
	resize(b, "Snout", Vector3.new(0.9, 0.8, 0.9), CFrame.new(0, -0.15, -HEAD_SIZE.Z / 2 - 0.4))
	recolor(b, { "Snout" }, Color3.fromRGB(230, 170, 140))
	local leaf = Color3.fromRGB(70, 170, 60)
	add(b, "Leaves1", Vector3.new(1.7, 0.6, 1.4), CFrame.new(0, 0.9, 0.05), leaf, {
		onHead = true,
		material = Enum.Material.Grass,
	})
	add(b, "Leaves2", Vector3.new(1.0, 0.55, 0.9), CFrame.new(0.2, 1.35, 0.1), leaf, {
		onHead = true,
		material = Enum.Material.Grass,
	})
	add(b, "Twig", Vector3.new(0.15, 0.7, 0.15), CFrame.new(-0.4, 1.4, 0) * CFrame.Angles(0, 0, math.rad(25)), bark, {
		onHead = true,
		material = Enum.Material.Wood,
	})
end

EXTRAS.spaghettino = function(b)
	local noodle = Color3.fromRGB(255, 220, 90)
	remove(b, "Tail")
	remove(b, "TailTip")
	for i = 1, 3 do
		add(
			b,
			"NoodleTail" .. i,
			Vector3.new(1.4, 0.16, 0.16),
			CFrame.new((i - 2) * 0.22, BODY_Y - 0.1, BODY_SIZE.Z / 2 + 0.2)
				* CFrame.Angles(0, math.rad(90), math.rad(60 + i * 8)),
			noodle,
			{ shape = Enum.PartType.Cylinder }
		)
	end
	for i = 1, 4 do
		local x = -0.55 + (i - 1) * 0.37
		add(
			b,
			"Hair" .. i,
			Vector3.new(1.0, 0.16, 0.16),
			CFrame.new(x, 0.55, -0.1) * CFrame.Angles(math.rad(10), 0, math.rad(if x < 0 then 70 else 110)),
			noodle,
			{ shape = Enum.PartType.Cylinder, onHead = true }
		)
	end
	add(b, "Meatball", Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, 0.8, 0), Color3.fromRGB(130, 60, 40), {
		shape = Enum.PartType.Ball,
		onHead = true,
	})
end

EXTRAS.lirili = function(b)
	local cactus = Color3.fromRGB(70, 140, 70)
	-- elephant-ish: big ears, trunk instead of snout
	remove(b, "NostrilL")
	remove(b, "NostrilR")
	resize(b, "EarL", Vector3.new(0.25, 1.1, 0.9), CFrame.new(-0.85, 0.05, 0.2))
	resize(b, "EarR", Vector3.new(0.25, 1.1, 0.9), CFrame.new(0.85, 0.05, 0.2))
	resize(
		b,
		"Snout",
		Vector3.new(0.4, 1.2, 0.4),
		CFrame.new(0, -0.6, -HEAD_SIZE.Z / 2 - 0.25) * CFrame.Angles(math.rad(-20), 0, 0)
	)
	recolor(b, { "Snout" }, b.cow.bodyColor)
	add(b, "Cactus", Vector3.new(1.3, 0.55, 0.55), CFrame.new(0, BODY_Y + 1.4, 0.3) * headCylinderUp(), cactus, {
		shape = Enum.PartType.Cylinder,
		material = Enum.Material.Grass,
	})
	add(b, "CactusArm", Vector3.new(0.7, 0.3, 0.3), CFrame.new(0.45, BODY_Y + 1.45, 0.3), cactus, {
		material = Enum.Material.Grass,
	})
	add(b, "CactusArmUp", Vector3.new(0.3, 0.55, 0.3), CFrame.new(0.65, BODY_Y + 1.75, 0.3), cactus, {
		material = Enum.Material.Grass,
	})
	add(b, "Flower", Vector3.new(0.3, 0.3, 0.3), CFrame.new(0, BODY_Y + 2.1, 0.3), Color3.fromRGB(255, 120, 200), {
		shape = Enum.PartType.Ball,
	})
	-- sandals under the front feet
	local sandal = Color3.fromRGB(150, 95, 50)
	add(b, "SandalL", Vector3.new(0.75, 0.12, 0.85), CFrame.new(-0.65, 0.06, -1.1), sandal)
	add(b, "SandalR", Vector3.new(0.75, 0.12, 0.85), CFrame.new(0.65, 0.06, -1.1), sandal)
end

EXTRAS.biscottino = function(b)
	recolor(b, { "Body", "Head" }, b.cow.bodyColor, Enum.Material.Sand)
	-- extra chocolate chips all over
	local chip = b.cow.spotColor
	local chips = {
		CFrame.new(-0.6, BODY_Y + 0.82, -0.8),
		CFrame.new(0.5, BODY_Y + 0.82, -0.3),
		CFrame.new(-0.3, BODY_Y + 0.82, 1.0),
		CFrame.new(-1.11, BODY_Y - 0.3, 0.9),
		CFrame.new(1.11, BODY_Y + 0.4, 0.2),
		CFrame.new(-1.11, BODY_Y + 0.3, 0.4),
	}
	for i, cf in chips do
		add(b, "Chip" .. i, Vector3.new(0.3, 0.3, 0.3), cf * CFrame.Angles(0, math.rad(i * 30), 0), chip)
	end
	add(b, "HeadChip", Vector3.new(0.25, 0.25, 0.25), CFrame.new(0.4, 0.68, 0.1), chip, { onHead = true })
end

EXTRAS.bananini = function(b)
	local peel = b.cow.bodyColor
	local fur = Color3.fromRGB(140, 95, 55)
	recolor(b, { "Body", "Head", "EarL", "EarR", "LegFL", "LegFR", "LegBL", "LegBR" }, fur)
	recolor(b, { "Tail" }, fur)
	-- monkey face plate
	add(
		b,
		"Face",
		Vector3.new(1.1, 0.9, 0.08),
		CFrame.new(0, -0.05, -HEAD_SIZE.Z / 2 - 0.02),
		Color3.fromRGB(235, 200, 160),
		{
			onHead = true,
		}
	)
	recolor(b, { "Snout" }, Color3.fromRGB(235, 200, 160))
	-- banana peel flaps around the body, opening outward
	add(
		b,
		"PeelL",
		Vector3.new(0.18, 2.0, 3.0),
		CFrame.new(-1.3, BODY_Y + 0.2, 0) * CFrame.Angles(0, 0, math.rad(15)),
		peel
	)
	add(
		b,
		"PeelR",
		Vector3.new(0.18, 2.0, 3.0),
		CFrame.new(1.3, BODY_Y + 0.2, 0) * CFrame.Angles(0, 0, math.rad(-15)),
		peel
	)
	add(
		b,
		"PeelBack",
		Vector3.new(2.0, 2.0, 0.18),
		CFrame.new(0, BODY_Y + 0.2, 1.75) * CFrame.Angles(math.rad(15), 0, 0),
		peel
	)
	add(b, "PeelTop", Vector3.new(2.2, 0.15, 3.0), CFrame.new(0, BODY_Y + 0.85, 0.1), peel)
	add(b, "Stem", Vector3.new(0.25, 0.5, 0.25), CFrame.new(0, BODY_Y + 1.1, 1.3), Color3.fromRGB(90, 70, 40))
end

EXTRAS.fragoletta = function(b)
	local seed = b.cow.spotColor
	local seeds = {
		CFrame.new(-1.11, BODY_Y + 0.4, -0.9),
		CFrame.new(-1.11, BODY_Y - 0.3, 0.2),
		CFrame.new(1.11, BODY_Y + 0.5, 0.2),
		CFrame.new(1.11, BODY_Y - 0.4, -0.6),
		CFrame.new(0.6, BODY_Y + 0.81, -0.9),
		CFrame.new(-0.5, BODY_Y + 0.81, 1.1),
	}
	for i, cf in seeds do
		add(b, "Seed" .. i, Vector3.new(0.15, 0.25, 0.15), cf, seed)
	end
	local leaf = Color3.fromRGB(60, 170, 70)
	for i = 1, 4 do
		local a = math.rad(45 + (i - 1) * 90)
		add(
			b,
			"Leaf" .. i,
			Vector3.new(0.5, 0.12, 0.25),
			CFrame.new(math.cos(a) * 0.3, 0.72, math.sin(a) * 0.3) * CFrame.Angles(0, -a, math.rad(20)),
			leaf,
			{ onHead = true, material = Enum.Material.Grass }
		)
	end
	add(b, "StrawStem", Vector3.new(0.14, 0.45, 0.14), CFrame.new(0, 0.95, 0), Color3.fromRGB(70, 130, 50), {
		onHead = true,
	})
end

EXTRAS.cappuccina = function(b)
	-- coffee-cup head: a white blocky mug with coffee on top, a handle and a saucer
	local cup = Color3.fromRGB(250, 250, 250)
	recolor(b, { "Head", "EarL", "EarR" }, cup)
	add(b, "Coffee", Vector3.new(1.3, 0.08, 1.1), CFrame.new(0, 0.68, 0), Color3.fromRGB(110, 65, 35), {
		onHead = true,
	})
	add(b, "Foam", Vector3.new(0.5, 0.06, 0.4), CFrame.new(0.2, 0.72, 0.1), Color3.fromRGB(240, 220, 190), {
		onHead = true,
	})
	add(b, "Handle", Vector3.new(0.18, 0.7, 0.45), CFrame.new(0.85, 0, 0.2), cup, { onHead = true })
	add(b, "Saucer", Vector3.new(1.9, 0.1, 1.7), CFrame.new(0, -0.72, 0), cup, { onHead = true })
	-- tutu
	add(
		b,
		"Tutu",
		Vector3.new(0.35, 3.6, 3.6),
		CFrame.new(0, BODY_Y - 0.55, 0) * headCylinderUp(),
		Color3.fromRGB(255, 150, 200),
		{
			shape = Enum.PartType.Cylinder,
			material = Enum.Material.Fabric,
			transparency = 0.1,
		}
	)
	-- tip-toes: thin legs with pointed pink shoes
	setLegs(b, 0.38, LEG_H, b.cow.bodyColor)
	for _, n in LEGS do
		local pos = LEG_POS[n]
		add(
			b,
			"Shoe" .. n,
			Vector3.new(0.42, 0.25, 0.42),
			CFrame.new(pos.X, 0.12, pos.Z),
			Color3.fromRGB(255, 150, 200)
		)
	end
end

EXTRAS.gelatino = function(b)
	local scoops = { Color3.fromRGB(255, 180, 220), Color3.fromRGB(170, 240, 200), Color3.fromRGB(255, 240, 150) }
	for i, c in scoops do
		add(
			b,
			"Scoop" .. i,
			Vector3.new(1.3 - i * 0.15, 1.3 - i * 0.15, 1.3 - i * 0.15),
			CFrame.new(0, BODY_Y + 0.6 + i * 0.75, 0.2),
			c,
			{ shape = Enum.PartType.Ball }
		)
	end
	add(b, "Cherry", Vector3.new(0.35, 0.35, 0.35), CFrame.new(0, BODY_Y + 3.15, 0.2), Color3.fromRGB(220, 30, 50), {
		shape = Enum.PartType.Ball,
	})
	-- waffle-cone tail
	remove(b, "TailTip")
	resize(
		b,
		"Tail",
		Vector3.new(0.45, 1.1, 0.45),
		CFrame.new(0, BODY_Y + 0.3, BODY_SIZE.Z / 2 + 0.35) * CFrame.Angles(math.rad(35), 0, 0)
	)
	recolor(b, { "Tail" }, Color3.fromRGB(210, 150, 80), Enum.Material.Sand)
	add(b, "TailScoop", Vector3.new(0.6, 0.6, 0.6), CFrame.new(0, BODY_Y + 0.8, BODY_SIZE.Z / 2 + 0.7), scoops[1], {
		shape = Enum.PartType.Ball,
	})
end

EXTRAS.trippi = function(b)
	-- cat ears (wedges) instead of cow ears
	remove(b, "EarL")
	remove(b, "EarR")
	add(b, "CatEarL", Vector3.new(0.4, 0.55, 0.35), CFrame.new(-0.5, 0.95, 0.1), b.cow.bodyColor, {
		class = "WedgePart",
		onHead = true,
	})
	add(b, "CatEarR", Vector3.new(0.4, 0.55, 0.35), CFrame.new(0.5, 0.95, 0.1), b.cow.bodyColor, {
		class = "WedgePart",
		onHead = true,
	})
	for i, side in { -1, 1 } do
		add(
			b,
			"Whisker" .. i,
			Vector3.new(0.8, 0.05, 0.05),
			CFrame.new(side * 0.85, -0.25, -HEAD_SIZE.Z / 2 - 0.3) * CFrame.Angles(0, 0, math.rad(side * 10)),
			BLACK,
			{ onHead = true }
		)
		add(
			b,
			"WhiskerB" .. i,
			Vector3.new(0.8, 0.05, 0.05),
			CFrame.new(side * 0.85, -0.4, -HEAD_SIZE.Z / 2 - 0.3) * CFrame.Angles(0, 0, math.rad(side * -10)),
			BLACK,
			{ onHead = true }
		)
	end
	-- segmented shrimp tail curling up and over
	remove(b, "Tail")
	remove(b, "TailTip")
	local shell = Color3.fromRGB(255, 120, 60)
	for i = 1, 3 do
		add(
			b,
			"Shrimp" .. i,
			Vector3.new(1.4 - i * 0.25, 0.5, 0.6),
			CFrame.new(0, BODY_Y + 0.1 + i * 0.35, BODY_SIZE.Z / 2 + 0.15 + i * 0.12)
				* CFrame.Angles(math.rad(-25 * i), 0, 0),
			if i % 2 == 0 then shell else Color3.fromRGB(255, 170, 100)
		)
	end
	add(b, "ShrimpFan", Vector3.new(1.3, 0.12, 0.7), CFrame.new(0, BODY_Y + 1.45, BODY_SIZE.Z / 2 + 0.2), WHITE)
end

EXTRAS.formaggiona = function(b)
	local cheese = b.cow.bodyColor
	-- pizza wedge on top of the body, crust at the back
	add(
		b,
		"Slice",
		Vector3.new(2.2, 0.8, 3.2),
		CFrame.new(0, BODY_Y + 1.2, 0) * CFrame.Angles(0, math.rad(180), 0),
		cheese,
		{ class = "WedgePart" }
	)
	add(
		b,
		"Crust",
		Vector3.new(2.3, 0.95, 0.35),
		CFrame.new(0, BODY_Y + 1.25, BODY_SIZE.Z / 2 + 0.05),
		Color3.fromRGB(200, 130, 60),
		{
			material = Enum.Material.Sand,
		}
	)
	local pep = b.cow.spotColor
	local peps = {
		CFrame.new(-1.12, BODY_Y + 0.3, -0.7),
		CFrame.new(-1.12, BODY_Y - 0.3, 0.6),
		CFrame.new(1.12, BODY_Y + 0.2, -0.1),
		CFrame.new(1.12, BODY_Y - 0.35, 1.0),
	}
	for i, cf in peps do
		add(b, "Pepperoni" .. i, Vector3.new(0.08, 0.55, 0.55), cf, pep, { shape = Enum.PartType.Cylinder })
	end
	for i = 1, 3 do
		add(
			b,
			"Drip" .. i,
			Vector3.new(0.25, 0.5 + i * 0.12, 0.12),
			CFrame.new(-0.7 + (i - 1) * 0.7, BODY_Y - 0.6 - i * 0.06, -BODY_SIZE.Z / 2 - 0.05),
			Color3.fromRGB(255, 225, 110)
		)
	end
	remove(b, "Spot1")
	remove(b, "Spot2")
	remove(b, "Spot4")
end

EXTRAS.frigo = function(b)
	-- tall fridge-box body
	resize(b, "Body", Vector3.new(2.2, 2.2, 3.0), CFrame.new(0, LEG_H + 1.1, 0))
	b.parts.Body.Material = Enum.Material.SmoothPlastic
	b.parts.Body.Reflectance = 0.08
	remove(b, "Spot1")
	remove(b, "Spot2")
	remove(b, "Spot3")
	remove(b, "Spot4")
	add(b, "DoorLine", Vector3.new(0.06, 2.1, 0.06), CFrame.new(-1.12, LEG_H + 1.1, 0.2), Color3.fromRGB(150, 160, 170))
	add(b, "DoorLine2", Vector3.new(0.06, 0.06, 2.9), CFrame.new(-1.12, LEG_H + 1.5, 0), Color3.fromRGB(150, 160, 170))
	add(
		b,
		"Handle",
		Vector3.new(0.15, 0.9, 0.15),
		CFrame.new(-1.22, LEG_H + 1.0, -0.9),
		Color3.fromRGB(120, 125, 135),
		{
			material = Enum.Material.Metal,
		}
	)
	add(b, "Hump", Vector3.new(1.4, 1.0, 1.4), CFrame.new(0, LEG_H + 2.3, 0.3), b.cow.spotColor, {
		shape = Enum.PartType.Ball,
	})
	add(b, "Magnet", Vector3.new(0.06, 0.3, 0.3), CFrame.new(-1.13, LEG_H + 1.7, 0.6), Color3.fromRGB(255, 80, 80))
	-- head sits a bit higher on the taller body
	local neck = b.head:FindFirstChild("Neck") :: Motor6D?
	if neck then
		local cf = HEAD_CF * CFrame.new(0, 0.35, 0)
		neck.C0 = scaled(b, cf)
	end
end

EXTRAS.robomucca = function(b)
	local metal = Enum.Material.DiamondPlate
	recolor(b, { "Body" }, b.cow.bodyColor, metal)
	recolor(b, { "Head", "LegFL", "LegFR", "LegBL", "LegBR" }, b.cow.bodyColor, Enum.Material.Metal)
	local glow = b.cow.milkColor
	recolor(b, { "EyeL", "EyeR" }, glow, Enum.Material.Neon)
	remove(b, "PupilL")
	remove(b, "PupilR")
	recolor(b, { "Snout" }, b.cow.spotColor, Enum.Material.Metal)
	add(b, "Antenna", Vector3.new(0.08, 0.8, 0.08), CFrame.new(0, 1.05, 0.2), b.cow.spotColor, { onHead = true })
	add(b, "AntennaBall", Vector3.new(0.3, 0.3, 0.3), CFrame.new(0, 1.5, 0.2), glow, {
		onHead = true,
		shape = Enum.PartType.Ball,
		material = Enum.Material.Neon,
	})
	for i, side in { -1, 1 } do
		add(b, "Bolt" .. i, Vector3.new(0.15, 0.4, 0.4), CFrame.new(side * 1.15, BODY_Y, -0.2), b.cow.spotColor, {
			shape = Enum.PartType.Cylinder,
			material = Enum.Material.Metal,
		})
	end
	add(b, "ChestLight", Vector3.new(0.6, 0.4, 0.06), CFrame.new(0, BODY_Y + 0.2, -BODY_SIZE.Z / 2 - 0.02), glow, {
		material = Enum.Material.Neon,
	})
	addLight(b, glow, 10, 1.5)
	addParticles(b, PARTICLE_SPARKLE, glow, 3, 0.5, 2, 1, "AntennaBall")
end

EXTRAS.lavalina = function(b)
	local stone = Enum.Material.Slate
	recolor(b, { "Body", "Head", "LegFL", "LegFR", "LegBL", "LegBR", "EarL", "EarR", "Tail" }, b.cow.bodyColor, stone)
	local lava = b.cow.spotColor
	recolor(b, { "Spot1", "Spot2", "Spot3", "Spot4", "TailTip" }, lava, Enum.Material.Neon)
	resize(
		b,
		"Spot1",
		Vector3.new(0.1, 0.15, 1.8),
		CFrame.new(-1.11, BODY_Y + 0.2, -0.2) * CFrame.Angles(math.rad(20), 0, 0)
	)
	resize(
		b,
		"Spot2",
		Vector3.new(0.1, 0.15, 1.6),
		CFrame.new(1.11, BODY_Y - 0.1, 0.4) * CFrame.Angles(math.rad(-25), 0, 0)
	)
	resize(
		b,
		"Spot3",
		Vector3.new(0.15, 0.1, 2.2),
		CFrame.new(0.2, BODY_Y + 0.81, 0.2) * CFrame.Angles(0, math.rad(20), 0)
	)
	add(
		b,
		"Crack5",
		Vector3.new(0.12, 0.1, 0.9),
		CFrame.new(-0.2, 0.68, 0) * CFrame.Angles(0, math.rad(-30), 0),
		lava,
		{
			onHead = true,
			material = Enum.Material.Neon,
		}
	)
	recolor(b, { "EyeL", "EyeR" }, lava, Enum.Material.Neon)
	remove(b, "PupilL")
	remove(b, "PupilR")
	addLight(b, lava, 12, 2)
	addParticles(b, PARTICLE_SMOKE, Color3.fromRGB(90, 85, 85), 6, 1.4, 2, 2.5)
	addParticles(b, PARTICLE_SPARKLE, lava, 4, 0.4, 3, 1)
end

EXTRAS.glorbo = function(b)
	local rind = b.cow.bodyColor
	local dark = Color3.fromRGB(40, 110, 40)
	-- watermelon stripes
	for i = 1, 3 do
		add(b, "Stripe" .. i, Vector3.new(2.25, 1.65, 0.25), CFrame.new(0, BODY_Y, -1.1 + (i - 1) * 1.1), dark)
	end
	-- pink flesh visible where the shell "opens" at the front
	add(b, "Flesh", Vector3.new(1.9, 1.3, 0.1), CFrame.new(0, BODY_Y, -BODY_SIZE.Z / 2 - 0.03), b.cow.spotColor)
	remove(b, "Spot1")
	remove(b, "Spot2")
	remove(b, "Spot4")
	recolor(b, { "Spot3" }, BLACK)
	resize(b, "Spot3", Vector3.new(0.2, 0.12, 0.3), CFrame.new(0.3, BODY_Y + 0.82, 0.5))
	-- crocodile snout with teeth
	resize(b, "Snout", Vector3.new(1.0, 0.5, 1.5), CFrame.new(0, -0.35, -HEAD_SIZE.Z / 2 - 0.7))
	recolor(b, { "Snout", "Head", "EarL", "EarR" }, rind)
	for i, side in { -1, 1 } do
		add(
			b,
			"Tooth" .. i,
			Vector3.new(0.14, 0.2, 0.14),
			CFrame.new(side * 0.4, -0.65, -HEAD_SIZE.Z / 2 - 1.1),
			WHITE,
			{ onHead = true, class = "WedgePart" }
		)
	end
	recolor(b, { "NostrilL", "NostrilR" }, dark)
	resize(b, "NostrilL", Vector3.new(0.14, 0.06, 0.14), CFrame.new(-0.25, -0.08, -HEAD_SIZE.Z / 2 - 1.3))
	resize(b, "NostrilR", Vector3.new(0.14, 0.06, 0.14), CFrame.new(0.25, -0.08, -HEAD_SIZE.Z / 2 - 1.3))
	addLight(b, b.cow.spotColor, 10, 1.5)
	addParticles(b, PARTICLE_SPARKLE, Color3.fromRGB(255, 140, 160), 4, 0.5, 2, 1.2)
end

EXTRAS.arcobalena = function(b)
	local rainbow = {
		Color3.fromRGB(255, 70, 70),
		Color3.fromRGB(255, 160, 50),
		Color3.fromRGB(255, 230, 60),
		Color3.fromRGB(80, 210, 90),
		Color3.fromRGB(70, 150, 255),
		Color3.fromRGB(170, 90, 255),
	}
	for i, c in rainbow do
		add(
			b,
			"Stripe" .. i,
			Vector3.new(2.25, 1.65, BODY_SIZE.Z / #rainbow),
			CFrame.new(0, BODY_Y, -BODY_SIZE.Z / 2 + (i - 0.5) * BODY_SIZE.Z / #rainbow),
			c
		)
	end
	remove(b, "Spot1")
	remove(b, "Spot2")
	remove(b, "Spot3")
	remove(b, "Spot4")
	-- cloud tail
	remove(b, "Tail")
	remove(b, "TailTip")
	local cloud = Color3.fromRGB(255, 255, 255)
	add(b, "Cloud1", Vector3.new(0.9, 0.9, 0.9), CFrame.new(0, BODY_Y + 0.4, BODY_SIZE.Z / 2 + 0.4), cloud, {
		shape = Enum.PartType.Ball,
	})
	add(b, "Cloud2", Vector3.new(0.7, 0.7, 0.7), CFrame.new(0.45, BODY_Y + 0.2, BODY_SIZE.Z / 2 + 0.5), cloud, {
		shape = Enum.PartType.Ball,
	})
	add(b, "Cloud3", Vector3.new(0.7, 0.7, 0.7), CFrame.new(-0.45, BODY_Y + 0.25, BODY_SIZE.Z / 2 + 0.5), cloud, {
		shape = Enum.PartType.Ball,
	})
	add(
		b,
		"Halo",
		Vector3.new(0.1, 1.0, 1.0),
		CFrame.new(0, 1.1, 0) * headCylinderUp(),
		Color3.fromRGB(255, 230, 120),
		{
			onHead = true,
			shape = Enum.PartType.Cylinder,
			material = Enum.Material.Neon,
			transparency = 0.2,
		}
	)
	addLight(b, Color3.fromRGB(255, 180, 255), 12, 2)
	addParticles(b, PARTICLE_SPARKLE, Color3.fromRGB(255, 150, 255), 8, 0.6, 3, 1.2)
end

EXTRAS.saturnita = function(b)
	-- planet body instead of a box
	resize(b, "Body", Vector3.new(3.0, 3.0, 3.0), CFrame.new(0, 2.6, 0))
	local planet = b.parts.Body :: Part
	planet.Shape = Enum.PartType.Ball
	planet.Material = Enum.Material.Sand
	remove(b, "Udder")
	remove(b, "Spot1")
	remove(b, "Spot2")
	remove(b, "Spot4")
	resize(b, "Spot3", Vector3.new(0.9, 0.9, 0.9), CFrame.new(0.8, 3.4, 0.6))
	recolor(b, { "Spot3" }, Color3.fromRGB(110, 95, 180))
	local moon = b.parts.Spot3 :: Part
	moon.Shape = Enum.PartType.Ball
	add(
		b,
		"Ring",
		Vector3.new(0.12, 5.2, 5.2),
		CFrame.new(0, 2.6, 0) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(math.rad(18), 0, 0),
		b.cow.spotColor,
		{ shape = Enum.PartType.Cylinder, material = Enum.Material.Neon, transparency = 0.15 }
	)
	-- human feet: two skinny legs with sneakers, no back legs
	remove(b, "LegBL")
	remove(b, "LegBR")
	local skin = Color3.fromRGB(240, 195, 160)
	resize(b, "LegFL", Vector3.new(0.35, 1.3, 0.35), CFrame.new(-0.5, 0.65, 0))
	resize(b, "LegFR", Vector3.new(0.35, 1.3, 0.35), CFrame.new(0.5, 0.65, 0))
	recolor(b, { "LegFL", "LegFR" }, skin)
	add(b, "ShoeL", Vector3.new(0.6, 0.3, 0.9), CFrame.new(-0.5, 0.15, -0.2), Color3.fromRGB(255, 255, 255))
	add(b, "ShoeR", Vector3.new(0.6, 0.3, 0.9), CFrame.new(0.5, 0.15, -0.2), Color3.fromRGB(255, 255, 255))
	-- tail sticks out of the back of the planet
	resize(b, "Tail", Vector3.new(0.2, 1.0, 0.2), CFrame.new(0, 2.5, 1.7) * CFrame.Angles(math.rad(-40), 0, 0))
	resize(b, "TailTip", Vector3.new(0.32, 0.4, 0.32), CFrame.new(0, 2.1, 2.0))
	-- head peeks out of the top front of the planet
	local neck = b.head:FindFirstChild("Neck") :: Motor6D?
	if neck then
		neck.C0 = scaled(b, CFrame.new(0, 3.9, -1.2))
	end
	addLight(b, Color3.fromRGB(190, 150, 255), 14, 2.5)
	addParticles(b, PARTICLE_SPARKLE, Color3.fromRGB(255, 230, 140), 10, 0.7, 3, 1.5)
	addParticles(b, PARTICLE_SPARKLE, Color3.fromRGB(170, 120, 255), 6, 0.4, 2, 2, "Ring")
end

-- Makes an approximate world-space CFrame for every part follow its joint again,
-- so the model looks right even where joints are not solved (ViewportFrames, or before
-- the model is parented to the workspace).
local function settle(b: Builder)
	local headCF = b.root.CFrame
	local neck = b.head:FindFirstChild("Neck") :: Motor6D?
	if neck then
		headCF = b.root.CFrame * neck.C0 * neck.C1:Inverse()
	end
	b.head.CFrame = headCF
	for _, d in b.model:GetDescendants() do
		if d:IsA("Weld") and d.Part0 == b.head and d.Part1 then
			(d.Part1 :: BasePart).CFrame = headCF * d.C0 * d.C1:Inverse()
		end
	end
end

function CowModels.Build(tier: number): Model
	local cow = Cows.Get(tier) or Cows.Tiers[1]
	local model = Instance.new("Model")
	model.Name = "Cow_" .. cow.id
	model:SetAttribute("CowTier", cow.tier)
	model:SetAttribute("CowId", cow.id)

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 0.2, 1)
	root.CFrame = CFrame.identity
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.Parent = model
	model.PrimaryPart = root

	local b: Builder = {
		model = model,
		root = root,
		head = root, -- replaced in buildBase
		scale = 1 + (cow.tier - 1) * 0.015, -- top tiers are a little bigger
		count = 1,
		cow = cow,
		parts = {},
	}

	buildBase(b)
	local extra = EXTRAS[cow.id]
	if extra then
		extra(b)
	end
	settle(b)

	if b.count > MAX_PARTS then
		warn(`[CowModels] {cow.id} uses {b.count} parts (max {MAX_PARTS})`)
	end
	return model
end

-- Number of parts per tier, handy for the PR/test snippet.
function CowModels.PartCount(model: Model): number
	local n = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

return CowModels
