--!strict
-- A cow model framed in a ViewportFrame. Shared by CratesPanel, DiscoveryController and IndexPanel.
-- Plain module (not auto-loaded).
--
--   CowViewport.Mount(parent, tier, opts?) -> (cleanup: () -> (), viewport: ViewportFrame?)
--     parent  a ViewportFrame to fill, or any GuiObject (a full-size ViewportFrame is created in it)
--     opts.spin   radians per second the camera orbits the cow (nil/0 = static shot)
--     opts.bob    studs of camera bob while spinning (default 0)
--     opts.view   camera direction for a static shot (default: from the front-left)
--   cleanup() stops the spin and removes what Mount created. Safe to call twice.
--   viewport is nil when the model could not be built (a warning is printed).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CowModels = require(ReplicatedStorage.Shared.CowModels)

export type Options = { spin: number?, bob: number?, view: Vector3? }

local FOV = 40
local DEFAULT_VIEW = Vector3.new(-0.55, 0.3, -1) -- front = -Z

local CowViewport = {}

function CowViewport.Mount(parent: Instance, tier: number, opts: Options?): (() -> (), ViewportFrame?)
	local o: Options = opts or {}
	local ok, model = pcall(CowModels.Build, tier)
	if not ok or not model then
		warn(`[CowViewport] could not build cow {tier}: {model}`)
		return function() end, nil
	end

	local vp: ViewportFrame
	local created = false
	if parent:IsA("ViewportFrame") then
		vp = parent
	else
		vp = Instance.new("ViewportFrame")
		vp.Name = "Cow"
		vp.BackgroundTransparency = 1
		vp.Size = UDim2.fromScale(1, 1)
		vp.Parent = parent
		created = true
	end
	vp.Ambient = Color3.fromRGB(170, 170, 180)
	vp.LightColor = Color3.fromRGB(255, 250, 240)
	vp.LightDirection = Vector3.new(-1, -1.5, -1)

	local cam = Instance.new("Camera")
	cam.FieldOfView = FOV
	cam.Parent = vp
	vp.CurrentCamera = cam
	model:PivotTo(CFrame.identity)
	model.Parent = vp

	local boxCF, boxSize = model:GetBoundingBox()
	local center = boxCF.Position
	local dist = boxSize.Magnitude * 0.5 / math.tan(math.rad(FOV / 2)) * 1.05

	local conn: RBXScriptConnection? = nil
	local spin = o.spin or 0
	if spin ~= 0 then
		local bob = o.bob or 0
		local start = os.clock()
		local function place()
			local t = os.clock() - start
			local a = t * spin
			local offset =
				Vector3.new(math.sin(a) * dist, boxSize.Y * 0.25 + math.sin(t * 2) * bob, -math.cos(a) * dist)
			cam.CFrame = CFrame.lookAt(center + offset, center)
		end
		place()
		conn = RunService.RenderStepped:Connect(place)
	else
		cam.CFrame = CFrame.lookAt(center + (o.view or DEFAULT_VIEW).Unit * dist, center)
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

return CowViewport
