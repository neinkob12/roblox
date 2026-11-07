--!nocheck
-- Broader systems scenario: codes, settings, tutorial, admin commands, monetization debug
-- grants, quests, tapping every UI button, a long soak (events, truck, crate drops),
-- rejoin with offline earnings, a full server and fast join/leave.

local Harness = require("../mock/Harness")
local T = require("../lib/T")

local H = Harness.new({ root = ".", echo = true })
local S = Harness.S
local Services = Harness.Services

local function dataOf(player)
	return H:serverModule("Services.DataService"):Get(player)
end

local function errorCount()
	return #H:errors()
end

local function newErrorsSince(n)
	local out = {}
	for i = n + 1, #H:errors() do
		table.insert(out, H:errors()[i].message)
	end
	return table.concat(out, " | ")
end

H:boot()
H:advance(2)

-- Alice and Dave are friends (FriendBoostService)
Services.state.friends[1001] = { [1003] = true }
Services.state.friends[1003] = { [1001] = true }
local alice = H:addPlayer("Alice")
local bob = H:addPlayer("Bob")
local dave = H:addPlayer("Dave")
H:advance(3)
local DataService = H:serverModule("Services.DataService")
local aData = dataOf(alice)

---------------------------------------------------------------- friends
T.section("friend boost")
H:advance(5)
T.check("Alice sees 1 friend", alice:GetAttribute("FriendCount") == 1, tostring(alice:GetAttribute("FriendCount")))

---------------------------------------------------------------- codes
T.section("codes")
local Codes = H:sharedModule("Config.Codes")
for code in Codes.List do
	H:advance(Codes.CooldownSeconds + 0.1)
	local ok, msg = H:invokeServer(alice, "RedeemCode", string.lower(code))
	T.check(`redeem {code}`, ok == true, tostring(msg))
	H:advance(Codes.CooldownSeconds + 0.1)
	local ok2 = H:invokeServer(alice, "RedeemCode", code)
	T.check(`redeem {code} twice is refused`, ok2 == false)
end
T.check("redeemedCodes saved", next(aData.redeemedCodes) ~= nil)

---------------------------------------------------------------- settings & tutorial
T.section("settings and tutorial")
H:fireServer(alice, "RequestSetting", "music", false)
H:step()
T.eq("RequestSetting music=false", aData.settings.music, false)
H:fireServer(alice, "RequestSetting", "notASetting", false)
H:step()
T.check("unknown setting ignored", aData.settings.notASetting == nil)
local Tutorial = H:sharedModule("Config.Tutorial")
for step = aData.tutorialStep + 1, Tutorial.Done do
	H:advance(0.6)
	H:fireServer(alice, "RequestTutorialStep", step)
end
H:advance(1)
T.eq("tutorial can be finished", aData.tutorialStep, Tutorial.Done)

---------------------------------------------------------------- admin commands (Studio = admin)
T.section("admin chat commands")
local before = errorCount()
local Events = H:sharedModule("Config.Events")
local firstEvent = Events.List and Events.List[1] and Events.List[1].id
local commands = {
	"/admin",
	"/cash 1e9",
	"/cash +2.5M",
	"/cows 3 5",
	"/rebirths 2",
	"/crate 3",
	"/price 1.2",
	"/price off",
	"/offline 3600",
	"/truck",
	"/cash notanumber",
	"/cows 99 1",
	"/crate -5",
}
if firstEvent then
	table.insert(commands, "/event " .. firstEvent)
	table.insert(commands, "/event off")
end
for _, cmd in commands do
	local found = H:chat(alice, cmd)
	T.check(`{cmd} is a registered command`, found)
	H:advance(0.5)
end
T.eq("admin commands raise no errors", errorCount(), before)
T.check("no admin '... failed' warnings", #H:warnings("%[AdminService%].*failed") == 0)
T.eq("/rebirths 2 sets rebirths", dataOf(alice).rebirths, 2)

---------------------------------------------------------------- monetization (Studio debug grants)
T.section("monetization")
local Monetization = H:serverModule("Services.MonetizationService")
local Products = H:sharedModule("Config.Products")
before = errorCount()
for key in Products.DevProducts do
	local res = H:run(function()
		return Monetization:DebugGrantProduct(bob, key)
	end)
	T.check(`DebugGrantProduct {key}`, res ~= nil, tostring(res))
	H:step()
end
for key in Products.Passes do
	H:run(function()
		Monetization:DebugSetPass(bob, key, true)
	end)
	H:step()
	T.check(`pass {key} owned`, H:run(function()
		return Monetization:OwnsPass(bob, key)
	end) == true)
end
H:advance(15) -- AutoMerge / AutoSell ticks
T.eq("monetization raises no errors", errorCount(), before)

---------------------------------------------------------------- quests
T.section("quests")
local bData = dataOf(bob)
T.check("Bob has active quests", type(bData.quests) == "table" and type(bData.quests.active) == "table" and #bData.quests.active > 0)
-- finish every quest by hand (progress is server data) and claim it
before = errorCount()
for _, q in table.clone(bData.quests.active or {}) do
	q.progress = q.target
	H:advance(0.4)
	H:fireServer(bob, "RequestClaimQuest", q.id)
end
H:advance(1)
T.eq("quest claims raise no errors", errorCount(), before)

---------------------------------------------------------------- UI: tap everything
T.section("tap every UI button")
before = errorCount()
local function allButtons(player)
	local out = {}
	for _, x in player.PlayerGui:GetDescendants() do
		if x:IsA("GuiButton") then
			table.insert(out, x)
		end
	end
	return out
end
local buttons = allButtons(alice)
T.check("Alice's UI has buttons", #buttons > 10, `{#buttons} buttons`)
for round = 1, 2 do
	for _, b in allButtons(alice) do
		if b.Parent then
			H:click(alice, b)
			H:step()
		end
	end
	H:advance(2)
end
T.eq("tapping every button raises no errors", errorCount(), before)
if errorCount() > before then
	print("  " .. newErrorsSince(before))
end
before = errorCount()
for _, key in { "F7", "C", "H", "F", "LeftBracket", "RightBracket", "One", "Two", "Three", "Four", "Five" } do
	H:pressKey(alice, key)
	H:step()
end
H:advance(2)
for _, key in { "F7" } do
	H:pressKey(alice, key)
end
H:advance(1)
T.eq("hotkeys raise no errors", errorCount(), before)

---------------------------------------------------------------- long soak
T.section("1 hour soak with a big herd (10 fps)")
before = errorCount()
H:run(function()
	local Rewards = H:serverModule("Util.Rewards")
	for tier = 1, 8 do
		Rewards.Cow(dave, tier, 4)
	end
end)
local crateTouches = 0
for _ = 1, 12 do
	H:advance(300, 0.1)
	local dropped = H.game.Workspace:FindFirstChild("DroppedCrates")
	if dropped then
		for _, c in dropped:GetChildren() do
			local owner = c:GetAttribute("OwnerUserId")
			for _, p in { alice, bob, dave } do
				if p.Parent and p.UserId == owner then
					H:touch(c, p)
					crateTouches += 1
				end
			end
		end
	end
	-- keep the loop going: Dave sells milk
	local plot = H.game.Workspace.Plots:FindFirstChild("Plot" .. tostring(dave:GetAttribute("PlotId")))
	if plot then
		H:touch(plot.TankTap, dave)
		H:touch(H.game.Workspace.Dairy.DepositPad, dave)
		H:advance(10)
		H:touch(H.game.Workspace.Dairy.CashPad, dave)
	end
end
T.eq("soak raises no errors", errorCount(), before)
if errorCount() > before then
	print("  " .. newErrorsSince(before))
end
T.check("an event ran during the soak", H.game.Workspace:GetAttribute("EventNextAt") ~= nil)
print(`  (picked up {crateTouches} dropped crates)`)

---------------------------------------------------------------- rejoin
T.section("rejoin with offline earnings")
local bobId = bob.UserId
-- offline milk only fills free tank space, so leave with an empty tank
dataOf(bob).tankMilk = 0
H:removePlayer(bob)
H:advance(3600, 0.25)
local bob2 = H:addPlayer("Bob", { userId = bobId })
H:advance(3)
T.check("Bob's data loads again", dataOf(bob2) ~= nil)
T.check("Bob kept his codes/quests", dataOf(bob2) and dataOf(bob2).quests ~= nil)
local offline = H:received(bob2, "OfflineEarnings")
T.check("OfflineEarnings popup after 1h away", #offline == 1, `{#offline} events`)

---------------------------------------------------------------- full server
T.section("full server")
before = errorCount()
local extra = {}
for i = 1, 4 do
	table.insert(extra, H:addPlayer("Extra" .. i))
end
H:advance(3)
local plots = {}
for _, p in { alice, bob2, dave, table.unpack(extra) } do
	local id = p:GetAttribute("PlotId")
	if id then
		plots[id] = (plots[id] or 0) + 1
	end
end
local dupes = false
for _, n in plots do
	if n > 1 then
		dupes = true
	end
end
T.check("no two players share a plot", not dupes)
local seventh = extra[4]
T.check("7th player gets no plot", seventh:GetAttribute("PlotId") == nil)
local notes = H:received(seventh, "Notify")
T.check("7th player is told the server is full", #notes > 0)
T.eq("full server raises no errors", errorCount(), before)

---------------------------------------------------------------- respawn / death
T.section("respawn and death")
before = errorCount()
local hum = alice.Character:FindFirstChildOfClass("Humanoid")
H:run(function()
	hum.Health = 0
end)
H:advance(1)
H:run(function()
	alice:LoadCharacter()
end)
H:advance(1)
local plot1 = H.game.Workspace.Plots:FindFirstChild("Plot" .. alice:GetAttribute("PlotId"))
local dist = (alice.Character:GetPivot().Position - plot1.Spawn.Position).Magnitude
T.check("respawned character is moved to the plot", dist < 15, `distance {math.floor(dist)}`)
T.eq("respawn raises no errors", errorCount(), before)

---------------------------------------------------------------- fast join/leave
T.section("leave while loading")
before = errorCount()
H:removePlayer(extra[1])
local flicker = H:addPlayer("Flicker")
H:removePlayer(flicker)
H:advance(5)
T.eq("join+leave in the same frame raises no errors", errorCount(), before)
T.check("plot of a player who left during load is free", (function()
	for _, plot in H.game.Workspace.Plots:GetChildren() do
		if plot:GetAttribute("OwnerUserId") == flicker.UserId then
			return false
		end
	end
	return true
end)())

---------------------------------------------------------------- data invariants
T.section("data invariants")
for _, p in H.game.Players:GetPlayers() do
	local d = dataOf(p)
	if d then
		local ok, err = pcall(Services.checkStorable, d, p.Name)
		T.check(`{p.Name}: data is DataStore-serializable (no NaN/inf/mixed tables)`, ok, tostring(err))
		T.check(`{p.Name}: cash >= 0`, d.cash >= 0, tostring(d.cash))
		local badCow = nil
		for tier, n in d.cows do
			if type(n) ~= "number" or n < 0 or n ~= math.floor(n) then
				badCow = `{tier}={n}`
			end
		end
		T.check(`{p.Name}: cow counts are whole and >= 0`, badCow == nil, tostring(badCow))
	end
end

---------------------------------------------------------------- shutdown
T.section("shutdown")
before = errorCount()
H:shutdown()
H:advance(5)
T.eq("BindToClose / leaving raises no errors", errorCount(), before)

---------------------------------------------------------------- global health
T.section("health")
T.eq("no script errors", errorCount(), 0)
for i, e in H:errors() do
	if i <= 8 then
		print(`  [{e.ctx}] {e.message}`)
	end
end
local failed = H:warnings("failed")
T.eq("no 'failed' warnings", #failed, 0)
for _, w in failed do
	print("  " .. w.ctx .. ": " .. w.text)
end
local yields = H:warnings("infinite yield")
T.eq("no infinite yields", #yields, 0)
for _, w in yields do
	print("  " .. w.ctx .. ": " .. w.text)
end
T.finish()
