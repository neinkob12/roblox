--!nocheck
-- F1 pets / eggs / nests (issue #51): free egg, hatch, equip, milk boost, merge, compliance gate,
-- offline hatching, rebirth keeps pets, odds sum to 1, remote fuzz.

local Harness = require("../mock/Harness")
local T = require("../lib/T")

local H = Harness.new({ root = ".", echo = true })

local function dataOf(player)
	return H:serverModule("Services.DataService"):Get(player)
end

local function count(t)
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

H:boot()
H:advance(2)
local alice = H:addPlayer("Alice")
local bob = H:addPlayer("Bob")
H:advance(5)
local DataService = H:serverModule("Services.DataService")
local Pets = H:sharedModule("Config.Pets")
local Eggs = H:sharedModule("Config.Eggs")
local Odds = H:sharedModule("Odds")
local Multipliers = H:sharedModule("Multipliers")
local aData = dataOf(alice)

---------------------------------------------------------------- odds
T.section("odds")
for _, egg in Eggs.List do
	for _, luck in { 0, 0.35, 1 } do
		local sum, n = 0, 0
		for _, o in Odds.Egg(egg.id, luck) do
			sum += o.chance
			n += 1
			T.check(`{egg.id} outcome {o.key} is a pet`, Pets.ById[o.key] ~= nil)
		end
		T.check(`{egg.id} odds (luck {luck}) sum to 1`, math.abs(sum - 1) < 1e-9, tostring(sum))
		T.check(`{egg.id} has outcomes`, n > 0)
	end
end
local cosmic = Odds.Egg("cosmic", 0)
local hasCommon = false
for _, o in cosmic do
	if Pets.ById[o.key].rarity == "common" then
		hasCommon = true
	end
end
T.check("Cosmic egg never drops commons", not hasCommon)
local function legendaryChance(outcomes)
	local c = 0
	for _, o in outcomes do
		if Pets.ById[o.key].rarity == "legendary" then
			c += o.chance
		end
	end
	return c
end
T.check("luck raises the legendary chance", legendaryChance(Odds.Egg("pasture", 1)) > legendaryChance(Odds.Egg("pasture", 0)))
T.check("pasture legendary = 0.2% without luck", math.abs(legendaryChance(Odds.Egg("pasture", 0)) - 0.002) < 1e-9)
local crateSum = 0
for _, o in Odds.Crate(5, 0, 0.5) do
	crateSum += o.chance
end
T.check("Odds.Crate with luck sums to 1", math.abs(crateSum - 1) < 1e-9)
T.eq("Odds.Egg of an unknown egg is empty", #Odds.Egg("nope", 0), 0)

---------------------------------------------------------------- free egg, hatch, equip
T.section("free egg, hatch, equip")
T.check("data has pet keys", type(aData.pets) == "table" and type(aData.nests) == "table" and type(aData.petIndex) == "table")
T.eq("EquippedPets attribute starts empty", alice:GetAttribute("EquippedPets"), "")
H:fireServer(alice, "RequestClaimFreeEgg")
H:step()
T.check("free egg placed in nest 1", aData.nests["1"] ~= nil and aData.nests["1"].egg == "pasture")
H:advance(1)
H:fireServer(alice, "RequestClaimFreeEgg")
H:step()
T.eq("second free egg refused (cooldown)", count(aData.nests), 1)
H:fireServer(alice, "RequestHatch", "1")
H:step()
T.eq("hatching too early is refused", count(aData.pets), 0)
H:advance(61)
H:clearReceived(alice)
H:fireServer(alice, "RequestHatch", "1")
H:step(2)
T.eq("hatched one pet", count(aData.pets), 1)
T.check("nest 1 is empty again", aData.nests["1"] == nil)
local hatched = H:received(alice, "PetHatched")
T.check("PetHatched fired", #hatched == 1 and aData.pets[hatched[1].args[1]] ~= nil)
local uid = next(aData.pets)
local pet = aData.pets[uid]
T.check("pet index updated", aData.petIndex[pet.id .. ":normal"] == true)

-- give Alice a milk pet so the milk/s check is deterministic
local PetService = H:serverModule("Services.PetService")
local milkUid = H:run(function()
	return PetService:AddPet(alice, "mochi", "normal")
end)
T.check("AddPet returns a uid", type(milkUid) == "string")
H:advance(3)
local mpsBefore = alice:GetAttribute("MilkPerSecond")
H:fireServer(alice, "RequestEquipPet", milkUid, true)
H:step()
T.check("pet equipped", table.find(aData.equippedPets, milkUid) ~= nil)
T.check("EquippedPets attribute lists it", string.find(alice:GetAttribute("EquippedPets") or "", "mochi:normal", 1, true) ~= nil)
H:advance(3)
local mpsAfter = alice:GetAttribute("MilkPerSecond")
T.check("MilkPerSecond goes up", mpsAfter > mpsBefore, `{mpsBefore} -> {mpsAfter}`)
T.check("PetBonus milk = 5%", math.abs(Multipliers.PetBonus(aData, "milk") - 0.05) < 1e-9)
H:fireServer(alice, "RequestEquipPet", "not-a-uid", true)
H:advance(0.3)
H:fireServer(bob, "RequestEquipPet", milkUid, true)
H:step()
T.eq("Bob can't equip Alice's pet", #dataOf(bob).equippedPets, 0)

---------------------------------------------------------------- merge
T.section("merge 5 into golden")
H:run(function()
	for _ = 1, 4 do
		PetService:AddPet(alice, "mochi", "normal")
	end
end)
H:advance(0.5)
H:fireServer(alice, "RequestMergePets", "mochi", "normal")
H:step()
local golden, normals = 0, 0
for _, p in aData.pets do
	if p.id == "mochi" and p.variant == "golden" then
		golden += 1
	elseif p.id == "mochi" and p.variant == "normal" then
		normals += 1
	end
end
T.eq("one golden mochi", golden, 1)
T.eq("no normal mochi left", normals, 0)
T.check("golden indexed", aData.petIndex["mochi:golden"] == true)
T.eq("golden replaced the equipped one", #aData.equippedPets, 1)
T.check("equipped pet is the golden", aData.pets[aData.equippedPets[1]].variant == "golden")
T.check("PetBonus milk = 12.5%", math.abs(Multipliers.PetBonus(aData, "milk") - 0.125) < 1e-9)
H:advance(0.5)
H:fireServer(alice, "RequestMergePets", "mochi", "golden")
H:step()
T.eq("merging without 5 changes nothing", golden, 1)

---------------------------------------------------------------- compliance
T.section("restricted player can't buy eggs")
H:run(function()
	DataService:AddCash(bob, 1e9)
	bob:SetAttribute("PaidRandomRestricted", true)
end)
local bobData = dataOf(bob)
local cashBefore = bobData.cash
H:fireServer(bob, "RequestBuyEgg", "pasture")
H:step()
T.eq("restricted: no egg", count(bobData.nests), 0)
T.eq("restricted: no cash spent", bobData.cash, cashBefore)
H:advance(1)
H:fireServer(bob, "RequestClaimFreeEgg")
H:step()
T.eq("restricted: free egg still works", count(bobData.nests), 1)
H:run(function()
	bob:SetAttribute("PaidRandomRestricted", false)
end)
H:advance(1)
H:fireServer(bob, "RequestBuyEgg", "pasture")
H:step()
T.eq("unrestricted: egg bought into nest 2", bobData.nests["2"] and bobData.nests["2"].egg, "pasture")
T.check("unrestricted: cash spent", bobData.cash < cashBefore)
H:advance(1)
H:fireServer(bob, "RequestBuyEgg", "dairy")
H:step()
T.eq("no free nest: third egg refused", count(bobData.nests), 2)
H:advance(1)
H:fireServer(bob, "RequestBuyEgg", "cosmic")
H:step()
T.eq("cosmic egg needs Rebirth 2", count(bobData.nests), 2)

---------------------------------------------------------------- offline
T.section("eggs hatch offline")
local bobId = bob.UserId
H:run(function()
	DataService:AddCash(alice, 1e9)
	aData.rebirths = 2
	alice:SetAttribute("PaidRandomRestricted", false)
end)
H:advance(1)
H:fireServer(alice, "RequestBuyEgg", "cosmic")
H:step()
T.check("Rebirth 2 can buy the Cosmic egg", aData.nests["1"] and aData.nests["1"].egg == "cosmic")
H:removePlayer(bob)
H:advance(15 * 60 + 5, 0.5)
local bob2 = H:addPlayer("Bob", { userId = bobId })
H:advance(5)
bobData = dataOf(bob2)
T.eq("Bob's nests survived the rejoin", count(bobData.nests), 2)
H:run(function()
	bob2:SetAttribute("PaidRandomRestricted", false)
end)
H:fireServer(bob2, "RequestHatch", "1")
H:advance(0.5)
H:fireServer(bob2, "RequestHatch", "2")
H:step(2)
T.eq("both offline eggs hatch right away", count(bobData.pets), 2)
H:fireServer(alice, "RequestHatch", "1")
H:step()
T.eq("Alice's cosmic egg hatched after 15 min", aData.nests["1"], nil)
T.eq("Alice now has 3 pets", count(aData.pets), 3)

---------------------------------------------------------------- rebirth
T.section("rebirth keeps pets")
local RebirthService = H:serverModule("Services.RebirthService")
H:run(function()
	DataService:AddCash(alice, RebirthService:Cost(aData.rebirths))
end)
local petsBefore = count(aData.pets)
local equippedBefore = #aData.equippedPets
local indexBefore = count(aData.petIndex)
H:advance(1.1)
H:fireServer(alice, "RequestRebirth")
H:step()
T.eq("rebirth happened", aData.rebirths, 3)
T.eq("rebirth keeps pets", count(aData.pets), petsBefore)
T.eq("rebirth keeps equipped pets", #aData.equippedPets, equippedBefore)
T.eq("rebirth keeps the index", count(aData.petIndex), indexBefore)
T.eq("Rebirth 3 has 4 nests", Eggs.NestsFor(aData.rebirths), 4)

---------------------------------------------------------------- equip slots & inventory cap
T.section("slots and cap")
H:run(function()
	aData.rebirths = 0
	for _ = 1, 3 do
		PetService:AddPet(alice, "cheddarino", "normal")
	end
end)
for uid2, p in aData.pets do
	if p.id == "cheddarino" then
		H:advance(0.2)
		H:fireServer(alice, "RequestEquipPet", uid2, true)
	end
end
H:step()
T.eq("only 3 slots at Rebirth 0", #aData.equippedPets, 3)
H:run(function()
	for _ = 1, 60 do
		PetService:AddPet(alice, "latte", "normal")
	end
end)
T.eq("inventory capped at 50", count(aData.pets), Pets.MaxInventory)
H:advance(Eggs.FreeEggSeconds + 1)
H:fireServer(alice, "RequestClaimFreeEgg")
H:step()
T.eq("full inventory: free egg refused", count(aData.nests), 0)

---------------------------------------------------------------- release (inventory deadlock fix)
T.section("release pets")
local equippedUid = aData.equippedPets[1]
local freeUids = {}
for u, p in aData.pets do
	if p.id == "latte" and not table.find(aData.equippedPets, u) then
		table.insert(freeUids, u)
	end
end
table.sort(freeUids)
T.check("Alice has unequipped lattes", #freeUids >= 5, tostring(#freeUids))
H:advance(0.6)
H:fireServer(bob2, "RequestReleasePets", { freeUids[1], freeUids[2] })
H:step()
T.eq("Bob can't release Alice's pets", count(aData.pets), Pets.MaxInventory)
H:advance(0.6)
H:fireServer(alice, "RequestReleasePets", { equippedUid })
H:step()
T.check("equipped pet can't be released", aData.pets[equippedUid] ~= nil)
H:advance(0.6)
H:clearReceived(alice)
H:fireServer(alice, "RequestReleasePets", { freeUids[1], freeUids[2], freeUids[3], freeUids[4], freeUids[5], freeUids[5], equippedUid })
H:step(2)
T.eq("released exactly 5 (duplicate and equipped skipped)", count(aData.pets), Pets.MaxInventory - 5)
T.check("equipped pet survives a mixed release", aData.pets[equippedUid] ~= nil)
T.check("released pets stay in the index", aData.petIndex["latte:normal"] == true)
local toasts = H:received(alice, "Notify")
T.check("toast says Released 5 pets", #toasts > 0 and toasts[#toasts].args[1] == "Released 5 pets", toasts[#toasts] and tostring(toasts[#toasts].args[1]))
H:advance(0.6)
H:fireServer(alice, "RequestClaimFreeEgg")
H:step()
T.eq("after releasing, the free egg works again", count(aData.nests), 1)
H:advance(0.6)
local tooMany = {}
for i = 1, Pets.MaxReleasePerRequest + 1 do
	tooMany[i] = freeUids[6] or "x"
end
H:fireServer(alice, "RequestReleasePets", tooMany)
H:step()
T.eq("more than 50 uids is refused", count(aData.pets), Pets.MaxInventory - 5)
local before = #H:errors()
for _, arg in { nil, 1, "x", true, { 1, 2 }, { {} }, { a = freeUids[6] }, { [1] = freeUids[6], [3] = "y" }, { alice }, { 0 / 0 } } do
	H:advance(0.6)
	H:fireServer(alice, "RequestReleasePets", arg)
end
H:advance(1)
T.eq("garbage release args raise no errors", #H:errors(), before)
T.eq("garbage release args release nothing", count(aData.pets), Pets.MaxInventory - 5)

---------------------------------------------------------------- fuzz
T.section("remote fuzz")
local errorsBefore = #H:errors()
for _, name in { "RequestBuyEgg", "RequestClaimFreeEgg", "RequestHatch", "RequestEquipPet", "RequestMergePets", "RequestReleasePets" } do
	for _, arg in { nil, 1e308, -1, 0 / 0, "x", "1", true, {}, alice, string.rep("A", 500) } do
		H:fireServer(bob2, name, arg, arg)
		H:advance(0.35)
	end
end
H:advance(1)
T.eq("garbage remote args raise no server errors", #H:errors(), errorsBefore)
local okStore, storeErr = pcall(Harness.Services.checkStorable, dataOf(alice), "data")
T.check("pet data is DataStore-serializable", okStore, tostring(storeErr))

---------------------------------------------------------------- health
T.section("health")
T.eq("no script errors", #H:errors(), 0)
for i, e in H:errors() do
	if i <= 8 then
		print(`  [{e.ctx}] {e.message}`)
	end
end
T.eq("no 'failed' warnings", #H:warnings("failed"), 0)
T.eq("no infinite yields", #H:warnings("infinite yield"), 0)
T.finish()
