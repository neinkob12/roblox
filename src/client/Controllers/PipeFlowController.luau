--!strict
-- Client visuals for YOUR plot: milk beads flowing through Pipes toward the Tank,
-- and the Tank's "Fill" part scaled to tankMilk / TankCapacity.
-- Owner: A3. Purely cosmetic: all values come from the server (data + attributes).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataController = require(script.Parent.DataController)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)

local PipeFlowController = {}

local player = Players.LocalPlayer

local BEAD_SIZE = 0.6
local BEAD_INTERVAL = 0.35 -- seconds between beads per pipe at base speed
local BEAD_STUDS_PER_SECOND = 8 -- base travel speed
local MIN_FILL = 0.05 -- studs, so the fill never fully disappears

local plot: Model? = nil
local beadFolder: Folder? = nil
local tankMilk = 0
local displayedRatio = 0

-- Fill geometry captured once per plot
type FillInfo = {
	fill: BasePart,
	upAxis: number, -- 1 = X, 2 = Y, 3 = Z (local axis of Fill pointing world-up)
	bottom: Vector3, -- world position of the Shell bottom center
	maxHeight: number,
	baseCFrame: CFrame, -- Fill rotation, no translation
}
local fillInfo: FillInfo? = nil

local function axisVector(cf: CFrame, axis: number): Vector3
	if axis == 1 then
		return cf.RightVector
	elseif axis == 2 then
		return cf.UpVector
	end
	return cf.LookVector
end

local function sizeOnAxis(size: Vector3, axis: number): number
	if axis == 1 then
		return size.X
	elseif axis == 2 then
		return size.Y
	end
	return size.Z
end

local function withAxis(size: Vector3, axis: number, value: number): Vector3
	if axis == 1 then
		return Vector3.new(value, size.Y, size.Z)
	elseif axis == 2 then
		return Vector3.new(size.X, value, size.Z)
	end
	return Vector3.new(size.X, size.Y, value)
end

-- local axis of a part most aligned with world up
local function upAxisOf(cf: CFrame): number
	local best, bestDot = 2, -1
	for axis = 1, 3 do
		local d = math.abs(axisVector(cf, axis):Dot(Vector3.yAxis))
		if d > bestDot then
			best, bestDot = axis, d
		end
	end
	return best
end

local function captureFill(p: Model): FillInfo?
	local tank = p:FindFirstChild("Tank")
	local shell = tank and tank:FindFirstChild("Shell")
	local fill = tank and tank:FindFirstChild("Fill")
	if not (shell and shell:IsA("BasePart") and fill and fill:IsA("BasePart")) then
		return nil
	end
	local shellUp = upAxisOf(shell.CFrame)
	local shellHeight = sizeOnAxis(shell.Size, shellUp)
	-- Shell bottom (world), under the shell center
	local bottom = shell.Position - Vector3.yAxis * (shellHeight / 2)
	-- keep the fill centered on the shell horizontally, inset a little from the walls
	local inset = shellHeight * 0.04
	return {
		fill = fill,
		upAxis = upAxisOf(fill.CFrame),
		bottom = bottom + Vector3.yAxis * inset,
		maxHeight = math.max(MIN_FILL, shellHeight - inset * 2),
		baseCFrame = fill.CFrame.Rotation,
	}
end

local function applyFill(ratio: number)
	local info = fillInfo
	if not info or not info.fill.Parent then
		return
	end
	local h = math.max(MIN_FILL, info.maxHeight * math.clamp(ratio, 0, 1))
	info.fill.Size = withAxis(info.fill.Size, info.upAxis, h)
	info.fill.CFrame = CFrame.new(info.bottom + Vector3.yAxis * (h / 2)) * info.baseCFrame
end

local function targetRatio(): number
	local cap = player:GetAttribute("TankCapacity")
	if typeof(cap) ~= "number" or cap <= 0 then
		return 0
	end
	return tankMilk / cap
end

local function flowing(): boolean
	local mps = player:GetAttribute("MilkPerSecond")
	if typeof(mps) ~= "number" or mps <= 0 then
		return false
	end
	return targetRatio() < 0.999
end

local function speedMultiplier(): number
	local data = DataController:Get()
	local lvl = (data and data.upgrades and data.upgrades.pipeSpeed) or 0
	return 1 + lvl * Upgrades.ById.pipeSpeed.perLevel
end

-- start/end points of a pipe along its longest axis, oriented toward the tank
local function pipeEnds(pipe: BasePart, tankPos: Vector3?): (Vector3, Vector3)
	local size = pipe.Size
	local axis = 1
	if size.Y > size.X and size.Y >= size.Z then
		axis = 2
	elseif size.Z > size.X and size.Z > size.Y then
		axis = 3
	end
	local dir = axisVector(pipe.CFrame, axis) * (sizeOnAxis(size, axis) / 2)
	local a, b = pipe.Position - dir, pipe.Position + dir
	if tankPos and (a - tankPos).Magnitude < (b - tankPos).Magnitude then
		a, b = b, a
	end
	return a, b
end

local function spawnBead(pipe: BasePart, tankPos: Vector3?, color: Color3)
	local folder = beadFolder
	if not folder then
		return
	end
	local a, b = pipeEnds(pipe, tankPos)
	local dist = (b - a).Magnitude
	if dist < 0.5 then
		return
	end
	local bead = Instance.new("Part")
	bead.Name = "MilkBead"
	bead.Shape = Enum.PartType.Ball
	bead.Size = Vector3.one * math.min(BEAD_SIZE, math.min(pipe.Size.X, pipe.Size.Y, pipe.Size.Z) * 1.1)
	bead.Material = Enum.Material.SmoothPlastic
	bead.Color = color
	bead.Anchored = true
	bead.CanCollide = false
	bead.CanQuery = false
	bead.CanTouch = false
	bead.CastShadow = false
	bead.Position = a
	bead.Parent = folder
	local duration = dist / (BEAD_STUDS_PER_SECOND * speedMultiplier())
	local tween = TweenService:Create(bead, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Position = b })
	tween.Completed:Connect(function()
		bead:Destroy()
	end)
	tween:Play()
end

local function pipeParts(p: Model): { BasePart }
	local list: { BasePart } = {}
	local pipes = p:FindFirstChild("Pipes")
	if not pipes then
		return list
	end
	for _, d in pipes:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

local function tankPosition(p: Model): Vector3?
	local tank = p:FindFirstChild("Tank")
	local shell = tank and tank:FindFirstChild("Shell")
	if shell and shell:IsA("BasePart") then
		return shell.Position
	end
	return nil
end

local function setPlot(id: any)
	plot = nil
	fillInfo = nil
	if typeof(id) ~= "number" then
		return
	end
	local plots = workspace:WaitForChild("Plots", 30)
	local p = plots and plots:WaitForChild("Plot" .. id, 10)
	if p and p:IsA("Model") then
		plot = p
		local tank = p:WaitForChild("Tank", 10)
		if tank then
			tank:WaitForChild("Fill", 10)
		end
		fillInfo = captureFill(p)
		if not fillInfo then
			warn("[PipeFlowController] Tank.Shell / Tank.Fill missing on " .. p.Name)
		end
	end
end

function PipeFlowController:Init()
	local folder = Instance.new("Folder")
	folder.Name = "MilkBeads_Client"
	folder.Parent = workspace
	beadFolder = folder
end

function PipeFlowController:Start()
	DataController:OnChanged("tankMilk", function(v)
		if typeof(v) == "number" then
			tankMilk = v
		end
	end)

	player:GetAttributeChangedSignal("PlotId"):Connect(function()
		task.spawn(setPlot, player:GetAttribute("PlotId"))
	end)
	task.spawn(setPlot, player:GetAttribute("PlotId"))

	-- smooth tank fill
	RunService.RenderStepped:Connect(function(dt: number)
		if not fillInfo then
			return
		end
		local target = targetRatio()
		displayedRatio += (target - displayedRatio) * math.min(1, dt * 4)
		applyFill(displayedRatio)
	end)

	-- bead spawner
	local milkColor = Color3.fromRGB(255, 255, 255)
	while true do
		task.wait(BEAD_INTERVAL / speedMultiplier())
		local p = plot
		if p and p.Parent and flowing() then
			local tankPos = tankPosition(p)
			for _, pipe in pipeParts(p) do
				spawnBead(pipe, tankPos, milkColor)
			end
		end
	end
end

return PipeFlowController
