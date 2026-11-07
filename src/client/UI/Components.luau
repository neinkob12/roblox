--!strict
-- B1: The panel manager. Pure building blocks (Label, Button, Tween, Screen...) live in Lib/UiKit.
-- No Init/Start.
--
--   Components.Panel(name, title, size, color?) -> (panel: Frame, body: Frame)
--   Components.OpenPanel(name) / ClosePanel() / TogglePanel(name) / IsOpen(name)
--   Components.OnPanelOpened(name, fn)

local C = require(script.Parent.Parent.Lib.UiKit)
local Theme = C.Theme

local Components = {}

type PanelEntry = { frame: Frame, scale: UIScale, opened: { () -> () } }

-- C6: center a panel in the area left of the side menu (the menu draws above the dimmer, see
-- Theme.Layers) and shrink it when it would not fit (tiny phones where UIScale hits MinScale).
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
	local areaW = avail.X.Offset - Theme.MenuReserve
	frame.Position = UDim2.new(0, areaW / 2, 0.5, 0)
	return math.min(1, (areaW - 16) / w, (avail.Y.Offset - 24) / h)
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
	local _, root = C.Screen("Panels", Theme.Layers.Panels)
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
	C.Corner(frame, 18)
	C.Stroke(frame, 4, Theme.Colors.Stroke, true)
	local scale = Instance.new("UIScale")
	scale.Parent = frame

	-- title bar
	local bar = Instance.new("Frame")
	bar.Name = "TitleBar"
	bar.Size = UDim2.new(1, 0, 0, 52)
	bar.BackgroundColor3 = accent
	bar.ZIndex = 2
	C.Corner(bar, 18)
	bar.Parent = frame
	-- square off the bottom corners of the bar
	local barFill = Instance.new("Frame")
	barFill.BorderSizePixel = 0
	barFill.BackgroundColor3 = accent
	barFill.Position = UDim2.new(0, 0, 1, -18)
	barFill.Size = UDim2.new(1, 0, 0, 18)
	barFill.ZIndex = 2
	barFill.Parent = bar

	C.Label(bar, {
		name = "Title",
		text = title,
		font = Theme.TitleFont,
		size = UDim2.new(1, -140, 0, 40),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		stroke = 3,
		zIndex = 3,
	})

	C.Button(bar, {
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
		local t = C.Tween(entry.scale, 0.15, { Scale = 0.7 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		t.Completed:Connect(function()
			if openName ~= name then
				entry.frame.Visible = false
			end
		end)
	end
	if dim then
		local d = dim
		C.Tween(d, 0.15, { BackgroundTransparency = 1 }).Completed:Connect(function()
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
	if C.ReduceMotion() then
		entry.scale.Scale = target
	else
		entry.scale.Scale = 0.6 * target
		C.Tween(entry.scale, 0.25, { Scale = target }, Enum.EasingStyle.Back)
	end
	if dim then
		dim.Visible = true
		C.Tween(dim, 0.2, { BackgroundTransparency = 0.45 })
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

return Components
