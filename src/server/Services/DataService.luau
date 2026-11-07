--!strict
-- Player data: ProfileStore session-locked saves + replication of top-level keys to the owner.
-- Owner: lead session. Other services use ONLY the public API below.
--
--   DataService:Get(player)               -> data | nil       (live table, read freely)
--   DataService:WaitFor(player)           -> data | nil       (yields until loaded or player left)
--   DataService:Set(player, key, value)                        (top-level set + replicate)
--   DataService:Update(player, key, fn)                        (fn(old) -> new, + replicate)
--   DataService:Replicate(player, key)                         (after mutating a nested table in place)
--   DataService:AddCash(player, amount, countsAsEarned?)       (tracks totalCashEarned unless countsAsEarned == false)
--   DataService:SpendCash(player, amount) -> boolean          (atomic check + subtract)
--   DataService:GetProfile(player)        -> profile | nil    (Monetization only: profile:Save() after receipts)
--   DataService.PlayerLoaded:Connect(fn(player, data))
--   DataService.PlayerSaving:Connect(fn(player, data))         (fires right before the final save on leave)
--
-- Template rules: cows are keyed by STRING tier ("1".."18") so DataStore never sees sparse arrays.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileStore = require(ReplicatedStorage.Packages.ProfileStore)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Net = require(ReplicatedStorage.Shared.Net)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)

local STORE_NAME = "PlayerData_v1"
-- Studio playtests use a mock store (data resets each test, never touches live data).
-- Flip to false to test real saving in Studio (needs "Enable Studio Access to API Services").
local USE_MOCK_IN_STUDIO = true

local function startingCows()
	local cows = {}
	for tier, count in Economy.StartingCows do
		cows[tostring(tier)] = count
	end
	return cows
end

local TEMPLATE = {
	cash = Economy.StartingCash,
	totalCashEarned = 0,
	cows = {}, -- { ["1"] = 3, ["2"] = 1, ... }  starting cows are seeded on first join only:
	-- a template default would be re-added by Reconcile after merging it away (free cow per rejoin)
	cowsBought = 0, -- this rebirth, drives buy price
	cratesBought = 0, -- this rebirth, drives crate price (Economy.Crate.BuyPriceGrowth)
	tankMilk = 0,
	canMilk = 0,
	dairyQueue = 0, -- milk deposited and waiting to be sold
	dairyCash = 0, -- sold cash waiting on the collect pad
	upgrades = {
		tankCapacity = 0,
		pipeSpeed = 0,
		canSize = 0,
		walkSpeed = 0,
		sellSpeed = 0,
		autoCollect = 0,
	},
	rebirths = 0,
	crates = 0, -- unopened Mystery Milk Crates
	discovered = {} :: { [string]: boolean }, -- index of tiers ever owned
	boosts = {} :: { [string]: { kind: string, mult: number, expires: number } },
	quests = {} :: { [string]: any }, -- QuestService owns the shape
	redeemedCodes = {} :: { [string]: boolean },
	purchases = {} :: { string }, -- last receipt PurchaseIds (MonetizationService idempotency)
	settings = { music = true, sfx = true, voice = true, reduceMotion = false },
	stats = { milkSold = 0, merges = 0, cratesOpened = 0, playSeconds = 0 },
	lastOnline = 0, -- os.time() of last save, used for offline earnings
	firstJoin = 0,
	tutorialStep = 0, -- C4 TutorialService; 0 = not started, Config/Tutorial.Done = finished
	-- F1 pets / eggs (shapes documented in PetService / EggService). Kept on rebirth.
	pets = {} :: { [string]: { id: string, variant: string } },
	equippedPets = {} :: { string },
	nests = {} :: { [string]: { egg: string, readyAt: number, luck: number } },
	petIndex = {} :: { [string]: boolean },
	lastFreeEgg = 0,
	dailyStreak = 0, -- E1 DailyService: days claimed in the current streak (see Config/Daily)
	dailyLastClaim = 0, -- E1 DailyService: Multipliers.Now() of the last daily claim, 0 = never
	indexClaimed = {} :: { number }, -- E1 IndexRewardService: claimed milestone counts, e.g. { 3, 6 }
}

local DataService = {}
DataService.PlayerLoaded = Signal.new()
DataService.PlayerSaving = Signal.new()
DataService.Template = TEMPLATE

local liveStore = ProfileStore.New(STORE_NAME, TEMPLATE)
local store = if RunService:IsStudio() and USE_MOCK_IN_STUDIO then liveStore.Mock else liveStore

local profiles: { [Player]: any } = {}

local function replicate(player: Player, key: string)
	local profile = profiles[player]
	if profile then
		Net.Event("DataChanged"):FireClient(player, key, profile.Data[key])
	end
end

local function onPlayerAdded(player: Player)
	local profile = store:StartSessionAsync(`Player_{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})
	if profile == nil then
		player:Kick("Could not load your farm. Please rejoin!")
		return
	end
	profile:AddUserId(player.UserId)
	profile:Reconcile()
	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		player:Kick("Your farm was opened on another server. Please rejoin!")
	end)
	profile.OnSave:Connect(function()
		profile.Data.lastOnline = os.time()
	end)
	if player.Parent ~= Players then
		profile:EndSession()
		return
	end
	if profile.Data.firstJoin == 0 then
		profile.Data.firstJoin = os.time()
		profile.Data.cows = DataService:NewStartingCows()
		DataService:MarkStartingCowsDiscovered(profile.Data)
		profile.Data.tankMilk = Economy.StartingTankMilk
		profile.Data.crates = Economy.StartingCrates
	end
	profiles[player] = profile

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local cash = Instance.new("StringValue")
	cash.Name = "Cash"
	cash.Parent = leaderstats
	local reb = Instance.new("IntValue")
	reb.Name = "Rebirths"
	reb.Value = profile.Data.rebirths
	reb.Parent = leaderstats
	leaderstats.Parent = player

	Net.Event("DataInit"):FireClient(player, profile.Data)
	DataService.PlayerLoaded:Fire(player, profile.Data)
end

function DataService:Init()
	local Format = require(ReplicatedStorage.Shared.Format)
	-- keep leaderstats in sync cheaply
	task.spawn(function()
		while true do
			task.wait(1)
			for player, profile in profiles do
				local ls = player:FindFirstChild("leaderstats")
				if ls then
					(ls :: any).Cash.Value = Format.Cash(profile.Data.cash);
					(ls :: any).Rebirths.Value = profile.Data.rebirths
				end
			end
		end
	end)
end

function DataService:Start()
	-- One waiting thread per player: while a call is already waiting for the profile, extra calls
	-- return nil right away (the client also gets DataInit), so spamming GetData can't pile up threads.
	local waiting: { [Player]: boolean } = {}
	Net.Function("GetData").OnServerInvoke = function(player: Player)
		local data = DataService:Get(player)
		if data or waiting[player] then
			return data
		end
		waiting[player] = true
		data = DataService:WaitFor(player)
		waiting[player] = nil
		return data
	end
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		local profile = profiles[player]
		if profile then
			DataService.PlayerSaving:Fire(player, profile.Data)
			profile.Data.lastOnline = os.time()
			profiles[player] = nil
			profile:EndSession()
		end
	end)
end

function DataService:Get(player: Player): any
	local profile = profiles[player]
	return profile and profile.Data
end

function DataService:WaitFor(player: Player): any
	while player.Parent == Players do
		local profile = profiles[player]
		if profile then
			return profile.Data
		end
		task.wait()
	end
	return nil
end

function DataService:GetProfile(player: Player): any
	return profiles[player]
end

function DataService:Set(player: Player, key: string, value: any)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.Data[key] = value
	replicate(player, key)
end

function DataService:Update(player: Player, key: string, fn: (any) -> any)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.Data[key] = fn(profile.Data[key])
	replicate(player, key)
end

function DataService:Replicate(player: Player, key: string)
	replicate(player, key)
end

local function isBadNumber(n: number): boolean
	return n ~= n or n == math.huge or n == -math.huge
end

-- Starting herd for brand-new players, after a rebirth and after /reset.
function DataService:NewStartingCows(): { [string]: number }
	return startingCows()
end

-- The starting herd is already "known": without this the first buy fires a NEW COW reveal
-- for a cow the player owns, and the Index shows it as "???".
function DataService:MarkStartingCowsDiscovered(data: any)
	for tier in Economy.StartingCows do
		data.discovered[tostring(tier)] = true
	end
end

function DataService:AddCash(player: Player, amount: number, countsAsEarned: boolean?)
	local profile = profiles[player]
	if not profile or isBadNumber(amount) then
		return
	end
	profile.Data.cash += amount
	if amount > 0 and countsAsEarned ~= false then
		profile.Data.totalCashEarned += amount
	end
	replicate(player, "cash")
end

function DataService:SpendCash(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile or isBadNumber(amount) or amount < 0 or profile.Data.cash < amount then
		return false
	end
	profile.Data.cash -= amount
	replicate(player, "cash")
	return true
end

return DataService
