--!strict
-- B1: Quests panel. Reads data.quests (shape owned by B2 QuestService) and fires
-- RequestClaimQuest(questId).
--
-- Expected shape (proposed to B2, see PR #17). Reading is tolerant so small differences work:
--   data.quests = {
--     [questId] = {
--       text = "Merge 5 cows",          -- or name / description; falls back to Config/Quests
--       progress = 2,                    -- number
--       goal = 5,                        -- or target / amount
--       claimed = false,
--       reward = { cash = 500 } | { crates = 1 } | { boost = "cash", mult = 2, seconds = 300 } | "text",
--       rewardText = "$500",             -- optional, wins over reward
--     },
--   }
--   An optional `data.quests.active` sub-table (list or map) is also accepted.
--   Optional `data.quests.resetsAt` (os.time) shows a "New quests in mm:ss" timer.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Format = require(ReplicatedStorage.Shared.Format)
local Theme = require(script.Parent.Parent.Lib.Theme)
local C = require(script.Parent.Parent.Lib.UiKit)
local Panels = require(script.Parent.Components)
local Menu = require(script.Parent.Menu)
local DataController = require(script.Parent.Parent.Controllers.DataController)

local Colors = Theme.Colors

local QuestsPanel = {}

local list: ScrollingFrame
local emptyText: TextLabel
local timerText: TextLabel

-- Optional Config/Quests (B2) for names when the data entry only has an id.
local questConfig: any = nil
do
	local cfg = ReplicatedStorage.Shared.Config:FindFirstChild("Quests")
	if cfg and cfg:IsA("ModuleScript") then
		local ok, mod = pcall(require, cfg)
		if ok then
			questConfig = mod
		end
	end
end

type Quest = { id: string, text: string, progress: number, goal: number, claimed: boolean, reward: string }

local function num(v: any): number?
	return if typeof(v) == "number" then v else nil
end

local function rewardText(q: any): string
	if typeof(q.rewardText) == "string" then
		return q.rewardText
	end
	local r = q.reward
	if typeof(r) == "string" then
		return r
	elseif typeof(r) == "number" then
		return Format.Cash(r)
	elseif typeof(r) == "table" then
		if typeof(r.text) == "string" then
			return r.text
		end
		-- B2 QuestService shape: { kind = "cash" | "crates" | "boost", amount, boostKind, mult, seconds }
		if typeof(r.kind) == "string" then
			if r.kind == "cash" and num(r.amount) then
				return Format.Cash(r.amount)
			elseif r.kind == "crates" and num(r.amount) then
				return `{r.amount} crate{if r.amount == 1 then "" else "s"}`
			elseif r.kind == "boost" then
				local kind = if r.boostKind == "production" then "Milk" else "Cash"
				local mult = num(r.mult) or 2
				local secs = num(r.seconds)
				return `x{Format.Number(mult)} {kind}{if secs then " " .. Format.Time(secs) else ""}`
			end
		end
		local parts = {}
		if num(r.cash) then
			table.insert(parts, Format.Cash(r.cash))
		end
		if num(r.crates) then
			table.insert(parts, `{r.crates} crate{if r.crates == 1 then "" else "s"}`)
		end
		if r.boost ~= nil then
			local kind = if r.boost == "production" or r.kind == "production" then "Milk" else "Cash"
			local mult = num(r.mult) or 2
			local secs = num(r.seconds)
			table.insert(parts, `x{Format.Number(mult)} {kind}{if secs then " " .. Format.Time(secs) else ""}`)
		end
		return table.concat(parts, " + ")
	end
	return ""
end

local function configName(id: string): string?
	if not questConfig then
		return nil
	end
	local byId = questConfig.ById
	local def = if typeof(byId) == "table" then byId[id] else nil
	if typeof(def) == "table" then
		return def.text or def.name or def.description
	end
	return nil
end

local function collect(): { Quest }
	local data = DataController:Get()
	local out: { Quest } = {}
	if not data or typeof(data.quests) ~= "table" then
		return out
	end
	local source = data.quests
	if typeof(source.active) == "table" then
		source = source.active
	end
	for key, q in source do
		if typeof(q) == "table" then
			local id = if typeof(q.id) == "string" then q.id else tostring(key)
			local goal = num(q.goal) or num(q.target) or num(q.amount)
			if goal then
				local text = q.text or q.name or q.description or configName(id) or id
				table.insert(out, {
					id = id,
					text = tostring(text),
					progress = num(q.progress) or 0,
					goal = goal,
					claimed = q.claimed == true,
					reward = rewardText(q),
				})
			end
		end
	end
	table.sort(out, function(a, b)
		local na = tonumber(string.match(a.id, "%d+$"))
		local nb = tonumber(string.match(b.id, "%d+$"))
		if na and nb then
			return na < nb
		end
		return a.id < b.id
	end)
	return out
end

local function refresh()
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local quests = collect()
	local claimable = 0
	for i, q in quests do
		local done = q.progress >= q.goal
		if done and not q.claimed then
			claimable += 1
		end
		local card = C.Card(list, 76, i)
		C.Label(card, {
			name = "Text",
			text = q.text,
			color = Colors.TextDark,
			size = UDim2.new(1, -170, 0, 26),
			position = UDim2.fromOffset(12, 6),
			align = Enum.TextXAlignment.Left,
			stroke = 0,
		})
		C.Label(card, {
			name = "Reward",
			text = if q.reward ~= "" then "Reward: " .. q.reward else "",
			color = Colors.PurpleDark,
			size = UDim2.new(1, -170, 0, 20),
			position = UDim2.fromOffset(12, 32),
			align = Enum.TextXAlignment.Left,
			stroke = 0,
		})
		local bar = Instance.new("Frame")
		bar.Name = "Bar"
		bar.BackgroundColor3 = Colors.PanelDark
		bar.Position = UDim2.fromOffset(12, 56)
		bar.Size = UDim2.new(1, -170, 0, 14)
		bar.Parent = card
		C.Corner(bar, 7)
		local fill = Instance.new("Frame")
		fill.BackgroundColor3 = if done then Colors.Green else Colors.Blue
		fill.Size = UDim2.fromScale(math.clamp(q.progress / math.max(q.goal, 1), 0, 1), 1)
		fill.Parent = bar
		C.Corner(fill, 7)
		C.Label(bar, {
			name = "Progress",
			text = `{Format.Number(math.min(q.progress, q.goal))} / {Format.Number(q.goal)}`,
			size = UDim2.fromScale(1, 1.2),
			position = UDim2.fromScale(0.5, 0.5),
			anchor = Vector2.new(0.5, 0.5),
			stroke = 2,
		})

		local claim, caption = C.Button(card, {
			name = "Claim",
			text = "CLAIM",
			color = Colors.Green,
			size = UDim2.fromOffset(140, Theme.MinTouch),
			position = UDim2.new(1, -10, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			onClick = function()
				Net.Event("RequestClaimQuest"):FireServer(q.id)
			end,
		})
		if q.claimed then
			caption.Text = "DONE ✔"
			C.SetButtonEnabled(claim, false)
		elseif not done then
			caption.Text = "IN PROGRESS"
			C.SetButtonEnabled(claim, false)
		end
	end
	emptyText.Visible = #quests == 0
	Menu.SetBadge("Quests", claimable)
end

local function updateTimer()
	local data = DataController:Get()
	local resetsAt = if data and typeof(data.quests) == "table" then num(data.quests.resetsAt) else nil
	if resetsAt and resetsAt > C.Now() then
		timerText.Text = `New quests in {Format.Time(resetsAt - C.Now())}`
	else
		timerText.Text = ""
	end
end

function QuestsPanel:Init()
	local _, body = Panels.Panel("Quests", "QUESTS", Vector2.new(560, 360), Colors.Blue)
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 1, -26)
	holder.Parent = body
	list = C.ScrollList(holder, 8)
	emptyText = C.Label(body, {
		name = "Empty",
		text = "No quests yet. Check back soon!",
		color = Colors.GreyDark,
		size = UDim2.new(1, 0, 0, 30),
		position = UDim2.fromScale(0.5, 0.4),
		anchor = Vector2.new(0.5, 0.5),
		stroke = 0,
	})
	timerText = C.Label(body, {
		name = "Timer",
		text = "",
		color = Colors.GreyDark,
		size = UDim2.new(1, 0, 0, 22),
		position = UDim2.fromScale(0, 1),
		anchor = Vector2.new(0, 1),
		stroke = 0,
	})
end

function QuestsPanel:Start()
	DataController:OnChanged("quests", refresh)
	Panels.OnPanelOpened("Quests", refresh)
	refresh()
	while true do
		updateTimer()
		task.wait(1)
	end
end

return QuestsPanel
