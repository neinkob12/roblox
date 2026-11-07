--!strict
-- F2: the nests on the local player's own plot, plus the hatch reveal.
--   World: Plots.PlotN.Nest1..Nest4 (PlotBuilder): NestKey attribute, BillboardGui "Label" > "Text",
--          Attachment "EggAnchor", ProximityPrompt "Prompt".
--   Data:  data.nests { ["1"] = { egg, readyAt, luck } } (F1 EggService), data.rebirths.
--
--   locked   nest above Eggs.NestsFor(rebirths): dimmed, label "Rebirth N", prompt off
--   empty    label "Empty Nest", prompt "Open Egg Shop" (opens the EggShop panel)
--   waiting  egg model wobbling faster as hatch time nears, label "Dairy Egg\n4:12"
--   ready    "Ready!" glow, prompt "Hatch!" -> Net RequestHatch(nestKey)
--   When a ready egg leaves the nest the egg cracks open; PetHatched(uid, petId, variant) then
--   queues the full-screen reveal (Lib/RevealQueue): pet model, name, rarity color, boost text.
--   Prompts on other players' plots are turned off locally.
--
-- Public: NestController:ShowReveal(petId, variant) (admin/trailer/tests).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)
local Eggs = require(ReplicatedStorage.Shared.Config.Eggs)
local Pets = require(ReplicatedStorage.Shared.Config.Pets)
local Format = require(ReplicatedStorage.Shared.Format)
local Multipliers = require(ReplicatedStorage.Shared.Multipliers)
local PetModels = require(ReplicatedStorage.Shared.PetModels)
local Safe = require(ReplicatedStorage.Shared.Safe)
local C = require(script.Parent.Parent.Lib.UiKit)
local PetViewport = require(script.Parent.Parent.Lib.PetViewport)
local RevealQueue = require(script.Parent.Parent.Lib.RevealQueue)
local Panels = require(script.Parent.Parent.UI.Components)
local DataController = require(script.Parent.DataController)
local SoundController = require(script.Parent.SoundController)

local player = Players.LocalPlayer
local Colors = C.Colors

local LABEL_TICK = 0.25
local AUTO_CLOSE = 6
local CLOSE_UNLOCK = 0.8
local RAY_COUNT = 10

type NestView = {
	part: BasePart,
	key: string,
	egg: Model?,
	eggId: string?,
	glow: PointLight?,
	ready: boolean,
	dimmed: boolean,
}

local NestController = {}

local views: { [string]: NestView } = {}
local plotModel: Instance? = nil
local labelClock = 0

------------------------------------------------------------------------------ helpers

local function nestsData(): { [string]: any }
	local data = DataController:Get()
	local n = data and data.nests
	return if typeof(n) == "table" then n else {}
end

local function rebirths(): number
	local data = DataController:Get()
	local r = data and data.rebirths
	return if typeof(r) == "number" then r else 0
end

-- smallest rebirth count that unlocks nest i (nil = never)
local function rebirthFor(i: number): number?
	local best: number? = nil
	for _, row in Eggs.NestSlots do
		if row.nests >= i and (best == nil or row.rebirths < best) then
			best = row.rebirths
		end
	end
	return best
end

local function setLabel(part: BasePart, text: string, color: Color3?)
	local gui = part:FindFirstChild("Label")
	local t = gui and gui:FindFirstChild("Text")
	if t and t:IsA("TextLabel") then
		t.Text = text
		t.TextColor3 = color or Color3.new(1, 1, 1)
	end
end

local function prompt(part: BasePart): ProximityPrompt?
	local p = part:FindFirstChild("Prompt")
	return if p and p:IsA("ProximityPrompt") then p else nil
end

local function setDimmed(view: NestView, dim: boolean)
	if view.dimmed == dim then
		return
	end
	view.dimmed = dim
	local parts: { BasePart } = { view.part }
	for _, d in view.part:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	for _, p in parts do
		local base = p:GetAttribute("NestBaseColor")
		if typeof(base) ~= "Color3" then
			base = p.Color
			p:SetAttribute("NestBaseColor", base)
		end
		p.Color = if dim then (base :: Color3):Lerp(Color3.new(0.15, 0.15, 0.2), 0.6) else base :: Color3
	end
end

local function eggAnchorCF(part: BasePart): CFrame
	local a = part:FindFirstChild("EggAnchor")
	if a and a:IsA("Attachment") then
		return CFrame.new(a.WorldPosition)
	end
	return CFrame.new(part.Position + Vector3.new(0, part.Size.X / 2 + 0.45, 0))
end

local function removeGlow(view: NestView)
	if view.glow then
		view.glow:Destroy()
		view.glow = nil
	end
end

-- crack the egg open: shake, split in two halves that fly apart, fade
local function crack(egg: Model)
	task.spawn(function()
		local base = egg:GetPivot()
		local reduce = C.ReduceMotion()
		if not reduce then
			for i = 1, 8 do
				egg:PivotTo(base * CFrame.Angles(0, 0, math.rad(if i % 2 == 0 then 14 else -14)))
				task.wait(0.04)
			end
		end
		egg:PivotTo(base)
		local shell = egg:FindFirstChild("Shell")
		local top = egg:FindFirstChild("Top")
		if top and top:IsA("BasePart") and not reduce then
			C.Tween(top, 0.35, { CFrame = top.CFrame * CFrame.new(0, 1.6, 0.6) * CFrame.Angles(0.8, 0, 0) })
		end
		for _, d in egg:GetDescendants() do
			if d:IsA("BasePart") then
				C.Tween(d, 0.4, { Transparency = 1 })
			end
		end
		if shell and shell:IsA("BasePart") then
			C.Tween(shell, 0.4, { Size = shell.Size * 1.3 })
		end
		task.wait(0.45)
		egg:Destroy()
	end)
end

------------------------------------------------------------------------------ sync

local function syncNest(view: NestView, now: number)
	local i = tonumber(view.key) or 1
	local unlocked = i <= Eggs.NestsFor(rebirths())
	local nest = nestsData()[view.key]
	local eggId = if typeof(nest) == "table" and typeof(nest.egg) == "string" then nest.egg else nil
	local p = prompt(view.part)

	-- egg model follows the data
	if view.eggId ~= eggId then
		if view.egg then
			if view.ready then
				crack(view.egg)
			else
				view.egg:Destroy()
			end
			view.egg = nil
		end
		removeGlow(view)
		view.ready = false
		view.eggId = eggId
		if eggId then
			local ok, model = pcall(PetModels.BuildEgg, eggId)
			if ok and model then
				model.Name = "NestEgg" .. view.key
				model:PivotTo(eggAnchorCF(view.part))
				model.Parent = view.part
				view.egg = model
			end
		end
	end

	-- an egg in a locked nest (admin rebirth change) still hatches, so only dim empty locked nests
	setDimmed(view, not unlocked and eggId == nil)

	if eggId and typeof(nest) == "table" then
		local egg = Eggs.ById[eggId]
		local readyAt = if typeof(nest.readyAt) == "number" then nest.readyAt else 0
		local left = math.max(0, readyAt - now)
		local ready = left <= 0
		if ready and not view.ready then
			view.ready = true
			local light = Instance.new("PointLight")
			light.Name = "ReadyGlow"
			light.Color = Color3.fromRGB(255, 230, 120)
			light.Brightness = 3
			light.Range = 10
			light.Parent = view.part
			view.glow = light
			SoundController:Play("RareSparkle")
		end
		local name = if egg then egg.name else "Egg"
		if ready then
			setLabel(view.part, "Ready! Tap to hatch", Colors.Yellow)
		else
			setLabel(view.part, `{name}\n{Format.Time(math.ceil(left))}`)
		end
		if p then
			p.Enabled = true
			p.ActionText = if ready then "Hatch!" else "Hatching..."
			p.ObjectText = name
		end
	elseif not unlocked then
		local need = rebirthFor(i)
		setLabel(view.part, if need then `Rebirth {need}` else "Locked", Colors.Grey)
		if p then
			p.Enabled = false
		end
	else
		setLabel(view.part, "Empty Nest")
		if p then
			p.Enabled = true
			p.ActionText = "Open Egg Shop"
			p.ObjectText = "Nest " .. view.key
		end
	end
end

local function syncAll()
	local now = Multipliers.Now()
	for _, view in views do
		syncNest(view, now)
	end
end

local function unbindPlot()
	for _, view in views do
		if view.egg then
			view.egg:Destroy()
		end
		removeGlow(view)
		setDimmed(view, false)
		setLabel(view.part, "Nest")
	end
	table.clear(views)
	plotModel = nil
end

-- prompts of nests on every plot that is not ours are switched off locally
local function disableForeignPrompts()
	local plots = workspace:FindFirstChild("Plots")
	if not plots then
		return
	end
	for _, plot in plots:GetChildren() do
		if plot ~= plotModel then
			for _, d in plot:GetChildren() do
				if d:IsA("BasePart") and d:GetAttribute("NestKey") ~= nil then
					local p = prompt(d)
					if p then
						p.Enabled = false
					end
				end
			end
		end
	end
end

local function bindPlot()
	local id = player:GetAttribute("PlotId")
	local plots = workspace:FindFirstChild("Plots")
	local plot = if typeof(id) == "number" and plots then plots:FindFirstChild("Plot" .. id) else nil
	if plot == plotModel then
		return
	end
	unbindPlot()
	if not plot then
		return
	end
	plotModel = plot
	for _, d in plot:GetChildren() do
		local key = d:GetAttribute("NestKey")
		if d:IsA("BasePart") and typeof(key) == "string" then
			views[key] = { part = d, key = key, egg = nil, eggId = nil, glow = nil, ready = false, dimmed = false }
		end
	end
	disableForeignPrompts()
	syncAll()
end

local function onPrompt(promptObj: ProximityPrompt)
	for key, view in views do
		if prompt(view.part) == promptObj then
			local nest = nestsData()[key]
			if typeof(nest) == "table" then
				Net.Event("RequestHatch"):FireServer(key)
			else
				Panels.OpenPanel("EggShop")
			end
			return
		end
	end
end

------------------------------------------------------------------------------ wobble

local function step(dt: number)
	local now = Multipliers.Now()
	local t = os.clock()
	local reduce = C.ReduceMotion()
	for _, view in views do
		local egg = view.egg
		local nest = nestsData()[view.key]
		if egg and egg.Parent and typeof(nest) == "table" then
			local def = Eggs.ById[nest.egg]
			local total = if def then def.hatchSeconds else 60
			local readyAt = if typeof(nest.readyAt) == "number" then nest.readyAt else 0
			local progress = math.clamp(1 - (readyAt - now) / math.max(1, total), 0, 1)
			local freq = 1.5 + progress * 9
			local amp = math.rad(if reduce then 2 else 4 + progress * 10)
			if view.ready then
				freq, amp = 12, math.rad(if reduce then 3 else 12)
			end
			-- wobble in bursts so it reads as "something is moving inside"
			local burst = if view.ready then 1 else math.clamp(math.sin(t * (0.8 + progress * 2)) * 2, 0, 1)
			local tilt = math.sin(t * freq) * amp * burst
			egg:PivotTo(eggAnchorCF(view.part) * CFrame.Angles(0, t * 0.3, 0) * CFrame.Angles(0, 0, tilt))
		end
	end
	labelClock += dt
	if labelClock >= LABEL_TICK then
		labelClock = 0
		for _, view in views do
			syncNest(view, now)
		end
	end
end

------------------------------------------------------------------------------ reveal

local function playReveal(petId: string, variant: string)
	local pet = Pets.ById[petId]
	if not pet then
		return
	end
	local rarity = Pets.RarityById[pet.rarity]
	local variantDef = Pets.VariantById[variant]
	local color = if rarity then rarity.color else Colors.Grey

	local gui = Instance.new("ScreenGui")
	gui.Name = "PetReveal"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = C.Layers.Reveal
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(15, 8, 30)
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Parent = gui
	local bg = Instance.new("UIGradient")
	bg.Rotation = 90
	bg.Color = ColorSequence.new(color:Lerp(Color3.new(0, 0, 0), 0.5), Color3.fromRGB(10, 5, 20))
	bg.Parent = backdrop

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.Size = UDim2.fromScale(1, 1)
	content.Parent = gui
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.25
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = content
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = content

	local rays: { Frame } = {}
	for i = 1, RAY_COUNT do
		local ray = Instance.new("Frame")
		ray.Name = "Ray"
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.48)
		ray.Size = UDim2.fromScale(0.09, 1.5)
		ray.BackgroundColor3 = C.Lighten(color, 0.35)
		ray.BackgroundTransparency = 0.55
		ray.BorderSizePixel = 0
		ray.Rotation = (i - 1) * (180 / RAY_COUNT)
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = ray
		ray.Parent = content
		table.insert(rays, ray)
	end

	local banner = C.Label(content, {
		name = "Banner",
		text = "YOU HATCHED",
		font = C.Theme.TitleFont,
		color = Colors.Yellow,
		size = UDim2.fromScale(0.8, 0.1),
		position = UDim2.fromScale(0.5, 0.08),
		anchor = Vector2.new(0.5, 0.5),
		stroke = 4,
		zIndex = 5,
	})

	local vp = Instance.new("ViewportFrame")
	vp.Name = "Pet"
	vp.AnchorPoint = Vector2.new(0.5, 0.5)
	vp.Position = UDim2.fromScale(0.5, 0.45)
	vp.Size = UDim2.fromScale(0.55, 0.55)
	vp.BackgroundTransparency = 1
	vp.ZIndex = 4
	vp.Parent = content
	local stopPet = PetViewport.Mount(vp, petId, variant, { spin = 1.3 })

	local vName = if variantDef and variant ~= "normal" then variantDef.name .. " " else ""
	C.Label(content, {
		name = "PetName",
		text = string.upper(vName .. pet.name),
		font = C.Theme.TitleFont,
		size = UDim2.fromScale(0.9, 0.1),
		position = UDim2.fromScale(0.5, 0.76),
		anchor = Vector2.new(0.5, 0.5),
		stroke = 4,
		zIndex = 5,
	})
	C.Label(content, {
		name = "Rarity",
		text = if rarity then rarity.name else "",
		color = color,
		size = UDim2.fromScale(0.5, 0.06),
		position = UDim2.fromScale(0.5, 0.84),
		anchor = Vector2.new(0.5, 0.5),
		stroke = 3,
		zIndex = 5,
	})
	C.Label(content, {
		name = "Boost",
		text = PetViewport.BoostText(petId, variant),
		color = Colors.Cash,
		size = UDim2.fromScale(0.5, 0.06),
		position = UDim2.fromScale(0.5, 0.91),
		anchor = Vector2.new(0.5, 0.5),
		stroke = 3,
		zIndex = 5,
	})
	local hint = C.Label(content, {
		name = "Hint",
		text = "Tap to continue",
		color = Color3.fromRGB(220, 220, 230),
		size = UDim2.fromScale(0.4, 0.04),
		position = UDim2.fromScale(0.5, 0.97),
		anchor = Vector2.new(0.5, 0.5),
		stroke = 0,
		zIndex = 5,
	})

	gui.Parent = player:WaitForChild("PlayerGui")
	SoundController:Play("CrateReveal")
	if rarity and rarity.order >= 4 then
		SoundController:Play("NewCowFanfare")
	end
	C.Tween(backdrop, 0.2, { BackgroundTransparency = 0.15 })
	if C.ReduceMotion() then
		scale.Scale = 1
	else
		C.Tween(scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
		banner.Rotation = -4
	end

	local spin = RunService.RenderStepped:Connect(function(dt: number)
		if C.ReduceMotion() then
			return
		end
		for i, ray in rays do
			ray.Rotation = (ray.Rotation + dt * (if i % 2 == 0 then 12 else 18)) % 360
		end
	end)

	local done = false
	local unlocked = false
	task.delay(CLOSE_UNLOCK, function()
		unlocked = true
	end)
	local function close()
		if done then
			return
		end
		done = true
		hint.Visible = false
		C.Tween(scale, 0.2, { Scale = 0.5 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		C.Tween(backdrop, 0.25, { BackgroundTransparency = 1 })
		task.wait(0.25)
		spin:Disconnect()
		stopPet()
		gui:Destroy()
	end
	backdrop.Activated:Connect(function()
		if unlocked then
			task.spawn(close)
		end
	end)
	local t0 = os.clock()
	while not done and os.clock() - t0 < AUTO_CLOSE do
		task.wait(0.1)
	end
	close()
end

function NestController:ShowReveal(petId: string, variant: string?)
	local v = if typeof(variant) == "string" and Pets.VariantById[variant] then variant else "normal"
	RevealQueue.Push(function()
		playReveal(petId, v)
	end, 5)
end

------------------------------------------------------------------------------ lifecycle

function NestController:Start()
	player:GetAttributeChangedSignal("PlotId"):Connect(bindPlot)
	DataController:OnChanged("nests", syncAll)
	DataController:OnChanged("rebirths", syncAll)
	bindPlot()
	-- the map may still be building when the client starts
	task.spawn(function()
		for _ = 1, 30 do
			if plotModel or not player.Parent then
				break
			end
			task.wait(1)
			bindPlot()
		end
	end)
	local plots = workspace:FindFirstChild("Plots")
	if plots then
		plots.ChildAdded:Connect(function()
			task.defer(bindPlot)
		end)
	end
	game:GetService("ProximityPromptService").PromptTriggered:Connect(function(p: ProximityPrompt, who: Player)
		if who == player then
			onPrompt(p)
		end
	end)
	Net.Event("PetHatched").OnClientEvent:Connect(function(_uid: any, petId: any, variant: any)
		if typeof(petId) == "string" and Pets.ById[petId] then
			NestController:ShowReveal(petId, if typeof(variant) == "string" then variant else "normal")
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		Safe.Run("NestController step", step, dt)
	end)
end

return NestController
