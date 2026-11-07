--!strict
-- Client entry point. Loads every ModuleScript in Controllers/ and UI/ with the same
-- :Init() / :Start() lifecycle as the server. DataController always loads first.

local root = script

local modules: { { name: string, mod: any } } = {}

local function collect(folder: Instance?)
	if not folder then
		return
	end
	local children = folder:GetChildren()
	table.sort(children, function(a, b)
		if a.Name == "DataController" then
			return true
		elseif b.Name == "DataController" then
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
				warn(`[Client] failed to load {child:GetFullName()}: {mod}`)
			end
		end
	end
end

collect(root:WaitForChild("Controllers"))
collect(root:FindFirstChild("UI"))

for _, m in modules do
	if type(m.mod) == "table" and type(m.mod.Init) == "function" then
		local ok, err = pcall(m.mod.Init, m.mod)
		if not ok then
			warn(`[Client] {m.name}:Init failed: {err}`)
		end
	end
end
for _, m in modules do
	if type(m.mod) == "table" and type(m.mod.Start) == "function" then
		task.spawn(function()
			local ok, err = pcall(m.mod.Start, m.mod)
			if not ok then
				warn(`[Client] {m.name}:Start failed: {err}`)
			end
		end)
	end
end
