--!strict
-- C6: One shared queue for full-screen reveals (crate spin, "NEW COW!" discovery, ...), so two
-- overlays never play at the same time. Not auto-loaded (plain module, no Init/Start).
--
--   RevealQueue.Push(fn, priority?)   fn runs (and may yield) until its overlay is gone.
--                                     Lower priority runs first among items still waiting
--                                     (equal priority keeps arrival order). Default 10.
--
-- Priorities used: 0 crate spin, 10 discovery reveal. A crate that gives a brand-new cow fires
-- CrateOpened and CowDiscovered in the same moment; the short START_DELAY lets both arrive so
-- the spin plays first and the "NEW COW!" reveal follows it instead of spoiling the result.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Safe = require(ReplicatedStorage.Shared.Safe)

local START_DELAY = 0.15
local GAP = 0.15

local RevealQueue = {}

type Item = { fn: () -> (), priority: number, seq: number }

local queue: { Item } = {}
local running = false
local seq = 0

local function takeNext(): Item?
	local best: number? = nil
	for i, item in queue do
		if best == nil then
			best = i
		else
			local b = queue[best]
			if item.priority < b.priority or (item.priority == b.priority and item.seq < b.seq) then
				best = i
			end
		end
	end
	if best == nil then
		return nil
	end
	return table.remove(queue, best)
end

local function pump()
	if running then
		return
	end
	running = true
	task.spawn(function()
		task.wait(START_DELAY)
		while true do
			local item = takeNext()
			if not item then
				break
			end
			Safe.Run("RevealQueue reveal", item.fn)
			task.wait(GAP)
		end
		running = false
	end)
end

function RevealQueue.Push(fn: () -> (), priority: number?)
	seq += 1
	table.insert(queue, { fn = fn, priority = priority or 10, seq = seq })
	pump()
end

function RevealQueue.IsBusy(): boolean
	return running
end

return RevealQueue
