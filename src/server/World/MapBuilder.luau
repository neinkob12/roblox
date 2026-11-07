--!strict
-- Builds the whole world at server start (CONTRACTS section 6):
--   workspace.Map    ground, water, plaza, paths, road, decor, lobby spawn
--   workspace.Dairy  central dairy pavilion with all named parts
--   workspace.Plots  Plot1..Plot6 around the dairy
-- Everything is built in :Init() so every Service can find parts by name in its own :Init().
-- When done it sets workspace attribute MapReady = true (clients can wait for it).
-- Owner: A1 World & Map.

local Builder = require(script.Parent.Builder)
local Decor = require(script.Parent.Decor)
local PlotBuilder = require(script.Parent.PlotBuilder)

local MapBuilder = {}

MapBuilder.PLOT_COUNT = 6
MapBuilder.PLOT_RADIUS = 106 -- dairy center -> plot center
MapBuilder.ISLAND_HALF = 175
MapBuilder.PLAZA_RADIUS = 30

local PLOT_COUNT = MapBuilder.PLOT_COUNT
local PLOT_RADIUS = MapBuilder.PLOT_RADIUS
local ISLAND_HALF = MapBuilder.ISLAND_HALF
local PLAZA_RADIUS = MapBuilder.PLAZA_RADIUS
local PLOT_FRONT = PLOT_RADIUS - PlotBuilder.PLOT_D / 2 -- radius of each plot's front edge

local ACCENTS = {
	Color3.fromRGB(235, 70, 70), -- red
	Color3.fromRGB(60, 140, 245), -- blue
	Color3.fromRGB(250, 200, 40), -- yellow
	Color3.fromRGB(160, 90, 230), -- purple
	Color3.fromRGB(255, 140, 40), -- orange
	Color3.fromRGB(250, 110, 190), -- pink
}

local C = {
	grass = Color3.fromRGB(98, 186, 64),
	sand = Color3.fromRGB(244, 222, 150),
	water = Color3.fromRGB(56, 160, 232),
	path = Color3.fromRGB(232, 196, 128),
	plaza = Color3.fromRGB(226, 226, 232),
	plazaRing = Color3.fromRGB(190, 190, 200),
	asphalt = Color3.fromRGB(70, 72, 80),
	yellow = Color3.fromRGB(255, 210, 40),
	white = Color3.fromRGB(255, 255, 255),
	red = Color3.fromRGB(214, 50, 50),
	blue = Color3.fromRGB(60, 140, 245),
	black = Color3.fromRGB(30, 30, 35),
	board = Color3.fromRGB(40, 44, 60),
	post = Color3.fromRGB(120, 80, 50),
	deposit = Color3.fromRGB(80, 170, 255),
	cash = Color3.fromRGB(60, 210, 90),
}

local function dir(angleDeg: number): Vector3
	local a = math.rad(angleDeg)
	return Vector3.new(math.cos(a), 0, math.sin(a))
end

-- Plot n sits at angle (n-1)*60 degrees. -Z of the returned CFrame faces the dairy.
function MapBuilder.PlotCFrame(id: number): CFrame
	local center = dir((id - 1) * 360 / PLOT_COUNT) * PLOT_RADIUS
	return CFrame.lookAt(center, Vector3.zero)
end

local function clearOld()
	for _, name in { "Map", "Dairy", "Plots" } do
		local old = workspace:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
end

-- Ground, water, plaza, paths, road ---------------------------------------
local function buildGround(map: Folder)
	local size = ISLAND_HALF * 2
	local ground = Builder.part({
		Name = "Ground",
		Size = Vector3.new(size, 4, size),
		CFrame = CFrame.new(0, -2, 0),
		Color = C.grass,
		Parent = map,
	})
	ground.TopSurface = Enum.SurfaceType.Studs
	Builder.part({
		Name = "Beach",
		Size = Vector3.new(size + 18, 3.6, size + 18),
		CFrame = CFrame.new(0, -2.2, 0),
		Color = C.sand,
		Parent = map,
	})
	Builder.part({
		Name = "Water",
		Size = Vector3.new(2000, 1, 2000),
		CFrame = CFrame.new(0, -1.6, 0),
		Color = C.water,
		Transparency = 0.15,
		Reflectance = 0.05,
		Parent = map,
	})
	-- invisible walls just past the beach so nobody wanders off into the sea
	local wallDist = ISLAND_HALF + 14
	for _, d in { Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis } do
		local isX = d.X ~= 0
		Builder.part({
			Name = "Boundary",
			Size = if isX then Vector3.new(2, 60, size + 40) else Vector3.new(size + 40, 60, 2),
			CFrame = CFrame.new(d * wallDist + Vector3.new(0, 29, 0)),
			Transparency = 1,
			CanTouch = false,
			CastShadow = false,
			Parent = map,
		})
	end

	-- plaza around the dairy
	Builder.vcyl(Vector3.new(0, -0.1, 0), PLAZA_RADIUS + 1.5, 0.2, {
		Name = "PlazaRing",
		Color = C.plazaRing,
		Parent = map,
	})
	Builder.vcyl(Vector3.new(0, -0.08, 0), PLAZA_RADIUS, 0.2, {
		Name = "Plaza",
		Color = C.plaza,
		Parent = map,
	})

	-- one path per plot: plaza edge -> plot gate (decor, walk on the ground below)
	local pathStart = PLAZA_RADIUS - 1
	local pathEnd = PLOT_FRONT + 2
	for id = 1, PLOT_COUNT do
		local d = dir((id - 1) * 360 / PLOT_COUNT)
		local mid = d * ((pathStart + pathEnd) / 2)
		Builder.decor({
			Name = "Path" .. id,
			Size = Vector3.new(14, 0.2, pathEnd - pathStart),
			CFrame = CFrame.lookAt(mid + Vector3.new(0, -0.02, 0), d * pathEnd + Vector3.new(0, -0.02, 0)),
			Color = C.path,
			Parent = map,
		})
	end

	-- truck road from the truck stop to the island edge (between plot 1 and plot 2)
	local roadDir = dir(30)
	local roadStart, roadEnd = PLAZA_RADIUS + 14, ISLAND_HALF + 9
	Builder.decor({
		Name = "TruckRoad",
		Size = Vector3.new(10, 0.2, roadEnd - roadStart),
		CFrame = CFrame.lookAt(roadDir * ((roadStart + roadEnd) / 2), roadDir * roadEnd),
		Color = C.asphalt,
		Parent = map,
	})

	-- neutral spawn for players before PlotService gives them a plot
	local lobby = Builder.part({
		Name = "LobbySpawn",
		Size = Vector3.new(6, 0.4, 6),
		CFrame = CFrame.lookAt(dir(270) * 20 + Vector3.new(0, 0.2, 0), Vector3.new(0, 0.2, 0)),
		Color = C.plazaRing,
		Parent = map,
	}, "SpawnLocation") :: SpawnLocation
	lobby.Neutral = true
	lobby.Duration = 0
end

-- Dairy ------------------------------------------------------------------------
local function boardOnPosts(
	name: string,
	angleDeg: number,
	radius: number,
	size: Vector3,
	bottomY: number,
	parent: Instance
): BasePart
	local pos = dir(angleDeg) * radius + Vector3.new(0, bottomY + size.Y / 2, 0)
	local cf = CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0)) -- Front face looks at the dairy center
	local board = Builder.part({
		Name = name,
		Size = size,
		CFrame = cf,
		Color = C.board,
		CanTouch = false,
		Parent = parent,
	})
	for _, side in { -1, 1 } do
		Builder.part({
			Name = name .. "Post",
			Size = Vector3.new(0.8, bottomY + size.Y, 0.8),
			CFrame = cf * CFrame.new(side * (size.X / 2 - 1), -size.Y / 2 - bottomY + (bottomY + size.Y) / 2, 0.8),
			Color = C.post,
			CanTouch = false,
			Parent = parent,
		})
	end
	return board
end

local function buildDairy(): Model
	local dairy = Instance.new("Model")
	dairy.Name = "Dairy"
	local building = Builder.folder("Building", dairy)

	-- pads under the pavilion roof
	local deposit = Builder.part({
		Name = "DepositPad",
		Size = Vector3.new(10, 0.2, 10),
		CFrame = CFrame.new(-6.5, 0.12, 0),
		Color = C.deposit,
		Parent = dairy,
	})
	Builder.padLabel(deposit, "Deposit Milk")
	local cash = Builder.part({
		Name = "CashPad",
		Size = Vector3.new(10, 0.2, 10),
		CFrame = CFrame.new(6.5, 0.12, 0),
		Color = C.cash,
		Parent = dairy,
	})
	Builder.padLabel(cash, "Collect Cash")

	-- pavilion: 6 pillars between the paths, a two-tier round roof and a giant milk bottle
	local roofY = 14
	for i = 0, 5 do
		local p = dir(30 + i * 60) * 15
		Builder.vcyl(p, 1, roofY, { Name = "Pillar", Color = C.white, CanTouch = false, Parent = building })
		Builder.vcyl(p, 1.4, 0.8, { Name = "PillarBase", Color = C.red, CanTouch = false, Parent = building })
	end
	Builder.vcyl(Vector3.new(0, roofY - 0.4, 0), 17.6, 0.6, {
		Name = "RoofTrim",
		Color = C.white,
		CanTouch = false,
		Parent = building,
	})
	Builder.vcyl(Vector3.new(0, roofY + 0.2, 0), 17, 1.2, {
		Name = "Roof",
		Color = C.red,
		CanTouch = false,
		Parent = building,
	})
	Builder.vcyl(Vector3.new(0, roofY + 1.4, 0), 12, 1.2, {
		Name = "RoofTop",
		Color = C.white,
		CanTouch = false,
		Parent = building,
	})
	local bottleY = roofY + 2.6
	Builder.vcyl(Vector3.new(0, bottleY, 0), 4.5, 9, {
		Name = "BottleBody",
		Color = C.white,
		CanTouch = false,
		Parent = building,
	})
	Builder.vcyl(Vector3.new(0, bottleY + 9, 0), 3.2, 1.6, {
		Name = "BottleShoulder",
		Color = C.white,
		CanTouch = false,
		Parent = building,
	})
	Builder.vcyl(Vector3.new(0, bottleY + 10.6, 0), 2, 2, {
		Name = "BottleNeck",
		Color = C.white,
		CanTouch = false,
		Parent = building,
	})
	local cap = Builder.vcyl(Vector3.new(0, bottleY + 12.6, 0), 2.3, 1.2, {
		Name = "BottleCap",
		Color = C.blue,
		CanTouch = false,
		Parent = building,
	})
	-- cow spots on the bottle
	for i, a in { 20, 110, 200, 290 } do
		local h = bottleY + 2.5 + (i % 2) * 3
		Builder.decor({
			Name = "BottleSpot",
			Size = Vector3.new(0.5, 2.6, 3),
			CFrame = CFrame.lookAt(dir(a) * 4.4 + Vector3.new(0, h, 0), Vector3.new(0, h, 0))
				* CFrame.Angles(0, math.pi / 2, 0),
			Color = C.black,
			Parent = building,
		})
	end
	Builder.billboard(cap, "Sign", "Text", "DAIRY", 18, 4.5, 4)

	-- price board at the plaza edge (faces the pads)
	local price = boardOnPosts("PriceBoard", 90, 26, Vector3.new(14, 7, 0.6), 5, dairy)
	Builder.surface(price, "Gui", "Price", "Milk Price: x1.00")

	-- leaderboards (B2 fills the SurfaceGui "Gui")
	local lbCash = boardOnPosts("LeaderboardCash", 150, 27, Vector3.new(12, 16, 0.8), 2, dairy)
	Builder.surface(lbCash, "Gui")
	local lbReb = boardOnPosts("LeaderboardRebirths", 210, 27, Vector3.new(12, 16, 0.8), 2, dairy)
	Builder.surface(lbReb, "Gui")

	-- truck stop: LookVector points along the road toward the island edge, so a truck
	-- placed at TruckStop.CFrame faces the way it will drive off
	local stopPos = dir(30) * (PLAZA_RADIUS + 6) + Vector3.new(0, 0.1, 0)
	local stopCF = CFrame.lookAt(stopPos, stopPos + dir(30))
	local stop = Builder.part({
		Name = "TruckStop",
		Size = Vector3.new(12, 0.2, 22),
		CFrame = stopCF,
		Color = C.asphalt,
		CanCollide = false,
		Parent = dairy,
	})
	for _, side in { -1, 1 } do
		Builder.decor({
			Name = "StopLine",
			Size = Vector3.new(0.6, 0.05, 22),
			CFrame = stopCF * CFrame.new(side * 5.4, 0.12, 0),
			Color = C.yellow,
			Parent = building,
		})
	end
	Builder.billboard(stop, "Label", "Text", "Milk Truck", 10, 2.5, 3)

	-- F2 egg stand at the free plaza slot (270 degrees): counter + giant egg; its ProximityPrompt
	-- "Prompt" opens the Egg Shop on the client (EggShopPanel). No server behavior.
	local eggPos = dir(270) * 24
	local eggCF = CFrame.lookAt(eggPos + Vector3.new(0, 1.5, 0), Vector3.new(0, 1.5, 0))
	local eggStand = Builder.part({
		Name = "EggStand",
		Size = Vector3.new(8, 3, 3),
		CFrame = eggCF,
		Color = Color3.fromRGB(250, 200, 90),
		CanTouch = false,
		Parent = dairy,
	})
	Builder.decor({
		Name = "EggStandTop",
		Size = Vector3.new(8.6, 0.4, 3.6),
		CFrame = eggCF * CFrame.new(0, 1.7, 0),
		Color = C.white,
		Parent = eggStand,
	})
	Builder.decor({
		Name = "BigEgg",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(4, 4, 4),
		CFrame = eggCF * CFrame.new(0, 4, 1),
		Color = Color3.fromRGB(255, 248, 230),
		Parent = eggStand,
	})
	Builder.billboard(eggStand, "Label", "Text", "EGG SHOP", 10, 2.5, 7.5)
	local eggPrompt = Instance.new("ProximityPrompt")
	eggPrompt.Name = "Prompt"
	eggPrompt.ActionText = "Egg Shop"
	eggPrompt.ObjectText = "Pet Eggs"
	eggPrompt.HoldDuration = 0
	eggPrompt.MaxActivationDistance = 14
	eggPrompt.RequiresLineOfSight = false
	eggPrompt.Parent = eggStand

	dairy.PrimaryPart = deposit
	dairy.Parent = workspace
	return dairy
end

-- Debug check: warns for every contract name that is missing ---------------------
function MapBuilder.Validate(): number
	local missing = 0
	local function need(parent: Instance?, path: string, className: string?): Instance?
		if not parent then
			return nil
		end
		local found = parent:FindFirstChild(path)
		if not found or (className and not found:IsA(className)) then
			missing += 1
			warn(`[MapBuilder] missing {parent:GetFullName()}.{path}` .. (if className then ` ({className})` else ""))
			return nil
		end
		return found
	end
	local function label(pad: Instance?)
		need(need(pad, "Label", "BillboardGui"), "Text", "TextLabel")
	end

	need(workspace, "Map", "Folder")
	local dairy = need(workspace, "Dairy")
	label(need(dairy, "DepositPad", "BasePart"))
	label(need(dairy, "CashPad", "BasePart"))
	need(need(need(dairy, "PriceBoard", "BasePart"), "Gui", "SurfaceGui"), "Price", "TextLabel")
	need(dairy, "TruckStop", "BasePart")
	need(need(dairy, "LeaderboardCash", "BasePart"), "Gui", "SurfaceGui")
	need(need(dairy, "LeaderboardRebirths", "BasePart"), "Gui", "SurfaceGui")

	local plots = need(workspace, "Plots")
	for id = 1, PLOT_COUNT do
		local plot = need(plots, "Plot" .. id, "Model")
		if plot then
			if plot:GetAttribute("PlotId") ~= id then
				missing += 1
				warn(`[MapBuilder] Plot{id} has wrong PlotId attribute`)
			end
			if plot:GetAttribute("OwnerUserId") ~= 0 then
				missing += 1
				warn(`[MapBuilder] Plot{id} OwnerUserId attribute is not 0`)
			end
		end
		need(plot, "Spawn", "SpawnLocation")
		for _, padName in { "BuyPad1", "BuyPad5", "BuyPad25", "MergePad", "TankTap" } do
			label(need(plot, padName, "BasePart"))
		end
		need(plot, "CrateSpawn", "BasePart")
		local tank = need(plot, "Tank", "Model")
		need(tank, "Shell", "BasePart")
		need(tank, "Fill", "BasePart")
		local pipes = need(plot, "Pipes", "Folder")
		if pipes and #pipes:GetChildren() == 0 then
			missing += 1
			warn(`[MapBuilder] Plot{id}.Pipes is empty`)
		end
		local stalls = need(plot, "Stalls", "Folder")
		for s = 1, PlotBuilder.STALL_COUNT do
			local stall = need(stalls, "Stall" .. s)
			need(stall, "CowAnchor", "Attachment")
			need(stall, "Count", "BillboardGui")
		end
		need(need(need(plot, "OwnerSign", "BasePart"), "Gui", "SurfaceGui"), "Name", "TextLabel")
	end
	return missing
end

function MapBuilder:Init()
	clearOld()
	Builder.partCount = 0

	local map = Builder.folder("Map", workspace)
	buildGround(map)
	buildDairy()

	local plots = Builder.folder("Plots", workspace)
	local plotCFrames = {}
	for id = 1, PLOT_COUNT do
		local cf = MapBuilder.PlotCFrame(id)
		plotCFrames[id] = cf
		PlotBuilder.Build(id, cf, ACCENTS[id], plots)
	end

	Decor.Build(map, {
		plotCFrames = plotCFrames,
		plotHalfW = PlotBuilder.PLOT_W / 2,
		plotHalfD = PlotBuilder.PLOT_D / 2,
		plotFront = PLOT_FRONT,
		plazaRadius = PLAZA_RADIUS,
		islandHalf = ISLAND_HALF,
		pathAngles = (function()
			local t = {}
			for id = 1, PLOT_COUNT do
				t[id] = (id - 1) * 360 / PLOT_COUNT
			end
			return t
		end)(),
		roadAngle = 30,
	})

	local missing = MapBuilder.Validate()
	workspace:SetAttribute("MapReady", true)
	print(`[MapBuilder] built world: {Builder.partCount} parts, {missing} missing contract names`)
end

return MapBuilder
