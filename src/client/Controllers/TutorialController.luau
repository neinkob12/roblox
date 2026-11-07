--!strict
-- C4: Client side of the onboarding tutorial.
--
-- Watches DataController ("tutorialStep" + the keys the step checks), shows:
--   * a big friendly banner (bottom-center, above the sell chip) with a Skip button
--   * a Beam from the character to the step's target part
--   * a bouncing, spinning 3D arrow (built from Parts) above the target
-- When a step's condition (Config/Tutorial) is met it sends RequestTutorialStep(current + 1).
-- The server re-validates everything. Never blocks gameplay: all world visuals are local,
-- non-colliding, non-touching and non-queryable. Missing targets are skipped gracefully.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)
local Tutorial = require(ReplicatedStorage.Shared.Config.Tutorial)
local DataController = require(script.Parent.DataController)
local C = require(script.Parent.Parent.Lib.UiKit)
local Theme = require(script.Parent.Parent.Lib.Theme)

local player = Players.LocalPlayer
local Colors = Theme.Colors

local TutorialController = {}

-------------------------------------------------------------------------------- state

local currentStep = -1 -- last tutorialStep value we reacted to
local ctx: Tutorial.Ctx = { startedAt = 0 }
local stepToken = 0 -- bumps on every step change, stops old loops
local requestedStep = 0
local requestedAt = 0
local lastDairyCash = 0

-- UI
local banner: Frame? = nil
local bannerScale: UIScale? = nil
local stepLabel: TextLabel? = nil
local textLabel: TextLabel? = nil
local skipButton: TextButton? = nil
local skipCaption: TextLabel? = nil
local skipArmedUntil = 0

-- world visuals
local arrow: Model? = nil
local beam: Beam? = nil
local charAttachment: Attachment? = nil
local targetAttachment: Attachment? = nil
local target: BasePart? = nil
local renderConn: RBXScriptConnection? = nil

-------------------------------------------------------------------------------- requests

local function request(step: number)
	local now = os.clock()
	if requestedStep == step and now - requestedAt < Tutorial.ResendSeconds then
		return
	end
	requestedStep = step
	requestedAt = now
	Net.Event("RequestTutorialStep"):FireServer(step)
end

-------------------------------------------------------------------------------- world visuals

local function localPart(className: string, size: Vector3, parent: Instance): BasePart
	local p = Instance.new(className) :: BasePart
	p.Size = size
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = Tutorial.ArrowColor
	p.Parent = parent
	return p
end

-- Downward-pointing arrow: a shaft on top of a triangle made of two mirrored wedges.
-- Built around the model pivot at the arrow TIP (so the tip hovers above the target).
local function buildArrow(): Model
	local model = Instance.new("Model")
	model.Name = "TutorialArrow"

	local headH, halfW, thick = 1.6, 1.2, 0.7
	local root = localPart("Part", Vector3.new(0.2, 0.2, 0.2), model)
	root.Name = "Tip"
	root.Transparency = 1
	model.PrimaryPart = root

	local headY = headH / 2
	local a = localPart("WedgePart", Vector3.new(thick, headH, halfW), model)
	a.CFrame = CFrame.new(0, headY, halfW / 2) * CFrame.Angles(math.pi, 0, 0)
	local b = localPart("WedgePart", Vector3.new(thick, headH, halfW), model)
	b.CFrame = CFrame.new(0, headY, -halfW / 2) * CFrame.Angles(0, 0, math.pi)
	local shaft = localPart("Part", Vector3.new(thick, 2.2, 0.9), model)
	shaft.CFrame = CFrame.new(0, headH + 1.1, 0)

	local light = Instance.new("PointLight")
	light.Color = Tutorial.ArrowColor
	light.Brightness = 2
	light.Range = 10
	light.Parent = shaft

	model.Parent = workspace.CurrentCamera
	return model
end

local function makeBeam(): Beam
	local bm = Instance.new("Beam")
	bm.Name = "TutorialBeam"
	bm.FaceCamera = true
	bm.Segments = 12
	bm.Width0 = 1.4
	bm.Width1 = 0.35 -- tapers toward the target like an arrow
	bm.LightEmission = 0.6
	bm.LightInfluence = 0
	bm.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Tutorial.ArrowColor)
	bm.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.85),
		NumberSequenceKeypoint.new(0.15, 0.25),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	bm.Parent = workspace.CurrentCamera
	return bm
end

local function clearVisuals()
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	if arrow then
		arrow:Destroy()
		arrow = nil
	end
	if beam then
		beam:Destroy()
		beam = nil
	end
	if charAttachment then
		charAttachment:Destroy()
		charAttachment = nil
	end
	if targetAttachment then
		targetAttachment:Destroy()
		targetAttachment = nil
	end
	target = nil
end

local function rootPart(): BasePart?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

local function showVisuals(part: BasePart)
	clearVisuals()
	target = part
	arrow = buildArrow()
	beam = makeBeam()

	local ta = Instance.new("Attachment")
	ta.Name = "TutorialTarget"
	ta.Parent = part
	targetAttachment = ta

	local t0 = os.clock()
	renderConn = RunService.RenderStepped:Connect(function()
		local tgt = target
		local a = arrow
		local bm = beam
		if not tgt or not a or not bm or not tgt.Parent then
			return
		end
		-- arrow: tip hovers above the top of the target, bounces and spins
		local t = os.clock() - t0
		local top = tgt.Position + Vector3.new(0, tgt.Size.Y / 2 + Tutorial.ArrowHeight, 0)
		local bounce = math.abs(math.sin(t * Tutorial.ArrowBounceSpeed)) * Tutorial.ArrowBounce
		a:PivotTo(CFrame.new(top + Vector3.new(0, bounce, 0)) * CFrame.Angles(0, t * Tutorial.ArrowSpinSpeed, 0))

		-- beam: re-attach to the character after respawns
		local hrp = rootPart()
		if hrp then
			local ca = charAttachment
			if not ca or ca.Parent ~= hrp then
				if ca then
					ca:Destroy()
				end
				local fresh = Instance.new("Attachment")
				fresh.Name = "TutorialFrom"
				fresh.Position = Vector3.new(0, -1.5, 0)
				fresh.Parent = hrp
				charAttachment = fresh
				ca = fresh
			end
			bm.Attachment0 = ca
			bm.Attachment1 = targetAttachment
			-- hide the beam once the player is basically there
			bm.Enabled = (hrp.Position - tgt.Position).Magnitude > 8
		else
			bm.Enabled = false
		end
	end)
end

-------------------------------------------------------------------------------- banner

local function popBanner()
	local s = bannerScale
	if s then
		s.Scale = 0.6
		C.Tween(s, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	end
end

local function setBanner(stepText: string, text: string, color: Color3?)
	local b = banner
	if not b then
		return
	end
	b.Visible = true
	b.BackgroundColor3 = color or Colors.Blue
	if stepLabel then
		stepLabel.Text = stepText
	end
	if textLabel then
		textLabel.Text = text
	end
	popBanner()
end

local function hideBanner()
	if banner then
		banner.Visible = false
	end
end

local function resetSkip()
	skipArmedUntil = 0
	if skipCaption then
		skipCaption.Text = "Skip"
	end
	if skipButton then
		C.SetButtonColor(skipButton, Colors.Grey)
	end
end

local function onSkip()
	local now = os.clock()
	if now < skipArmedUntil then
		resetSkip()
		request(Tutorial.Done)
		return
	end
	-- first tap arms it, second tap within 3s confirms (no accidental skips on mobile)
	skipArmedUntil = now + 3
	if skipCaption then
		skipCaption.Text = "Sure?"
	end
	if skipButton then
		C.SetButtonColor(skipButton, Colors.Red)
	end
	task.delay(3, function()
		if os.clock() >= skipArmedUntil and skipArmedUntil ~= 0 then
			resetSkip()
		end
	end)
end

local function buildBanner()
	-- Above panels + dimmer and popups, below toasts (see Theme.Layers).
	local _, root = C.Screen("Tutorial", Theme.Layers.Tutorial)

	local b = Instance.new("Frame")
	b.Name = "Banner"
	-- Bottom-center, just above the HUD's sell chip (bottom 72..98). Top-center is taken by the
	-- event chip, truck banner and toasts. 380 wide keeps it clear of the lifted cash block on
	-- the left (x 12..262) and the mobile jump button on the right.
	b.AnchorPoint = Vector2.new(0.5, 1)
	b.Position = UDim2.new(0.5, 0, 1, -106)
	b.Size = UDim2.fromOffset(380, 72)
	b.BackgroundColor3 = Colors.Blue
	b.BorderSizePixel = 0
	b.Visible = false
	b.Active = false
	C.Corner(b, 16)
	C.Stroke(b, 3, Colors.Stroke, true)
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200))
	grad.Parent = b
	local s = Instance.new("UIScale")
	s.Parent = b
	bannerScale = s
	b.Parent = root
	banner = b

	local chip = Instance.new("Frame")
	chip.Name = "StepChip"
	chip.AnchorPoint = Vector2.new(0, 0.5)
	chip.Position = UDim2.new(0, 10, 0.5, 0)
	chip.Size = UDim2.fromOffset(50, 52)
	chip.BackgroundColor3 = Colors.Yellow
	chip.BorderSizePixel = 0
	C.Corner(chip, 12)
	C.Stroke(chip, 3, Colors.Stroke, true)
	chip.Parent = b
	stepLabel = C.Label(chip, {
		name = "Step",
		text = "1/6",
		size = UDim2.new(1, -8, 1, -10),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		font = Theme.TitleFont,
	})

	textLabel = C.Label(b, {
		name = "Text",
		text = "",
		size = UDim2.new(1, -160, 1, -14),
		position = UDim2.new(0, 68, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		font = Theme.TitleFont,
		stroke = 3,
		maxTextSize = 30,
	})

	local btn, caption = C.Button(b, {
		name = "Skip",
		text = "Skip",
		size = UDim2.fromOffset(76, Theme.MinTouch),
		position = UDim2.new(1, -8, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		color = Colors.Grey,
		onClick = onSkip,
	})
	skipButton = btn
	skipCaption = caption
end

-------------------------------------------------------------------------------- steps

local function finish(showThanks: boolean)
	stepToken += 1
	clearVisuals()
	resetSkip()
	if showThanks and banner then
		if skipButton then
			skipButton.Visible = false
		end
		setBanner(":D", "You're a real farmer now!", Colors.Green)
		local token = stepToken
		task.delay(3, function()
			if token == stepToken then
				hideBanner()
			end
		end)
	else
		hideBanner()
	end
end

-- Runs while one step is active: finds the target, polls the condition, requests the next step.
local function runStep(index: number, token: number)
	local step = Tutorial.Steps[index]
	local waited = 0
	local shownTarget: BasePart? = nil
	while token == stepToken do
		-- target (re)resolution: the plot may be assigned after we start
		local part = Tutorial.FindTarget(player, step)
		if part ~= shownTarget then
			shownTarget = part
			if part then
				showVisuals(part)
			else
				clearVisuals()
			end
		end
		if not part then
			waited += Tutorial.PollSeconds
			if waited >= Tutorial.TargetWaitSeconds then
				-- server also checks the target is missing before it lets us skip
				request(index + 1)
			end
		end

		local data = DataController:Get()
		if data and step.done(data, ctx) then
			request(if index >= #Tutorial.Steps then Tutorial.Done else index + 1)
		end
		task.wait(Tutorial.PollSeconds)
	end
end

local function onStep(value: any)
	local step = if type(value) == "number" then value else 0
	if step == currentStep then
		return
	end
	local previous = currentStep
	currentStep = step
	stepToken += 1
	requestedStep = 0

	if step >= Tutorial.Done then
		-- only celebrate when we just watched the last step finish, not on join
		finish(previous >= 1 and previous < Tutorial.Done)
		return
	end
	if step <= 0 then
		clearVisuals()
		hideBanner()
		request(1)
		-- resend if the server didn't answer (e.g. data still loading)
		local token = stepToken
		task.spawn(function()
			while token == stepToken do
				task.wait(Tutorial.ResendSeconds)
				if token == stepToken then
					request(1)
				end
			end
		end)
		return
	end

	local def = Tutorial.Steps[step]
	if not def then
		return
	end
	ctx = { startedAt = os.clock() }
	if skipButton then
		skipButton.Visible = true
	end
	resetSkip()
	setBanner(`{step}/{#Tutorial.Steps}`, def.text, if def.autoSeconds then Colors.Purple else Colors.Blue)
	task.spawn(runStep, step, stepToken)
end

-------------------------------------------------------------------------------- lifecycle

function TutorialController:Init()
	-- nothing to build before data arrives
end

function TutorialController:Start()
	local data = DataController:WaitForData()
	-- built even for finished players (hidden) so /reset can restart the tutorial
	buildBanner()

	lastDairyCash = data.dairyCash or 0
	DataController:OnChanged("dairyCash", function(value: any)
		local v = if type(value) == "number" then value else 0
		if lastDairyCash > 0 and v <= 0 then
			ctx.collected = true -- cash pad collected (step "collect")
		end
		lastDairyCash = v
	end)

	DataController:OnChanged("tutorialStep", onStep)
end

return TutorialController
