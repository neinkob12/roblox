--!strict
-- F1: pet inventory, equipping, merging and the pet index. Owner: F1.
--
-- DATA SHAPES (DataService keys, replicated to the owner with DataChanged(key, value)):
--   data.pets         { [uid: string] = { id: string, variant: "normal" | "golden" | "rainbow" } }
--                     uid = HttpService:GenerateGUID(false). Pet ids/variants: Config/Pets.
--   data.equippedPets { uid, ... }   array, at most Pets.SlotsFor(data.rebirths) entries, every uid
--                                    is a key of data.pets (repaired on load)
--   data.petIndex     { ["mochi:golden"] = true }   ever-owned id:variant (Pets.IndexKey)
--
-- PLAYER ATTRIBUTES:
--   EquippedPets : string   "mochi:normal,turbo:golden" (comma separated id:variant, equip order),
--                           "" when nothing is equipped. Every client renders other players' pets.
--
-- BOOSTS (shared/Multipliers.luau, server + client):
--   Multipliers.PetBonus(data, kind)   summed bonus of equipped pets, caps applied (0.25 = +25%)
--   Multipliers.PetIndexMilk(data)     1 + 0.02 x floor(index entries / 5)
--
-- REMOTES:
--   RequestEquipPet(petUid: string, equip: boolean)
--   RequestMergePets(petId: string, variant: string)  5 of id+variant -> 1 of the next variant.
--       Unequipped copies are used first; if an equipped copy was used, the new pet is equipped.
--
-- API (server):
--   PetService:AddPet(player, petId, variant) -> uid?    inventory cap checked, index updated
--   PetService:Count(data) -> number
--   PetService:Refresh(player)                          attribute + walk speed after a change

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Pets = require(ReplicatedStorage.Shared.Config.Pets)
local DataService = require(script.Parent.DataService)
local WalkSpeedService = require(script.Parent.WalkSpeedService)
local Notify = require(script.Parent.Parent.Util.Notify)
local Debounce = require(script.Parent.Parent.Util.Debounce)

local PetService = {}

function PetService:Count(data: any): number
	local n = 0
	for _ in data.pets or {} do
		n += 1
	end
	return n
end

local function attributeFor(data: any): string
	local parts = {}
	for _, uid in data.equippedPets do
		local pet = data.pets[uid]
		if pet then
			table.insert(parts, pet.id .. ":" .. pet.variant)
		end
	end
	return table.concat(parts, ",")
end

function PetService:Refresh(player: Player)
	local data = DataService:Get(player)
	if not data then
		return
	end
	player:SetAttribute("EquippedPets", attributeFor(data))
	WalkSpeedService:Apply(player)
end

-- marks the index entry; returns true when it was new
local function discover(player: Player, data: any, petId: string, variant: string): boolean
	local key = Pets.IndexKey(petId, variant)
	if data.petIndex[key] then
		return false
	end
	data.petIndex[key] = true
	DataService:Replicate(player, "petIndex")
	return true
end

function PetService:AddPet(player: Player, petId: string, variant: string): string?
	local data = DataService:Get(player)
	if not data or not Pets.ById[petId] or not Pets.VariantById[variant] then
		return nil
	end
	if PetService:Count(data) >= Pets.MaxInventory then
		return nil
	end
	local uid = HttpService:GenerateGUID(false)
	data.pets[uid] = { id = petId, variant = variant }
	DataService:Replicate(player, "pets")
	discover(player, data, petId, variant)
	return uid
end

-- Drops unknown/duplicate uids and pets with bad ids, trims to the slot count.
local function repair(data: any)
	if typeof(data.pets) ~= "table" then
		data.pets = {}
	end
	for uid, pet in data.pets do
		if typeof(pet) ~= "table" or not Pets.ById[pet.id] or not Pets.VariantById[pet.variant] then
			data.pets[uid] = nil
		end
	end
	if typeof(data.petIndex) ~= "table" then
		data.petIndex = {}
	end
	local slots = Pets.SlotsFor(data.rebirths or 0)
	local seen = {}
	local fixed = {}
	for _, uid in (if typeof(data.equippedPets) == "table" then data.equippedPets else {}) do
		if typeof(uid) == "string" and data.pets[uid] and not seen[uid] and #fixed < slots then
			seen[uid] = true
			table.insert(fixed, uid)
		end
	end
	data.equippedPets = fixed
end

local function onEquip(player: Player, uid: any, equip: any)
	if typeof(uid) ~= "string" or #uid > 64 or typeof(equip) ~= "boolean" then
		return
	end
	if not Debounce.Try(player, "equipPet", 0.1) then
		return
	end
	local data = DataService:Get(player)
	if not data or not data.pets[uid] then
		return
	end
	local idx = table.find(data.equippedPets, uid)
	if equip then
		if idx then
			return
		end
		local slots = Pets.SlotsFor(data.rebirths or 0)
		if #data.equippedPets >= slots then
			Notify.To(player, `All {slots} pet slots are full! Unequip one first.`, "error")
			return
		end
		table.insert(data.equippedPets, uid)
	else
		if not idx then
			return
		end
		table.remove(data.equippedPets, idx)
	end
	DataService:Replicate(player, "equippedPets")
	PetService:Refresh(player)
end

local function onMerge(player: Player, petId: any, variant: any)
	if typeof(petId) ~= "string" or typeof(variant) ~= "string" then
		return
	end
	local pet = Pets.ById[petId]
	local nextVariant = Pets.NextVariant[variant]
	if not pet or not nextVariant then
		return
	end
	if not Debounce.Try(player, "mergePets", 0.2) then
		return
	end
	local data = DataService:Get(player)
	if not data then
		return
	end
	-- unequipped copies first, then equipped ones (so the boost loss is as small as possible)
	local free, equipped = {}, {}
	for uid, p in data.pets do
		if p.id == petId and p.variant == variant then
			table.insert(if table.find(data.equippedPets, uid) then equipped else free, uid)
		end
	end
	table.sort(free)
	table.sort(equipped)
	if #free + #equipped < Pets.MergeCount then
		Notify.To(player, `You need {Pets.MergeCount} {Pets.VariantById[variant].name} {pet.name} to merge!`, "error")
		return
	end
	local used = {}
	for _, uid in free do
		if #used < Pets.MergeCount then
			table.insert(used, uid)
		end
	end
	local usedEquipped = false
	for _, uid in equipped do
		if #used < Pets.MergeCount then
			table.insert(used, uid)
			usedEquipped = true
		end
	end
	for _, uid in used do
		data.pets[uid] = nil
		local i = table.find(data.equippedPets, uid)
		if i then
			table.remove(data.equippedPets, i)
		end
	end
	-- 5 pets were removed, so there is always room for the new one
	local uid = HttpService:GenerateGUID(false)
	data.pets[uid] = { id = petId, variant = nextVariant }
	if usedEquipped then
		table.insert(data.equippedPets, uid)
	end
	discover(player, data, petId, nextVariant)
	DataService:Replicate(player, "pets")
	DataService:Replicate(player, "equippedPets")
	PetService:Refresh(player)
	Notify.To(player, `Merged into a {Pets.VariantById[nextVariant].name} {pet.name}!`, "rare")
end

function PetService:Start()
	Net.Event("RequestEquipPet").OnServerEvent:Connect(onEquip)
	Net.Event("RequestMergePets").OnServerEvent:Connect(onMerge)
	DataService.PlayerLoaded:Connect(function(player, data)
		repair(data)
		DataService:Replicate(player, "pets")
		DataService:Replicate(player, "equippedPets")
		PetService:Refresh(player)
	end)
	for _, player in Players:GetPlayers() do
		local data = DataService:Get(player)
		if data then
			repair(data)
			PetService:Refresh(player)
		end
	end
end

return PetService
