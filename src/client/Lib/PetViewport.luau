--!strict
-- F2: a pet model framed in a ViewportFrame (the CowViewport of pets). Plain module.
--
--   PetViewport.Mount(parent, petId, variant?, opts?) -> (cleanup, viewport?)
--     parent  a ViewportFrame to fill, or any GuiObject (a full-size ViewportFrame is created in it)
--     opts.spin        radians per second the camera orbits (nil/0 = static front-left shot)
--     opts.silhouette  true = black shape only (pet index, undiscovered entries)
--   cleanup() removes what Mount created and stops the spin. Safe to call twice.
--   Rainbow pets keep cycling their colors.
--   PetViewport.BoostText(petId, variant) -> "+5% Milk"     PetViewport.Percent(0.125) -> "12.5%"
--   PetViewport.RarityColor(petId) -> Color3

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PetModels = require(ReplicatedStorage.Shared.PetModels)
local Pets = require(ReplicatedStorage.Shared.Config.Pets)

export type Options = { spin: number?, silhouette: boolean? }

local PetViewport = {}

local KIND_NAMES: { [string]: string } = { milk = "Milk", cash = "Cash", speed = "Speed", luck = "Egg Luck" }

-- "+5% Milk", "+12.5% Egg Luck" (the policy wants luck effects stated as a number)
function PetViewport.Percent(value: number): string
	local p = math.floor(value * 1000 + 0.5) / 10
	if p == math.floor(p) then
		return `{math.floor(p)}%`
	end
	return `{p}%`
end

function PetViewport.BoostText(petId: string, variant: string): string
	local kind, value = Pets.Boost(petId, variant)
	if not kind then
		return ""
	end
	return `+{PetViewport.Percent(value)} {KIND_NAMES[kind] or kind}`
end

function PetViewport.RarityColor(petId: string): Color3
	local pet = Pets.ById[petId]
	local r = pet and Pets.RarityById[pet.rarity]
	return if r then r.color else Color3.fromRGB(150, 150, 160)
end

local FOV = 40
local VIEW = Vector3.new(-0.6, 0.35, -1)

function PetViewport.Mount(
	parent: Instance,
	petId: string,
	variant: string?,
	opts: Options?
): (() -> (), ViewportFrame?)
	local o: Options = opts or {}
	local ok, model = pcall(PetModels.Build, petId, variant)
	if not ok or not model then
		warn(`[PetViewport] could not build pet {petId}: {model}`)
		return function() end, nil
	end

	local vp: ViewportFrame
	local created = false
	if parent:IsA("ViewportFrame") then
		vp = parent
	else
		vp = Instance.new("ViewportFrame")
		vp.Name = "Pet"
		vp.BackgroundTransparency = 1
		vp.Size = UDim2.fromScale(1, 1)
		vp.Parent = parent
		created = true
	end
	if o.silhouette then
		vp.Ambient = Color3.new(0, 0, 0)
		vp.LightColor = Color3.new(0, 0, 0)
		vp.ImageColor3 = Color3.fromRGB(40, 35, 55)
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Color = Color3.new(0, 0, 0)
				d.Material = Enum.Material.SmoothPlastic
				d:SetAttribute("RainbowPart", nil)
			elseif d:IsA("ParticleEmitter") then
				d:Destroy()
			end
		end
	else
		vp.Ambient = Color3.fromRGB(170, 170, 180)
		vp.LightColor = Color3.fromRGB(255, 250, 240)
		vp.LightDirection = Vector3.new(-1, -1.5, -1)
	end

	local cam = Instance.new("Camera")
	cam.FieldOfView = FOV
	cam.Parent = vp
	vp.CurrentCamera = cam
	model:PivotTo(CFrame.identity)
	model.Parent = vp

	local boxCF, boxSize = model:GetBoundingBox()
	local center = boxCF.Position
	local dist = boxSize.Magnitude * 0.5 / math.tan(math.rad(FOV / 2)) * 1.1

	local rainbow: { BasePart } = {}
	local offsets: { number } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("RainbowPart") then
			table.insert(rainbow, d)
			local off = d:GetAttribute("RainbowOffset")
			table.insert(offsets, if typeof(off) == "number" then off else 0)
		end
	end

	local conn: RBXScriptConnection? = nil
	local spin = o.spin or 0
	if spin ~= 0 or #rainbow > 0 then
		local start = os.clock()
		local function frame()
			local t = os.clock() - start
			if spin ~= 0 then
				local a = t * spin
				cam.CFrame = CFrame.lookAt(
					center + Vector3.new(math.sin(a) * dist, boxSize.Y * 0.3, -math.cos(a) * dist),
					center
				)
			end
			for k, part in rainbow do
				part.Color = PetModels.RainbowColor(os.clock(), offsets[k])
			end
		end
		cam.CFrame = CFrame.lookAt(center + VIEW.Unit * dist, center)
		frame()
		conn = RunService.RenderStepped:Connect(frame)
	else
		cam.CFrame = CFrame.lookAt(center + VIEW.Unit * dist, center)
	end

	local cleaned = false
	return function()
		if cleaned then
			return
		end
		cleaned = true
		if conn then
			conn:Disconnect()
		end
		if created then
			vp:Destroy()
		else
			model:Destroy()
			cam:Destroy()
		end
	end,
		vp
end

return PetViewport
