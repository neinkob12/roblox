--!strict
-- B1: Reusable UI building blocks + the panel manager. No Init/Start (pure helpers).
--
--   Components.Screen(name, displayOrder) -> (ScreenGui, root: Frame)
--       root is a full-screen frame laid out in Theme.ReferenceSize pixels (UIScale inside).
--   Components.Corner(parent, radius?) / Stroke(parent, thickness?, color?, border?)
--   Components.Label(parent, props) -> TextLabel
--   Components.Button(parent, props) -> (TextButton, TextLabel)
--   Components.SetButtonColor(button, color) / SetButtonEnabled(button, enabled, color?)
--   Components.Tween(inst, time, props, style?, dir?) -> Tween
--   Components.CountUp(label, to, fmt, time?)  tweened number text (one NumberValue per label)
--   Components.Card(parent, height, order?) / ScrollList(parent, padding) / Now() (server time)
--   Components.Rainbow(stroke)                 animated rainbow UIGradient on a UIStroke
--   Components.Panel(name, title, size, color?) -> (panel: Frame, body: Frame)
--   Components.OpenPanel(name) / ClosePanel() / TogglePanel(name) / IsOpen(name)
--   Components.OnPanelOpened(name, fn)
--   Components.ReduceMotion() -> boolean     data.settings.reduceMotion (C6)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local DataController = require(script.Parent.Parent.Controllers.DataController)

local Components = {}

local player = Players.LocalPlayer

local function playerGui(): PlayerGui
	return player:WaitForChild("PlayerGui") :: PlayerGui
end

function Components.Tween(
	inst: Instance,
	time: number,
	props: { [string]: any },
	style: Enum.EasingStyle?,
	dir: Enum.EasingDirection?
): Tween
	local t = TweenService:Create(
		inst,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		props
	)
	t:Play()
	return t
end

function Components.Corner(parent: Instance, radius: number?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or Theme.Corner)
	c.Parent = parent
	return c
end

function Components.Stroke(parent: Instance, thickness: number?, color: Color3?, border: boolean?): UIStroke
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or Theme.StrokeThickness
	s.Color = color or Theme.Colors.Stroke
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.ApplyStrokeMode = if border then Enum.ApplyStrokeMode.Border else Enum.ApplyStrokeMode.Contextual
	s.Parent = parent
	return s
end

function Components.Padding(parent: Instance, px: number)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.Parent = parent
end

function Components.List(parent: Instance, padding: number, horizontal: boolean?, align: Enum.HorizontalAlignment?)
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, padding)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	l.HorizontalAlignment = align or Enum.HorizontalAlignment.Center
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.Parent = parent
	return l
end

export type LabelProps = {
	name: string?,
	text: string?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	color: Color3?,
	font: Enum.Font?,
	stroke: number?, -- text outline thickness (0 = none)
	align: Enum.TextXAlignment?,
	maxTextSize: number?,
	zIndex: number?,
	order: number?,
}

function Components.Label(parent: Instance, props: LabelProps): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = props.name or "Label"
	l.Text = props.text or ""
	l.Size = props.size or UDim2.fromOffset(100, 30)
	l.Position = props.position or UDim2.new()
	l.AnchorPoint = props.anchor or Vector2.zero
	l.BackgroundTransparency = 1
	l.Font = props.font or Theme.Font
	l.TextScaled = true
	l.TextColor3 = props.color or Theme.Colors.Text
	l.TextXAlignment = props.align or Enum.TextXAlignment.Center
	l.ZIndex = props.zIndex or 1
	l.LayoutOrder = props.order or 0
	l.Active = false
	if props.maxTextSize then
		local c = Instance.new("UITextSizeConstraint")
		c.MaxTextSize = props.maxTextSize
		c.Parent = l
	end
	local strokeSize = if props.stroke == nil then 2 else props.stroke
	if strokeSize > 0 then
		Components.Stroke(l, strokeSize)
	end
	l.Parent = parent
	return l
end

-- True when the player turned on "Reduce motion" in Settings (skip bounces and popups).
function Components.ReduceMotion(): boolean
	local data = DataController:Get()
	local settings = if data and typeof(data.settings) == "table" then data.settings else nil
	return settings ~= nil and settings.reduceMotion == true
end

local function darken(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), amount)
end

local function lighten(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), amount)
end

Components.Darken = darken
Components.Lighten = lighten

export type ButtonProps = {
	name: string?,
	text: string?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	color: Color3?,
	textColor: Color3?,
	font: Enum.Font?,
	order: number?,
	zIndex: number?,
	onClick: (() -> ())?,
}

-- Chunky rounded button: colored body + top highlight gradient + thick dark border.
-- The caption is a child TextLabel named "Caption" (so the text keeps its own outline).
function Components.Button(parent: Instance, props: ButtonProps): (TextButton, TextLabel)
	local color = props.color or Theme.Colors.Green
	local b = Instance.new("TextButton")
	b.Name = props.name or "Button"
	b.Text = ""
	b.AutoButtonColor = false
	b.Size = props.size or UDim2.fromOffset(160, Theme.MinTouch)
	b.Position = props.position or UDim2.new()
	b.AnchorPoint = props.anchor or Vector2.zero
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.LayoutOrder = props.order or 0
	b.ZIndex = props.zIndex or 1
	b:SetAttribute("BaseColor", color)
	b:SetAttribute("Enabled", true)
	Components.Corner(b)
	Components.Stroke(b, 3, Theme.Colors.Stroke, true)
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190))
	grad.Parent = b

	local scale = Instance.new("UIScale")
	scale.Parent = b

	local caption = Components.Label(b, {
		name = "Caption",
		text = props.text or "",
		size = UDim2.new(1, -12, 1, -10),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		color = props.textColor,
		font = props.font,
		stroke = 2,
		zIndex = b.ZIndex + 1,
	})

	b.MouseButton1Down:Connect(function()
		Components.Tween(scale, 0.06, { Scale = 0.92 })
	end)
	b.MouseButton1Up:Connect(function()
		Components.Tween(scale, 0.12, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	b.MouseLeave:Connect(function()
		Components.Tween(scale, 0.12, { Scale = 1 })
	end)
	b.MouseEnter:Connect(function()
		if b:GetAttribute("Enabled") then
			Components.Tween(scale, 0.1, { Scale = 1.04 })
		end
	end)
	if props.onClick then
		local fn = props.onClick
		b.Activated:Connect(function()
			if b:GetAttribute("Enabled") then
				fn()
			end
		end)
	end
	b.Parent = parent
	return b, caption
end

function Components.SetButtonColor(b: GuiObject, color: Color3)
	b:SetAttribute("BaseColor", color)
	if b:GetAttribute("Enabled") ~= false then
		b.BackgroundColor3 = color
	end
end

-- Disabled buttons turn grey but still receive clicks (onClick is skipped while disabled).
function Components.SetButtonEnabled(b: GuiObject, enabled: boolean)
	b:SetAttribute("Enabled", enabled)
	local base = b:GetAttribute("BaseColor")
	if enabled then
		b.BackgroundColor3 = if typeof(base) == "Color3" then base else Theme.Colors.Green
	else
		b.BackgroundColor3 = Theme.Colors.Grey
	end
end

-- Tweened number text. Each label keeps one NumberValue between calls.
local counters: { [Instance]: NumberValue } = {}
function Components.CountUp(label: TextLabel, to: number, fmt: (number) -> string, time: number?)
	local nv = counters[label]
	if not nv then
		local created = Instance.new("NumberValue")
		created.Value = to
		created.Changed:Connect(function(v)
			label.Text = fmt(v)
		end)
		counters[label] = created
		label.Destroying:Connect(function()
			counters[label] = nil
			created:Destroy()
		end)
		label.Text = fmt(to)
		return
	end
	if math.abs(to - nv.Value) < 1e-9 then
		label.Text = fmt(to)
		return
	end
	Components.Tween(nv, time or 0.45, { Value = to }, Enum.EasingStyle.Quart)
end

-- Animated rainbow on a UIStroke (or any instance that can hold a UIGradient).
function Components.Rainbow(target: Instance): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = Theme.Rainbow
	g.Parent = target
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		if not g.Parent then
			conn:Disconnect()
			return
		end
		if not Components.ReduceMotion() then
			g.Rotation = (os.clock() * 120) % 360
		end
	end)
	return g
end

------------------------------------------------------------------------------- screens

-- Root frame sized so that after UIScale it exactly covers the ScreenGui.
function Components.Screen(name: string, displayOrder: number): (ScreenGui, Frame)
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.DisplayOrder = displayOrder
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.IgnoreGuiInset = false

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Active = false
	root.Parent = gui
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = root

	local function rescale()
		local size = gui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local ref = Theme.ReferenceSize
		local s = math.clamp(math.min(size.X / ref.X, size.Y / ref.Y), Theme.MinScale, Theme.MaxScale)
		uiScale.Scale = s
		root.Size = UDim2.fromOffset(size.X / s, size.Y / s)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
	gui.Parent = playerGui()
	rescale()
	task.defer(rescale)
	return gui, root
end

-------------------------------------------------------------------------- panel manager

type PanelEntry = { frame: Frame, scale: UIScale, opened: { () -> () } }

-- C6: shrink a panel that would not fit the screen (tiny phones where UIScale hits MinScale).
local function fitScale(frame: Frame): number
	local parent = frame.Parent
	if not parent or not parent:IsA("GuiObject") then
		return 1
	end
	local avail = (parent :: GuiObject).Size
	local w, h = frame.Size.X.Offset, frame.Size.Y.Offset
	if w <= 0 or h <= 0 or avail.X.Offset <= 0 or avail.Y.Offset <= 0 then
		return 1
	end
	return math.min(1, (avail.X.Offset - 16) / w, (avail.Y.Offset - 24) / h)
end

local panels: { [string]: PanelEntry } = {}
local pendingOpenFns: { [string]: { () -> () } } = {}
local openName: string? = nil
local panelRoot: Frame? = nil
local dim: TextButton? = nil

local function ensurePanelRoot(): Frame
	if panelRoot then
		return panelRoot
	end
	local _, root = Components.Screen("Panels", 20)
	local d = Instance.new("TextButton")
	d.Name = "Dim"
	d.Text = ""
	d.AutoButtonColor = false
	d.Size = UDim2.fromScale(1, 1)
	d.BackgroundColor3 = Color3.new(0, 0, 0)
	d.BackgroundTransparency = 1
	d.Visible = false
	d.ZIndex = 1
	d.Parent = root
	d.Activated:Connect(function()
		Components.ClosePanel()
	end)
	dim = d
	panelRoot = root
	return root
end

function Components.Panel(name: string, title: string, size: Vector2, color: Color3?): (Frame, Frame)
	local root = ensurePanelRoot()
	local accent = color or Theme.Colors.Green

	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(size.X, size.Y)
	frame.BackgroundColor3 = Theme.Colors.Panel
	frame.Visible = false
	frame.ZIndex = 2
	frame.Active = true
	Components.Corner(frame, 18)
	Components.Stroke(frame, 4, Theme.Colors.Stroke, true)
	local scale = Instance.new("UIScale")
	scale.Parent = frame

	-- title bar
	local bar = Instance.new("Frame")
	bar.Name = "TitleBar"
	bar.Size = UDim2.new(1, 0, 0, 52)
	bar.BackgroundColor3 = accent
	bar.ZIndex = 2
	Components.Corner(bar, 18)
	bar.Parent = frame
	-- square off the bottom corners of the bar
	local barFill = Instance.new("Frame")
	barFill.BorderSizePixel = 0
	barFill.BackgroundColor3 = accent
	barFill.Position = UDim2.new(0, 0, 1, -18)
	barFill.Size = UDim2.new(1, 0, 0, 18)
	barFill.ZIndex = 2
	barFill.Parent = bar

	Components.Label(bar, {
		name = "Title",
		text = title,
		font = Theme.TitleFont,
		size = UDim2.new(1, -140, 0, 40),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		stroke = 3,
		zIndex = 3,
	})

	Components.Button(bar, {
		name = "Close",
		text = "X",
		color = Theme.Colors.Red,
		size = UDim2.fromOffset(Theme.MinTouch, Theme.MinTouch),
		position = UDim2.new(1, 10, 0, -10),
		anchor = Vector2.new(1, 0),
		zIndex = 4,
		onClick = function()
			Components.ClosePanel()
		end,
	})

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(14, 62)
	body.Size = UDim2.new(1, -28, 1, -74)
	body.ZIndex = 2
	body.Parent = frame

	frame.Parent = root
	local entry: PanelEntry = { frame = frame, scale = scale, opened = pendingOpenFns[name] or {} }
	pendingOpenFns[name] = nil
	panels[name] = entry
	return frame, body
end

function Components.OnPanelOpened(name: string, fn: () -> ())
	local entry = panels[name]
	if entry then
		table.insert(entry.opened, fn)
	else
		local list = pendingOpenFns[name] or {}
		table.insert(list, fn)
		pendingOpenFns[name] = list
	end
end

function Components.IsOpen(name: string): boolean
	return openName == name
end

function Components.ClosePanel()
	local name = openName
	if not name then
		return
	end
	openName = nil
	local entry = panels[name]
	if entry then
		local t = Components.Tween(entry.scale, 0.15, { Scale = 0.7 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		t.Completed:Connect(function()
			if openName ~= name then
				entry.frame.Visible = false
			end
		end)
	end
	if dim then
		local d = dim
		Components.Tween(d, 0.15, { BackgroundTransparency = 1 }).Completed:Connect(function()
			if not openName then
				d.Visible = false
			end
		end)
	end
end

function Components.OpenPanel(name: string)
	local entry = panels[name]
	if not entry then
		warn(`[UI] unknown panel {name}`)
		return
	end
	if openName and openName ~= name then
		local old = panels[openName]
		if old then
			old.frame.Visible = false
		end
	end
	openName = name
	entry.frame.Visible = true
	local target = fitScale(entry.frame)
	if Components.ReduceMotion() then
		entry.scale.Scale = target
	else
		entry.scale.Scale = 0.6 * target
		Components.Tween(entry.scale, 0.25, { Scale = target }, Enum.EasingStyle.Back)
	end
	if dim then
		dim.Visible = true
		Components.Tween(dim, 0.2, { BackgroundTransparency = 0.45 })
	end
	for _, fn in entry.opened do
		task.spawn(fn)
	end
end

function Components.TogglePanel(name: string)
	if openName == name then
		Components.ClosePanel()
	else
		Components.OpenPanel(name)
	end
end

-- Scrolling list body for panels (vertical, auto canvas size).
function Components.ScrollList(parent: Instance, padding: number): ScrollingFrame
	local sf = Instance.new("ScrollingFrame")
	sf.Name = "List"
	sf.BackgroundTransparency = 1
	sf.BorderSizePixel = 0
	sf.Size = UDim2.fromScale(1, 1)
	sf.CanvasSize = UDim2.new()
	sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sf.ScrollingDirection = Enum.ScrollingDirection.Y
	sf.ScrollBarThickness = 8
	sf.ScrollBarImageColor3 = Theme.Colors.GreyDark
	sf.ZIndex = 2
	local l = Components.List(sf, padding)
	l.VerticalAlignment = Enum.VerticalAlignment.Top
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, 4)
	p.PaddingBottom = UDim.new(0, 4)
	p.PaddingRight = UDim.new(0, 10)
	p.Parent = sf
	sf.Parent = parent
	return sf
end

-- White rounded card for list rows.
function Components.Card(parent: Instance, height: number, order: number?): Frame
	local f = Instance.new("Frame")
	f.Name = "Card"
	f.Size = UDim2.new(1, 0, 0, height)
	f.BackgroundColor3 = Theme.Colors.Card
	f.LayoutOrder = order or 0
	f.ZIndex = 2
	Components.Corner(f, 12)
	Components.Stroke(f, 2, Theme.Colors.PanelDark, true)
	f.Parent = parent
	return f
end

-- Server time (workspace attributes are os.time() on the server).
function Components.Now(): number
	return workspace:GetServerTimeNow()
end

return Components
