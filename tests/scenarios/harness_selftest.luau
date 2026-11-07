--!nocheck
-- Proves the harness catches what it claims to: thread errors, loader "failed" warnings,
-- typos in child names and bad remote usage, and that the fake clock drives task/os.time.
-- Every module below is injected only into this test's in-memory place (src/ is untouched).

local Harness = require("../mock/Harness")
local T = require("../lib/T")

local H = Harness.new({
	root = ".",
	echo = false,
	beforeStart = function(game)
		local services = game.ServerScriptService.Server.Services
		Harness.addModule(services, "ZZBrokenRequire", "error('boom on require')")
		Harness.addModule(
			services,
			"ZZBrokenStart",
			"return { Start = function() task.wait(1); local x: any = nil; x.y = 1 end }"
		)
		Harness.addModule(
			services,
			"ZZTypo",
			"return { Start = function() task.wait(2); local _ = workspace.Plots.Plot1.TankTapp end }"
		)
		Harness.addModule(
			services,
			"ZZDelayedError",
			"return { Init = function() task.delay(3, function() error('delayed boom') end) end }"
		)
		Harness.addModule(
			services,
			"ZZClock",
			[[return {
				Read = function() return os.time(), os.clock() end,
				Sleep = function(s) local t = os.clock(); task.wait(s); return os.clock() - t end,
				ClientFire = function()
					return pcall(function()
						game.ReplicatedStorage.Net.Notify:FireClient(nil, "x")
					end)
				end,
			}]]
		)
	end,
})
local S = Harness.S

H:boot()

T.section("loader failures are reported")
local w = H:warnings("failed")
local function hasWarn(pattern)
	for _, x in w do
		if string.find(x.text, pattern) then
			return true
		end
	end
	return false
end
T.check("require error -> '[Server] failed to load' warning", hasWarn("failed to load .*ZZBrokenRequire"))

T.section("fake clock")
local Clock = H:serverModule("Services.ZZClock")
local t0, c0 = H:run(function()
	return Clock.Read()
end)
H:advance(10)
local t1, c1 = H:run(function()
	return Clock.Read()
end)
T.check("os.clock follows the fake clock", math.abs((c1 - c0) - 10) < 0.05, `{c1 - c0}`)
T.check("os.time follows the fake clock", t1 - t0 >= 9 and t1 - t0 <= 11, `{t1 - t0}`)
local slept = H:run(function()
	return Clock.Sleep(2.5)
end)
T.check("task.wait(2.5) waits 2.5 fake seconds", slept >= 2.5 and slept < 2.6, `{slept}`)

T.section("runtime errors are reported")
w = H:warnings("failed")
T.check("error in :Start -> '[Server] ... :Start failed' warning", hasWarn("ZZBrokenStart:Start failed"))
T.check("typo in a child name is an error", hasWarn("TankTapp is not a valid member"))
local delayed = false
for _, e in H:errors() do
	if string.find(e.message, "delayed boom") then
		delayed = true
	end
end
T.check("error in a task.delay thread is recorded", delayed)

T.section("remote misuse")
local ok, err = H:run(function()
	return Clock.ClientFire()
end)
T.check("FireClient(nil) errors like Roblox", ok == false and string.find(tostring(err), "Player") ~= nil, tostring(err))

T.section("instances")
local attrOk = pcall(function()
	H.game.Workspace:SetAttribute("Bad", {})
end)
T.check("SetAttribute with a table errors like Roblox", attrOk == false)
local newOk = pcall(function()
	Harness.Inst.new("NotAClass")
end)
T.check("Instance.new with an unknown class errors", newOk == false)

T.finish()
