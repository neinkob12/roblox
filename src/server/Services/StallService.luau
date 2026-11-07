--!strict
-- Shows ONE cow model per owned tier in each owned plot's stalls, plus an "Name\nx47" counter.
-- Owner: A2.
--
-- World contract (built by A1, see CONTRACTS section 6):
--   workspace.Plots.PlotN (attribute OwnerUserId, 0 = free)
--     Stalls/StallK (K = tier 1..18), each with a "CowAnchor" Attachment and a BillboardGui "Count".
-- The cow model is parented into its stall as "Cow" (feet at CowAnchor, facing the anchor's LookVector).
-- The counter text goes into the first TextLabel inside "Count" (one is created if A1 left it empty).
--
-- Reacts to data.cows by polling every 0.5s (cheap: it only compares numbers and touches
-- instances when a count changes), and clears instantly when OwnerUserId changes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cows = require(ReplicatedStorage.Shared.Config.Cows)
local CowModels = require(ReplicatedStorage.Shared.CowModels)
local Format = require(ReplicatedStorage.Shared.Format)
local DataService = require(script.Parent.DataService)

local POLL_SECONDS = 0.5

type StallState = { model: Model?, count: number }
type PlotState = { ownerId: number, stalls: { [number]: StallState } }

local StallService = {}

local plotStates: { [Instance]: PlotState } = {}

local function getStall(plot: Instance, tier: number): Instance?
	local stalls = plot:FindFirstChild("Stalls")
	return stalls and stalls:FindFirstChild("Stall" .. tier)
end

local function getCountLabel(stall: Instance): TextLabel?
	local gui = stall:FindFirstChild("Count", true)
	if not gui or not gui:IsA("BillboardGui") then
		return nil
	end
	local label = gui:FindFirstChildWhichIsA("TextLabel", true)
	if not label then
		local l = Instance.new("TextLabel")
		l.Name = "Text"
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundTransparency = 1
		l.TextScaled = true
		l.Font = Enum.Font.FredokaOne
		l.TextColor3 = Color3.new(1, 1, 1)
		l.TextStrokeTransparency = 0
		l.Parent = gui
		label = l
	end
	return label
end

local function setCount(stall: Instance, tier: number, count: number)
	local gui = stall:FindFirstChild("Count", true)
	local label = getCountLabel(stall)
	if label then
		local cow = Cows.Get(tier)
		label.Text = if count > 0 and cow then `{cow.name}\nx{Format.Number(count)}` else ""
	end
	if gui and gui:IsA("BillboardGui") then
		gui.Enabled = count > 0
	end
end

local function clearStall(plot: Instance, tier: number, state: StallState)
	if state.model then
		state.model:Destroy()
		state.model = nil
	end
	state.count = 0
	local stall = getStall(plot, tier)
	if stall then
		setCount(stall, tier, 0)
	end
end

local function clearPlot(plot: Instance)
	local ps = plotStates[plot]
	if not ps then
		return
	end
	for tier, state in ps.stalls do
		clearStall(plot, tier, state)
	end
	plotStates[plot] = nil
end

local function placeCow(stall: Instance, tier: number): Model?
	local anchor = stall:FindFirstChild("CowAnchor", true)
	if not anchor or not anchor:IsA("Attachment") then
		return nil
	end
	local model = CowModels.Build(tier)
	model.Name = "Cow"
	model:PivotTo(anchor.WorldCFrame)
	model.Parent = stall
	return model
end

local function syncPlot(plot: Instance)
	local ownerId = plot:GetAttribute("OwnerUserId")
	local owner = if type(ownerId) == "number" and ownerId ~= 0 then Players:GetPlayerByUserId(ownerId) else nil
	local data = owner and DataService:Get(owner)

	local ps: PlotState? = plotStates[plot]
	if ps and ps.ownerId ~= ownerId then
		clearPlot(plot)
		ps = nil
	end
	if not data or type(data.cows) ~= "table" then
		if ps then
			clearPlot(plot)
		end
		return
	end
	if not ps then
		ps = { ownerId = ownerId :: number, stalls = {} }
		plotStates[plot] = ps
	end
	local state = ps :: PlotState

	for tier = 1, Cows.Count do
		local raw = data.cows[tostring(tier)]
		local count = if type(raw) == "number" then math.max(0, math.floor(raw)) else 0
		local st = state.stalls[tier]
		if not st then
			st = { model = nil, count = 0 }
			state.stalls[tier] = st
		end
		local stallState = st :: StallState
		local stall = getStall(plot, tier)
		if stall then
			-- model may have been removed externally (e.g. A1 rebuilt the stall)
			if stallState.model and stallState.model.Parent ~= stall then
				stallState.model:Destroy()
				stallState.model = nil
			end
			if count > 0 and not stallState.model then
				stallState.model = placeCow(stall, tier)
			elseif count == 0 and stallState.model then
				stallState.model:Destroy()
				stallState.model = nil
			end
			if count ~= stallState.count then
				setCount(stall, tier, count)
			end
			stallState.count = count
		end
	end
end

local function watchPlot(plot: Instance)
	plot:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
		syncPlot(plot)
	end)
	-- hide all counters on an empty plot
	for tier = 1, Cows.Count do
		local stall = getStall(plot, tier)
		if stall then
			setCount(stall, tier, 0)
		end
	end
	syncPlot(plot)
end

function StallService:Start()
	local plots = workspace:WaitForChild("Plots", 60)
	if not plots then
		warn("[StallService] workspace.Plots not found; stalls disabled")
		return
	end
	for _, plot in plots:GetChildren() do
		task.spawn(watchPlot, plot)
	end
	plots.ChildAdded:Connect(function(plot)
		task.spawn(watchPlot, plot)
	end)
	plots.ChildRemoved:Connect(function(plot)
		plotStates[plot] = nil
	end)

	while true do
		task.wait(POLL_SECONDS)
		for _, plot in plots:GetChildren() do
			local ok, err = pcall(syncPlot :: any, plot)
			if not ok then
				warn(`[StallService] {plot.Name}: {err}`)
			end
		end
	end
end

return StallService
