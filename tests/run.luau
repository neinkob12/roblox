--!nocheck
-- Runs every scenario in tests/scenarios in its own Lune process (fresh mock state each).
-- Usage (from the repo root):  lune run tests/run.luau [name-filter]

local fs = require("@lune/fs")
local process = require("@lune/process")

local filter = process.args[1]
local files = {}
for _, f in fs.readDir("tests/scenarios") do
	if string.sub(f, -5) == ".luau" and (filter == nil or string.find(f, filter, 1, true)) then
		table.insert(files, f)
	end
end
table.sort(files)

local failed = {}
for _, f in files do
	print(`\n######## {f}`)
	local res = process.exec("lune", { "run", "tests/scenarios/" .. f }, { stdio = "inherit" })
	if not res.ok then
		table.insert(failed, f)
	end
end
print(`\n######## {#files - #failed}/{#files} scenarios passed`)
if #failed > 0 then
	print("failed: " .. table.concat(failed, ", "))
	process.exit(1)
end
