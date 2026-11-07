--!nocheck
-- Core loop scenario (issue #22): two players join, milk -> can -> dairy -> cash,
-- buy + merge, crate, upgrade, rebirth, leave. Runs the real server and client code.

local Harness = require("../mock/Harness")
local T = require("../lib/T")

local H = Harness.new({ root = ".", echo = true })
local S = Harness.S

local function dataOf(player)
	return H:serverModule("Services.DataService"):Get(player)
end

local function plotOf(player)
	local id = player:GetAttribute("PlotId")
	return id and H.game.Workspace.Plots:FindFirstChild("Plot" .. id)
end

---------------------------------------------------------------- boot
T.section("boot")
H:boot()
H:advance(2)
T.check("workspace.MapReady", H.game.Workspace:GetAttribute("MapReady") == true or H.game.Workspace:FindFirstChild("MapReady") ~= nil)
T.check("workspace.Plots exists", H.game.Workspace:FindFirstChild("Plots") ~= nil)
T.check("workspace.Dairy exists", H.game.Workspace:FindFirstChild("Dairy") ~= nil)
T.check("ReplicatedStorage.Net exists", H.game.ReplicatedStorage:FindFirstChild("Net") ~= nil)

---------------------------------------------------------------- join
T.section("two players join")
local alice = H:addPlayer("Alice")
local bob = H:addPlayer("Bob")
H:advance(3)
T.eq("Alice gets PlotId 1", alice:GetAttribute("PlotId"), 1)
T.eq("Bob gets PlotId 2", bob:GetAttribute("PlotId"), 2)
T.eq("Plot1 OwnerUserId = Alice", H.game.Workspace.Plots.Plot1:GetAttribute("OwnerUserId"), alice.UserId)
T.eq("Plot2 OwnerUserId = Bob", H.game.Workspace.Plots.Plot2:GetAttribute("OwnerUserId"), bob.UserId)
local aData = dataOf(alice)
T.check("Alice data loaded", aData ~= nil)
T.check("Alice has a character", alice.Character ~= nil and alice.Character.Parent == H.game.Workspace)
T.check("Alice has leaderstats", alice:FindFirstChild("leaderstats") ~= nil)
T.check("client got DataInit", #H:received(alice, "DataInit") == 1)
local aliceClientData = H:clientModule(alice, "Controllers.DataController"):Get()
T.check("client DataController has data", aliceClientData ~= nil)
T.check("client built HUD", alice.PlayerGui:FindFirstChild("Hud") ~= nil)
local startCash = aData.cash

---------------------------------------------------------------- milk
T.section("tank fills, can, dairy, cash")
H:advance(60)
local tankBefore = aData.tankMilk
T.check("tank filled after 60s", tankBefore > 0, `tankMilk={tankBefore}`)
T.check("MilkPerSecond attribute set", (alice:GetAttribute("MilkPerSecond") or 0) > 0)
T.check("TankCapacity attribute set", (alice:GetAttribute("TankCapacity") or 0) > 0)

local plot = plotOf(alice)
H:touch(plot.TankTap, alice)
H:step()
T.check("TankTap fills the can", aData.canMilk > 0, `canMilk={aData.canMilk}`)
T.check("TankTap drains the tank", aData.tankMilk < tankBefore, `tank {tankBefore} -> {aData.tankMilk}`)

local can = aData.canMilk
H:touch(H.game.Workspace.Dairy.DepositPad, alice)
H:step()
T.eq("DepositPad empties the can", aData.canMilk, 0)
T.check("milk queued or sold at the dairy", aData.dairyQueue > 0 or aData.dairyCash > 0, `queue={aData.dairyQueue} cash={aData.dairyCash} can was {can}`)

H:advance(30)
T.check("dairy sold the milk", aData.dairyCash > 0, `dairyCash={aData.dairyCash}`)
local cashBefore = aData.cash
H:touch(H.game.Workspace.Dairy.CashPad, alice)
H:step()
T.check("CashPad pays out", aData.cash > cashBefore, `cash {cashBefore} -> {aData.cash}`)
T.eq("dairyCash reset", aData.dairyCash, 0)
local clientData = H:clientModule(alice, "Controllers.DataController"):Get()
H:step(2)
T.eq("client cash mirrors server", clientData and clientData.cash, aData.cash)

---------------------------------------------------------------- buy & merge
T.section("buy 5, merge, discovery")
local DataService = H:serverModule("Services.DataService")
H:run(function()
	DataService:AddCash(alice, 1000)
end)
local BuyService = H:serverModule("Services.BuyService")
local price5 = BuyService:Price(aData.cowsBought, 5)
local cows1 = aData.cows["1"] or 0
cashBefore = aData.cash
H:touch(plot.BuyPad5, alice)
H:step()
T.eq("BuyPad5 gives 5 tier-1 cows", aData.cows["1"], cows1 + 5)
T.eq("BuyPad5 charges the price", cashBefore - aData.cash, price5)

H:clearReceived(alice)
H:advance(1.1) -- pad debounce
H:touch(plot.MergePad, alice)
H:step()
local expectedTier2 = (cows1 + 5) // 3
T.eq("MergePad merges into tier 2", aData.cows["2"], expectedTier2)
T.check("tier 2 discovered", aData.discovered["2"] == true)
local disc = H:received(alice, "CowDiscovered")
T.check("CowDiscovered fired with tier 2", #disc >= 1 and disc[1].args[1] == 2, `got {#disc} events`)
H:advance(1)
local stall = plot.Stalls:FindFirstChild("Stall2")
T.check("Stall2 shows a cow", stall ~= nil and stall:FindFirstChild("Cow") ~= nil)
local cow = stall and stall:FindFirstChild("Cow")
T.check("stall cow carries CowTier = 2", cow ~= nil and cow:GetAttribute("CowTier") == 2)

---------------------------------------------------------------- crate, upgrade, rebirth
T.section("crate, upgrade, rebirth")
H:run(function()
	DataService:AddCash(alice, 1e6)
end)
local cratesBefore = aData.crates
H:fireServer(alice, "RequestBuyCrate")
H:step()
T.eq("RequestBuyCrate adds a crate", aData.crates, cratesBefore + 1)
H:clearReceived(alice)
H:advance(0.5)
H:fireServer(alice, "RequestOpenCrate")
H:step()
T.eq("RequestOpenCrate uses the crate", aData.crates, cratesBefore)
local opened = H:received(alice, "CrateOpened")
T.check("CrateOpened fired", #opened == 1 and type(opened[1].args[1]) == "number", `got {#opened}`)

local lvl = aData.upgrades.tankCapacity
H:fireServer(alice, "RequestUpgrade", "tankCapacity")
H:step()
T.eq("RequestUpgrade tankCapacity +1", aData.upgrades.tankCapacity, lvl + 1)
H:fireServer(alice, "RequestUpgrade", "notAnUpgrade")
H:fireServer(alice, "RequestUpgrade", { evil = true })
H:step()
T.check("bad upgrade ids are ignored", aData.upgrades.notAnUpgrade == nil)

local RebirthService = H:serverModule("Services.RebirthService")
H:run(function()
	DataService:AddCash(alice, RebirthService:Cost(aData.rebirths))
end)
H:advance(1.1)
H:fireServer(alice, "RequestRebirth")
H:step()
aData = dataOf(alice)
T.eq("rebirth count 1", aData.rebirths, 1)
T.eq("rebirth resets cash", aData.cash, H:sharedModule("Config.Economy").StartingCash)
T.eq("rebirth resets upgrades", aData.upgrades.tankCapacity, 0)
T.check("rebirth keeps discovered", aData.discovered["2"] == true)

---------------------------------------------------------------- remote fuzz (server must not error)
T.section("remote validation")
local errorsBefore = #H:errors()
for _, name in { "RequestUpgrade", "RequestClaimQuest", "RequestSetting", "RequestTutorialStep" } do
	for _, arg in { nil, 1e308, -1, 0 / 0, "x", true, {}, alice } do
		H:fireServer(bob, name, arg, arg)
	end
end
local ok, msg = H:invokeServer(bob, "RedeemCode", nil)
H:invokeServer(bob, "RedeemCode", 12345)
H:invokeServer(bob, "RedeemCode", string.rep("A", 1000))
H:advance(1)
T.eq("garbage remote args raise no server errors", #H:errors(), errorsBefore)
T.check("GetData returns the snapshot", type(H:invokeServer(bob, "GetData")) == "table")

---------------------------------------------------------------- leave
T.section("player leaves")
local bobId = bob.UserId
H:removePlayer(bob)
H:advance(2)
T.eq("Plot2 freed (OwnerUserId = 0)", H.game.Workspace.Plots.Plot2:GetAttribute("OwnerUserId"), 0)
T.check("Bob's data released", dataOf(bob) == nil)
local carol = H:addPlayer("Carol")
H:advance(3)
T.eq("next player reuses Plot2", carol:GetAttribute("PlotId"), 2)

-- data that is saved must be DataStore-serializable
local okStore, storeErr = pcall(Harness.Services.checkStorable, dataOf(alice), "data")
T.check("Alice's data is DataStore-serializable", okStore, tostring(storeErr))

---------------------------------------------------------------- longer soak
T.section("soak 5 minutes")
H:advance(300)
T.check("server still ticking (tank refills)", dataOf(alice).tankMilk > 0)

---------------------------------------------------------------- global health
T.section("health")
local errs = H:errors()
local lines = {}
for i, e in errs do
	if i > 5 then
		break
	end
	table.insert(lines, `[{e.ctx}] {e.message}`)
end
T.eq("no script errors", #errs, 0)
if #errs > 0 then
	print("first errors:\n  " .. table.concat(lines, "\n  "))
end
local failed = H:warnings("failed")
T.eq("no 'failed' warnings from loaders/services", #failed, 0)
for _, w in failed do
	print("  " .. w.ctx .. ": " .. w.text)
end
local yields = H:warnings("infinite yield")
T.eq("no infinite yields", #yields, 0)
for _, w in yields do
	print("  " .. w.ctx .. ": " .. w.text)
end

T.finish()
