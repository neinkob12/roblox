--!strict
-- A4: Mystery Milk Crates.
--   * Drops: every DropCheckSeconds each cow has DropChancePerCowPerMinute to drop a crate
--     (max 1 drop per player per roll, x crateDropMultiplier during the CrateRain event).
--     A glowing "?" crate appears at the plot's CrateSpawn; the owner touches it -> data.crates += 1.
--   * RequestBuyCrate: price = max(BuyBasePrice, milk/sec * BuyPriceSecondsOfProduction).
--   * RequestOpenCrate: rolls Economy.Crate.Odds relative to the best owned tier.
--
--   CrateService:GiveCrate(player, premium) -> number?
--       premium = false: adds one unopened crate to data.crates (returns nil)
--       premium = true : opens immediately with odds shifted +PremiumOddsShift, gives the cow,
--                        fires CrateOpened(tier, "premium") and returns the tier
--   CrateService:BuyPrice(player) -> number
--   CrateService:Roll(bestTier, shift) -> number

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Safe = require(ReplicatedStorage.Shared.Safe)
local Net = require(ReplicatedStorage.Shared.Net)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Format = require(ReplicatedStorage.Shared.Format)
local DataService = require(script.Parent.DataService)
local Pricing = require(ReplicatedStorage.Shared.Pricing)
local Odds = require(ReplicatedStorage.Shared.Odds)
local Notify = require(script.Parent.Parent.Util.Notify)
local Debounce = require(script.Parent.Parent.Util.Debounce)
local PlotService = require(script.Parent.PlotService)
local Pads = require(script.Parent.Parent.Util.Pads)
local Multipliers = require(ReplicatedStorage.Shared.Multipliers)
local Rewards = require(script.Parent.Parent.Util.Rewards)

local CrateConfig = Economy.Crate
local CRATE_COLOR = Color3.fromRGB(255, 200, 60)

local CrateService = {}

local rng = Random.new()
local worldCrates: { [Player]: { BasePart } } = {}
local crateFolder: Folder

function CrateService:BuyPrice(player: Player): number
	return Pricing.Crate(player, DataService:Get(player))
end

function CrateService:Roll(bestTier: number, shift: number): number
	-- same outcome table the Crates panel shows (shared/Odds), so displayed odds == real odds
	return Odds.Roll(Odds.Crate(bestTier, shift), rng)
end

-- highest tier with count > 0 (1 if none)
local function bestTier(data: any): number
	local best = 1
	for key, count in data.cows do
		local tier = tonumber(key)
		if tier and count > 0 and tier > best then
			best = tier
		end
	end
	return best
end

local function openOne(player: Player, data: any, shift: number, source: string): number
	local tier = CrateService:Roll(bestTier(data), shift)
	data.stats.cratesOpened += 1
	DataService:Replicate(player, "stats")
	Rewards.Cow(player, tier, 1)
	Net.Event("CrateOpened"):FireClient(player, tier, source)
	return tier
end

function CrateService:GiveCrate(player: Player, premium: boolean): number?
	local data = DataService:Get(player)
	if not data then
		return nil
	end
	if premium then
		return openOne(player, data, CrateConfig.PremiumOddsShift, "premium")
	end
	Rewards.Crates(player, 1)
	return nil
end

local function onOpen(player: Player)
	if not Debounce.Try(player, "openCrate", 0.3) then
		return
	end
	local data = DataService:Get(player)
	if not data then
		return
	end
	if data.crates <= 0 then
		Notify.To(player, "You have no crates!", "error")
		return
	end
	data.crates -= 1
	DataService:Replicate(player, "crates")
	openOne(player, data, 0, "crate")
end

local function onBuy(player: Player)
	if not Debounce.Try(player, "buyCrate", 0.3) then
		return
	end
	if not DataService:Get(player) then
		return
	end
	local price = CrateService:BuyPrice(player)
	if not DataService:SpendCash(player, price) then
		Notify.To(player, `Not enough cash! Crate costs {Format.Cash(price)}`, "error")
		return
	end
	local data = DataService:Get(player)
	data.cratesBought = (data.cratesBought or 0) + 1
	DataService:Replicate(player, "cratesBought")
	CrateService:GiveCrate(player, false)
	Notify.To(player, "Bought a Mystery Milk Crate!", "success")
end

-- World drops ------------------------------------------------------------------------

local function removeCrate(player: Player, crate: BasePart)
	local list = worldCrates[player]
	if list then
		local i = table.find(list, crate)
		if i then
			table.remove(list, i)
		end
	end
	crate:Destroy()
end

local function buildCrate(): BasePart
	local crate = Instance.new("Part")
	crate.Name = "MysteryCrate"
	crate.Size = Vector3.new(2.5, 2.5, 2.5)
	crate.Material = Enum.Material.Neon
	crate.Color = CRATE_COLOR
	crate.Anchored = true
	crate.CanCollide = false
	crate.CanQuery = false

	local light = Instance.new("PointLight")
	light.Color = CRATE_COLOR
	light.Brightness = 2
	light.Range = 10
	light.Parent = crate

	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromScale(3, 3)
	gui.StudsOffset = Vector3.new(0, 2.5, 0)
	gui.AlwaysOnTop = true
	gui.Parent = crate
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Text = "?"
	text.TextScaled = true
	text.Font = Enum.Font.FredokaOne
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0
	text.Parent = gui
	return crate
end

local function spawnCrate(player: Player): boolean
	local plot = PlotService:GetPlot(player)
	local spawnPart = plot and plot:FindFirstChild("CrateSpawn")
	if not spawnPart or not spawnPart:IsA("BasePart") then
		return false
	end
	local list = worldCrates[player]
	if not list then
		list = {}
		worldCrates[player] = list
	end
	if #list >= CrateConfig.MaxWorldCrates then
		return false
	end

	local crate = buildCrate()
	local half = spawnPart.Size / 2
	local offset =
		Vector3.new(rng:NextNumber(-half.X, half.X) * 0.8, half.Y + 1.5, rng:NextNumber(-half.Z, half.Z) * 0.8)
	crate.CFrame = CFrame.new(spawnPart.Position + offset)
	crate:SetAttribute("OwnerUserId", player.UserId)
	crate.Parent = crateFolder
	table.insert(list, crate)

	local spin = TweenService:Create(
		crate,
		TweenInfo.new(3, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
		{ CFrame = crate.CFrame * CFrame.Angles(0, math.pi, 0) }
	)
	spin:Play()

	local taken = false
	crate.Touched:Connect(function(hit)
		if taken then
			return
		end
		local toucher = Pads.PlayerFromHit(hit, crate)
		if toucher ~= player then
			return
		end
		local data = DataService:Get(player)
		if not data then
			return
		end
		taken = true
		spin:Cancel()
		Rewards.Crates(player, 1)
		Notify.To(player, "Picked up a Mystery Milk Crate!", "rare")
		Net.Event("Fx"):FireClient(player, "crate", { position = crate.Position })
		removeCrate(player, crate)
	end)
	Notify.To(player, "A Mystery Milk Crate dropped on your farm!", "rare")
	return true
end

local function rollDrops()
	local minutes = CrateConfig.DropCheckSeconds / 60
	local ev = Multipliers.ActiveEvent()
	local eventMult = if ev and typeof(ev.crateDropMultiplier) == "number" then ev.crateDropMultiplier else 1
	local perCow = math.min(1, CrateConfig.DropChancePerCowPerMinute * minutes * eventMult)
	for _, player in Players:GetPlayers() do
		local data = DataService:Get(player)
		if data then
			local cowCount = 0
			for _, count in data.cows do
				cowCount += count
			end
			-- chance that at least one cow drops; capped at one crate per roll
			local chance = 1 - (1 - perCow) ^ cowCount
			if cowCount > 0 and rng:NextNumber() < chance then
				spawnCrate(player)
			end
		end
	end
end

function CrateService:Init()
	crateFolder = Instance.new("Folder")
	crateFolder.Name = "DroppedCrates"
	crateFolder.Parent = workspace
end

function CrateService:Start()
	Net.Event("RequestOpenCrate").OnServerEvent:Connect(onOpen)
	Net.Event("RequestBuyCrate").OnServerEvent:Connect(onBuy)
	Players.PlayerRemoving:Connect(function(player)
		local list = worldCrates[player]
		worldCrates[player] = nil
		if list then
			for _, crate in list do
				crate:Destroy()
			end
		end
	end)
	while true do
		task.wait(CrateConfig.DropCheckSeconds)
		Safe.Run("CrateService drops", rollDrops)
	end
end

return CrateService
