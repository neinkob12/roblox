--!strict
-- Client mirror of the local player's data. READ ONLY: the server is the source of truth.
--
--   DataController:Get()               -> data | nil
--   DataController:WaitForData()       -> data
--   DataController:OnChanged(key, fn)  -> connection   fn(newValue) on every change of that key
--   DataController.Changed:Connect(fn(key, value))      any key

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Signal)

local DataController = {}
DataController.Changed = Signal.new()
DataController.Loaded = Signal.new()

local data: any = nil

function DataController:Init()
	Net.Event("DataInit").OnClientEvent:Connect(function(snapshot)
		data = snapshot
		DataController.Loaded:Fire(data)
		for key, value in data do
			DataController.Changed:Fire(key, value)
		end
	end)
	Net.Event("DataChanged").OnClientEvent:Connect(function(key: string, value: any)
		if data then
			data[key] = value
			DataController.Changed:Fire(key, value)
		end
	end)
end

function DataController:Start()
	if data then
		return
	end
	local snapshot = Net.Function("GetData"):InvokeServer()
	if snapshot and not data then
		data = snapshot
		DataController.Loaded:Fire(data)
		for key, value in data do
			DataController.Changed:Fire(key, value)
		end
	end
end

function DataController:Get(): any
	return data
end

function DataController:WaitForData(): any
	while not data do
		task.wait()
	end
	return data
end

function DataController:OnChanged(key: string, fn: (any) -> ())
	if data and data[key] ~= nil then
		task.spawn(fn, data[key])
	end
	return DataController.Changed:Connect(function(k, v)
		if k == key then
			fn(v)
		end
	end)
end

return DataController
