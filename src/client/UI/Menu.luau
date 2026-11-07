--!strict
-- B1: Side buttons on the right edge (2 columns x 4 rows, anchored top-right so they stay
-- above the mobile jump button; C6 added Index and moved the grid up, see docs/MOBILE_AUDIT.md).
-- Each one toggles a panel registered with Components.Panel(name, ...).

local Theme = require(script.Parent.Parent.Lib.Theme)
local C = require(script.Parent.Parent.Lib.UiKit)
local Panels = require(script.Parent.Components)

local Colors = Theme.Colors

local BUTTONS = {
	{ panel = "Upgrades", icon = "⬆️", label = "Upgrades", color = Colors.Green },
	{ panel = "Rebirth", icon = "🔁", label = "Rebirth", color = Colors.Pink },
	{ panel = "Crates", icon = "📦", label = "Crates", color = Colors.Yellow },
	{ panel = "Quests", icon = "📜", label = "Quests", color = Colors.Blue },
	{ panel = "Shop", icon = "🛒", label = "Shop", color = Colors.Purple },
	{ panel = "Index", icon = "📖", label = "Index", color = Colors.Orange },
	{ panel = "Daily", icon = "🎁", label = "Daily", color = Colors.Red }, -- E1 DailyPanel (popup, not a panel)
	{ panel = "Settings", icon = "⚙️", label = "Settings", color = Colors.Grey },
}

local SIZE = 64
local GAP = 8

local Menu = {}

-- Small red badge (e.g. unopened crates, claimable quests). Other UI modules call this.
local badges: { [string]: TextLabel } = {}
-- Buttons whose target is not a Components panel (e.g. the Daily popup) register a click action.
local actions: { [string]: () -> () } = {}
function Menu.SetAction(panel: string, fn: () -> ())
	actions[panel] = fn
end

function Menu.SetBadge(panel: string, count: number)
	local b = badges[panel]
	if not b then
		return
	end
	b.Visible = count > 0
	b.Text = if count > 99 then "99+" else tostring(count)
end

function Menu:Init()
	local _, root = C.Screen("Menu", Theme.Layers.Menu)
	local holder = Instance.new("Frame")
	holder.Name = "SideButtons"
	holder.BackgroundTransparency = 1
	local rows = math.ceil(#BUTTONS / 2)
	holder.AnchorPoint = Vector2.new(1, 0)
	holder.Position = UDim2.new(1, -10, 0, 10)
	holder.Size = UDim2.fromOffset(SIZE * 2 + GAP, SIZE * rows + GAP * (rows - 1))
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
				local action = actions[def.panel]
				if action then
					action()
				else
					Panels.TogglePanel(def.panel)
				end
			end,
		})
		caption.Size = UDim2.new(1, -16, 0.6, -4)
		caption.Position = UDim2.fromScale(0.5, 0.36)
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
