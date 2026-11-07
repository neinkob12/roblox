--!strict
-- B4: Trailer / thumbnail camera. Type /trailer in chat (or press F7) to toggle.
-- Hides the HUD and chat, takes over the camera and plays smooth cinematic presets:
--
--   1  Plot orbit       slow orbit around your barn plot
--   2  Stall dolly      low dolly shot along your stalls (front row)
--   3  Dairy orbit      orbit around the dairy in the middle of the map
--   4  Top down         whole map from above, slowly turning
--   5  Hero cow         close, low orbit around your best cow (thumbnail shot)
--
--   F  9:16 safe frame (for Roblox Shorts; the 16:9 thumbnail uses the full screen)
--   [  ]  slower / faster       C  hide or show your own character
--   H  hide or show the button panel      F7 or /trailer  exit
--
-- Every key also has a button (mobile). Client only: changes nothing on the server.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local TrailerCamController = {}

type Preset = {
	name: string,
	-- returns the target camera CFrame at time t (seconds since the preset started)
	shot: (t: number) -> CFrame?,
	fov: number,
}

local SMOOTHING = 3 -- higher = snappier camera when switching shots
local MIN_SPEED, MAX_SPEED = 0.25, 4
local BUTTON_H = 48 -- >= 44px touch target

local active = false
local presetIndex = 1
local presetStart = 0
local speed = 1
local hideCharacter = false
local safeFrameOn = false

local gui: ScreenGui? = nil
local panel: Frame? = nil
local safeFrame: Frame? = nil
local toast: TextLabel? = nil
local presets: { Preset } = {}

local savedGuis: { [ScreenGui]: boolean } = {}
local savedCore: { [Enum.CoreGuiType]: boolean } = {}
local savedChatWindow: boolean? = nil
local savedChatBar: boolean? = nil
local savedFov = 70
local guiAddedConn: RBXScriptConnection? = nil
local currentCf: CFrame? = nil

----------------------------------------------------------------------------- world lookups

local function myPlot(): Model?
	local id = player:GetAttribute("PlotId")
	local plots = workspace:FindFirstChild("Plots")
	if typeof(id) ~= "number" or not plots then
		return nil
	end
	local plot = plots:FindFirstChild("Plot" .. id)
	if plot and plot:IsA("Model") then
		return plot
	end
	return nil
end

-- center + size of anything (Model uses GetBoundingBox, otherwise all BaseParts below it)
local function bounds(inst: Instance?): (Vector3?, Vector3?)
	if not inst then
		return nil, nil
	end
	if inst:IsA("Model") then
		local cf, size = inst:GetBoundingBox()
		return cf.Position, size
	end
	if inst:IsA("BasePart") then
		return inst.Position, inst.Size
	end
	local minV: Vector3? = nil
	local maxV: Vector3? = nil
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			local half = d.Size / 2
			local lo = d.Position - half
			local hi = d.Position + half
			minV = if minV then minV:Min(lo) else lo
			maxV = if maxV then maxV:Max(hi) else hi
		end
	end
	if minV and maxV then
		return (minV + maxV) / 2, maxV - minV
	end
	return nil, nil
end

local function stall(plot: Model, n: number): BasePart?
	local stalls = plot:FindFirstChild("Stalls")
	local s = stalls and stalls:FindFirstChild("Stall" .. n)
	if s and s:IsA("BasePart") then
		return s
	end
	return nil
end

local function bestCow(plot: Model): Model?
	for n = 18, 1, -1 do
		local s = stall(plot, n)
		local cow = s and s:FindFirstChild("Cow")
		if cow and cow:IsA("Model") then
			return cow
		end
	end
	return nil
end

local function orbit(center: Vector3, radius: number, height: number, angle: number): CFrame
	local pos = center + Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
	return CFrame.lookAt(pos, center)
end

local function smoothstep(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

----------------------------------------------------------------------------- presets

presets = {
	{
		name = "1  Plot orbit",
		fov = 55,
		shot = function(t)
			local plot = myPlot()
			local center, size = bounds(plot)
			if not center or not size then
				return nil
			end
			local r = math.max(size.X, size.Z) * 0.85
			return orbit(center, r, r * 0.45, t * 0.12)
		end,
	},
	{
		name = "2  Stall dolly",
		fov = 50,
		shot = function(t)
			local plot = myPlot()
			local a = plot and stall(plot, 1)
			local b = plot and stall(plot, 9)
			if not plot or not a or not b then
				return nil
			end
			local front = plot:GetPivot().LookVector -- -Z of the plot faces the dairy = stall fronts
			-- ping-pong across the row every 14 seconds
			local phase = (t / 14) % 2
			local k = smoothstep(if phase < 1 then phase else 2 - phase)
			local focus = a.Position:Lerp(b.Position, k) + Vector3.new(0, 2.5, 0)
			local pos = focus + front * 13 + Vector3.new(0, 2.5, 0)
			return CFrame.lookAt(pos, focus)
		end,
	},
	{
		name = "3  Dairy orbit",
		fov = 55,
		shot = function(t)
			local dairy = workspace:FindFirstChild("Dairy")
			local center, size = bounds(dairy)
			if not center or not size then
				return nil
			end
			local r = math.max(size.X, size.Z) * 0.75 + 12
			return orbit(center, r, r * 0.35, -t * 0.1)
		end,
	},
	{
		name = "4  Top down",
		fov = 60,
		shot = function(t)
			local map = workspace:FindFirstChild("Map")
			local center = Vector3.zero
			local height = 300
			local c, size = bounds(map)
			if c and size then
				center = Vector3.new(c.X, 0, c.Z)
				-- ignore the giant water plane: island is about 350 studs, fit ~70% of it
				height = math.clamp(math.min(size.X, size.Z), 150, 420) * 0.8
			end
			return CFrame.new(center + Vector3.new(0, height, 0))
				* CFrame.Angles(0, t * 0.03, 0)
				* CFrame.Angles(-math.pi / 2, 0, 0)
		end,
	},
	{
		name = "5  Hero cow",
		fov = 40,
		shot = function(t)
			local plot = myPlot()
			local cow = plot and bestCow(plot)
			local center, size = bounds(cow)
			if not plot or not center or not size then
				return nil
			end
			local front = plot:GetPivot().LookVector
			local r = math.max(size.X, size.Y, size.Z) * 1.6 + 4
			-- swing +-50 degrees in front of the cow, camera slightly below its head (heroic)
			local baseAngle = math.atan2(front.Z, front.X)
			local angle = baseAngle + math.sin(t * 0.35) * math.rad(50)
			local look = center + Vector3.new(0, size.Y * 0.15, 0)
			local pos = center + Vector3.new(math.cos(angle) * r, size.Y * 0.05, math.sin(angle) * r)
			return CFrame.lookAt(pos, look)
		end,
	},
}

----------------------------------------------------------------------------- UI

local function showToast(text: string)
	local t = toast
	if not t then
		return
	end
	t.Text = text
	t.TextTransparency = 0
	t.TextStrokeTransparency = 0.3
	TweenService:Create(
		t,
		TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.4),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	):Play()
end

local function updateSafeFrame()
	local frame = safeFrame
	local cam = workspace.CurrentCamera
	if not frame or not cam then
		return
	end
	frame.Visible = active and safeFrameOn
	local vp = cam.ViewportSize
	if vp.X <= 0 or vp.Y <= 0 then
		return
	end
	local innerW = math.min(vp.X, vp.Y * 9 / 16)
	local barW = (vp.X - innerW) / 2
	local left = frame:FindFirstChild("Left") :: Frame?
	local right = frame:FindFirstChild("Right") :: Frame?
	local inner = frame:FindFirstChild("Inner") :: Frame?
	if left and right and inner then
		left.Size = UDim2.new(0, barW, 1, 0)
		right.Size = UDim2.new(0, barW, 1, 0)
		right.Position = UDim2.new(1, -barW, 0, 0)
		inner.Size = UDim2.new(0, innerW, 1, 0)
		inner.Position = UDim2.fromOffset(barW, 0)
	end
end

local function makeButton(parent: Instance, text: string, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Text = text
	b.Font = Enum.Font.FredokaOne
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	b.BackgroundTransparency = 0.25
	b.AutoButtonColor = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = b
	b.Activated:Connect(onClick)
	b.Parent = parent
	return b
end

local setPreset: (number) -> ()
local changeSpeed: (number) -> ()
local toggleSafeFrame: () -> ()
local toggleCharacter: () -> ()
local togglePanel: () -> ()
local setActive: (boolean) -> ()

local function buildGui(): ScreenGui
	local sg = Instance.new("ScreenGui")
	sg.Name = "TrailerCamGui"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.DisplayOrder = 1000
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.Enabled = false

	-- 9:16 safe frame: dark bars outside, white outline inside
	local frame = Instance.new("Frame")
	frame.Name = "SafeFrame"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = sg
	for _, side in { "Left", "Right" } do
		local bar = Instance.new("Frame")
		bar.Name = side
		bar.BackgroundColor3 = Color3.new(0, 0, 0)
		bar.BackgroundTransparency = 0.45
		bar.BorderSizePixel = 0
		bar.Parent = frame
	end
	local inner = Instance.new("Frame")
	inner.Name = "Inner"
	inner.BackgroundTransparency = 1
	inner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = inner
	-- Shorts UI covers roughly the bottom 20% and the right edge: mark it
	local bottom = Instance.new("Frame")
	bottom.Name = "ShortsUiZone"
	bottom.AnchorPoint = Vector2.new(0, 1)
	bottom.Position = UDim2.fromScale(0, 1)
	bottom.Size = UDim2.fromScale(1, 0.2)
	bottom.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
	bottom.BackgroundTransparency = 0.85
	bottom.BorderSizePixel = 0
	bottom.Parent = inner
	safeFrame = frame
	safeFrameOn = false

	local t = Instance.new("TextLabel")
	t.Name = "Toast"
	t.AnchorPoint = Vector2.new(0.5, 0)
	t.Position = UDim2.new(0.5, 0, 0, 16)
	t.Size = UDim2.new(0.5, 0, 0, 40)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextTransparency = 1
	t.TextStrokeTransparency = 1
	t.Parent = sg
	toast = t

	local p = Instance.new("Frame")
	p.Name = "Panel"
	p.AnchorPoint = Vector2.new(0, 1)
	p.Position = UDim2.new(0, 12, 1, -12)
	p.Size = UDim2.fromOffset(5 * 70, 2 * (BUTTON_H + 6))
	p.BackgroundTransparency = 1
	p.Parent = sg
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(64, BUTTON_H)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = p
	for i = 1, #presets do
		makeButton(p, tostring(i), function()
			setPreset(i)
		end).LayoutOrder = i
	end
	makeButton(p, "9:16", function()
		toggleSafeFrame()
	end).LayoutOrder = 10
	makeButton(p, "Slow", function()
		changeSpeed(0.5)
	end).LayoutOrder = 11
	makeButton(p, "Fast", function()
		changeSpeed(2)
	end).LayoutOrder = 12
	makeButton(p, "Me", function()
		toggleCharacter()
	end).LayoutOrder = 13
	makeButton(p, "Exit", function()
		setActive(false)
	end).LayoutOrder = 14
	-- scale the panel down on small phones
	local scale = Instance.new("UIScale")
	scale.Parent = p
	panel = p

	-- "Hide" keeps one tiny, almost invisible button to bring the panel back
	local hide = makeButton(sg, "o", function()
		togglePanel()
	end)
	hide.Name = "HideButton"
	hide.AnchorPoint = Vector2.new(1, 1)
	hide.Position = UDim2.new(1, -8, 1, -8)
	hide.Size = UDim2.fromOffset(44, 44)
	hide.BackgroundTransparency = 0.85
	hide.TextTransparency = 0.6

	local function fit()
		local cam = workspace.CurrentCamera
		if cam then
			scale.Scale = math.clamp(cam.ViewportSize.X / 900, 0.75, 1.25)
		end
		updateSafeFrame()
	end
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
	fit()

	sg.Parent = player:WaitForChild("PlayerGui")
	return sg
end

----------------------------------------------------------------------------- HUD hide / restore

local function hideGui(g: Instance)
	if g:IsA("ScreenGui") and g ~= gui and savedGuis[g] == nil then
		savedGuis[g] = g.Enabled
		g.Enabled = false
	end
end

local function hideHud()
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if pg then
		for _, g in pg:GetChildren() do
			hideGui(g)
		end
		guiAddedConn = pg.ChildAdded:Connect(hideGui)
	end
	for _, t in
		{
			Enum.CoreGuiType.PlayerList,
			Enum.CoreGuiType.Chat,
			Enum.CoreGuiType.Backpack,
			Enum.CoreGuiType.Health,
			Enum.CoreGuiType.EmotesMenu,
		}
	do
		savedCore[t] = StarterGui:GetCoreGuiEnabled(t)
		StarterGui:SetCoreGuiEnabled(t, false)
	end
	local cw = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
	if cw then
		savedChatWindow = cw.Enabled
		cw.Enabled = false
	end
	local cb = TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
	if cb then
		savedChatBar = cb.Enabled
		cb.Enabled = false
	end
end

local function restoreHud()
	if guiAddedConn then
		guiAddedConn:Disconnect()
		guiAddedConn = nil
	end
	for g, enabled in savedGuis do
		if g.Parent then
			g.Enabled = enabled
		end
	end
	table.clear(savedGuis)
	for t, enabled in savedCore do
		StarterGui:SetCoreGuiEnabled(t, enabled)
	end
	table.clear(savedCore)
	local cw = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
	if cw and savedChatWindow ~= nil then
		cw.Enabled = savedChatWindow
	end
	local cb = TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
	if cb and savedChatBar ~= nil then
		cb.Enabled = savedChatBar
	end
	savedChatWindow = nil
	savedChatBar = nil
end

local function applyCharacterVisibility()
	local character = player.Character
	if not character then
		return
	end
	local value = if active and hideCharacter then 1 else 0
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			d.LocalTransparencyModifier = value
		end
	end
end

----------------------------------------------------------------------------- control

setPreset = function(i: number)
	if not presets[i] then
		return
	end
	presetIndex = i
	presetStart = 0
	local cam = workspace.CurrentCamera
	if cam then
		cam.FieldOfView = presets[i].fov
	end
	showToast(presets[i].name)
end

changeSpeed = function(factor: number)
	speed = math.clamp(speed * factor, MIN_SPEED, MAX_SPEED)
	showToast(string.format("Speed x%.2f", speed))
end

toggleSafeFrame = function()
	safeFrameOn = not safeFrameOn
	updateSafeFrame()
	showToast(if safeFrameOn then "9:16 safe frame ON" else "9:16 safe frame OFF")
end

toggleCharacter = function()
	hideCharacter = not hideCharacter
	applyCharacterVisibility()
	showToast(if hideCharacter then "Character hidden" else "Character visible")
end

togglePanel = function()
	local p = panel
	if p then
		p.Visible = not p.Visible
	end
end

local function onRender(dt: number)
	if not active then
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	presetStart += dt * speed
	local preset = presets[presetIndex]
	local target = preset and preset.shot(presetStart)
	if not target then
		return -- the thing to film is missing (no plot yet, no cow): hold the camera still
	end
	cam.CameraType = Enum.CameraType.Scriptable
	local from = currentCf or cam.CFrame
	local alpha = 1 - math.exp(-SMOOTHING * dt)
	local cf = from:Lerp(target, alpha)
	currentCf = cf
	cam.CFrame = cf
	if hideCharacter then
		applyCharacterVisibility() -- the default camera scripts reset this every frame
	end
end

setActive = function(on: boolean)
	if on == active then
		return
	end
	local cam = workspace.CurrentCamera
	local g = gui or buildGui()
	gui = g
	active = on
	if on then
		if cam then
			savedFov = cam.FieldOfView
			currentCf = cam.CFrame
		end
		hideHud()
		g.Enabled = true
		local p = panel
		if p then
			p.Visible = true
		end
		RunService:BindToRenderStep("TrailerCam", Enum.RenderPriority.Camera.Value + 1, onRender)
		setPreset(presetIndex)
	else
		RunService:UnbindFromRenderStep("TrailerCam")
		g.Enabled = false
		restoreHud()
		applyCharacterVisibility()
		currentCf = nil
		if cam then
			cam.FieldOfView = savedFov
			cam.CameraType = Enum.CameraType.Custom
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				cam.CameraSubject = humanoid
			end
		end
	end
	updateSafeFrame()
end

function TrailerCamController:IsActive(): boolean
	return active
end

function TrailerCamController:Toggle()
	setActive(not active)
end

----------------------------------------------------------------------------- lifecycle

local KEY_PRESETS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.KeypadOne] = 1,
	[Enum.KeyCode.KeypadTwo] = 2,
	[Enum.KeyCode.KeypadThree] = 3,
	[Enum.KeyCode.KeypadFour] = 4,
	[Enum.KeyCode.KeypadFive] = 5,
}

function TrailerCamController:Start()
	if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
		local cmd = Instance.new("TextChatCommand")
		cmd.Name = "TrailerCommand"
		cmd.PrimaryAlias = "/trailer"
		cmd.Triggered:Connect(function(source: TextSource, _text: string)
			if source.UserId == player.UserId then
				TrailerCamController:Toggle()
			end
		end)
		cmd.Parent = TextChatService
	else
		player.Chatted:Connect(function(message)
			if string.lower(message) == "/trailer" then
				TrailerCamController:Toggle()
			end
		end)
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.F7 then
			TrailerCamController:Toggle()
			return
		end
		if processed or not active then
			return
		end
		local key = input.KeyCode
		local preset = KEY_PRESETS[key]
		if preset then
			setPreset(preset)
		elseif key == Enum.KeyCode.F then
			toggleSafeFrame()
		elseif key == Enum.KeyCode.LeftBracket then
			changeSpeed(0.5)
		elseif key == Enum.KeyCode.RightBracket then
			changeSpeed(2)
		elseif key == Enum.KeyCode.C then
			toggleCharacter()
		elseif key == Enum.KeyCode.H then
			togglePanel()
		end
	end)

	player.CharacterAdded:Connect(function()
		if active then
			task.defer(applyCharacterVisibility)
		end
	end)
end

return TrailerCamController
