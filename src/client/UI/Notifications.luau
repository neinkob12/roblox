--!strict
-- B1: Toasts. Net "Notify"(text, kind) stacks toasts top-center, colored by kind
-- (info / success / error / rare). "rare" gets an animated rainbow stroke.
-- Also the "Welcome back" popup on Net "OfflineEarnings"(milk, seconds).
--
--   Notifications.Show(text, kind?)   local toast from any UI module

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Format = require(ReplicatedStorage.Shared.Format)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local TopStack = require(script.Parent.TopStack)

local Colors = Theme.Colors

local MAX_TOASTS = 4
local LIFETIME = 3.2
local RARE_LIFETIME = 4.5

local Notifications = {}

local root: Frame
local stack: Frame
local popupRoot: Frame
local order = 0

local function removeToast(toast: Frame)
	if toast:GetAttribute("Leaving") then
		return
	end
	toast:SetAttribute("Leaving", true)
	local s = toast:FindFirstChildOfClass("UIScale")
	if s then
		C.Tween(s, 0.18, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	end
	task.delay(0.2, function()
		toast:Destroy()
	end)
end

function Notifications.Show(text: string, kind: string?)
	if typeof(text) ~= "string" or text == "" then
		return
	end
	local k = if typeof(kind) == "string" and Theme.NotifyColors[kind] then kind else "info"
	order += 1

	local toast = Instance.new("Frame")
	toast.Name = "Toast"
	toast.Size = UDim2.fromOffset(380, 38)
	toast.BackgroundColor3 = Theme.NotifyColors[k]
	toast.LayoutOrder = -order -- newest on top
	toast.Active = false
	C.Corner(toast, 12)
	local stroke = C.Stroke(toast, if k == "rare" then 4 else 3, Colors.Stroke, true)
	if k == "rare" then
		stroke.Color = Color3.new(1, 1, 1)
		C.Rainbow(stroke)
	end
	local s = Instance.new("UIScale")
	s.Scale = 0.3
	s.Parent = toast
	C.Label(toast, {
		name = "Text",
		text = text,
		size = UDim2.new(1, -16, 1, -8),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		stroke = 2,
	})
	toast.Parent = stack
	C.Tween(s, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)

	-- trim the oldest
	local toasts = {}
	for _, child in stack:GetChildren() do
		if child:IsA("Frame") and not child:GetAttribute("Leaving") then
			table.insert(toasts, child)
		end
	end
	table.sort(toasts, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = MAX_TOASTS + 1, #toasts do
		removeToast(toasts[i])
	end

	task.delay(if k == "rare" then RARE_LIFETIME else LIFETIME, function()
		if toast.Parent then
			removeToast(toast)
		end
	end)
end

------------------------------------------------------------------------- welcome back

local function welcomeBack(milk: number, seconds: number)
	if typeof(milk) ~= "number" or milk <= 0 then
		return
	end
	local secs = if typeof(seconds) == "number" then seconds else 0

	local dim = Instance.new("TextButton")
	dim.Name = "WelcomeBack"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.Parent = popupRoot
	C.Tween(dim, 0.2, { BackgroundTransparency = 0.45 })

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(420, 250)
	card.BackgroundColor3 = Colors.Panel
	card.Active = true
	card.Parent = dim
	C.Corner(card, 18)
	C.Stroke(card, 4, Colors.Stroke, true)
	local s = Instance.new("UIScale")
	s.Scale = 0.4
	s.Parent = card
	C.Tween(s, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)

	C.Label(card, {
		name = "Title",
		text = "WELCOME BACK!",
		font = Theme.TitleFont,
		color = Colors.Yellow,
		size = UDim2.new(1, -20, 0, 46),
		position = UDim2.fromOffset(10, 10),
		stroke = 3,
	})
	C.Label(card, {
		name = "Away",
		text = `You were away for {Format.Time(secs)}`,
		color = Colors.TextDark,
		size = UDim2.new(1, -20, 0, 24),
		position = UDim2.fromOffset(10, 62),
		stroke = 0,
	})
	C.Label(card, {
		name = "Milk",
		text = `🥛 +{Format.Number(math.floor(milk))} milk`,
		font = Theme.TitleFont,
		color = Colors.Milk,
		size = UDim2.new(1, -20, 0, 48),
		position = UDim2.fromOffset(10, 92),
		stroke = 3,
	})
	C.Label(card, {
		name = "Hint",
		text = "Your cows filled your tank. Sell it at the dairy!",
		color = Colors.GreyDark,
		size = UDim2.new(1, -20, 0, 20),
		position = UDim2.fromOffset(10, 144),
		stroke = 0,
	})

	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		C.Tween(s, 0.18, { Scale = 0.5 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		C.Tween(dim, 0.2, { BackgroundTransparency = 1 })
		task.delay(0.22, function()
			dim:Destroy()
		end)
	end
	C.Button(card, {
		name = "Ok",
		text = "AWESOME!",
		font = Theme.TitleFont,
		color = Colors.Green,
		size = UDim2.fromOffset(220, 60),
		position = UDim2.new(0.5, 0, 1, -12),
		anchor = Vector2.new(0.5, 1),
		onClick = close,
	})
	dim.Activated:Connect(close)
end

function Notifications:Init()
	local _, r = C.Screen("Notifications", Theme.Layers.Toasts)
	root = r
	stack = Instance.new("Frame")
	stack.Name = "Stack"
	stack.BackgroundTransparency = 1
	stack.AnchorPoint = Vector2.new(0.5, 0)
	stack.Position = UDim2.new(0.5, 0, 0, 90)
	stack.Size = UDim2.fromOffset(400, 200)
	stack.Active = false
	stack.Parent = root
	local l = C.List(stack, 6)
	l.VerticalAlignment = Enum.VerticalAlignment.Top
	-- toasts sit right under the top-center banner stack (C6)
	local function place()
		stack.Position = UDim2.new(0.5, 0, 0, TopStack.Bottom() + 8)
	end
	TopStack.Changed:Connect(place)
	place()

	local _, p = C.Screen("Popups", Theme.Layers.Popups)
	popupRoot = p

	Net.Event("Notify").OnClientEvent:Connect(function(text: string, kind: string)
		Notifications.Show(text, kind)
	end)
	Net.Event("OfflineEarnings").OnClientEvent:Connect(function(milk: number, seconds: number)
		welcomeBack(milk, seconds)
	end)
end

return Notifications
