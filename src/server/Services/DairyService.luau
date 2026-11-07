--!strict
-- The Dairy: milk price board, milk truck, deposit pad (can -> queue), selling, cash pad.
-- Owner: A3.
--
--   Capacity.SellPerSecond(player, data) -> number
--   DairyService:Deposit(player) -> number      (milk deposited; used by DepositPad and Auto Sell)
--
-- Workspace attributes set here: MilkPrice, MilkPriceNextAt, TruckActive, TruckLeavesAt, TruckNextAt.
-- Player attribute set here: SellPerSecond (formula in shared/Capacity).
--
-- The price is LOCKED at deposit time: data.dairyQueue holds milk VALUE (milk * price incl. truck),
-- not raw milk. The queue drains at SellPerSecond value units/sec, times Multipliers.Cash, into
-- data.dairyCash. stats.milkSold counts raw milk at deposit time.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Safe = require(ReplicatedStorage.Shared.Safe)
local Format = require(ReplicatedStorage.Shared.Format)
local Multipliers = require(ReplicatedStorage.Shared.Multipliers)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local DataService = require(script.Parent.DataService)
local Notify = require(script.Parent.Parent.Util.Notify)
local Debounce = require(script.Parent.Parent.Util.Debounce)
local Pads = require(script.Parent.Parent.Util.Pads)
local Capacity = require(ReplicatedStorage.Shared.Capacity)

local DairyService = {}

local rng = Random.new()

local dairy: Instance? = nil
local truckModel: Model? = nil

local COLOR_UP = Color3.fromRGB(80, 220, 90)
local COLOR_DOWN = Color3.fromRGB(235, 70, 60)
local COLOR_FLAT = Color3.fromRGB(255, 255, 255)

----------------------------------------------------------------------------- selling

function DairyService:Deposit(player: Player): number
	local data = DataService:Get(player)
	if not data then
		return 0
	end
	local milk = data.canMilk or 0
	if milk <= 0 then
		return 0
	end
	local value = milk * Multipliers.MilkPrice()
	data.canMilk = 0
	data.dairyQueue = (data.dairyQueue or 0) + value
	data.stats.milkSold = (data.stats.milkSold or 0) + milk
	DataService:Replicate(player, "canMilk")
	DataService:Replicate(player, "dairyQueue")
	DataService:Replicate(player, "stats")
	return milk
end

local function sellTick(dt: number)
	for _, player in Players:GetPlayers() do
		local data = DataService:Get(player)
		if data then
			local rate = Capacity.SellPerSecond(player, data)
			player:SetAttribute("SellPerSecond", rate)
			local queue = data.dairyQueue or 0
			if queue > 0 then
				local sold = math.min(queue, rate * dt)
				-- drop float dust so the queue reaches exactly 0
				local remaining = queue - sold
				if remaining < 1e-6 then
					sold = queue
					remaining = 0
				end
				data.dairyQueue = remaining
				data.dairyCash = (data.dairyCash or 0) + sold * Multipliers.Cash(player, data)
				DataService:Replicate(player, "dairyQueue")
				DataService:Replicate(player, "dairyCash")
			end
		end
	end
end

local function onDeposit(player: Player)
	local price = Multipliers.MilkPrice()
	local milk = DairyService:Deposit(player)
	if milk > 0 then
		Notify.To(player, `Sold {Format.Number(milk)} milk at {string.format("%.2f", price)}x!`, "success")
	else
		Notify.To(player, "Your can is empty! Fill it at your tank tap", "info")
	end
end

local function onCollect(player: Player)
	local data = DataService:Get(player)
	if not data then
		return
	end
	local cash = data.dairyCash or 0
	if cash <= 0 then
		if (data.dairyQueue or 0) > 0 then
			Notify.To(player, "Still selling, come back in a moment!", "info")
		end
		return
	end
	data.dairyCash = 0
	DataService:Replicate(player, "dairyCash")
	DataService:AddCash(player, cash)
	Notify.To(player, `+{Format.Cash(cash)}`, "success")
end

----------------------------------------------------------------------------- price board

local function updateBoard()
	local board = dairy and dairy:FindFirstChild("PriceBoard")
	local gui = board and board:FindFirstChild("Gui")
	local label = gui and gui:FindFirstChild("Price")
	if not label or not label:IsA("TextLabel") then
		return
	end
	local price = Multipliers.MilkPrice()
	local text = `Milk Price: {string.format("%.2f", price)}x`
	if workspace:GetAttribute("TruckActive") then
		text ..= `\nMILK TRUCK! (x{Economy.Truck.PriceBonus})`
	end
	local nextAt = workspace:GetAttribute("MilkPriceNextAt")
	if typeof(nextAt) == "number" then
		text ..= `\nNew price in {math.max(0, nextAt - os.time())}s`
	end
	label.Text = text
	if price > 1.0001 then
		label.TextColor3 = COLOR_UP
	elseif price < 0.9999 then
		label.TextColor3 = COLOR_DOWN
	else
		label.TextColor3 = COLOR_FLAT
	end
end

local function rollPrice()
	local cfg = Economy.MilkPrice
	local p = cfg.Min + rng:NextNumber() * (cfg.Max - cfg.Min)
	p = math.floor(p * 100 + 0.5) / 100
	workspace:SetAttribute("MilkPrice", p)
	workspace:SetAttribute("MilkPriceNextAt", os.time() + cfg.IntervalSeconds)
end

----------------------------------------------------------------------------- truck

local function part(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

-- Blocky milk truck built from Parts. Pivot = center of the chassis bottom. Faces -Z (LookVector).
local function buildTruck(): (Model, Part)
	local model = Instance.new("Model")
	model.Name = "MilkTruck"
	local root = part({
		Name = "Root",
		Size = Vector3.new(7, 1, 18),
		Color = Color3.fromRGB(60, 60, 70),
		Anchored = true,
	}, model)
	local function attach(p: BasePart, offset: CFrame)
		p.CFrame = root.CFrame * offset
		local w = Instance.new("WeldConstraint")
		w.Part0 = root
		w.Part1 = p
		w.Parent = p
	end
	-- cab (front = -Z)
	attach(
		part({ Name = "Cab", Size = Vector3.new(7, 5, 5), Color = Color3.fromRGB(70, 130, 220) }, model),
		CFrame.new(0, 3.5, -6.5)
	)
	attach(
		part({
			Name = "Windshield",
			Size = Vector3.new(6, 2, 0.2),
			Color = Color3.fromRGB(170, 220, 255),
			Material = Enum.Material.Glass,
			Transparency = 0.3,
		}, model),
		CFrame.new(0, 4.5, -9.05)
	)
	-- milk tank (cylinder lies along X by default, rotate so it runs along Z)
	attach(
		part({
			Name = "MilkTank",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(12, 6, 6),
			Color = Color3.fromRGB(245, 245, 245),
		}, model),
		CFrame.new(0, 4, 2.5) * CFrame.Angles(0, math.rad(90), 0)
	)
	-- black spots on the tank (it's a cow truck)
	for i, off in
		{ Vector3.new(2.9, 4.5, 0), Vector3.new(-2.9, 3.6, 4), Vector3.new(2.9, 3.4, 6), Vector3.new(-2.9, 4.6, -1) }
	do
		attach(
			part({
				Name = `Spot{i}`,
				Size = Vector3.new(0.3, 1.6, 2.2),
				Color = Color3.fromRGB(30, 30, 30),
			}, model),
			CFrame.new(off)
		)
	end
	-- wheels
	for _, z in { -6, 6 } do
		for _, x in { -3.6, 3.6 } do
			attach(
				part({
					Name = "Wheel",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(1, 3, 3),
					Color = Color3.fromRGB(25, 25, 25),
				}, model),
				CFrame.new(x, 0, z)
			)
		end
	end
	-- "MILK" sign on both sides
	for _, face in { Enum.NormalId.Left, Enum.NormalId.Right } do
		local sign = Instance.new("SurfaceGui")
		sign.Face = face
		sign.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sign.PixelsPerStud = 20
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.Font = Enum.Font.FredokaOne
		t.TextScaled = true
		t.Text = "MILK"
		t.TextColor3 = Color3.fromRGB(70, 130, 220)
		t.Parent = sign
		sign.Parent = model:FindFirstChild("Cab")
	end
	model.PrimaryPart = root
	return model, root
end

local function truckStop(): BasePart?
	local stop = dairy and dairy:FindFirstChild("TruckStop")
	if stop and stop:IsA("BasePart") then
		return stop
	end
	return nil
end

local function truckArrive()
	local stop = truckStop()
	if not stop then
		return
	end
	if truckModel then
		truckModel:Destroy()
	end
	local model, root = buildTruck()
	-- wheel centers = root center and wheel radius is 1.5, so lift the root 1.5 above the stop's top
	local parked = stop.CFrame * CFrame.new(0, stop.Size.Y / 2 + 1.5, 0)
	local start = parked * CFrame.new(0, 0, Economy.Truck.DriveDistance) -- comes from behind, drives forward (-Z)
	model:PivotTo(start) -- moves every part; setting root.CFrame alone leaves unparented welded parts behind
	model.Parent = workspace
	truckModel = model
	TweenService:Create(
		root,
		TweenInfo.new(Economy.Truck.DriveSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = parked }
	):Play()
end

local function truckLeave()
	local model = truckModel
	truckModel = nil
	if not model then
		return
	end
	local root = model.PrimaryPart
	if not root then
		model:Destroy()
		return
	end
	local away = root.CFrame * CFrame.new(0, 0, -Economy.Truck.DriveDistance)
	local tween = TweenService:Create(
		root,
		TweenInfo.new(Economy.Truck.DriveSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ CFrame = away }
	)
	tween.Completed:Connect(function()
		model:Destroy()
	end)
	tween:Play()
end

local function truckTick()
	local now = os.time()
	if workspace:GetAttribute("TruckActive") then
		local leavesAt = workspace:GetAttribute("TruckLeavesAt")
		if typeof(leavesAt) ~= "number" or now >= leavesAt then
			workspace:SetAttribute("TruckActive", false)
			workspace:SetAttribute("TruckNextAt", now + Economy.Truck.EverySeconds)
			truckLeave()
			Notify.All("The milk truck left. See you next time!", "info")
		end
	else
		local nextAt = workspace:GetAttribute("TruckNextAt")
		if typeof(nextAt) ~= "number" then
			workspace:SetAttribute("TruckNextAt", now + Economy.Truck.EverySeconds)
		elseif now >= nextAt then
			workspace:SetAttribute("TruckActive", true)
			workspace:SetAttribute("TruckLeavesAt", now + Economy.Truck.StaysSeconds)
			truckArrive()
			Notify.All(
				`The MILK TRUCK is here! x{Economy.Truck.PriceBonus} milk price for {Economy.Truck.StaysSeconds}s`,
				"rare"
			)
		end
	end
end

----------------------------------------------------------------------------- lifecycle

function DairyService:Init()
	rollPrice()
	workspace:SetAttribute("TruckActive", false)
	workspace:SetAttribute("TruckNextAt", os.time() + Economy.Truck.EverySeconds)
	workspace:SetAttribute("TruckLeavesAt", 0)
end

function DairyService:Start()
	dairy = workspace:FindFirstChild("Dairy") or workspace:WaitForChild("Dairy", 30)
	if dairy then
		local deposit = dairy:FindFirstChild("DepositPad") or dairy:WaitForChild("DepositPad", 10)
		if deposit and deposit:IsA("BasePart") then
			Pads.BindWorldPad(deposit, "DepositPad", onDeposit)
		else
			warn("[DairyService] Dairy.DepositPad not found")
		end
		local cashPad = dairy:FindFirstChild("CashPad") or dairy:WaitForChild("CashPad", 10)
		if cashPad and cashPad:IsA("BasePart") then
			Pads.BindWorldPad(cashPad, "CashPad", onCollect)
		else
			warn("[DairyService] Dairy.CashPad not found")
		end
	else
		warn("[DairyService] workspace.Dairy not found (A1 builds it)")
	end

	-- price + truck + board, once per second
	task.spawn(function()
		while true do
			-- each step is protected: one error must never stop prices, the truck or Auto Sell server-wide
			Safe.Run("DairyService price roll", function()
				local nextAt = workspace:GetAttribute("MilkPriceNextAt")
				if typeof(nextAt) ~= "number" or os.time() >= nextAt then
					rollPrice()
				end
			end)
			Safe.Run("DairyService truck", truckTick)
			Safe.Run("DairyService board", updateBoard)
			-- Auto Sell gamepass: deposit the can remotely
			for _, player in Players:GetPlayers() do
				if player:GetAttribute("Pass_AutoSell") then
					if Debounce.Try(player, "autoSell", Economy.Dairy.AutoSellSeconds) then
						Safe.Run("DairyService auto sell", DairyService.Deposit, DairyService, player)
					end
				end
			end
			task.wait(1)
		end
	end)

	-- selling loop
	local last = os.clock()
	while true do
		task.wait(Economy.Dairy.TickSeconds)
		local now = os.clock()
		local dt = math.min(now - last, Economy.Dairy.TickSeconds * 4)
		last = now
		Safe.Run("DairyService sell tick", sellTick, dt)
	end
end

return DairyService
