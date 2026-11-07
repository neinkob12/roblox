--!strict
-- C6: Reserved top-center banner stack, so the event chip, truck banner, tutorial banner and
-- toasts never overlap. Banners are laid out top to bottom by LayoutOrder; hidden banners
-- take no space. No Init/Start (created lazily on first use).
--
--   TopStack.Add(frame, order)   reparent a banner into the stack (its Position is ignored)
--   TopStack.Bottom() -> number  current bottom edge in reference px (Theme.ReferenceSize)
--   TopStack.Changed             Signal fired when Bottom() changes
--
-- Suggested orders: 10 event chip, 20 truck banner, 30 tutorial banner (C4).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Signal)
local C = require(script.Parent.Components)

local TOP = 8
local GAP = 6

local TopStack = {}
TopStack.Changed = Signal.new()

local holder: Frame? = nil
local layout: UIListLayout? = nil

local function ensure(): Frame
	if holder then
		return holder
	end
	local _, root = C.Screen("TopStack", 7)
	local f = Instance.new("Frame")
	f.Name = "Stack"
	f.BackgroundTransparency = 1
	f.AnchorPoint = Vector2.new(0.5, 0)
	f.Position = UDim2.new(0.5, 0, 0, TOP)
	f.Size = UDim2.fromOffset(420, 0)
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.Active = false
	f.Parent = root
	local l = C.List(f, GAP)
	l.VerticalAlignment = Enum.VerticalAlignment.Top
	l:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		TopStack.Changed:Fire(TopStack.Bottom())
	end)
	holder = f
	layout = l
	return f
end

function TopStack.Add(frame: GuiObject, order: number)
	local f = ensure()
	frame.AnchorPoint = Vector2.zero
	frame.Position = UDim2.new()
	frame.LayoutOrder = order
	frame.Parent = f
end

function TopStack.Bottom(): number
	ensure()
	local l = layout
	local f = holder
	if not l or not f then
		return TOP
	end
	-- AbsoluteContentSize is in real pixels; convert back to reference px via the root UIScale.
	local root = f.Parent
	local scaleObj = if root then root:FindFirstChildOfClass("UIScale") else nil
	local s = if scaleObj and scaleObj.Scale > 0 then scaleObj.Scale else 1
	local h = l.AbsoluteContentSize.Y / s
	return TOP + h
end

return TopStack
