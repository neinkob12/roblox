--!nocheck
-- E1 retention scenario: daily login reward (claim, 20h cooldown, 48h streak reset) and
-- Cow Index milestone rewards (claim, refusals, permanent cash bonus).

local Harness = require("../mock/Harness")
local T = require("../lib/T")

local H = Harness.new({ root = ".", echo = true })
local S = Harness.S

local function dataOf(player)
	return H:serverModule("Services.DataService"):Get(player)
end

-- Jump the wall clock (Multipliers.Now / os.time) without simulating every frame in between.
local function jumpHours(hours)
	S.epoch += hours * 3600
	H:advance(1.5) -- past the per-player request debounce (os.clock)
end

local function finishTutorial(player)
	local Tutorial = H:sharedModule("Config.Tutorial")
	local d = dataOf(player)
	for step = d.tutorialStep + 1, Tutorial.Done do
		H:advance(0.6)
		H:fireServer(player, "RequestTutorialStep", step)
	end
	H:advance(1)
	return d.tutorialStep == Tutorial.Done
end

local function dailyDim(player)
	local gui = player.PlayerGui:FindFirstChild("Daily")
	return gui and gui.Root:FindFirstChild("Dim")
end

local function menuBadge(player, name)
	local menu = player.PlayerGui:FindFirstChild("Menu")
	local b = menu and menu.Root.SideButtons:FindFirstChild(name)
	return b and b:FindFirstChild("Badge")
end

H:boot()
H:advance(2)
local alice = H:addPlayer("Alice")
local bob = H:addPlayer("Bob")
H:advance(4)
local aData = dataOf(alice)
local Daily = H:sharedModule("Config.Daily")
local IndexRewards = H:sharedModule("Config.IndexRewards")
local Multipliers = H:sharedModule("Multipliers")

---------------------------------------------------------------- daily popup
T.section("daily popup")
T.check("Daily ScreenGui built", alice.PlayerGui:FindFirstChild("Daily") ~= nil)
T.check("no daily popup during the tutorial", dailyDim(alice) and dailyDim(alice).Visible == false)
T.check("Daily menu badge while a claim is available", menuBadge(alice, "Daily") and menuBadge(alice, "Daily").Visible)
T.check("Alice finishes the tutorial", finishTutorial(alice))
H:advance(4)
T.check("daily popup opens after the tutorial", dailyDim(alice) and dailyDim(alice).Visible == true)
T.check("Bob (tutorial running) sees no popup", dailyDim(bob) and dailyDim(bob).Visible == false)

---------------------------------------------------------------- day 1
T.section("daily day 1")
local cashBefore = aData.cash
H:click(alice, dailyDim(alice).Card.Claim)
H:advance(1)
T.eq("day 1 claimed (streak 1)", aData.dailyStreak, 1)
T.check("day 1 gives cash", aData.cash >= cashBefore + Daily.CashMinimum, `{cashBefore} -> {aData.cash}`)
T.check("dailyLastClaim set", aData.dailyLastClaim > 0)
H:advance(1.5)
H:fireServer(alice, "RequestDailyClaim")
H:advance(1)
T.eq("second claim right away is refused", aData.dailyStreak, 1)
T.check("Daily menu badge hidden after claiming", menuBadge(alice, "Daily").Visible == false)

---------------------------------------------------------------- day 2 after 21h
T.section("daily day 2 after 21h")
jumpHours(19)
H:fireServer(alice, "RequestDailyClaim")
H:advance(1)
T.eq("claim after 19h is refused", aData.dailyStreak, 1)
jumpHours(2)
local cratesBefore = aData.crates
H:fireServer(alice, "RequestDailyClaim")
H:advance(1)
T.eq("day 2 claimed after 21h (streak 2)", aData.dailyStreak, 2)
T.eq("day 2 gives 1 crate", aData.crates, cratesBefore + 1)

---------------------------------------------------------------- streak reset after 49h
T.section("daily streak reset after 49h")
jumpHours(49)
cashBefore = aData.cash
H:fireServer(alice, "RequestDailyClaim")
H:advance(1)
T.eq("streak resets to day 1 after 49h", aData.dailyStreak, 1)
T.check("reset claim gives day 1 cash", aData.cash > cashBefore, `{cashBefore} -> {aData.cash}`)

---------------------------------------------------------------- full 7-day cycle loops
T.section("daily 7-day cycle")
for day = 2, #Daily.Days + 1 do
	jumpHours(21)
	H:fireServer(alice, "RequestDailyClaim")
	H:advance(1)
	T.eq(`cycle claim {day}`, aData.dailyStreak, day)
end
T.eq("the cycle loops (claim 8 was day 1, next is day 2)", Daily.NextDay(aData, Multipliers.Now()), 2)

---------------------------------------------------------------- index milestones
T.section("index milestones")
local Rewards = H:serverModule("Util.Rewards")
local function discover(n)
	H:run(function()
		for tier = 1, n do
			Rewards.Cow(alice, tier, 1)
		end
	end)
	H:advance(0.6)
end
aData.indexClaimed = {}
H:fireServer(alice, "RequestIndexClaim", 6)
H:advance(0.6)
T.eq("milestone 6 refused with too few cows", #aData.indexClaimed, 0)
discover(3)
T.check("3 tiers discovered", IndexRewards.DiscoveredCount(aData) >= 3)
cashBefore = aData.cash
H:fireServer(alice, "RequestIndexClaim", 3)
H:advance(0.6)
T.check("milestone 3 claimed", IndexRewards.IsClaimed(aData, 3))
T.check("milestone 3 gives cash", aData.cash > cashBefore, `{cashBefore} -> {aData.cash}`)
cashBefore = aData.cash
H:fireServer(alice, "RequestIndexClaim", 3)
H:advance(0.6)
T.eq("milestone 3 twice is refused", #aData.indexClaimed, 1)
for _, bad in { "3", 4, -1, 0 / 0, math.huge, {}, nil } do
	H:fireServer(alice, "RequestIndexClaim", bad)
	H:advance(0.6)
end
T.eq("bad milestone requests are ignored", #aData.indexClaimed, 1)

discover(12)
for _, count in { 6, 9, 12 } do
	H:fireServer(alice, "RequestIndexClaim", count)
	H:advance(0.6)
	T.check(`milestone {count} claimed`, IndexRewards.IsClaimed(aData, count))
end
-- same instant, with and without the claimed list (so a running event can't change the result)
local withBonus = Multipliers.Cash(alice, aData)
local saved = aData.indexClaimed
aData.indexClaimed = {}
local without = Multipliers.Cash(alice, aData)
aData.indexClaimed = saved
local ratio = withBonus / without
T.check("milestone 12 adds +5% cash forever", math.abs(ratio - 1.05) < 1e-6, tostring(ratio))
T.eq("Index badge hidden when all reached milestones are claimed", menuBadge(alice, "Index").Visible, false)

---------------------------------------------------------------- tap the new UI
T.section("tap the new UI")
local before = #H:errors()
for _, b in alice.PlayerGui:GetDescendants() do
	if b:IsA("GuiButton") and (b:IsDescendantOf(alice.PlayerGui.Daily) or b.Name:match("^Milestone") or b.Name == "Daily") then
		H:click(alice, b)
		H:advance(0.6)
	end
end
T.eq("tapping daily/index buttons raises no errors", #H:errors(), before)

---------------------------------------------------------------- data invariants + health
T.section("health")
local ok, err = pcall(Harness.Services.checkStorable, aData, "Alice")
T.check("data is DataStore-serializable", ok, tostring(err))
T.eq("no script errors", #H:errors(), 0)
for i, e in H:errors() do
	if i <= 8 then
		print(`  [{e.ctx}] {e.message}`)
	end
end
T.eq("no 'failed' warnings", #H:warnings("failed"), 0)
T.eq("no infinite yields", #H:warnings("infinite yield"), 0)
T.finish()
