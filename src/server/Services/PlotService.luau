--!strict
-- Plot ownership: one barn plot (workspace.Plots.PlotN) per player.
-- Owner: A3.
--
--   PlotService:GetPlot(player)          -> Model | nil
--   PlotService:GetOwner(plot)           -> Player | nil
--   PlotService:GetPlayerFromHit(hit)    -> Player | nil   (alive character that touched a part)
--   PlotService:IsOwnerTouch(plot, hit)  -> Player | nil   (the toucher, only if they own the plot)
--   PlotService.PlotAssigned:Connect(fn(player, plot))
--
-- Sets: plot attribute OwnerUserId, player attribute PlotId, OwnerSign text,
-- player.RespawnLocation and teleports the character to the plot's Spawn.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Signal)
local DataService = require(script.Parent.DataService)
local Notify = require(script.Parent.Parent.Util.Notify)

local PlotService = {}
PlotService.PlotAssigned = Signal.new()

local plotOf: { [Player]: Model } = {}
local ownerOf: { [Model]: Player } = {}

local FREE_SIGN_TEXT = "Free Plot"

local function getPlotsFolder(): Instance?
	local folder = workspace:FindFirstChild("Plots")
	if folder then
		return folder
	end
	return workspace:WaitForChild("Plots", 30)
end

-- Plots sorted by PlotId (falls back to the number in the name)
local function sortedPlots(): { Model }
	local folder = getPlotsFolder()
	if not folder then
		warn("[PlotService] workspace.Plots not found (A1 builds it)")
		return {}
	end
	local list: { Model } = {}
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			table.insert(list, child)
		end
	end
	local function idOf(m: Model): number
		local id = m:GetAttribute("PlotId")
		if typeof(id) == "number" then
			return id
		end
		return tonumber(string.match(m.Name, "%d+")) or 99
	end
	table.sort(list, function(a, b)
		return idOf(a) < idOf(b)
	end)
	return list
end

local function plotIdOf(plot: Model): number
	local id = plot:GetAttribute("PlotId")
	if typeof(id) == "number" then
		return id
	end
	return tonumber(string.match(plot.Name, "%d+")) or 0
end

local function setSign(plot: Model, text: string)
	local sign = plot:FindFirstChild("OwnerSign")
	local gui = sign and sign:FindFirstChild("Gui")
	local label = gui and gui:FindFirstChild("Name")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

local function spawnCFrame(plot: Model): CFrame?
	local spawn = plot:FindFirstChild("Spawn")
	if spawn and spawn:IsA("BasePart") then
		return spawn.CFrame * CFrame.new(0, spawn.Size.Y / 2 + 3, 0)
	end
	return nil
end

local function teleportToPlot(player: Player, character: Model?)
	local plot = plotOf[player]
	local char = character or player.Character
	if not plot or not char then
		return
	end
	local cf = spawnCFrame(plot)
	if not cf then
		return
	end
	-- wait for the root part so PivotTo moves the whole rig
	local root = char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart", 5)
	if root and char.Parent then
		char:PivotTo(cf)
	end
end

local function assign(player: Player)
	if plotOf[player] or player.Parent ~= Players then
		return
	end
	for _, plot in sortedPlots() do
		if not ownerOf[plot] then
			ownerOf[plot] = player
			plotOf[player] = plot
			plot:SetAttribute("OwnerUserId", player.UserId)
			player:SetAttribute("PlotId", plotIdOf(plot))
			setSign(plot, `{player.DisplayName}'s Farm`)
			local spawn = plot:FindFirstChild("Spawn")
			if spawn and spawn:IsA("SpawnLocation") then
				player.RespawnLocation = spawn
			end
			task.spawn(teleportToPlot, player, nil)
			PlotService.PlotAssigned:Fire(player, plot)
			return
		end
	end
	warn(`[PlotService] no free plot for {player.Name}`)
	Notify.To(player, "No free farm plot on this server!", "error")
end

local function release(player: Player)
	local plot = plotOf[player]
	if not plot then
		return
	end
	plotOf[player] = nil
	ownerOf[plot] = nil
	plot:SetAttribute("OwnerUserId", 0)
	setSign(plot, FREE_SIGN_TEXT)
end

local hooked: { [Player]: boolean } = {}
local function hookCharacter(player: Player)
	if hooked[player] then
		return
	end
	hooked[player] = true
	player.CharacterAdded:Connect(function(char)
		-- RespawnLocation needs a matching team on non-neutral spawns, so we also pivot by hand
		task.spawn(teleportToPlot, player, char)
	end)
end

function PlotService:Init()
	DataService.PlayerLoaded:Connect(function(player: Player)
		task.spawn(assign, player)
	end)
	Players.PlayerAdded:Connect(hookCharacter)
	Players.PlayerRemoving:Connect(function(player)
		release(player)
		hooked[player] = nil
	end)
end

function PlotService:Start()
	for _, plot in sortedPlots() do
		if not ownerOf[plot] then
			plot:SetAttribute("OwnerUserId", 0)
			setSign(plot, FREE_SIGN_TEXT)
		end
	end
	-- players who were already in game before this module started
	for _, player in Players:GetPlayers() do
		hookCharacter(player)
		if DataService:Get(player) then
			task.spawn(assign, player)
		end
	end
end

function PlotService:GetPlot(player: Player): Model?
	return plotOf[player]
end

function PlotService:GetOwner(plot: Model): Player?
	return ownerOf[plot]
end

function PlotService:GetPlayerFromHit(hit: BasePart): Player?
	local model = hit:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end
	local player = Players:GetPlayerFromCharacter(model)
	if not player then
		return nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return player
end

function PlotService:IsOwnerTouch(plot: Model, hit: BasePart): Player?
	local player = PlotService:GetPlayerFromHit(hit)
	if player and ownerOf[plot] == player then
		return player
	end
	return nil
end

return PlotService
