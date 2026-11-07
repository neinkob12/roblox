--!strict
-- F1: eggs and nests: buying, the free egg, offline hatch timers and hatching. Owner: F1.
--
-- DATA SHAPES (DataService keys, replicated with DataChanged(key, value)):
--   data.nests       { ["1"] = { egg = "pasture", readyAt = number, luck = number } }
--                    String keys "1".."Eggs.MaxNests"; an absent key = empty nest.
--                    readyAt is Multipliers.Now() (server Unix time) + hatchSeconds, so eggs keep
--                    hatching while the player is offline. luck = the player's luck when the egg was
--                    placed: the egg rolls with Odds.Egg(egg, luck), the odds shown before buying.
--   data.lastFreeEgg number   Multipliers.Now() of the last free egg claim (0 = never).
--                    Next free egg at lastFreeEgg + Eggs.FreeEggSeconds.
--
-- Unlocked nests: Eggs.NestsFor(data.rebirths). An egg in a nest above that count (admin rebirth
-- change) still hatches; new eggs only go into unlocked nests.
--
-- REMOTES:
--   RequestBuyEgg(eggId)        cash price Pricing.Egg(player, data, eggId) -> first free nest.
--                               Refused when ComplianceService:IsPaidRandomRestricted(player).
--   RequestClaimFreeEgg()       a free Eggs.FreeEggId egg when the cooldown is over (never gated)
--   RequestHatch(nestKey)       hatches a ready egg: rolls on the server, adds the pet, fires
--                               PetHatched(petUid, petId, variant) to the owner + Fx "crate" at the nest
-- Refusals always answer with a Notify toast.
--
-- API (server):
--   EggService:PlaceEgg(player, eggId) -> nestKey?    puts a free egg in the first free nest
--                                                     (codes/quests can use it; no price, no gate)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Eggs = require(ReplicatedStorage.Shared.Config.Eggs)
local Pets = require(ReplicatedStorage.Shared.Config.Pets)
local Odds = require(ReplicatedStorage.Shared.Odds)
local Format = require(ReplicatedStorage.Shared.Format)
local Pricing = require(ReplicatedStorage.Shared.Pricing)
local Multipliers = require(ReplicatedStorage.Shared.Multipliers)
local DataService = require(script.Parent.DataService)
local PetService = require(script.Parent.PetService)
local PlotService = require(script.Parent.PlotService)
local ComplianceService = require(script.Parent.ComplianceService)
local Notify = require(script.Parent.Parent.Util.Notify)
local Debounce = require(script.Parent.Parent.Util.Debounce)

local EggService = {}

local rng = Random.new()

local function occupiedCount(data: any): number
	local n = 0
	for _ in data.nests do
		n += 1
	end
	return n
end

local function freeNest(data: any): string?
	for i = 1, Eggs.NestsFor(data.rebirths or 0) do
		local key = tostring(i)
		if data.nests[key] == nil then
			return key
		end
	end
	return nil
end

-- why a new egg can't be placed right now (nil = it can)
local function placeBlocker(data: any): string?
	if PetService:Count(data) + occupiedCount(data) >= Pets.MaxInventory then
		return `Your pet inventory is full ({Pets.MaxInventory})! Merge or release some pets first.`
	end
	if not freeNest(data) then
		return "All your nests are busy! Hatch an egg first."
	end
	return nil
end

local function place(player: Player, data: any, egg: Eggs.Egg): string?
	local key = freeNest(data)
	if not key then
		return nil
	end
	data.nests[key] = {
		egg = egg.id,
		readyAt = Multipliers.Now() + egg.hatchSeconds,
		luck = Multipliers.PetBonus(data, "luck"),
	}
	DataService:Replicate(player, "nests")
	return key
end

function EggService:PlaceEgg(player: Player, eggId: string): string?
	local data = DataService:Get(player)
	local egg = Eggs.ById[eggId]
	if not data or not egg or placeBlocker(data) then
		return nil
	end
	return place(player, data, egg)
end

local function onBuy(player: Player, eggId: any)
	if typeof(eggId) ~= "string" then
		return
	end
	local egg = Eggs.ById[eggId]
	if not egg or not Debounce.Try(player, "buyEgg", 0.3) then
		return
	end
	local data = DataService:Get(player)
	if not data then
		return
	end
	if ComplianceService:IsPaidRandomRestricted(player) then
		Notify.To(player, "Buying eggs is not available in your region. Claim the free egg!", "error")
		return
	end
	if (data.rebirths or 0) < egg.rebirthsRequired then
		Notify.To(player, `{egg.name} needs Rebirth {egg.rebirthsRequired}!`, "error")
		return
	end
	local blocker = placeBlocker(data)
	if blocker then
		Notify.To(player, blocker, "error")
		return
	end
	local price = Pricing.Egg(player, data, egg.id)
	if not DataService:SpendCash(player, price) then
		Notify.To(player, `Not enough cash! {egg.name} costs {Format.Cash(price)}`, "error")
		return
	end
	place(player, data, egg)
	Notify.To(player, `{egg.name} is in your nest! Hatches in {Format.Time(egg.hatchSeconds)}`, "success")
end

local function onClaimFree(player: Player)
	if not Debounce.Try(player, "freeEgg", 0.5) then
		return
	end
	local data = DataService:Get(player)
	if not data then
		return
	end
	local nextAt = (data.lastFreeEgg or 0) + Eggs.FreeEggSeconds
	local now = Multipliers.Now()
	if now < nextAt then
		Notify.To(player, `Next free egg in {Format.Time(math.ceil(nextAt - now))}`, "error")
		return
	end
	local blocker = placeBlocker(data)
	if blocker then
		Notify.To(player, blocker, "error")
		return
	end
	local egg = Eggs.ById[Eggs.FreeEggId]
	data.lastFreeEgg = now
	DataService:Replicate(player, "lastFreeEgg")
	place(player, data, egg)
	Notify.To(player, `Free {egg.name} is in your nest!`, "success")
end

local function nestPosition(player: Player, key: string): Vector3?
	local plot = PlotService:GetPlot(player)
	local nest = plot and plot:FindFirstChild("Nest" .. key, true)
	if nest and nest:IsA("BasePart") then
		return nest.Position
	elseif nest and nest:IsA("Model") then
		return nest:GetPivot().Position
	end
	return nil
end

local function onHatch(player: Player, key: any)
	if typeof(key) ~= "string" or #key > 4 then
		return
	end
	if not Debounce.Try(player, "hatchEgg", 0.3) then
		return
	end
	local data = DataService:Get(player)
	local nest = data and data.nests[key]
	if not data or typeof(nest) ~= "table" then
		return
	end
	local egg = Eggs.ById[nest.egg]
	if not egg then
		data.nests[key] = nil -- unknown egg id (removed from config): free the nest
		DataService:Replicate(player, "nests")
		return
	end
	local now = Multipliers.Now()
	if now < nest.readyAt then
		Notify.To(player, `Not ready yet! {Format.Time(math.ceil(nest.readyAt - now))} left`, "error")
		return
	end
	if PetService:Count(data) >= Pets.MaxInventory then
		Notify.To(
			player,
			`Your pet inventory is full ({Pets.MaxInventory})! Merge or release some pets first.`,
			"error"
		)
		return
	end
	local luck = math.clamp(tonumber(nest.luck) or 0, 0, Pets.LuckCap)
	local petId = Odds.Roll(Odds.Egg(egg.id, luck), rng)
	local uid = PetService:AddPet(player, petId, "normal")
	if not uid then
		return
	end
	data.nests[key] = nil
	DataService:Replicate(player, "nests")
	Net.Event("PetHatched"):FireClient(player, uid, petId, "normal")
	local pos = nestPosition(player, key)
	if pos then
		Net.Event("Fx"):FireClient(player, "crate", { position = pos })
	end
	local pet = Pets.ById[petId]
	local rarity = Pets.RarityById[pet.rarity]
	Notify.To(player, `Hatched {rarity.name} {pet.name}!`, if rarity.order >= 4 then "rare" else "success")
end

local function repair(data: any)
	if typeof(data.nests) ~= "table" then
		data.nests = {}
	end
	for key, nest in data.nests do
		if
			typeof(key) ~= "string"
			or typeof(nest) ~= "table"
			or not Eggs.ById[nest.egg]
			or typeof(nest.readyAt) ~= "number"
		then
			data.nests[key] = nil
		end
	end
	if typeof(data.lastFreeEgg) ~= "number" then
		data.lastFreeEgg = 0
	end
end

function EggService:Start()
	Net.Event("RequestBuyEgg").OnServerEvent:Connect(onBuy)
	Net.Event("RequestClaimFreeEgg").OnServerEvent:Connect(onClaimFree)
	Net.Event("RequestHatch").OnServerEvent:Connect(onHatch)
	DataService.PlayerLoaded:Connect(function(player, data)
		repair(data)
		DataService:Replicate(player, "nests")
	end)
	for _, player in Players:GetPlayers() do
		local data = DataService:Get(player)
		if data then
			repair(data)
		end
	end
end

return EggService
