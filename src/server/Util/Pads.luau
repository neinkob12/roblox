--!strict
-- Touch pads. Plain module (not auto-loaded). Every touch-to-use part on the server goes through here.
--
--   Pads.PlayerFromHit(hit, pad) -> Player?
--       The player whose LIVE character touched `pad`, and only if their HumanoidRootPart is within
--       MAX_DISTANCE studs of the pad's surface. Characters are client-owned, so a Touched event alone
--       can be faked from across the map; the distance check stops that.
--   Pads.BindPlotPad(name, fn(player, plot, pad))
--       Every plot part named `name` (now and later). Only the plot owner, data loaded, 1s debounce.
--   Pads.BindWorldPad(part, key, fn(player))
--       One shared part (e.g. the Dairy pads). Any loaded player, 1s debounce per `key`.
--   Pads.BindPlotPart(name, fn(part, plot))
--       Calls fn once for every BasePart named `name` that is a direct child of a plot, now and later.
--   Pads.SetLabel(part, text, color?)
--       BillboardGui "Label" > TextLabel "Text" (CONTRACTS section 6).

local Players = game:GetService("Players")

local DataService = require(script.Parent.Parent.Services.DataService)
local PlotService = require(script.Parent.Parent.Services.PlotService)
local Debounce = require(script.Parent.Debounce)

local PAD_DEBOUNCE = 1
local MAX_DISTANCE = 12 -- studs between HumanoidRootPart and the closest point of the pad

local Pads = {}

-- Distance from a world point to the closest point of a (possibly rotated) box part.
local function distanceToPart(part: BasePart, point: Vector3): number
	local here = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2
	local closest = Vector3.new(
		math.clamp(here.X, -half.X, half.X),
		math.clamp(here.Y, -half.Y, half.Y),
		math.clamp(here.Z, -half.Z, half.Z)
	)
	return (here - closest).Magnitude
end

function Pads.PlayerFromHit(hit: BasePart, pad: BasePart): Player?
	local model = hit:FindFirstAncestorOfClass("Model")
	local player: Player? = nil
	while model do
		player = Players:GetPlayerFromCharacter(model)
		if player then
			break
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	if not player or not model then
		return nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") or distanceToPart(pad, root.Position) > MAX_DISTANCE then
		return nil
	end
	return player
end

function Pads.BindPlotPart(name: string, fn: (BasePart, Model) -> ())
	task.spawn(function()
		local plots = workspace:WaitForChild("Plots")
		local bound: { [Instance]: boolean } = {}
		local function tryBind(child: Instance, plot: Model)
			if child.Name == name and child:IsA("BasePart") and not bound[child] then
				bound[child] = true
				fn(child, plot)
			end
		end
		local function watchPlot(plot: Instance)
			if not plot:IsA("Model") then
				return
			end
			for _, child in plot:GetChildren() do
				tryBind(child, plot)
			end
			plot.ChildAdded:Connect(function(child)
				tryBind(child, plot)
			end)
		end
		for _, plot in plots:GetChildren() do
			watchPlot(plot)
		end
		plots.ChildAdded:Connect(watchPlot)
	end)
end

function Pads.BindPlotPad(name: string, fn: (Player, Model, BasePart) -> ())
	Pads.BindPlotPart(name, function(pad, plot)
		pad.Touched:Connect(function(hit)
			local player = Pads.PlayerFromHit(hit, pad)
			if not player or not PlotService:OwnsPlot(player, plot) or not DataService:Get(player) then
				return
			end
			if Debounce.Try(player, "pad:" .. name, PAD_DEBOUNCE) then
				fn(player, plot, pad)
			end
		end)
	end)
end

function Pads.BindWorldPad(part: BasePart, key: string, fn: (Player) -> ())
	part.Touched:Connect(function(hit)
		local player = Pads.PlayerFromHit(hit, part)
		if not player or not DataService:Get(player) then
			return
		end
		if Debounce.Try(player, "pad:" .. key, PAD_DEBOUNCE) then
			fn(player)
		end
	end)
end

function Pads.SetLabel(part: Instance, text: string, color: Color3?)
	local gui = part:FindFirstChild("Label")
	local label = gui and gui:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		label.Text = text
		if color then
			label.TextColor3 = color
		end
	end
end

return Pads
