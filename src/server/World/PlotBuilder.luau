--!strict
-- Builds one barn plot (CONTRACTS section 6). Library only, called by MapBuilder.
-- Owner: A1 World & Map. Geometry, names and labels only: NO pad behavior here.
--
-- Plot-local coordinates (relative to the plot CFrame passed in):
--   origin = plot center on the ground, -Z = front (toward the dairy), +Z = back (barn wall).
--   Plot is PLOT_W (x) by PLOT_D (z). Front edge is z = -PLOT_D/2 and has a wide open gate.
--
-- Layout (top view, dairy is below):
--
--   +Z  [ barn wall + door ......................................... ]
--       [ Stall10 .. Stall18  (raised back row)                      ]
--       [ Stall1  .. Stall9   (front row)                            ]
--   |pipe                         CrateSpawn
--   |      Tank                            MergePad
--   |                Spawn
--          TankTap                 BuyPad1  BuyPad5  BuyPad25
--   -Z  ----fence----        gate / OwnerSign            ----fence----

local Builder = require(script.Parent.Builder)

local PlotBuilder = {}

PlotBuilder.PLOT_W = 64
PlotBuilder.PLOT_D = 72
PlotBuilder.STALL_COUNT = 18

local PLOT_W = PlotBuilder.PLOT_W
local PLOT_D = PlotBuilder.PLOT_D
local HALF_W = PLOT_W / 2
local HALF_D = PLOT_D / 2
local FLOOR = 0.3 -- top of the plot floor slab
local GATE_HALF = 24 -- front fence is open for |x| < GATE_HALF

local STALLS_PER_ROW = 9
local STALL_PITCH = 6.6
local STALL_W = 6
local STALL_D = 7
local FRONT_ROW_Z = 18
local BACK_ROW_Z = 29.5
local BACK_ROW_RISE = 1.2
local PIPE_HEIGHT = 6 -- above each row's floor
local PIPE_D = 0.7
local MAIN_X = -30.6 -- the main pipe runs along the left side of the plot

local TANK_X = -22
local TANK_Z = -13
local TANK_SIZE = 10
local TANK_H = 13
local TANK_PLINTH = 0.6

-- F2 nests: plot-local (x, z) of Nest1..Nest4, right of the spawn, between MergePad and the stalls
local NEST_SPOTS = { Vector2.new(17, -1), Vector2.new(25, -1), Vector2.new(17, 7), Vector2.new(25, 7) }
local NEST_RADIUS = 1.8
local NEST_H = 1.4

local C = {
	stone = Color3.fromRGB(170, 165, 160),
	hayDark = Color3.fromRGB(205, 165, 70),
	floor = Color3.fromRGB(140, 206, 86),
	dirt = Color3.fromRGB(214, 172, 110),
	fence = Color3.fromRGB(250, 246, 236),
	barn = Color3.fromRGB(206, 52, 46),
	barnDark = Color3.fromRGB(160, 36, 34),
	trim = Color3.fromRGB(255, 255, 255),
	hay = Color3.fromRGB(240, 204, 96),
	stallWall = Color3.fromRGB(196, 140, 84),
	pipe = Color3.fromRGB(200, 210, 222),
	glass = Color3.fromRGB(190, 230, 255),
	milk = Color3.fromRGB(255, 255, 250),
	metal = Color3.fromRGB(150, 160, 175),
	buy = Color3.fromRGB(70, 200, 90),
	merge = Color3.fromRGB(170, 90, 230),
	tap = Color3.fromRGB(70, 160, 255),
	crate = Color3.fromRGB(255, 190, 60),
	post = Color3.fromRGB(120, 80, 50),
}

local function pad(name: string, cf: CFrame, color: Color3, text: string, parent: Instance): BasePart
	local p = Builder.part({
		Name = name,
		Size = Vector3.new(9, 0.2, 9),
		CFrame = cf,
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	Builder.padLabel(p, text)
	return p
end

-- Builds a plot. `cf` = plot center on the ground with -Z facing the dairy.
function PlotBuilder.Build(id: number, cf: CFrame, accent: Color3, parent: Instance): Model
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local function wp(x: number, y: number, z: number): Vector3
		return cf:PointToWorldSpace(Vector3.new(x, y, z))
	end

	local plot = Instance.new("Model")
	plot.Name = "Plot" .. id
	plot:SetAttribute("PlotId", id)
	plot:SetAttribute("OwnerUserId", 0)

	local decor = Builder.folder("Decor", plot)

	-- Floor ---------------------------------------------------------------
	local floor = Builder.part({
		Name = "Floor",
		Size = Vector3.new(PLOT_W, FLOOR, PLOT_D),
		CFrame = at(0, FLOOR / 2, 0),
		Color = C.floor,
		Parent = plot,
	})
	plot.PrimaryPart = floor
	-- dirt walkway from the gate into the yard
	Builder.decor({
		Name = "Walkway",
		Size = Vector3.new(2 * GATE_HALF, 0.05, 30),
		CFrame = at(0, FLOOR + 0.025, -HALF_D + 15),
		Color = C.dirt,
		Parent = decor,
	})

	-- Fences (sides + front corners; the barn wall closes the back) --------
	local function rail(len: number, cfr: CFrame)
		for _, y in { 1.2, 2.5 } do
			Builder.part({
				Name = "Rail",
				Size = Vector3.new(len, 0.4, 0.3),
				CFrame = cfr * CFrame.new(0, y, 0),
				Color = C.fence,
				CanTouch = false,
				Parent = decor,
			})
		end
	end
	local function post(x: number, z: number, cap: boolean)
		Builder.part({
			Name = "Post",
			Size = Vector3.new(0.8, 3.4, 0.8),
			CFrame = at(x, FLOOR + 1.7, z),
			Color = C.fence,
			CanTouch = false,
			Parent = decor,
		})
		if cap then
			Builder.decor({
				Name = "PostCap",
				Size = Vector3.new(1.1, 0.5, 1.1),
				CFrame = at(x, FLOOR + 3.6, z),
				Color = accent,
				Parent = decor,
			})
		end
	end
	for _, side in { -1, 1 } do
		local x = side * HALF_W
		rail(PLOT_D, at(x, FLOOR, 0) * CFrame.Angles(0, math.pi / 2, 0))
		for z = -HALF_D, HALF_D - 8, 8 do
			post(x, z, z == -HALF_D)
		end
		-- front corner segment
		local segLen = HALF_W - GATE_HALF
		rail(segLen, at(side * (GATE_HALF + segLen / 2), FLOOR, -HALF_D))
		post(side * GATE_HALF, -HALF_D, true)
	end

	-- Barn wall at the back ------------------------------------------------
	local wallH = 10
	Builder.part({
		Name = "BarnWall",
		Size = Vector3.new(PLOT_W, wallH, 1),
		CFrame = at(0, FLOOR + wallH / 2, HALF_D - 0.5),
		Color = C.barn,
		CanTouch = false,
		Parent = decor,
	})
	Builder.decor({
		Name = "BarnTrim",
		Size = Vector3.new(PLOT_W + 0.4, 0.6, 1.4),
		CFrame = at(0, FLOOR + wallH, HALF_D - 0.5),
		Color = C.trim,
		Parent = decor,
	})
	-- stepped (blocky) gable
	local stepW = { 52, 40, 28, 16 }
	for i, w in stepW do
		Builder.decor({
			Name = "Gable",
			Size = Vector3.new(w, 2.5, 1),
			CFrame = at(0, FLOOR + wallH + 0.3 + 1.25 + (i - 1) * 2.5, HALF_D - 0.5),
			Color = if i % 2 == 0 then C.barnDark else C.barn,
			Parent = decor,
		})
	end
	Builder.decor({
		Name = "GableTop",
		Size = Vector3.new(6, 1, 1.4),
		CFrame = at(0, FLOOR + wallH + 0.3 + 10.5, HALF_D - 0.5),
		Color = accent,
		Parent = decor,
	})
	-- barn door with white X
	local doorW, doorH = 14, 8.5
	local doorZ = HALF_D - 1.15
	Builder.decor({
		Name = "BarnDoor",
		Size = Vector3.new(doorW, doorH, 0.3),
		CFrame = at(0, FLOOR + doorH / 2, doorZ),
		Color = C.barnDark,
		Parent = decor,
	})
	local diag = math.sqrt(doorW * doorW + doorH * doorH)
	local ang = math.atan2(doorH, doorW)
	for _, sign in { -1, 1 } do
		Builder.decor({
			Name = "DoorX",
			Size = Vector3.new(diag - 0.6, 0.6, 0.2),
			CFrame = at(0, FLOOR + doorH / 2, doorZ - 0.2) * CFrame.Angles(0, 0, sign * ang),
			Color = C.trim,
			Parent = decor,
		})
	end
	Builder.decor({
		Name = "DoorFrame",
		Size = Vector3.new(doorW + 1, 0.8, 0.4),
		CFrame = at(0, FLOOR + doorH + 0.4, doorZ - 0.1),
		Color = C.trim,
		Parent = decor,
	})

	-- Back row platform ----------------------------------------------------
	Builder.part({
		Name = "StallPlatform",
		Size = Vector3.new(STALLS_PER_ROW * STALL_PITCH + 1, BACK_ROW_RISE, STALL_D + 2),
		CFrame = at(0, FLOOR + BACK_ROW_RISE / 2, BACK_ROW_Z),
		Color = C.stallWall,
		CanTouch = false,
		Parent = decor,
	})

	-- Stalls + pipes ---------------------------------------------------------
	local stalls = Builder.folder("Stalls", plot)
	local pipes = Builder.folder("Pipes", plot)
	local function addPipe(name: string, a: Vector3, b: Vector3, order: number): BasePart
		local p = Builder.pipe(a, b, PIPE_D, {
			Name = name,
			Color = C.pipe,
			Material = Enum.Material.SmoothPlastic,
			Parent = pipes,
		})
		p:SetAttribute("FlowOrder", order)
		return p
	end
	local function joint(pos: Vector3)
		Builder.ball(pos, PIPE_D + 0.25, { Name = "Joint", Color = C.metal, Parent = decor })
	end

	local firstX = -((STALLS_PER_ROW - 1) * STALL_PITCH) / 2
	local rows = {
		{ z = BACK_ROW_Z, baseY = FLOOR + BACK_ROW_RISE, first = 10 },
		{ z = FRONT_ROW_Z, baseY = FLOOR, first = 1 },
	}
	-- FlowOrder: 1 = risers, 2 = manifolds, 3.. = main line toward the tank
	for _, row in rows do
		local pipeY = row.baseY + PIPE_HEIGHT
		local pipeZ = row.z + STALL_D / 2 - 0.85
		for i = 0, STALLS_PER_ROW - 1 do
			local tier = row.first + i
			local x = firstX + i * STALL_PITCH
			local base = Builder.part({
				Name = "Stall" .. tier,
				Size = Vector3.new(STALL_W, 0.5, STALL_D),
				CFrame = at(x, row.baseY + 0.25, row.z),
				Color = C.hay,
				CanTouch = false,
				Parent = stalls,
			})
			base:SetAttribute("Tier", tier)
			-- walls (children of the stall part so the stall stays one object)
			Builder.part({
				Name = "BackWall",
				Size = Vector3.new(STALL_W, 3.5, 0.4),
				CFrame = at(x, row.baseY + 0.5 + 1.75, row.z + STALL_D / 2 - 0.2),
				Color = C.stallWall,
				CanTouch = false,
				Parent = base,
			})
			for _, side in { -1, 1 } do
				Builder.part({
					Name = "SideWall",
					Size = Vector3.new(0.4, 2.4, STALL_D),
					CFrame = at(x + side * (STALL_W / 2 - 0.2), row.baseY + 0.5 + 1.2, row.z),
					Color = C.stallWall,
					CanTouch = false,
					Parent = base,
				})
			end
			Builder.decor({
				Name = "NumberPlate",
				Size = Vector3.new(1.6, 1.2, 0.2),
				CFrame = at(x, row.baseY + 3.2, row.z + STALL_D / 2 - 0.5),
				Color = accent,
				Parent = base,
			})

			local anchor = Instance.new("Attachment")
			anchor.Name = "CowAnchor"
			anchor.Position = Vector3.new(0, 0.25, -0.4) -- top of the stall floor; LookVector = front
			anchor.Parent = base

			Builder.billboard(base, "Count", "Text", "", 5, 1.6, 6.5)

			-- riser from the stall floor up to the manifold
			local rx = x + STALL_W / 2 - 0.9
			addPipe("Riser" .. tier, wp(rx, row.baseY + 0.5, pipeZ), wp(rx, pipeY, pipeZ), 1):SetAttribute(
				"Stall",
				tier
			)
		end
		-- manifold collects every riser of the row and runs to the main line on the left
		local lastX = firstX + (STALLS_PER_ROW - 1) * STALL_PITCH + STALL_W / 2 - 0.9
		local rowName = if row.first == 1 then "FrontManifold" else "BackManifold"
		addPipe(rowName, wp(lastX, pipeY, pipeZ), wp(MAIN_X, pipeY, pipeZ), 2)
		joint(wp(MAIN_X, pipeY, pipeZ))
		joint(wp(lastX, pipeY, pipeZ))
	end

	-- main line: back manifold -> down to front height -> along the left side -> into the tank
	local backY = FLOOR + BACK_ROW_RISE + PIPE_HEIGHT
	local frontY = FLOOR + PIPE_HEIGHT
	local backZ = BACK_ROW_Z + STALL_D / 2 - 0.85
	local frontZ = FRONT_ROW_Z + STALL_D / 2 - 0.85
	local tankSideX = TANK_X - TANK_SIZE / 2
	local flowOrder = 3
	addPipe("MainDrop", wp(MAIN_X, backY, backZ), wp(MAIN_X, frontY, backZ), flowOrder)
	joint(wp(MAIN_X, frontY, backZ))
	addPipe("MainBack", wp(MAIN_X, frontY, backZ), wp(MAIN_X, frontY, frontZ), flowOrder + 1)
	addPipe("MainSide", wp(MAIN_X, frontY, frontZ), wp(MAIN_X, frontY, TANK_Z), flowOrder + 2)
	joint(wp(MAIN_X, frontY, TANK_Z))
	addPipe("MainInlet", wp(MAIN_X, frontY, TANK_Z), wp(tankSideX, frontY, TANK_Z), flowOrder + 3)

	-- Tank -------------------------------------------------------------------
	local tank = Instance.new("Model")
	tank.Name = "Tank"
	Builder.part({
		Name = "Plinth",
		Size = Vector3.new(TANK_SIZE + 0.8, TANK_PLINTH, TANK_SIZE + 0.8),
		CFrame = at(TANK_X, FLOOR + TANK_PLINTH / 2, TANK_Z),
		Color = C.metal,
		CanTouch = false,
		Parent = tank,
	})
	local shell = Builder.part({
		Name = "Shell",
		Size = Vector3.new(TANK_SIZE, TANK_H, TANK_SIZE),
		CFrame = at(TANK_X, FLOOR + TANK_PLINTH + TANK_H / 2, TANK_Z),
		Color = C.glass,
		Transparency = 0.6,
		CastShadow = false,
		CanTouch = false,
		Parent = tank,
	})
	local fillBottom = FLOOR + TANK_PLINTH + 0.1
	local fillMax = TANK_H - 0.4
	local fill = Builder.part({
		Name = "Fill",
		Size = Vector3.new(TANK_SIZE - 0.6, 0.2, TANK_SIZE - 0.6),
		CFrame = at(TANK_X, fillBottom + 0.1, TANK_Z),
		Color = C.milk,
		CanCollide = false,
		CanTouch = false,
		CastShadow = false,
		Parent = tank,
	})
	-- Help for A3: Fill is a Block. Scale Size.Y in [0, FillMaxHeight] and keep its bottom at FillBottomY.
	tank:SetAttribute("FillMaxHeight", fillMax)
	tank:SetAttribute("FillBottomY", fill.Position.Y - fill.Size.Y / 2)
	Builder.part({
		Name = "Cap",
		Size = Vector3.new(TANK_SIZE + 0.8, 0.8, TANK_SIZE + 0.8),
		CFrame = at(TANK_X, FLOOR + TANK_PLINTH + TANK_H + 0.4, TANK_Z),
		Color = accent,
		CanTouch = false,
		Parent = tank,
	})
	for _, dx in { -1, 1 } do
		for _, dz in { -1, 1 } do
			Builder.part({
				Name = "Frame",
				Size = Vector3.new(0.6, TANK_H, 0.6),
				CFrame = at(TANK_X + dx * TANK_SIZE / 2, FLOOR + TANK_PLINTH + TANK_H / 2, TANK_Z + dz * TANK_SIZE / 2),
				Color = C.metal,
				CanTouch = false,
				Parent = tank,
			})
		end
	end
	tank.PrimaryPart = shell
	tank.Parent = plot
	Builder.billboard(shell, "Sign", "Text", "MILK TANK", 8, 1.8, TANK_H / 2 + 2.2)

	-- faucet from the tank front toward the tap
	local faucetY = FLOOR + 3.5
	local tankFrontZ = TANK_Z - TANK_SIZE / 2
	Builder.pipe(wp(TANK_X, faucetY, tankFrontZ), wp(TANK_X, faucetY, tankFrontZ - 3), 0.9, {
		Name = "Faucet",
		Color = C.metal,
		Parent = decor,
	})
	Builder.pipe(wp(TANK_X, faucetY, tankFrontZ - 3), wp(TANK_X, faucetY - 1.4, tankFrontZ - 3), 0.9, {
		Name = "FaucetSpout",
		Color = C.metal,
		Parent = decor,
	})

	-- Pads -------------------------------------------------------------------
	local padY = FLOOR + 0.1
	pad("TankTap", at(TANK_X, padY, -25), C.tap, "Fill Can", plot)
	pad("BuyPad1", at(4, padY, -26), C.buy, "Buy x1", plot)
	pad("BuyPad5", at(15, padY, -26), C.buy, "Buy x5", plot)
	pad("BuyPad25", at(26, padY, -26), C.buy, "Buy x25", plot)
	pad("MergePad", at(15, padY, -12), C.merge, "Merge!", plot)

	Builder.part({
		Name = "CrateSpawn",
		Size = Vector3.new(6, 0.1, 6),
		CFrame = at(-4, FLOOR + 0.05, 6),
		Color = C.crate,
		Transparency = 0.35,
		CanCollide = false,
		Parent = plot,
	})

	-- Nests (F2): hay nests on stone pedestals, a 2x2 grid in the free yard right of the spawn.
	-- NestN is the pedestal Part: attribute NestKey = "N", BillboardGui "Label" > TextLabel "Text",
	-- Attachment "EggAnchor" on top, ProximityPrompt "Prompt". NestController (client) drives the
	-- egg model, labels and prompt text; the server only validates RequestHatch(nestKey).
	for i, xz in NEST_SPOTS do
		local nest = Builder.vcyl(at(xz.X, FLOOR, xz.Y).Position, NEST_RADIUS, NEST_H, {
			Name = "Nest" .. i,
			Color = C.stone,
			CanTouch = false,
			Parent = plot,
		})
		nest:SetAttribute("NestKey", tostring(i))
		local topY = FLOOR + NEST_H
		Builder.vcyl(at(xz.X, topY, xz.Y).Position, NEST_RADIUS + 0.25, 0.5, {
			Name = "Hay",
			Color = C.hay,
			Material = Enum.Material.Grass,
			CanTouch = false,
			CanCollide = false,
			Parent = nest,
		})
		for k = 0, 5 do
			local a = k * math.pi / 3
			Builder.decor({
				Name = "Straw",
				Size = Vector3.new(1.4, 0.35, 0.5),
				CFrame = at(xz.X + math.cos(a) * NEST_RADIUS, topY + 0.55, xz.Y + math.sin(a) * NEST_RADIUS)
					* CFrame.Angles(0, -a + math.pi / 2, math.rad(18)),
				Color = if k % 2 == 0 then C.hay else C.hayDark,
				Parent = nest,
			})
		end
		local anchor = Instance.new("Attachment")
		anchor.Name = "EggAnchor"
		anchor.Position = Vector3.new(NEST_H / 2 + 0.45, 0, 0) -- vcyl's local +X is world up
		anchor.Parent = nest
		-- the nest is a rotated cylinder, so a plain StudsOffset would point sideways: adorn the label to
		-- an attachment placed along the nest's local +X (= world up) instead
		local labelAnchor = Instance.new("Attachment")
		labelAnchor.Name = "LabelAnchor"
		labelAnchor.Position = Vector3.new(NEST_H / 2 + 4.2, 0, 0)
		labelAnchor.Parent = nest
		local label = Builder.billboard(nest, "Label", "Text", "Nest", 7, 1.6, 0)
		label.Adornee = labelAnchor
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "Prompt"
		prompt.ActionText = "Open Egg Shop"
		prompt.ObjectText = "Nest " .. i
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = nest
	end

	-- Spawn ------------------------------------------------------------------
	local spawn = Builder.part({
		Name = "Spawn",
		Size = Vector3.new(6, 0.4, 6),
		CFrame = at(0, FLOOR + 0.2, -6),
		Color = accent,
		Parent = plot,
	}, "SpawnLocation") :: SpawnLocation
	spawn.Neutral = false
	spawn.Enabled = true
	spawn.AllowTeamChangeOnTouch = false
	spawn.Duration = 0

	-- Owner sign over the gate --------------------------------------------------
	local signZ = -HALF_D - 1
	for _, side in { -1, 1 } do
		Builder.part({
			Name = "SignPost",
			Size = Vector3.new(1, 12, 1),
			CFrame = at(side * 9.5, FLOOR + 6, signZ),
			Color = C.post,
			CanTouch = false,
			Parent = decor,
		})
	end
	local sign = Builder.part({
		Name = "OwnerSign",
		Size = Vector3.new(18, 4, 0.6),
		CFrame = at(0, FLOOR + 10.5, signZ),
		Color = accent,
		CanTouch = false,
		Parent = plot,
	})
	Builder.surface(sign, "Gui", "Name", "Free Plot")

	-- hay bales for flavor (front corners, inside the fence)
	for _, x in { -28, 28 } do
		Builder.part({
			Name = "HayBale",
			Size = Vector3.new(3, 2.2, 4),
			CFrame = at(x, FLOOR + 1.1, -33),
			Color = C.hay,
			CanTouch = false,
			Parent = decor,
		})
	end

	plot.WorldPivot = cf
	plot.Parent = parent
	return plot
end

return PlotBuilder
