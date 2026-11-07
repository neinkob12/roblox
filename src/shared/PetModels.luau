--!strict
-- F2: Part-built pet models (no meshes, no Toolbox). Shared so the server could use them too, but
-- today only the client builds them (PetFollowController, NestController, PetViewport).
--
--   PetModels.Build(petId, variant?) -> Model
--     Small blocky brainrot creature, about 1.5 to 2.5 studs. PrimaryPart "Root" (invisible) sits
--     at the model's feet, front = -Z (same convention as CowModels). Every part is anchored,
--     non-colliding, non-touching and non-queryable, so the caller just PivotTo()s the model.
--     At most 25 parts per pet (Root and the variant sparkle anchor included).
--   variant "normal" | "golden" | "rainbow" (unknown -> "normal")
--     golden   every colored part turns gold (Foil) + a sparkle ParticleEmitter
--     rainbow  every colored part is tagged with attribute RainbowPart = true (the client cycles
--              their color, see PetModels.RainbowColor) + a rainbow ParticleEmitter
--   PetModels.BuildEgg(eggId) -> Model         an egg for nests (PrimaryPart "Root" at the bottom)
--   PetModels.RainbowColor(t, offset) -> Color3  the shared rainbow cycle
--   PetModels.Has(petId) -> boolean             true when a dedicated style exists for that id
--
-- Styles are keyed by the Config/Pets ids (F1). An unknown id still builds (plain colored body).

local PetModels = {}

type Spec = {
	body: Color3,
	belly: Color3,
	accent: Color3,
	shape: string, -- "block" | "ball" | "tall" | "wide"
	size: number, -- overall scale, 1 = 2 studs tall
	extras: (add: AddFn, s: number, spec: Spec) -> (),
}

type AddFn = (name: string, size: Vector3, pos: Vector3, color: Color3, opts: PartOpts?) -> BasePart
type PartOpts = { shape: Enum.PartType?, material: Enum.Material?, rot: Vector3?, keepColor: boolean? }

local WHITE = Color3.fromRGB(255, 255, 255)
local BLACK = Color3.fromRGB(25, 20, 30)
local PINK = Color3.fromRGB(255, 160, 190)
local GOLD = Color3.fromRGB(255, 200, 60)
local CREAM = Color3.fromRGB(255, 244, 214)

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function norm(s: string): string
	return (string.gsub(string.lower(s), "[^%w]", ""))
end

------------------------------------------------------------------------------ styles
-- `extras` adds the themed bits on top of the shared body (body, head, eyes, legs, snout).
-- Coordinates are in studs for size = 1, origin at the feet, front = -Z. Head center is about
-- (0, 1.45, -0.35); body top is at y = 1.1.

local STYLES: { [string]: Spec } = {
	-- Common ------------------------------------------------------------
	mochi = { -- squishy rice cake cow (milk)
		body = rgb(255, 214, 230),
		belly = WHITE,
		accent = rgb(150, 220, 140),
		shape = "ball",
		size = 0.8,
		extras = function(add, s, spec)
			add("Leaf", Vector3.new(0.5, 0.08, 0.3) * s, Vector3.new(0, 1.95, -0.35) * s, spec.accent)
			add("Blush", Vector3.new(0.2, 0.1, 0.05) * s, Vector3.new(-0.32, 1.32, -0.73) * s, PINK)
			add("Blush2", Vector3.new(0.2, 0.1, 0.05) * s, Vector3.new(0.32, 1.32, -0.73) * s, PINK)
		end,
	},
	cheddarino = { -- cheese wedge gentleman (cash)
		body = rgb(255, 205, 60),
		belly = rgb(255, 230, 120),
		accent = BLACK,
		shape = "wide",
		size = 0.85,
		extras = function(add, s, spec)
			add("HatBrim", Vector3.new(0.8, 0.06, 0.8) * s, Vector3.new(0, 1.83, -0.35) * s, spec.accent)
			add("HatTop", Vector3.new(0.5, 0.45, 0.5) * s, Vector3.new(0, 2.08, -0.35) * s, spec.accent)
			add("Hole", Vector3.new(0.18, 0.18, 0.05) * s, Vector3.new(0.4, 0.75, -0.62) * s, rgb(220, 160, 30))
			add("Hole2", Vector3.new(0.12, 0.12, 0.05) * s, Vector3.new(-0.35, 0.55, -0.62) * s, rgb(220, 160, 30))
			add("Monocle", Vector3.new(0.22, 0.22, 0.04) * s, Vector3.new(0.18, 1.5, -0.75) * s, GOLD, {
				shape = Enum.PartType.Cylinder,
				rot = Vector3.new(0, 90, 0),
			})
		end,
	},
	calfetto = { -- tiny calf with a racing stripe (speed)
		body = rgb(250, 250, 250),
		belly = rgb(240, 240, 240),
		accent = rgb(235, 60, 60),
		shape = "block",
		size = 0.75,
		extras = function(add, s, spec)
			add("Stripe", Vector3.new(0.2, 0.05, 1.22) * s, Vector3.new(0, 1.12, 0.05) * s, spec.accent)
			add(
				"Spot",
				Vector3.new(0.35, 0.3, 0.05) * s,
				Vector3.new(0.6, 0.75, 0.2) * s,
				BLACK,
				{ rot = Vector3.new(0, 90, 0) }
			)
			add("Goggles", Vector3.new(0.7, 0.14, 0.06) * s, Vector3.new(0, 1.72, -0.72) * s, rgb(60, 160, 255))
		end,
	},
	-- Uncommon ----------------------------------------------------------
	butterbun = { -- butter bun (milk)
		body = rgb(240, 180, 90),
		belly = rgb(255, 230, 150),
		accent = rgb(255, 235, 110),
		shape = "ball",
		size = 0.9,
		extras = function(add, s, spec)
			add("Butter", Vector3.new(0.45, 0.15, 0.45) * s, Vector3.new(0, 1.92, -0.35) * s, spec.accent)
			add("Seed", Vector3.new(0.08, 0.05, 0.14) * s, Vector3.new(0.3, 1.1, 0.3) * s, CREAM)
			add("Seed2", Vector3.new(0.08, 0.05, 0.14) * s, Vector3.new(-0.25, 1.1, 0.1) * s, CREAM)
		end,
	},
	latte = { -- coffee cup llama-cow (cash)
		body = rgb(160, 110, 75),
		belly = rgb(235, 215, 185),
		accent = WHITE,
		shape = "tall",
		size = 0.9,
		extras = function(add, s, spec)
			add("Foam", Vector3.new(0.75, 0.12, 0.75) * s, Vector3.new(0, 1.12, 0.05) * s, spec.accent)
			add("Handle", Vector3.new(0.12, 0.45, 0.35) * s, Vector3.new(0.62, 0.65, 0.05) * s, spec.accent)
			add(
				"Heart",
				Vector3.new(0.2, 0.2, 0.04) * s,
				Vector3.new(0, 1.2, 0.05) * s,
				rgb(200, 140, 100),
				{ rot = Vector3.new(90, 45, 0) }
			)
		end,
	},
	clover = { -- lucky clover cow (luck)
		body = rgb(120, 210, 110),
		belly = rgb(200, 245, 190),
		accent = rgb(40, 150, 60),
		shape = "block",
		size = 0.85,
		extras = function(add, s, spec)
			for i = 0, 3 do
				local a = math.rad(i * 90 + 45)
				add(
					"Clover" .. i,
					Vector3.new(0.25, 0.08, 0.25) * s,
					Vector3.new(math.cos(a) * 0.15, 1.93, -0.35 + math.sin(a) * 0.15) * s,
					spec.accent,
					{ shape = Enum.PartType.Ball }
				)
			end
		end,
	},
	-- Rare --------------------------------------------------------------
	sprinkle = { -- donut with sprinkles (milk)
		body = rgb(255, 150, 200),
		belly = rgb(240, 190, 130),
		accent = rgb(120, 200, 255),
		shape = "wide",
		size = 0.95,
		extras = function(add, s, spec)
			local cols = { spec.accent, rgb(255, 230, 80), rgb(120, 230, 120), WHITE }
			for i = 1, 4 do
				add(
					"Sprinkle" .. i,
					Vector3.new(0.06, 0.04, 0.2) * s,
					Vector3.new(-0.45 + i * 0.2, 1.12, -0.1 + (i % 2) * 0.3) * s,
					cols[i],
					{ rot = Vector3.new(0, i * 40, 0) }
				)
			end
		end,
	},
	moozzarella = { -- stretchy cheese twirl (cash)
		body = rgb(255, 250, 235),
		belly = rgb(250, 240, 210),
		accent = rgb(230, 70, 60),
		shape = "tall",
		size = 1,
		extras = function(add, s, spec)
			for i = 1, 3 do
				add(
					"Twirl" .. i,
					Vector3.new(0.9 - i * 0.18, 0.12, 0.9 - i * 0.18) * s,
					Vector3.new(0, 1.85 + i * 0.13, -0.35) * s,
					if i % 2 == 0 then spec.accent else spec.body,
					{ shape = Enum.PartType.Cylinder, rot = Vector3.new(0, 0, 90) }
				)
			end
			add("Basil", Vector3.new(0.25, 0.05, 0.15) * s, Vector3.new(0.35, 1.13, 0.2) * s, rgb(60, 170, 70))
		end,
	},
	turbo = { -- rocket hooves (speed)
		body = rgb(70, 140, 255),
		belly = rgb(190, 220, 255),
		accent = rgb(255, 140, 40),
		shape = "block",
		size = 0.95,
		extras = function(add, s, spec)
			for _, x in { -0.35, 0.35 } do
				add(
					"Booster",
					Vector3.new(0.5, 0.25, 0.25) * s,
					Vector3.new(x, 0.75, 0.78) * s,
					rgb(180, 185, 200),
					{ shape = Enum.PartType.Cylinder, rot = Vector3.new(0, 90, 0) }
				)
				add("Flame", Vector3.new(0.18, 0.18, 0.18) * s, Vector3.new(x, 0.75, 1.1) * s, spec.accent, {
					shape = Enum.PartType.Ball,
					material = Enum.Material.Neon,
				})
			end
		end,
	},
	-- Epic --------------------------------------------------------------
	galacto = { -- ice cream cone cow (milk)
		body = rgb(180, 140, 255),
		belly = rgb(230, 210, 255),
		accent = rgb(220, 170, 100),
		shape = "ball",
		size = 1,
		extras = function(add, s, spec)
			add(
				"Scoop",
				Vector3.new(0.6, 0.5, 0.6) * s,
				Vector3.new(0, 2.05, -0.35) * s,
				rgb(120, 230, 210),
				{ shape = Enum.PartType.Ball }
			)
			add(
				"Cherry",
				Vector3.new(0.2, 0.2, 0.2) * s,
				Vector3.new(0, 2.38, -0.35) * s,
				rgb(230, 40, 60),
				{ shape = Enum.PartType.Ball }
			)
			add(
				"Cone",
				Vector3.new(0.5, 0.35, 0.5) * s,
				Vector3.new(0, 0.2, 0) * s,
				spec.accent,
				{ rot = Vector3.new(0, 45, 0) }
			)
			add(
				"Star",
				Vector3.new(0.12, 0.12, 0.12) * s,
				Vector3.new(0.5, 0.9, -0.5) * s,
				WHITE,
				{ material = Enum.Material.Neon }
			)
		end,
	},
	bubbletea = { -- bubble tea bull (luck)
		body = rgb(210, 170, 130),
		belly = rgb(240, 220, 190),
		accent = rgb(255, 120, 170),
		shape = "tall",
		size = 1,
		extras = function(add, s, spec)
			add(
				"Lid",
				Vector3.new(0.85, 0.1, 0.85) * s,
				Vector3.new(0, 1.15, 0.05) * s,
				WHITE,
				{ material = Enum.Material.Glass }
			)
			add(
				"Straw",
				Vector3.new(0.1, 0.9, 0.1) * s,
				Vector3.new(0.25, 1.55, 0.25) * s,
				spec.accent,
				{ rot = Vector3.new(0, 0, -15) }
			)
			for i = 1, 3 do
				add(
					"Pearl" .. i,
					Vector3.new(0.14, 0.14, 0.14) * s,
					Vector3.new(-0.5 + i * 0.25, 0.25, -0.63) * s,
					BLACK,
					{ shape = Enum.PartType.Ball }
				)
			end
			add(
				"HornL",
				Vector3.new(0.12, 0.3, 0.12) * s,
				Vector3.new(-0.38, 1.85, -0.35) * s,
				CREAM,
				{ rot = Vector3.new(0, 0, 25) }
			)
			add(
				"HornR",
				Vector3.new(0.12, 0.3, 0.12) * s,
				Vector3.new(0.38, 1.85, -0.35) * s,
				CREAM,
				{ rot = Vector3.new(0, 0, -25) }
			)
		end,
	},
	creamquake = { -- cowboy cream (cash)
		body = rgb(255, 240, 220),
		belly = WHITE,
		accent = rgb(150, 95, 50),
		shape = "block",
		size = 1.05,
		extras = function(add, s, spec)
			add("HatBrim", Vector3.new(1.2, 0.07, 0.95) * s, Vector3.new(0, 1.82, -0.35) * s, spec.accent)
			add("HatTop", Vector3.new(0.6, 0.35, 0.55) * s, Vector3.new(0, 2.02, -0.35) * s, spec.accent)
			add("HatBand", Vector3.new(0.62, 0.08, 0.57) * s, Vector3.new(0, 1.9, -0.35) * s, rgb(230, 60, 60))
			add("Bandana", Vector3.new(0.75, 0.2, 0.08) * s, Vector3.new(0, 1.05, -0.62) * s, rgb(230, 60, 60))
			add(
				"Spot",
				Vector3.new(0.3, 0.35, 0.05) * s,
				Vector3.new(-0.62, 0.7, 0.1) * s,
				spec.accent,
				{ rot = Vector3.new(0, 90, 0) }
			)
		end,
	},
	-- Legendary ---------------------------------------------------------
	churnado = { -- swirling galaxy butter churn (milk)
		body = rgb(60, 40, 140),
		belly = rgb(120, 90, 220),
		accent = rgb(110, 230, 255),
		shape = "tall",
		size = 1.15,
		extras = function(add, s, spec)
			for i = 1, 3 do
				add(
					"Swirl" .. i,
					Vector3.new(0.12, 1.3 - i * 0.2, 1.3 - i * 0.2) * s,
					Vector3.new(0, 1.85 + i * 0.12, -0.35) * s,
					spec.accent,
					{ shape = Enum.PartType.Cylinder, rot = Vector3.new(0, 0, 90), material = Enum.Material.Neon }
				)
			end
			add(
				"Star",
				Vector3.new(0.14, 0.14, 0.14) * s,
				Vector3.new(-0.5, 0.9, -0.62) * s,
				WHITE,
				{ material = Enum.Material.Neon }
			)
			add(
				"Star2",
				Vector3.new(0.1, 0.1, 0.1) * s,
				Vector3.new(0.45, 0.5, -0.62) * s,
				rgb(255, 230, 120),
				{ material = Enum.Material.Neon }
			)
		end,
	},
	yogurtron = { -- yogurt robot king (cash)
		body = rgb(235, 240, 255),
		belly = rgb(200, 210, 235),
		accent = GOLD,
		shape = "block",
		size = 1.2,
		extras = function(add, s, spec)
			add(
				"Crown",
				Vector3.new(0.7, 0.2, 0.7) * s,
				Vector3.new(0, 1.9, -0.35) * s,
				spec.accent,
				{ material = Enum.Material.Foil, keepColor = true }
			)
			for i, x in { -0.25, 0, 0.25 } do
				add(
					"Spike" .. i,
					Vector3.new(0.14, 0.22, 0.14) * s,
					Vector3.new(x, 2.1, -0.35) * s,
					spec.accent,
					{ material = Enum.Material.Foil, keepColor = true }
				)
			end
			add(
				"Gem",
				Vector3.new(0.12, 0.12, 0.05) * s,
				Vector3.new(0, 1.92, -0.72) * s,
				rgb(230, 40, 80),
				{ material = Enum.Material.Neon }
			)
			add("Antenna", Vector3.new(0.06, 0.4, 0.06) * s, Vector3.new(0.35, 0.95, 0.4) * s, rgb(150, 160, 180))
			add(
				"Light",
				Vector3.new(0.14, 0.14, 0.14) * s,
				Vector3.new(0.35, 1.2, 0.4) * s,
				rgb(90, 255, 140),
				{ shape = Enum.PartType.Ball, material = Enum.Material.Neon }
			)
		end,
	},
	moonmilk = { -- crescent moon milk spirit (luck)
		body = rgb(40, 50, 110),
		belly = rgb(240, 240, 210),
		accent = rgb(255, 235, 140),
		shape = "ball",
		size = 1.1,
		extras = function(add, s, spec)
			add("Moon", Vector3.new(0.12, 0.6, 0.6) * s, Vector3.new(0, 2.05, -0.35) * s, spec.accent, {
				shape = Enum.PartType.Cylinder,
				rot = Vector3.new(0, 90, 0),
				material = Enum.Material.Neon,
			})
			add("MoonCut", Vector3.new(0.14, 0.5, 0.5) * s, Vector3.new(0, 2.12, -0.22) * s, spec.body, {
				shape = Enum.PartType.Cylinder,
				rot = Vector3.new(0, 90, 0),
			})
			add(
				"Clover",
				Vector3.new(0.18, 0.18, 0.05) * s,
				Vector3.new(-0.3, 0.75, -0.72) * s,
				rgb(90, 220, 110),
				{ rot = Vector3.new(0, 0, 45) }
			)
			add(
				"Star",
				Vector3.new(0.12, 0.12, 0.12) * s,
				Vector3.new(0.55, 1.3, -0.4) * s,
				WHITE,
				{ material = Enum.Material.Neon }
			)
		end,
	},
}

local function styleFor(petId: string): (Spec, boolean)
	local spec = STYLES[petId]
	if spec then
		return spec, true
	end
	-- unknown pet: a deterministic color from the id, plain body
	local h = 0
	for i = 1, #petId do
		h = (h * 31 + string.byte(petId, i)) % 360
	end
	return {
		body = Color3.fromHSV(h / 360, 0.5, 0.95),
		belly = WHITE,
		accent = Color3.fromHSV(((h + 180) % 360) / 360, 0.7, 0.9),
		shape = "block",
		size = 0.9,
		extras = function() end,
	},
		false
end

function PetModels.Has(petId: string): boolean
	local _, known = styleFor(petId)
	return known
end

------------------------------------------------------------------------------ build

local function newPart(name: string, size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Massless = true
	return p
end

function PetModels.RainbowColor(t: number, offset: number): Color3
	return Color3.fromHSV((t * 0.25 + offset) % 1, 0.75, 1)
end

local function emitter(parent: Instance, color: ColorSequence, rate: number)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Sparkle"
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = color
	e.Rate = rate
	e.Lifetime = NumberRange.new(0.6, 1.1)
	e.Speed = NumberRange.new(0.5, 1.5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
	e.LightEmission = 0.8
	e.Parent = parent
end

function PetModels.Build(petId: string, variant: string?): Model
	local v = if variant == "golden" or variant == "rainbow" then variant else "normal"
	local spec = styleFor(petId)
	local s = spec.size

	local model = Instance.new("Model")
	model.Name = "Pet_" .. petId
	model:SetAttribute("PetId", petId)
	model:SetAttribute("Variant", v)

	local root = newPart("Root", Vector3.new(0.4, 0.2, 0.4), CFrame.new(0, 0.1, 0), WHITE)
	root.Transparency = 1
	root.Parent = model
	model.PrimaryPart = root

	local count = 1
	local rainbowIndex = 0
	local function add(name: string, size: Vector3, pos: Vector3, color: Color3, opts: PartOpts?): BasePart
		local o: PartOpts = opts or {}
		local rot = o.rot or Vector3.zero
		local cf = CFrame.new(pos) * CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
		local p = newPart(name, size, cf, color, o.shape)
		if o.material then
			p.Material = o.material
		end
		-- eyes stay black/white in every variant so the face reads
		local isFace = color == BLACK or color == WHITE and string.find(name, "Eye") ~= nil
		if not isFace then
			if v == "golden" then
				p.Color = GOLD:Lerp(color, 0.15)
				p.Material = Enum.Material.Foil
			elseif v == "rainbow" then
				rainbowIndex += 1
				p:SetAttribute("RainbowPart", true)
				p:SetAttribute("RainbowOffset", (rainbowIndex * 0.07) % 1)
				p.Color = PetModels.RainbowColor(0, (rainbowIndex * 0.07) % 1)
			end
		end
		count += 1
		if count > 25 then
			warn(`[PetModels] {petId} exceeds 25 parts`)
			p:Destroy()
			return p
		end
		p.Parent = model
		return p
	end

	-- shared body ---------------------------------------------------------
	local bodySize = if spec.shape == "wide"
		then Vector3.new(1.3, 0.8, 1.2)
		elseif spec.shape == "tall" then Vector3.new(1.1, 0.95, 1.1)
		else Vector3.new(1.15, 0.8, 1.25)
	local bodyShape: Enum.PartType? = if spec.shape == "ball" then Enum.PartType.Ball else nil
	if spec.shape == "ball" then
		bodySize = Vector3.new(1.2, 1.2, 1.2)
	end
	local bodyY = 0.3 + bodySize.Y / 2
	add("Body", bodySize * s, Vector3.new(0, bodyY, 0.05) * s, spec.body, { shape = bodyShape })
	add(
		"Belly",
		Vector3.new(bodySize.X * 0.7, bodySize.Y * 0.6, 0.06) * s,
		Vector3.new(0, bodyY - 0.05, 0.05 - bodySize.Z / 2 - 0.02) * s,
		spec.belly
	)
	-- head
	add("Head", Vector3.new(0.9, 0.75, 0.75) * s, Vector3.new(0, 1.45, -0.35) * s, spec.body)
	add("Snout", Vector3.new(0.55, 0.28, 0.12) * s, Vector3.new(0, 1.25, -0.77) * s, PINK)
	for _, side in { -1, 1 } do
		add("Eye", Vector3.new(0.2, 0.22, 0.05) * s, Vector3.new(side * 0.2, 1.55, -0.74) * s, WHITE)
		add("Pupil", Vector3.new(0.1, 0.12, 0.04) * s, Vector3.new(side * 0.2, 1.53, -0.775) * s, BLACK)
		add(
			"Ear",
			Vector3.new(0.28, 0.14, 0.18) * s,
			Vector3.new(side * 0.55, 1.62, -0.3) * s,
			spec.body,
			{ rot = Vector3.new(0, 0, side * -20) }
		)
	end
	-- stubby legs
	for _, x in { -0.35, 0.35 } do
		for _, z in { -0.35, 0.4 } do
			add("Leg", Vector3.new(0.25, 0.3, 0.25) * s, Vector3.new(x, 0.15, z) * s, spec.belly)
		end
	end

	spec.extras(add, s, spec)

	-- variant sparkle ---------------------------------------------------------
	if v == "golden" then
		emitter(root, ColorSequence.new(rgb(255, 230, 120)), 6)
	elseif v == "rainbow" then
		emitter(
			root,
			ColorSequence.new({
				ColorSequenceKeypoint.new(0, rgb(255, 80, 80)),
				ColorSequenceKeypoint.new(0.5, rgb(80, 220, 255)),
				ColorSequenceKeypoint.new(1, rgb(200, 100, 255)),
			}),
			10
		)
	end
	model.WorldPivot = root.CFrame * CFrame.new(0, -0.1, 0)
	return model
end

------------------------------------------------------------------------------ eggs

local EGG_COLORS: { [string]: { Color3 } } = {
	pasture = { rgb(250, 248, 235), rgb(120, 200, 90) },
	dairy = { rgb(200, 230, 255), rgb(70, 140, 230) },
	cosmic = { rgb(90, 60, 180), rgb(120, 230, 255) },
}

function PetModels.BuildEgg(eggId: string): Model
	local key = norm(eggId)
	local cols = EGG_COLORS[key]
	if not cols then
		for k, c in EGG_COLORS do
			if string.find(key, k, 1, true) then
				cols = c
				break
			end
		end
	end
	local base = if cols then cols[1] else CREAM
	local spot = if cols then cols[2] else rgb(255, 180, 80)

	local model = Instance.new("Model")
	model.Name = "Egg"
	model:SetAttribute("EggId", eggId)
	local root = newPart("Root", Vector3.new(0.4, 0.2, 0.4), CFrame.new(0, 0.1, 0), WHITE)
	root.Transparency = 1
	root.Parent = model
	model.PrimaryPart = root
	local shell = newPart("Shell", Vector3.new(1.6, 2, 1.6), CFrame.new(0, 1, 0), base, Enum.PartType.Ball)
	shell.Parent = model
	local top = newPart("Top", Vector3.new(1.1, 0.9, 1.1), CFrame.new(0, 1.75, 0), base, Enum.PartType.Ball)
	top.Parent = model
	for i = 0, 4 do
		local a = math.rad(i * 72)
		local pos = Vector3.new(math.cos(a) * 0.72, 0.8 + (i % 2) * 0.55, math.sin(a) * 0.72)
		local dot = newPart("Spot", Vector3.new(0.35, 0.35, 0.12), CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0)), spot)
		dot.Parent = model
	end
	if key == "cosmic" or string.find(key, "cosmic", 1, true) then
		shell.Material = Enum.Material.Neon
		shell.Transparency = 0.15
	end
	model.WorldPivot = CFrame.identity
	return model
end

return PetModels
