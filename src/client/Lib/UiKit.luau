--!strict
-- Pure UI building blocks (no state, no panels). Plain module (not auto-loaded).
-- UI files import it as `C` by convention; the panel manager lives in UI/Components.
--
--   UiKit.Theme / UiKit.Colors / UiKit.Layers   (Lib/Theme: colors, fonts, sizes, DisplayOrders)
--   UiKit.Screen(name, displayOrder) -> (ScreenGui, root: Frame)
--       root is a full-screen frame laid out in Theme.ReferenceSize pixels (UIScale inside).
--   UiKit.Corner(parent, radius?) / Stroke(parent, thickness?, color?, border?) / Padding / List
--   UiKit.Label(parent, props) -> TextLabel
--   UiKit.Button(parent, props) -> (TextButton, TextLabel)
--   UiKit.SetButtonColor(button, color) / SetButtonEnabled(button, enabled)
--   UiKit.Tween(inst, time, props, style?, dir?) -> Tween
--   UiKit.CountUp(label, to, fmt, time?)  tweened number text (one NumberValue per label)
--   UiKit.Card(parent, height, order?) / ScrollList(parent, padding)
--   UiKit.Now() -> number                 server clock (Multipliers.Now, same as boost expiry)
--   UiKit.Rainbow(stroke)                 animated rainbow UIGradient on a UIStroke
--   UiKit.Darken(c, a) / Lighten(c, a)
--   UiKit.ReduceMotion() -> boolean       data.settings.reduceMotion (C6)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Multipliers = require(ReplicatedStorage.Shared.Multipliers)
local Theme = require(script.Parent.Theme)
local DataController = require(script.Parent.Parent.Controllers.DataController)

local UiKit = {}
UiKit.Theme = Theme
UiKit.Colors = Theme.Colors
UiKit.Layers = Theme.Layers

local player = Players.LocalPlayer

local function playerGui(): PlayerGui
	return player:WaitForChild("PlayerGui") :: PlayerGui
end

function UiKit.Tween(
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

function UiKit.Corner(parent: Instance, radius: number?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or Theme.Corner)
	c.Parent = parent
	return c
end

function UiKit.Stroke(parent: Instance, thickness: number?, color: Color3?, border: boolean?): UIStroke
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or Theme.StrokeThickness
	s.Color = color or Theme.Colors.Stroke
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.ApplyStrokeMode = if border then Enum.ApplyStrokeMode.Border else Enum.ApplyStrokeMode.Contextual
	s.Parent = parent
	return s
end

function UiKit.Padding(parent: Instance, px: number)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.Parent = parent
end

function UiKit.List(parent: Instance, padding: number, horizontal: boolean?, align: Enum.HorizontalAlignment?)
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

function UiKit.Label(parent: Instance, props: LabelProps): TextLabel
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
		UiKit.Stroke(l, strokeSize)
	end
	l.Parent = parent
	return l
end

-- True when the player turned on "Reduce motion" in Settings (skip bounces and popups).
function UiKit.ReduceMotion(): boolean
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

UiKit.Darken = darken
UiKit.Lighten = lighten

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
function UiKit.Button(parent: Instance, props: ButtonProps): (TextButton, TextLabel)
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
	UiKit.Corner(b)
	UiKit.Stroke(b, 3, Theme.Colors.Stroke, true)
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190))
	grad.Parent = b

	local scale = Instance.new("UIScale")
	scale.Parent = b

	local caption = UiKit.Label(b, {
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
		UiKit.Tween(scale, 0.06, { Scale = 0.92 })
	end)
	b.MouseButton1Up:Connect(function()
		UiKit.Tween(scale, 0.12, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	b.MouseLeave:Connect(function()
		UiKit.Tween(scale, 0.12, { Scale = 1 })
	end)
	b.MouseEnter:Connect(function()
		if b:GetAttribute("Enabled") then
			UiKit.Tween(scale, 0.1, { Scale = 1.04 })
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

function UiKit.SetButtonColor(b: GuiObject, color: Color3)
	b:SetAttribute("BaseColor", color)
	if b:GetAttribute("Enabled") ~= false then
		b.BackgroundColor3 = color
	end
end

-- Disabled buttons turn grey but still receive clicks (onClick is skipped while disabled).
function UiKit.SetButtonEnabled(b: GuiObject, enabled: boolean)
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
function UiKit.CountUp(label: TextLabel, to: number, fmt: (number) -> string, time: number?)
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
	UiKit.Tween(nv, time or 0.45, { Value = to }, Enum.EasingStyle.Quart)
end

-- Animated rainbow on a UIStroke (or any instance that can hold a UIGradient).
function UiKit.Rainbow(target: Instance): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = Theme.Rainbow
	g.Parent = target
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		if not g.Parent then
			conn:Disconnect()
			return
		end
		if not UiKit.ReduceMotion() then
			g.Rotation = (os.clock() * 120) % 360
		end
	end)
	return g
end

-- Root frame sized so that after UIScale it exactly covers the ScreenGui.
function UiKit.Screen(name: string, displayOrder: number): (ScreenGui, Frame)
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

-- Scrolling list body for panels (vertical, auto canvas size).
function UiKit.ScrollList(parent: Instance, padding: number): ScrollingFrame
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
	local l = UiKit.List(sf, padding)
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
function UiKit.Card(parent: Instance, height: number, order: number?): Frame
	local f = Instance.new("Frame")
	f.Name = "Card"
	f.Size = UDim2.new(1, 0, 0, height)
	f.BackgroundColor3 = Theme.Colors.Card
	f.LayoutOrder = order or 0
	f.ZIndex = 2
	UiKit.Corner(f, 12)
	UiKit.Stroke(f, 2, Theme.Colors.PanelDark, true)
	f.Parent = parent
	return f
end

-- Server time: the same clock as boost expiry (Multipliers.Now). Workspace timer attributes are
-- os.time() on the server, which is the same Unix scale.
UiKit.Now = Multipliers.Now

return UiKit
