--!strict
-- C6: Cow Index. A grid of all Cows.Count cows.
--   Discovered (data.discovered[tostring(tier)]): the real model in a ViewportFrame, name, milk/s.
--   Undiscovered: the same model as a black silhouette and "???".
--   Header: "x/18 discovered". Tapping a discovered cow closes the panel and replays
--   DiscoveryController:Show(tier).
-- Viewports are built lazily the first time the panel opens (18 small static models).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cows = require(ReplicatedStorage.Shared.Config.Cows)
local Format = require(ReplicatedStorage.Shared.Format)
local Theme = require(script.Parent.Parent.Lib.Theme)
local C = require(script.Parent.Parent.Lib.UiKit)
local Panels = require(script.Parent.Components)
local DataController = require(script.Parent.Parent.Controllers.DataController)
local DiscoveryController = require(script.Parent.Parent.Controllers.DiscoveryController)
local CowViewport = require(script.Parent.Parent.Lib.CowViewport)

local Colors = Theme.Colors

local COLUMNS = 4
local CELL_H = 150
local CELL_GAP = 10

local IndexPanel = {}

type Cell = {
	button: TextButton,
	viewport: ViewportFrame,
	name: TextLabel,
	mps: TextLabel,
	built: boolean,
}

local cells: { [number]: Cell } = {}
local header: TextLabel
local headerFill: Frame
local built = false

local function isDiscovered(data: any, tier: number): boolean
	if not data or typeof(data.discovered) ~= "table" then
		return false
	end
	return data.discovered[tostring(tier)] == true
end

-- Put the cow model in the viewport, framed from the front-left (front = -Z).
local function buildViewport(cell: Cell, tier: number)
	if cell.built then
		return
	end
	cell.built = true
	CowViewport.Mount(cell.viewport, tier)
end

local function refresh()
	local data = DataController:Get()
	local found = 0
	for tier, cell in cells do
		local cow = Cows.Get(tier)
		local known = isDiscovered(data, tier)
		if known then
			found += 1
		end
		if built then
			buildViewport(cell, tier)
		end
		if known and cow then
			cell.viewport.ImageColor3 = Color3.new(1, 1, 1)
			cell.button.BackgroundColor3 = C.Lighten(cow.bodyColor, 0.35)
			cell.name.Text = cow.name
			cell.mps.Text = `{Format.Number(cow.milkPerSecond)} milk/s`
			cell.mps.Visible = true
		else
			-- black silhouette of the real shape
			cell.viewport.ImageColor3 = Color3.new(0, 0, 0)
			cell.button.BackgroundColor3 = Colors.GreyDark
			cell.name.Text = "???"
			cell.mps.Text = `Tier {tier}`
			cell.mps.Visible = true
		end
	end
	header.Text = `{found}/{Cows.Count} discovered`
	C.Tween(headerFill, 0.3, { Size = UDim2.fromScale(math.clamp(found / math.max(Cows.Count, 1), 0, 1), 1) })
end

function IndexPanel:Init()
	local _, body = Panels.Panel("Index", "COW INDEX", Vector2.new(600, 380), Colors.Orange)

	-- header: progress text over a bar
	local bar = Instance.new("Frame")
	bar.Name = "Progress"
	bar.BackgroundColor3 = Colors.PanelDark
	bar.Size = UDim2.new(1, -10, 0, 28)
	bar.Position = UDim2.fromOffset(0, 0)
	bar.ZIndex = 2
	bar.Parent = body
	C.Corner(bar, 14)
	C.Stroke(bar, 2, Colors.Stroke, true)
	headerFill = Instance.new("Frame")
	headerFill.Name = "Fill"
	headerFill.BackgroundColor3 = Colors.Orange
	headerFill.Size = UDim2.fromScale(0, 1)
	headerFill.ZIndex = 2
	headerFill.Parent = bar
	C.Corner(headerFill, 14)
	header = C.Label(bar, {
		name = "Count",
		text = `0/{Cows.Count} discovered`,
		size = UDim2.new(1, -16, 1, -4),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		zIndex = 3,
	})

	local holder = Instance.new("Frame")
	holder.Name = "GridHolder"
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.fromOffset(0, 36)
	holder.Size = UDim2.new(1, 0, 1, -36)
	holder.ZIndex = 2
	holder.Parent = body

	local list = C.ScrollList(holder, CELL_GAP)
	-- swap the vertical list for a grid
	local oldLayout = list:FindFirstChildOfClass("UIListLayout")
	if oldLayout then
		oldLayout:Destroy()
	end
	local grid = Instance.new("UIGridLayout")
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.CellPadding = UDim2.fromOffset(CELL_GAP, CELL_GAP)
	grid.CellSize = UDim2.new(1 / COLUMNS, -CELL_GAP, 0, CELL_H)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.Parent = list

	for tier = 1, Cows.Count do
		local button = Instance.new("TextButton")
		button.Name = "Cow" .. tier
		button.Text = ""
		button.AutoButtonColor = false
		button.BackgroundColor3 = Colors.GreyDark
		button.LayoutOrder = tier
		button.ZIndex = 2
		C.Corner(button, 12)
		C.Stroke(button, 3, Colors.Stroke, true)
		local press = Instance.new("UIScale")
		press.Parent = button

		local vp = Instance.new("ViewportFrame")
		vp.Name = "Model"
		vp.BackgroundTransparency = 1
		vp.Size = UDim2.new(1, -8, 1, -50)
		vp.Position = UDim2.fromOffset(4, 4)
		vp.ImageColor3 = Color3.new(0, 0, 0)
		vp.ZIndex = 3
		vp.Active = false
		vp.Parent = button

		local name = C.Label(button, {
			name = "CowName",
			text = "???",
			size = UDim2.new(1, -10, 0, 24),
			position = UDim2.new(0.5, 0, 1, -24),
			anchor = Vector2.new(0.5, 1),
			stroke = 2,
			zIndex = 4,
		})
		local mps = C.Label(button, {
			name = "MilkPerSecond",
			text = `Tier {tier}`,
			color = Colors.Milk,
			size = UDim2.new(1, -10, 0, 18),
			position = UDim2.new(0.5, 0, 1, -4),
			anchor = Vector2.new(0.5, 1),
			stroke = 2,
			zIndex = 4,
		})

		button.MouseButton1Down:Connect(function()
			C.Tween(press, 0.06, { Scale = 0.94 })
		end)
		button.MouseButton1Up:Connect(function()
			C.Tween(press, 0.12, { Scale = 1 }, Enum.EasingStyle.Back)
		end)
		button.MouseLeave:Connect(function()
			C.Tween(press, 0.12, { Scale = 1 })
		end)
		local t = tier
		button.Activated:Connect(function()
			if not isDiscovered(DataController:Get(), t) then
				return
			end
			Panels.ClosePanel()
			DiscoveryController:Show(t)
		end)

		button.Parent = list
		cells[tier] = { button = button, viewport = vp, name = name, mps = mps, built = false }
	end
end

function IndexPanel:Start()
	DataController:OnChanged("discovered", refresh)
	Panels.OnPanelOpened("Index", function()
		built = true
		refresh()
	end)
	refresh()
end

return IndexPanel
