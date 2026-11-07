--!strict
-- B2 LeaderboardService: global top 10 for total cash earned and rebirths.
--
-- OrderedDataStores:
--   "LB_TotalCash_v1"  key = tostring(UserId), value = encoded totalCashEarned (see encodeCash)
--   "LB_Rebirths_v1"   key = tostring(UserId), value = rebirths (integer)
-- Each player is written at most once per UpdateSeconds (only if the value changed) and once
-- more when they leave. Every call is pcall'd and checks the DataStore request budget first.
--
-- Rendering: workspace.Dairy.LeaderboardCash / LeaderboardRebirths > SurfaceGui "Gui".
-- We add a Frame "Board" with a title and 10 rows. If DataStores are unavailable (Studio
-- without API access, unpublished place) the boards show the players on THIS server instead
-- and we warn once, no error spam. Studio never WRITES unless WRITE_IN_STUDIO = true.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)
local DataService = require(script.Parent.DataService)

local LeaderboardService = {}

local UPDATE_SECONDS = 60
local TOP_N = 10
-- totalCashEarned can exceed 2^63, so we store a log: floor(log10(cash + 1) * 1e13).
-- Max ~3.1e15 (fits easily), ordering is preserved, decoding keeps ~13 significant digits.
local CASH_SCALE = 1e13
-- Studio playtests use mock player data; keep it off the live global boards unless you flip this.
local WRITE_IN_STUDIO = false
local IS_STUDIO = RunService:IsStudio()

type Board = {
	partName: string,
	title: string,
	storeName: string,
	color: Color3,
	read: (data: any) -> number, -- raw value from player data
	encode: (n: number) -> number,
	decode: (n: number) -> number,
	format: (n: number) -> string,
	store: OrderedDataStore?,
	written: { [number]: number }, -- userId -> last encoded value written
}

local function encodeCash(n: number): number
	if n ~= n or n <= 0 then
		return 0
	end
	return math.floor(math.log10(n + 1) * CASH_SCALE)
end

local function decodeCash(v: number): number
	return 10 ^ (v / CASH_SCALE) - 1
end

local boards: { Board } = {
	{
		partName = "LeaderboardCash",
		title = "TOP MILK MONEY",
		storeName = "LB_TotalCash_v1",
		color = Color3.fromRGB(255, 214, 64),
		read = function(data)
			return data.totalCashEarned or 0
		end,
		encode = encodeCash,
		decode = decodeCash,
		format = Format.Cash,
		store = nil,
		written = {},
	},
	{
		partName = "LeaderboardRebirths",
		title = "TOP REBIRTHS",
		storeName = "LB_Rebirths_v1",
		color = Color3.fromRGB(190, 120, 255),
		read = function(data)
			return data.rebirths or 0
		end,
		encode = function(n)
			return math.max(0, math.floor(n))
		end,
		decode = function(n)
			return n
		end,
		format = Format.Number,
		store = nil,
		written = {},
	},
}

local available = true
local warned = false
local function fail(what: string, err: any)
	if not warned then
		warned = true
		warn(`[LeaderboardService] DataStores unavailable ({what}): {err}. Showing this server only.`)
	end
end

local function hasBudget(kind: Enum.DataStoreRequestType): boolean
	local ok, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(kind)
	end)
	return ok and budget > 0
end

-- names --------------------------------------------------------------------

local names: { [number]: string } = {}
local function nameOf(userId: number): string
	local p = Players:GetPlayerByUserId(userId)
	if p then
		names[userId] = p.DisplayName
		return p.DisplayName
	end
	local cached = names[userId]
	if cached then
		return cached
	end
	if userId <= 0 then
		return "Player" -- Studio test accounts
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and typeof(name) == "string" then name else "???"
	names[userId] = result
	return result
end

-- rendering ----------------------------------------------------------------

type Row = { name: string, value: string }

local function makeLabel(parent: Instance, name: string, text: string, color: Color3, bold: boolean): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = color
	l.TextScaled = true
	l.Font = if bold then Enum.Font.FredokaOne else Enum.Font.GothamBold
	l.TextStrokeTransparency = 0.4
	l.Parent = parent
	return l
end

local function getGui(board: Board): SurfaceGui?
	local dairy = workspace:FindFirstChild("Dairy")
	local part = dairy and dairy:FindFirstChild(board.partName)
	local gui = part and part:FindFirstChild("Gui")
	if gui and gui:IsA("SurfaceGui") then
		return gui
	end
	return nil
end

local function render(board: Board, rows: { Row }, subtitle: string)
	local gui = getGui(board)
	if not gui then
		return
	end
	local old = gui:FindFirstChild("Board")
	if old then
		old:Destroy()
	end
	local frame = Instance.new("Frame")
	frame.Name = "Board"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(30, 26, 48)
	frame.BorderSizePixel = 0

	local title = makeLabel(frame, "Title", board.title, board.color, true)
	title.Size = UDim2.fromScale(0.92, 0.1)
	title.Position = UDim2.fromScale(0.04, 0.015)
	local sub = makeLabel(frame, "Subtitle", subtitle, Color3.fromRGB(200, 200, 220), false)
	sub.Size = UDim2.fromScale(0.92, 0.04)
	sub.Position = UDim2.fromScale(0.04, 0.115)

	local top = 0.17
	local rowH = (1 - top - 0.02) / TOP_N
	for i = 1, TOP_N do
		local row = rows[i]
		local y = top + (i - 1) * rowH
		local bg = Instance.new("Frame")
		bg.Name = "Row" .. i
		bg.Size = UDim2.fromScale(0.94, rowH * 0.9)
		bg.Position = UDim2.fromScale(0.03, y)
		bg.BackgroundColor3 = if i % 2 == 0 then Color3.fromRGB(48, 42, 72) else Color3.fromRGB(58, 50, 88)
		bg.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.2, 0)
		corner.Parent = bg
		local rankColor = if i == 1
			then Color3.fromRGB(255, 214, 64)
			elseif i == 2 then Color3.fromRGB(210, 220, 230)
			elseif i == 3 then Color3.fromRGB(230, 150, 90)
			else Color3.fromRGB(255, 255, 255)
		local rank = makeLabel(bg, "Rank", `#{i}`, rankColor, true)
		rank.Size = UDim2.fromScale(0.14, 0.8)
		rank.Position = UDim2.fromScale(0.02, 0.1)
		local name = makeLabel(bg, "Name", if row then row.name else "-", Color3.fromRGB(255, 255, 255), false)
		name.Size = UDim2.fromScale(0.5, 0.7)
		name.Position = UDim2.fromScale(0.17, 0.15)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local value = makeLabel(bg, "Value", if row then row.value else "", board.color, true)
		value.Size = UDim2.fromScale(0.3, 0.7)
		value.Position = UDim2.fromScale(0.68, 0.15)
		value.TextXAlignment = Enum.TextXAlignment.Right
		bg.Parent = frame
	end
	frame.Parent = gui
end

-- fallback: rank the players on this server from live data
local function renderLocal(board: Board)
	local entries = {}
	for _, p in Players:GetPlayers() do
		local data = DataService:Get(p)
		if data then
			table.insert(entries, { name = p.DisplayName, raw = board.read(data) })
		end
	end
	table.sort(entries, function(a, b)
		return a.raw > b.raw
	end)
	local rows = {}
	for i = 1, math.min(TOP_N, #entries) do
		rows[i] = { name = entries[i].name, value = board.format(entries[i].raw) }
	end
	render(board, rows, "This server")
end

-- datastore ----------------------------------------------------------------

local function write(board: Board, player: Player, liveData: any?)
	local store = board.store
	if not store or not available or (IS_STUDIO and not WRITE_IN_STUDIO) then
		return
	end
	local data = liveData or DataService:Get(player)
	if not data then
		return
	end
	local value = board.encode(board.read(data))
	local userId = player.UserId
	if userId <= 0 or board.written[userId] == value then
		return
	end
	if not hasBudget(Enum.DataStoreRequestType.SetIncrementSortedAsync) then
		return -- try again next cycle
	end
	local ok, err = pcall(function()
		store:SetAsync(tostring(userId), value)
	end)
	if ok then
		board.written[userId] = value
	else
		fail("SetAsync", err)
	end
end

local function refresh(board: Board)
	local store = board.store
	if not store or not available then
		renderLocal(board)
		return
	end
	if not hasBudget(Enum.DataStoreRequestType.GetSortedAsync) then
		return -- keep showing the old board
	end
	local ok, result = pcall(function()
		local pages = store:GetSortedAsync(false, TOP_N)
		return pages:GetCurrentPage()
	end)
	if not ok then
		fail("GetSortedAsync", result)
		available = false
		renderLocal(board)
		return
	end
	local rows = {}
	for i, entry in result do
		local userId = tonumber(entry.key) or 0
		rows[i] = { name = nameOf(userId), value = board.format(board.decode(entry.value)) }
	end
	render(board, rows, "All servers")
end

function LeaderboardService:Init()
	for _, board in boards do
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(board.storeName)
		end)
		if ok then
			board.store = store
		else
			fail("GetOrderedDataStore", store)
			available = false
		end
	end
end

function LeaderboardService:Start()
	-- final write on leave (PlayerSaving fires while the data is still available)
	DataService.PlayerSaving:Connect(function(player: Player, data: any)
		local userId = player.UserId
		task.spawn(function()
			for _, board in boards do
				pcall(write, board, player, data)
				board.written[userId] = nil
			end
		end)
	end)

	-- wait for A1's map so the boards exist (MapBuilder builds in Init, but be safe)
	workspace:WaitForChild("Dairy", 30)
	task.wait(5) -- let the first players load before the first refresh

	while true do
		for _, board in boards do
			local ok, err = pcall(refresh, board)
			if not ok then
				warn(`[LeaderboardService] refresh failed: {err}`)
			end
		end
		-- spread writes over the cycle instead of bursting
		local players = Players:GetPlayers()
		local gap = if #players > 0 then UPDATE_SECONDS / #players else UPDATE_SECONDS
		if #players == 0 then
			task.wait(UPDATE_SECONDS)
		end
		for _, player in players do
			if player.Parent == Players then
				for _, board in boards do
					local ok, err = pcall(write, board, player)
					if not ok then
						warn(`[LeaderboardService] write failed: {err}`)
					end
				end
			end
			task.wait(gap)
		end
	end
end

return LeaderboardService
