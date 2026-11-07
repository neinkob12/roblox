--!strict
-- Server entry point. Loads every ModuleScript in Services/ and World/.
-- Each module may define :Init() (sync setup, no yielding on other services)
-- and :Start() (runs after ALL Init calls; may yield, connect events, start loops).
-- Order: World first (builds the map), then Services alphabetically, DataService first.

local ServerScriptService = game:GetService("ServerScriptService")
local root = ServerScriptService:WaitForChild("Server")

local modules: { { name: string, mod: any } } = {}

local function collect(folder: Instance?)
	if not folder then
		return
	end
	local children = folder:GetChildren()
	table.sort(children, function(a, b)
		if a.Name == "DataService" then
			return true
		elseif b.Name == "DataService" then
			return false
		end
		return a.Name < b.Name
	end)
	for _, child in children do
		if child:IsA("ModuleScript") then
			local ok, mod = pcall(require, child)
			if ok then
				table.insert(modules, { name = child.Name, mod = mod })
			else
				warn(`[Server] failed to load {child:GetFullName()}: {mod}`)
			end
		end
	end
end

collect(root:FindFirstChild("World"))
collect(root:FindFirstChild("Services"))

for _, m in modules do
	if type(m.mod) == "table" and type(m.mod.Init) == "function" then
		local ok, err = pcall(m.mod.Init, m.mod)
		if not ok then
			warn(`[Server] {m.name}:Init failed: {err}`)
		end
	end
end
for _, m in modules do
	if type(m.mod) == "table" and type(m.mod.Start) == "function" then
		task.spawn(function()
			local ok, err = pcall(m.mod.Start, m.mod)
			if not ok then
				warn(`[Server] {m.name}:Start failed: {err}`)
			end
		end)
	end
end
print(`[Server] started {#modules} modules`)
