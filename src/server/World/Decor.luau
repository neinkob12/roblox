--!strict
-- Blocky decor scattered over the island: trees, bushes, flowers, rocks, clouds, a windmill.
-- Library only, called by MapBuilder. Deterministic (fixed seed) so every server looks the same.
-- Nothing here is placed on plots, paths, the plaza or the truck road.
-- Owner: A1 World & Map.

local Builder = require(script.Parent.Builder)

local Decor = {}

export type Layout = {
	plotCFrames: { CFrame },
	plotHalfW: number,
	plotHalfD: number,
	plotFront: number,
	plazaRadius: number,
	islandHalf: number,
	pathAngles: { number },
	roadAngle: number,
}

local C = {
	trunk = Color3.fromRGB(130, 86, 52),
	leaves = {
		Color3.fromRGB(70, 170, 60),
		Color3.fromRGB(90, 196, 70),
		Color3.fromRGB(56, 150, 70),
	},
	bush = Color3.fromRGB(64, 160, 60),
	rock = Color3.fromRGB(150, 150, 158),
	stem = Color3.fromRGB(60, 150, 50),
	flowers = {
		Color3.fromRGB(255, 90, 110),
		Color3.fromRGB(255, 220, 60),
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(180, 110, 255),
		Color3.fromRGB(255, 150, 60),
	},
	cloud = Color3.fromRGB(255, 255, 255),
	mill = Color3.fromRGB(245, 240, 230),
	millRoof = Color3.fromRGB(206, 52, 46),
}

local function dir(angleDeg: number): Vector3
	local a = math.rad(angleDeg)
	return Vector3.new(math.cos(a), 0, math.sin(a))
end

-- distance from point p to the segment from the origin along `d` up to length `len` (XZ only)
local function distToRay(p: Vector3, d: Vector3, len: number): number
	local flat = Vector3.new(p.X, 0, p.Z)
	local t = math.clamp(flat:Dot(d), 0, len)
	return (flat - d * t).Magnitude
end

local function isFree(p: Vector3, margin: number, layout: Layout): boolean
	local edge = layout.islandHalf - 4
	if math.abs(p.X) > edge or math.abs(p.Z) > edge then
		return false
	end
	if Vector3.new(p.X, 0, p.Z).Magnitude < layout.plazaRadius + 8 + margin then
		return false
	end
	for _, cf in layout.plotCFrames do
		local l = cf:PointToObjectSpace(p)
		-- plots plus the sign posts in front of the gate
		if math.abs(l.X) < layout.plotHalfW + 3 + margin and l.Z > -layout.plotHalfD - 4 - margin then
			if l.Z < layout.plotHalfD + 3 + margin then
				return false
			end
		end
	end
	for _, a in layout.pathAngles do
		if distToRay(p, dir(a), layout.plotFront + 4) < 9 + margin then
			return false
		end
	end
	if distToRay(p, dir(layout.roadAngle), layout.islandHalf * 2) < 8 + margin then
		return false
	end
	return true
end

local function tree(pos: Vector3, rng: Random, parent: Instance)
	local h = rng:NextNumber(5, 7.5)
	local w = rng:NextNumber(6, 8.5)
	local yaw = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	Builder.part({
		Name = "Trunk",
		Size = Vector3.new(1.6, h, 1.6),
		CFrame = CFrame.new(pos + Vector3.new(0, h / 2, 0)) * yaw,
		Color = C.trunk,
		CanTouch = false,
		Parent = parent,
	})
	local leaf = C.leaves[rng:NextInteger(1, #C.leaves)]
	Builder.decor({
		Name = "Leaves",
		Size = Vector3.new(w, w * 0.75, w),
		CFrame = CFrame.new(pos + Vector3.new(0, h + w * 0.3, 0)) * yaw,
		Color = leaf,
		Parent = parent,
	})
	Builder.decor({
		Name = "LeavesTop",
		Size = Vector3.new(w * 0.6, w * 0.5, w * 0.6),
		CFrame = CFrame.new(pos + Vector3.new(0, h + w * 0.85, 0)) * yaw * CFrame.Angles(0, math.pi / 4, 0),
		Color = leaf,
		Parent = parent,
	})
end

local function bush(pos: Vector3, rng: Random, parent: Instance)
	local s = rng:NextNumber(2.5, 4)
	Builder.decor({
		Name = "Bush",
		Size = Vector3.new(s * 1.3, s, s),
		CFrame = CFrame.new(pos + Vector3.new(0, s / 2 - 0.3, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
		Color = C.bush,
		Parent = parent,
	})
end

local function flower(pos: Vector3, rng: Random, parent: Instance)
	Builder.decor({
		Name = "Stem",
		Size = Vector3.new(0.25, 1, 0.25),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.5, 0)),
		Color = C.stem,
		Parent = parent,
	})
	Builder.decor({
		Name = "Bloom",
		Size = Vector3.new(0.8, 0.5, 0.8),
		CFrame = CFrame.new(pos + Vector3.new(0, 1.1, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
		Color = C.flowers[rng:NextInteger(1, #C.flowers)],
		Parent = parent,
	})
end

local function rock(pos: Vector3, rng: Random, parent: Instance)
	local s = rng:NextNumber(1.5, 3.5)
	Builder.part({
		Name = "Rock",
		Size = Vector3.new(s * 1.4, s * 0.8, s),
		CFrame = CFrame.new(pos + Vector3.new(0, s * 0.3, 0))
			* CFrame.Angles(rng:NextNumber(-0.2, 0.2), rng:NextNumber(0, math.pi), rng:NextNumber(-0.2, 0.2)),
		Color = C.rock,
		CanTouch = false,
		Parent = parent,
	})
end

local function cloud(pos: Vector3, rng: Random, parent: Instance)
	for _ = 1, 3 do
		local s = rng:NextNumber(10, 22)
		Builder.decor({
			Name = "Cloud",
			Size = Vector3.new(s * 1.6, s * 0.5, s),
			CFrame = CFrame.new(
				pos + Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(-2, 2), rng:NextNumber(-8, 8))
			),
			Color = C.cloud,
			Transparency = 0.1,
			CastShadow = false,
			Parent = parent,
		})
	end
end

local function windmill(pos: Vector3, facing: Vector3, parent: Instance)
	local base = CFrame.lookAt(pos, pos + facing)
	Builder.part({
		Name = "MillTower",
		Size = Vector3.new(8, 18, 8),
		CFrame = base * CFrame.new(0, 9, 0),
		Color = C.mill,
		CanTouch = false,
		Parent = parent,
	})
	Builder.part({
		Name = "MillRoof",
		Size = Vector3.new(9, 3, 9),
		CFrame = base * CFrame.new(0, 19.5, 0),
		Color = C.millRoof,
		CanTouch = false,
		Parent = parent,
	})
	Builder.decor({
		Name = "MillRoofTop",
		Size = Vector3.new(5, 2, 5),
		CFrame = base * CFrame.new(0, 22, 0),
		Color = C.millRoof,
		Parent = parent,
	})
	local hub = base * CFrame.new(0, 16, -4.6)
	Builder.decor({
		Name = "MillHub",
		Size = Vector3.new(1.6, 1.6, 1.6),
		CFrame = hub,
		Color = C.trunk,
		Parent = parent,
	})
	for i = 0, 3 do
		Builder.decor({
			Name = "MillBlade",
			Size = Vector3.new(1.8, 13, 0.3),
			CFrame = hub * CFrame.Angles(0, 0, i * math.pi / 2 + math.pi / 4) * CFrame.new(0, 6.8, -0.4),
			Color = C.mill,
			Parent = parent,
		})
	end
end

function Decor.Build(map: Instance, layout: Layout)
	local rng = Random.new(20261106)
	local folder = Builder.folder("Decor", map)

	local function scatter(count: number, margin: number, maxTries: number, fn: (Vector3, Random, Instance) -> ())
		local placed = 0
		local tries = 0
		local edge = layout.islandHalf - 4
		while placed < count and tries < maxTries do
			tries += 1
			local p = Vector3.new(rng:NextNumber(-edge, edge), 0, rng:NextNumber(-edge, edge))
			if isFree(p, margin, layout) then
				fn(p, rng, folder)
				placed += 1
			end
		end
	end

	-- a few hand-placed landmarks first (outer corners of the island)
	windmill(Vector3.new(layout.islandHalf - 18, 0, -(layout.islandHalf - 18)), Vector3.new(-1, 0, 1), folder)

	scatter(55, 4, 3000, tree)
	scatter(40, 2, 2000, bush)
	scatter(25, 1, 1500, rock)
	scatter(140, 0, 4000, flower)

	-- flower beds along both sides of every path
	for _, a in layout.pathAngles do
		local d = dir(a)
		local side = Vector3.new(-d.Z, 0, d.X)
		for r = layout.plazaRadius + 6, layout.plotFront - 4, 7 do
			for _, s in { -1, 1 } do
				flower(d * r + side * s * 8.5, rng, folder)
			end
		end
	end

	for _ = 1, 8 do
		local a = rng:NextNumber(0, 360)
		cloud(dir(a) * rng:NextNumber(60, 260) + Vector3.new(0, rng:NextNumber(90, 120), 0), rng, folder)
	end
end

return Decor
