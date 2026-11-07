--!nocheck
local Harness = require("../mock/Harness")
local H = Harness.new({ root = "." })
H:boot()
H:advance(2)
local a = H:addPlayer("Alice")
H:advance(5)
print("errors:", #H:errors())
print("PlotId", a:GetAttribute("PlotId"))
local DS = H:serverModule("Services.DataService")
local data = DS:Get(a)
print("cash", data and data.cash)
print("gui children:")
for _, g in a.PlayerGui:GetChildren() do print("  ", g.Name, g.ClassName) end
local ctx = Harness.Services.state.clients[a]
local n = 0
for m, e in ctx.modules do n += 1 end
print("client modules loaded", n)
for k, v in Harness.Inst.unknownReads do print("unknown read", k, v) end
print("char", a.Character, a.Character and a.Character:GetPivot())
