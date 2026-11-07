--!strict
-- B1: Side buttons on the right edge (2 columns x 3 rows, above the mobile jump button).
-- Each one toggles a panel registered with Components.Panel(name, ...).

local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)

local Colors = Theme.Colors

local BUTTONS = {
	{ panel = "Upgrades", icon = "⬆️", label = "Upgrades", color = Colors.Green },
	{ panel = "Rebirth", icon = "🔁", label = "Rebirth", color = Colors.Pink },
	{ panel = "Crates", icon = "📦", label = "Crates", color = Colors.Yellow },
	{ panel = "Quests", icon = "📜", label = "Quests", color = Colors.Blue },
	{ panel = "Shop", icon = "🛒", label = "Shop", color = Colors.Purple },
	{ panel = "Settings", icon = "⚙️", label = "Settings", color = Colors.Grey },
}

local SIZE = 64
local GAP = 8

local Menu = {}

-- Small red badge (e.g. unopened crates, claimable quests). Other UI modules call this.
local badges: { [string]: TextLabel } = {}
function Menu.SetBadge(panel: string, count: number)
	local b = badges[panel]
	if not b then
		return
	end
	b.Visible = count > 0
	b.Text = if count > 99 then "99+" else tostring(count)
end

function Menu:Init()
	local _, root = C.Screen("Menu", 6)
	local holder = Instance.new("Frame")
	holder.Name = "SideButtons"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(1, 0.5)
	holder.Position = UDim2.new(1, -10, 0.42, 0)
	holder.Size = UDim2.fromOffset(SIZE * 2 + GAP, SIZE * 3 + GAP * 2)
	holder.Parent = root
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(SIZE, SIZE)
	grid.CellPadding = UDim2.fromOffset(GAP, GAP)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = holder

	for i, def in BUTTONS do
		local b, caption = C.Button(holder, {
			name = def.panel,
			text = def.icon,
			color = def.color,
			order = i,
			onClick = function()
				C.TogglePanel(def.panel)
			end,
		})
		caption.Size = UDim2.new(1, -16, 0.6, -4)
		caption.Position = UDim2.new(0.5, 0, 0.36, 0)
		local stroke = caption:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Enabled = false
		end
		C.Label(b, {
			name = "Name",
			text = def.label,
			size = UDim2.new(1, -4, 0.3, 0),
			position = UDim2.new(0.5, 0, 1, -4),
			anchor = Vector2.new(0.5, 1),
			stroke = 2,
			zIndex = b.ZIndex + 1,
		})
		local badge = C.Label(b, {
			name = "Badge",
			text = "0",
			size = UDim2.fromOffset(24, 24),
			position = UDim2.new(1, 6, 0, -6),
			anchor = Vector2.new(1, 0),
			stroke = 2,
			zIndex = b.ZIndex + 2,
		})
		badge.BackgroundTransparency = 0
		badge.BackgroundColor3 = Colors.Red
		badge.Visible = false
		C.Corner(badge, 12)
		badges[def.panel] = badge
	end
end

return Menu
