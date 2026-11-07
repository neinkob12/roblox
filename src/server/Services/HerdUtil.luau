--!strict
-- Shared helpers for the herd economy (A4). Not a service: no Init/Start.
--
--   HerdUtil.GiveCow(player, tier, n)          add n cows of a tier (marks discovered, fires CowDiscovered)
--   HerdUtil.AddCowsRaw(player, data, tier, n) same but does NOT replicate "cows" (for batch changes)
--   HerdUtil.BestTier(data) -> number           highest tier with count > 0 (1 if none)
--   HerdUtil.GetPlot(player) -> Model?          workspace.Plots["Plot"..PlotId]
--   HerdUtil.OwnsPlot(player, plot) -> boolean
--   HerdUtil.PlayerFromHit(hit) -> Player?
--   HerdUtil.BindPlotPart(name, fn(part, plot))  calls fn once for every plot part with that name,
--                                                 including plots/parts created later
--   HerdUtil.BindPad(name, fn(player, plot, pad)) Touched + owner check + 1s per-player debounce
--   HerdUtil.SetLabel(part, text, color?)        BillboardGui "Label" > TextLabel "Text"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Cows = require(ReplicatedStorage.Shared.Config.Cows)
local DataService = require(script.Parent.DataService)
local Debounce = require(script.Parent.Parent.Util.Debounce)

local HerdUtil = {}

local PAD_DEBOUNCE = 1

-- Adds cows without replicating "cows". Returns true if "discovered" changed.
function HerdUtil.AddCowsRaw(player: Player, data: any, tier: number, n: number): boolean
	if n <= 0 or tier < 1 or tier > Cows.Count or tier ~= math.floor(tier) then
		return false
	end
	local key = tostring(tier)
	data.cows[key] = (data.cows[key] or 0) + n
	if not data.discovered[key] then
		data.discovered[key] = true
		Net.Event("CowDiscovered"):FireClient(player, tier)
		return true
	end
	return false
end

function HerdUtil.GiveCow(player: Player, tier: number, n: number)
	local data = DataService:Get(player)
	if not data then
		return
	end
	local newDiscovery = HerdUtil.AddCowsRaw(player, data, tier, n)
	DataService:Replicate(player, "cows")
	if newDiscovery then
		DataService:Replicate(player, "discovered")
	end
end

function HerdUtil.BestTier(data: any): number
	local best = 0
	for key, count in data.cows do
		local tier = tonumber(key)
		if tier and count > 0 and tier > best then
			best = tier
		end
	end
	return if best == 0 then 1 else best
end

function HerdUtil.GetPlot(player: Player): Model?
	local id = player:GetAttribute("PlotId")
	if typeof(id) ~= "number" then
		return nil
	end
	local plots = workspace:FindFirstChild("Plots")
	local plot = plots and plots:FindFirstChild("Plot" .. id)
	if plot and plot:IsA("Model") then
		return plot
	end
	return nil
end

local function plotIdOf(plot: Instance): number?
	local id = plot:GetAttribute("PlotId")
	if typeof(id) == "number" then
		return id
	end
	return tonumber(string.match(plot.Name, "^Plot(%d+)$"))
end

function HerdUtil.OwnsPlot(player: Player, plot: Instance): boolean
	local id = player:GetAttribute("PlotId")
	return typeof(id) == "number" and id == plotIdOf(plot)
end

function HerdUtil.PlayerFromHit(hit: BasePart): Player?
	local model = hit:FindFirstAncestorOfClass("Model")
	while model do
		local player = Players:GetPlayerFromCharacter(model)
		if player then
			return player
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

-- Calls fn(part, plot) for every BasePart named `name` that is a direct child of a plot,
-- now and in the future (A1 may build plots after we start).
function HerdUtil.BindPlotPart(name: string, fn: (BasePart, Model) -> ())
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

function HerdUtil.BindPad(name: string, fn: (Player, Model, BasePart) -> ())
	HerdUtil.BindPlotPart(name, function(pad, plot)
		pad.Touched:Connect(function(hit)
			local player = HerdUtil.PlayerFromHit(hit)
			if not player or not HerdUtil.OwnsPlot(player, plot) then
				return
			end
			if not DataService:Get(player) then
				return
			end
			if not Debounce.Try(player, "pad:" .. name, PAD_DEBOUNCE) then
				return
			end
			fn(player, plot, pad)
		end)
	end)
end

function HerdUtil.SetLabel(part: Instance, text: string, color: Color3?)
	local gui = part:FindFirstChild("Label")
	local label = gui and gui:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		label.Text = text
		if color then
			label.TextColor3 = color
		end
	end
end

return HerdUtil
