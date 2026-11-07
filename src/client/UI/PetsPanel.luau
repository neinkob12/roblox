--!strict
-- F2: Pets panel ("Pets"), opened from the Menu.
--   Header: tabs Pets / Index, an Eggs button (opens the Egg Shop), "12/50 pets · 3/5 equipped"
--           and the total boosts (milk %, cash %, speed %, luck %, index milk).
--   Pets tab: 50-slot inventory grid (rarity colors, variant badges, equipped mark). Tapping a pet
--     selects it; the detail pane shows it with Equip/Unequip (RequestEquipPet), "Merge 5 into
--     Golden/Rainbow" (RequestMergePets) and "Merge all" (every group that has 5).
--   Index tab: the 45 entries (15 pets x 3 variants), silhouettes for undiscovered ones and the
--     "+2% milk per 5" milestone.
--   Menu badge "Pets" = ready eggs in nests + an available free egg.
-- Data shapes: F1 PetService/EggService headers (data.pets, equippedPets, petIndex, nests).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Pets = require(ReplicatedStorage.Shared.Config.Pets)
local Eggs = require(ReplicatedStorage.Shared.Config.Eggs)
local Multipliers = require(ReplicatedStorage.Shared.Multipliers)
local C = require(script.Parent.Parent.Lib.UiKit)
local PetViewport = require(script.Parent.Parent.Lib.PetViewport)
local Panels = require(script.Parent.Components)
local Menu = require(script.Parent.Menu)
local DataController = require(script.Parent.Parent.Controllers.DataController)

local Colors = C.Colors
local Theme = C.Theme

local PANEL = Vector2.new(700, 396)
local CELL = 64
local CELL_GAP = 6
local GRID_W = 440
local MERGE_GAP = 0.35 -- seconds between merge requests (server debounce is 0.3)

type PetRow = { uid: string, id: string, variant: string, equipped: boolean, order: number }

local PetsPanel = {}

local tab = "pets"
local tabButtons: { [string]: TextButton } = {}
local countLabel: TextLabel
local boostLabel: TextLabel
local petsPage: Frame
local indexPage: Frame
local grid: ScrollingFrame
local indexGrid: ScrollingFrame
local indexHeader: TextLabel
local detailVp: Frame
local detailName: TextLabel
local detailBoost: TextLabel
local emptyHint: TextLabel
local equipBtn: TextButton
local equipCaption: TextLabel
local mergeBtn: TextButton
local mergeCaption: TextLabel
local mergeAllBtn: TextButton

local selected: string? = nil
local gridDirty = true
local indexDirty = true
local cellCleanups: { () -> () } = {}
local indexCleanups: { () -> () } = {}
local detailCleanup: (() -> ())? = nil
local merging = false
local cellsByUid: { [string]: TextButton } = {}

------------------------------------------------------------------------------ data helpers

local function data(): any
	return DataController:Get()
end

local function petsTable(): { [string]: any }
	local d = data()
	return if d and typeof(d.pets) == "table" then d.pets else {}
end

local function equippedList(): { string }
	local d = data()
	return if d and typeof(d.equippedPets) == "table" then d.equippedPets else {}
end

local function slots(): number
	local d = data()
	return Pets.SlotsFor(if d and typeof(d.rebirths) == "number" then d.rebirths else 0)
end

local function rarityOrder(id: string): number
	local pet = Pets.ById[id]
	local r = pet and Pets.RarityById[pet.rarity]
	return if r then r.order else 0
end

local function variantOrder(v: string): number
	local def = Pets.VariantById[v]
	return if def then def.order else 0
end

local function rows(): { PetRow }
	local eq: { [string]: number } = {}
	for i, uid in equippedList() do
		eq[uid] = i
	end
	local out: { PetRow } = {}
	for uid, pet in petsTable() do
		if typeof(pet) == "table" and typeof(pet.id) == "string" and Pets.ById[pet.id] then
			local variant = if typeof(pet.variant) == "string" then pet.variant else "normal"
			table.insert(
				out,
				{ uid = uid, id = pet.id, variant = variant, equipped = eq[uid] ~= nil, order = eq[uid] or 99 }
			)
		end
	end
	table.sort(out, function(a, b)
		if a.equipped ~= b.equipped then
			return a.equipped
		end
		if a.equipped then
			return a.order < b.order
		end
		local ra, rb = rarityOrder(a.id), rarityOrder(b.id)
		if ra ~= rb then
			return ra > rb
		end
		local va, vb = variantOrder(a.variant), variantOrder(b.variant)
		if va ~= vb then
			return va > vb
		end
		if a.id ~= b.id then
			return a.id < b.id
		end
		return a.uid < b.uid
	end)
	return out
end

-- how many pets of this id + variant the player owns
local function countOf(id: string, variant: string): number
	local n = 0
	for _, pet in petsTable() do
		if typeof(pet) == "table" and pet.id == id and pet.variant == variant then
			n += 1
		end
	end
	return n
end

-- every id:variant group that can merge right now -> number of merges
local function mergeGroups(): { { id: string, variant: string, times: number } }
	local counts: { [string]: number } = {}
	for _, pet in petsTable() do
		if typeof(pet) == "table" and typeof(pet.id) == "string" and typeof(pet.variant) == "string" then
			local key = pet.id .. ":" .. pet.variant
			counts[key] = (counts[key] or 0) + 1
		end
	end
	local out = {}
	for key, n in counts do
		local id, variant = string.match(key, "^(.-):(.+)$")
		if id and variant and Pets.NextVariant[variant] and n >= Pets.MergeCount then
			table.insert(out, { id = id, variant = variant, times = math.floor(n / Pets.MergeCount) })
		end
	end
	table.sort(out, function(a, b)
		return a.id .. a.variant < b.id .. b.variant
	end)
	return out
end

------------------------------------------------------------------------------ header

local function refreshHeader()
	local d = data()
	local owned = 0
	for _ in petsTable() do
		owned += 1
	end
	countLabel.Text = `{owned}/{Pets.MaxInventory} pets · {#equippedList()}/{slots()} equipped`
	local function pct(kind: string): string
		return PetViewport.Percent(if d then Multipliers.PetBonus(d, kind) else 0)
	end
	local index = (if d then Multipliers.PetIndexMilk(d) else 1) - 1
	boostLabel.Text =
		`Milk +{pct("milk")}  Cash +{pct("cash")}  Speed +{pct("speed")}  Luck +{pct("luck")}  Index +{PetViewport.Percent(
			index
		)} milk`
end

------------------------------------------------------------------------------ detail

local function selectedRow(): PetRow?
	if not selected then
		return nil
	end
	local pet = petsTable()[selected]
	if typeof(pet) ~= "table" or not Pets.ById[pet.id] then
		return nil
	end
	local eq = false
	for _, uid in equippedList() do
		if uid == selected then
			eq = true
		end
	end
	return { uid = selected, id = pet.id, variant = pet.variant or "normal", equipped = eq, order = 0 }
end

local function refreshDetail()
	if detailCleanup then
		detailCleanup()
		detailCleanup = nil
	end
	local row = selectedRow()
	local groups = mergeGroups()
	C.SetButtonEnabled(mergeAllBtn, #groups > 0 and not merging)
	if not row then
		detailName.Text = ""
		detailBoost.Text = ""
		emptyHint.Visible = true
		C.SetButtonEnabled(equipBtn, false)
		equipCaption.Text = "Equip"
		C.SetButtonEnabled(mergeBtn, false)
		mergeCaption.Text = "Merge 5"
		return
	end
	emptyHint.Visible = false
	local pet = Pets.ById[row.id]
	local rarity = Pets.RarityById[pet.rarity]
	local vDef = Pets.VariantById[row.variant]
	detailName.Text = (if vDef and row.variant ~= "normal" then vDef.name .. " " else "") .. pet.name
	detailBoost.Text = `{rarity.name} · {PetViewport.BoostText(row.id, row.variant)}`
	detailBoost.TextColor3 = C.Darken(rarity.color, 0.2)
	detailCleanup = PetViewport.Mount(detailVp, row.id, row.variant, { spin = 1 })

	if row.equipped then
		equipCaption.Text = "Unequip"
		C.SetButtonColor(equipBtn, Colors.Red)
		C.SetButtonEnabled(equipBtn, true)
	else
		local full = #equippedList() >= slots()
		equipCaption.Text = if full then "Slots full" else "Equip"
		C.SetButtonColor(equipBtn, Colors.Green)
		C.SetButtonEnabled(equipBtn, not full)
	end

	local nextV = Pets.NextVariant[row.variant]
	local have = countOf(row.id, row.variant)
	if nextV then
		local nDef = Pets.VariantById[nextV]
		mergeCaption.Text = `Merge {Pets.MergeCount} into {if nDef then nDef.name else nextV} ({math.min(
			have,
			Pets.MergeCount
		)}/{Pets.MergeCount})`
		C.SetButtonEnabled(mergeBtn, have >= Pets.MergeCount and not merging)
	else
		mergeCaption.Text = "Max variant"
		C.SetButtonEnabled(mergeBtn, false)
	end
end

------------------------------------------------------------------------------ grid

local VARIANT_BADGE: { [string]: { text: string, color: Color3 } } = {
	golden = { text = "G", color = Colors.Yellow },
	rainbow = { text = "R", color = Colors.Pink },
}

local function cellFrame(parent: Instance, name: string, color: Color3, order: number): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	b.AutoButtonColor = false
	b.Size = UDim2.fromOffset(CELL, CELL)
	b.BackgroundColor3 = C.Lighten(color, 0.55)
	b.LayoutOrder = order
	b.ZIndex = 3
	C.Corner(b, 10)
	C.Stroke(b, 3, color, true)
	b.Parent = parent
	return b
end

local function badge(parent: Instance, text: string, color: Color3, pos: UDim2, anchor: Vector2)
	local l = C.Label(parent, {
		name = "Badge",
		text = text,
		size = UDim2.fromOffset(20, 20),
		position = pos,
		anchor = anchor,
		stroke = 2,
		zIndex = 5,
	})
	l.BackgroundTransparency = 0
	l.BackgroundColor3 = color
	C.Corner(l, 10)
end

local function clearCleanups(list: { () -> () })
	for _, fn in list do
		fn()
	end
	table.clear(list)
end

local function highlightSelected()
	for uid, cell in cellsByUid do
		local stroke = cell:FindFirstChildOfClass("UIStroke")
		local base = cell:GetAttribute("RarityColor")
		if stroke then
			stroke.Color = if uid == selected
				then Colors.Stroke
				elseif typeof(base) == "Color3" then base
				else Colors.Grey
			stroke.Thickness = if uid == selected then 4 else 3
		end
	end
end

local function rebuildGrid()
	gridDirty = false
	clearCleanups(cellCleanups)
	for _, child in grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(cellsByUid)
	local list = rows()
	if selected and not petsTable()[selected] then
		selected = nil
	end
	if not selected and list[1] then
		selected = list[1].uid
	end
	for i, row in list do
		local color = PetViewport.RarityColor(row.id)
		local cell = cellFrame(grid, "Pet_" .. row.uid, color, i)
		cell:SetAttribute("RarityColor", color)
		cellsByUid[row.uid] = cell
		local holder = Instance.new("Frame")
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.new(1, -6, 1, -6)
		holder.Position = UDim2.fromOffset(3, 3)
		holder.ZIndex = 4
		holder.Parent = cell
		table.insert(cellCleanups, (PetViewport.Mount(holder, row.id, row.variant)))
		local vb = VARIANT_BADGE[row.variant]
		if vb then
			badge(cell, vb.text, vb.color, UDim2.new(1, 4, 0, -4), Vector2.new(1, 0))
		end
		if row.equipped then
			badge(cell, "E", Colors.Green, UDim2.new(0, -4, 1, 4), Vector2.new(0, 1))
		end
		local uid = row.uid
		cell.Activated:Connect(function()
			selected = uid
			highlightSelected()
			refreshDetail()
		end)
	end
	highlightSelected()
	-- empty slots up to the cap, so "50 slots" reads at a glance
	for i = #list + 1, Pets.MaxInventory do
		local f = Instance.new("Frame")
		f.Name = "Empty"
		f.Size = UDim2.fromOffset(CELL, CELL)
		f.BackgroundColor3 = Colors.PanelDark
		f.BackgroundTransparency = 0.4
		f.LayoutOrder = i
		f.ZIndex = 3
		C.Corner(f, 10)
		f.Parent = grid
	end
end

local function rebuildIndex()
	indexDirty = false
	clearCleanups(indexCleanups)
	for _, child in indexGrid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local d = data()
	local idx = if d and typeof(d.petIndex) == "table" then d.petIndex else {}
	local found = 0
	local order = 0
	for _, v in Pets.Variants do
		for _, pet in Pets.List do
			order += 1
			local key = Pets.IndexKey(pet.id, v.id)
			local known = idx[key] == true
			if known then
				found += 1
			end
			local rarity = Pets.RarityById[pet.rarity]
			local cell = cellFrame(indexGrid, "Index_" .. key, if known then rarity.color else Colors.Grey, order)
			local holder = Instance.new("Frame")
			holder.BackgroundTransparency = 1
			holder.Size = UDim2.new(1, -6, 1, -18)
			holder.Position = UDim2.fromOffset(3, 2)
			holder.ZIndex = 4
			holder.Parent = cell
			table.insert(indexCleanups, (PetViewport.Mount(holder, pet.id, v.id, { silhouette = not known })))
			C.Label(cell, {
				name = "Name",
				text = if known then pet.name else "???",
				color = Colors.TextDark,
				size = UDim2.new(1, -4, 0, 14),
				position = UDim2.new(0.5, 0, 1, -2),
				anchor = Vector2.new(0.5, 1),
				stroke = 0,
				zIndex = 5,
			})
			local vb = VARIANT_BADGE[v.id]
			if vb then
				badge(cell, vb.text, vb.color, UDim2.new(1, 4, 0, -4), Vector2.new(1, 0))
			end
		end
	end
	local steps = math.floor(found / Pets.IndexStep)
	local toNext = Pets.IndexStep - found % Pets.IndexStep
	indexHeader.Text =
		`Discovered {found}/{Pets.IndexSize} · +{PetViewport.Percent(Pets.IndexMilkPerStep)} milk per {Pets.IndexStep} (now +{PetViewport.Percent(
			steps * Pets.IndexMilkPerStep
		)}, {if found >= Pets.IndexSize then "complete!" else `{toNext} more for the next`})`
end

------------------------------------------------------------------------------ actions

local function onEquip()
	local row = selectedRow()
	if not row then
		return
	end
	Net.Event("RequestEquipPet"):FireServer(row.uid, not row.equipped)
end

local function runMerges(list: { { id: string, variant: string, times: number } })
	if merging or #list == 0 then
		return
	end
	merging = true
	refreshDetail()
	task.spawn(function()
		for _, g in list do
			for _ = 1, g.times do
				Net.Event("RequestMergePets"):FireServer(g.id, g.variant)
				task.wait(MERGE_GAP)
			end
		end
		merging = false
		refreshDetail()
	end)
end

local function onMerge()
	local row = selectedRow()
	if row and Pets.NextVariant[row.variant] and countOf(row.id, row.variant) >= Pets.MergeCount then
		runMerges({ { id = row.id, variant = row.variant, times = 1 } })
	end
end

------------------------------------------------------------------------------ refresh

local function setTab(name: string)
	tab = name
	petsPage.Visible = name == "pets"
	indexPage.Visible = name == "index"
	for n, b in tabButtons do
		C.SetButtonColor(b, if n == name then Colors.Orange else Colors.Grey)
	end
	if name == "pets" and gridDirty then
		rebuildGrid()
	elseif name == "index" and indexDirty then
		rebuildIndex()
	end
	refreshDetail()
end

local function onDataChanged(key: string)
	if key == "pets" or key == "equippedPets" or key == "rebirths" then
		gridDirty = true
	end
	if key == "petIndex" then
		indexDirty = true
	end
	if not Panels.IsOpen("Pets") then
		return
	end
	refreshHeader()
	if tab == "pets" and gridDirty then
		rebuildGrid()
	elseif tab == "index" and indexDirty then
		rebuildIndex()
	end
	refreshDetail()
end

-- Menu badge: eggs ready to hatch + the free egg
local function refreshBadge()
	local d = data()
	if not d then
		return
	end
	local now = Multipliers.Now()
	local n = 0
	if typeof(d.nests) == "table" then
		for _, nest in d.nests do
			if typeof(nest) == "table" and typeof(nest.readyAt) == "number" and nest.readyAt <= now then
				n += 1
			end
		end
	end
	local last = if typeof(d.lastFreeEgg) == "number" then d.lastFreeEgg else 0
	if last + Eggs.FreeEggSeconds <= now then
		n += 1
	end
	Menu.SetBadge("Pets", n)
end

------------------------------------------------------------------------------ build

function PetsPanel:Init()
	local _, body = Panels.Panel("Pets", "PETS", PANEL, Colors.Orange)

	-- header row: tabs + Eggs button + count/boosts
	for i, def in { { id = "pets", text = "Pets" }, { id = "index", text = "Index" } } do
		local b = C.Button(body, {
			name = "Tab_" .. def.id,
			text = def.text,
			color = Colors.Grey,
			size = UDim2.fromOffset(96, Theme.MinTouch),
			position = UDim2.fromOffset((i - 1) * 102, 0),
			zIndex = 3,
			onClick = function()
				setTab(def.id)
			end,
		})
		tabButtons[def.id] = b
	end
	C.Button(body, {
		name = "Eggs",
		text = "🥚 Eggs",
		color = Colors.Pink,
		size = UDim2.fromOffset(96, Theme.MinTouch),
		position = UDim2.fromOffset(204, 0),
		zIndex = 3,
		onClick = function()
			Panels.OpenPanel("EggShop")
		end,
	})
	countLabel = C.Label(body, {
		name = "Count",
		text = "",
		color = Colors.TextDark,
		size = UDim2.new(1, -312, 0, 30),
		position = UDim2.fromScale(1, 0),
		anchor = Vector2.new(1, 0),
		align = Enum.TextXAlignment.Right,
		stroke = 0,
		zIndex = 3,
	})
	boostLabel = C.Label(body, {
		name = "Boosts",
		text = "",
		color = Colors.GreenDark,
		size = UDim2.new(1, -312, 0, 26),
		position = UDim2.new(1, 0, 0, 34),
		anchor = Vector2.new(1, 0),
		align = Enum.TextXAlignment.Right,
		stroke = 0,
		zIndex = 3,
	})

	local contentTop = Theme.MinTouch + 6
	local function page(name: string): Frame
		local f = Instance.new("Frame")
		f.Name = name
		f.BackgroundTransparency = 1
		f.Position = UDim2.fromOffset(0, contentTop)
		f.Size = UDim2.new(1, 0, 1, -contentTop)
		f.ZIndex = 2
		f.Parent = body
		return f
	end

	-- Pets page: grid + detail pane
	petsPage = page("PetsPage")
	local gridHolder = Instance.new("Frame")
	gridHolder.Name = "GridHolder"
	gridHolder.BackgroundTransparency = 1
	gridHolder.Size = UDim2.new(0, GRID_W, 1, 0)
	gridHolder.ZIndex = 2
	gridHolder.Parent = petsPage
	grid = C.ScrollList(gridHolder, CELL_GAP)
	local list = grid:FindFirstChildOfClass("UIListLayout")
	if list then
		list:Destroy()
	end
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CELL, CELL)
	layout.CellPadding = UDim2.fromOffset(CELL_GAP, CELL_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	local detail = Instance.new("Frame")
	detail.Name = "Detail"
	detail.BackgroundColor3 = Colors.Card
	detail.Position = UDim2.fromOffset(GRID_W + 8, 0)
	detail.Size = UDim2.new(1, -(GRID_W + 8), 1, 0)
	detail.ZIndex = 2
	C.Corner(detail, 12)
	C.Stroke(detail, 2, Colors.PanelDark, true)
	detail.Parent = petsPage
	local vpHolder = Instance.new("Frame")
	vpHolder.Name = "View"
	vpHolder.BackgroundTransparency = 1
	vpHolder.Size = UDim2.new(1, 0, 0, 64)
	vpHolder.ZIndex = 3
	vpHolder.Parent = detail
	detailVp = vpHolder
	detailName = C.Label(detail, {
		name = "PetName",
		text = "",
		color = Colors.TextDark,
		size = UDim2.new(1, -12, 0, 22),
		position = UDim2.fromOffset(6, 64),
		stroke = 0,
		zIndex = 3,
	})
	detailBoost = C.Label(detail, {
		name = "Boost",
		text = "",
		color = Colors.GreyDark,
		size = UDim2.new(1, -12, 0, 20),
		position = UDim2.fromOffset(6, 88),
		stroke = 0,
		zIndex = 3,
	})
	emptyHint = C.Label(detail, {
		name = "Empty",
		text = "No pets yet!\nHatch an egg in your nests.",
		color = Colors.GreyDark,
		size = UDim2.new(1, -12, 0, 60),
		position = UDim2.fromOffset(6, 30),
		stroke = 0,
		zIndex = 3,
	})
	local half = UDim2.new(0.5, -9, 0, Theme.MinTouch)
	equipBtn, equipCaption = C.Button(detail, {
		name = "Equip",
		text = "Equip",
		color = Colors.Green,
		size = half,
		position = UDim2.fromOffset(6, 114),
		zIndex = 3,
		onClick = onEquip,
	})
	mergeBtn, mergeCaption = C.Button(detail, {
		name = "Merge",
		text = "Merge 5",
		color = Colors.Purple,
		size = half,
		position = UDim2.new(0.5, 3, 0, 114),
		zIndex = 3,
		onClick = onMerge,
	})
	mergeAllBtn = C.Button(detail, {
		name = "MergeAll",
		text = "Merge all",
		color = Colors.PurpleDark,
		size = UDim2.new(1, -12, 0, Theme.MinTouch),
		position = UDim2.fromOffset(6, 184),
		zIndex = 3,
		onClick = function()
			runMerges(mergeGroups())
		end,
	})

	-- Index page
	indexPage = page("IndexPage")
	indexHeader = C.Label(indexPage, {
		name = "Header",
		text = "",
		color = Colors.TextDark,
		size = UDim2.new(1, 0, 0, 24),
		stroke = 0,
		zIndex = 3,
	})
	local indexHolder = Instance.new("Frame")
	indexHolder.Name = "IndexHolder"
	indexHolder.BackgroundTransparency = 1
	indexHolder.Position = UDim2.fromOffset(0, 28)
	indexHolder.Size = UDim2.new(1, 0, 1, -28)
	indexHolder.ZIndex = 2
	indexHolder.Parent = indexPage
	indexGrid = C.ScrollList(indexHolder, CELL_GAP)
	local il = indexGrid:FindFirstChildOfClass("UIListLayout")
	if il then
		il:Destroy()
	end
	local igl = Instance.new("UIGridLayout")
	igl.CellSize = UDim2.fromOffset(CELL, CELL)
	igl.CellPadding = UDim2.fromOffset(CELL_GAP, CELL_GAP)
	igl.SortOrder = Enum.SortOrder.LayoutOrder
	igl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	igl.Parent = indexGrid
	indexPage.Visible = false
end

function PetsPanel:Start()
	DataController.Changed:Connect(function(key: string)
		if key == "pets" or key == "equippedPets" or key == "rebirths" or key == "petIndex" then
			onDataChanged(key)
		end
		if key == "nests" or key == "lastFreeEgg" then
			refreshBadge()
		end
	end)
	Panels.OnPanelOpened("Pets", function()
		refreshHeader()
		setTab(tab)
	end)
	task.spawn(function()
		while true do
			refreshBadge()
			task.wait(1)
		end
	end)
end

return PetsPanel
