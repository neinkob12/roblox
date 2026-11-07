--!strict
-- B1: Settings. Music / SFX / Voice toggles (RequestSetting(name, value), state from
-- data.settings) and a code redeem box (Net.Function "RedeemCode" -> ok, message).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local Notifications = require(script.Parent.Notifications)
local DataController = require(script.Parent.Parent.Controllers.DataController)

local Colors = Theme.Colors

local TOGGLES = {
	{ key = "music", label = "🎵 Music" },
	{ key = "sfx", label = "🔊 Sound effects" },
	{ key = "voice", label = "🗣️ Cow voices" },
}

local REDEEM_TIMEOUT = 8

local SettingsPanel = {}

type Toggle = { button: TextButton, caption: TextLabel }
local toggles: { [string]: Toggle } = {}
-- local optimistic state, until the server replicates data.settings
local pending: { [string]: boolean } = {}

local codeBox: TextBox
local redeemBtn: TextButton
local redeemCaption: TextLabel
local redeeming = false

local function current(key: string): boolean
	if pending[key] ~= nil then
		return pending[key]
	end
	local data = DataController:Get()
	local settings = if data and typeof(data.settings) == "table" then data.settings else nil
	if settings and typeof(settings[key]) == "boolean" then
		return settings[key]
	end
	return true
end

local function refresh()
	for key, t in toggles do
		local on = current(key)
		t.caption.Text = if on then "ON" else "OFF"
		C.SetButtonColor(t.button, if on then Colors.Green else Colors.Red)
	end
end

local function redeem()
	if redeeming then
		return
	end
	local code = string.gsub(codeBox.Text, "^%s*(.-)%s*$", "%1")
	if code == "" then
		Notifications.Show("Type a code first!", "error")
		return
	end
	redeeming = true
	redeemCaption.Text = "..."
	C.SetButtonEnabled(redeemBtn, false)

	local answered = false
	task.spawn(function()
		local ok, success, message = pcall(function()
			return Net.Function("RedeemCode"):InvokeServer(code)
		end)
		if answered then
			return
		end
		answered = true
		if not ok then
			Notifications.Show("Could not check the code, try again.", "error")
		elseif success then
			Notifications.Show(if typeof(message) == "string" then message else "Code redeemed!", "success")
			codeBox.Text = ""
		else
			Notifications.Show(if typeof(message) == "string" then message else "Invalid code", "error")
		end
		redeeming = false
		redeemCaption.Text = "REDEEM"
		C.SetButtonEnabled(redeemBtn, true)
	end)
	task.delay(REDEEM_TIMEOUT, function()
		if answered then
			return
		end
		answered = true
		Notifications.Show("Codes are not available right now.", "error")
		redeeming = false
		redeemCaption.Text = "REDEEM"
		C.SetButtonEnabled(redeemBtn, true)
	end)
end

function SettingsPanel:Init()
	local _, body = C.Panel("Settings", "SETTINGS", Vector2.new(480, 340), Colors.Grey)

	for i, def in TOGGLES do
		local y = (i - 1) * 62
		C.Label(body, {
			name = def.key .. "Label",
			text = def.label,
			color = Colors.TextDark,
			size = UDim2.fromOffset(260, 34),
			position = UDim2.fromOffset(8, y + 11),
			align = Enum.TextXAlignment.Left,
			stroke = 0,
		})
		local key = def.key
		local button, caption = C.Button(body, {
			name = key,
			text = "ON",
			color = Colors.Green,
			size = UDim2.fromOffset(120, Theme.MinTouch),
			position = UDim2.new(1, -8, 0, y),
			anchor = Vector2.new(1, 0),
			onClick = function()
				local value = not current(key)
				pending[key] = value
				refresh()
				Net.Event("RequestSetting"):FireServer(key, value)
			end,
		})
		toggles[key] = { button = button, caption = caption }
	end

	-- code redeem
	local y = #TOGGLES * 62 + 8
	local boxFrame = Instance.new("Frame")
	boxFrame.Name = "CodeFrame"
	boxFrame.BackgroundColor3 = Colors.Card
	boxFrame.Position = UDim2.fromOffset(8, y)
	boxFrame.Size = UDim2.new(1, -170, 0, Theme.MinTouch)
	boxFrame.Parent = body
	C.Corner(boxFrame, 12)
	C.Stroke(boxFrame, 3, Colors.Stroke, true)
	codeBox = Instance.new("TextBox")
	codeBox.Name = "Code"
	codeBox.BackgroundTransparency = 1
	codeBox.Size = UDim2.new(1, -20, 1, -12)
	codeBox.Position = UDim2.fromScale(0.5, 0.5)
	codeBox.AnchorPoint = Vector2.new(0.5, 0.5)
	codeBox.Font = Theme.Font
	codeBox.TextScaled = true
	codeBox.PlaceholderText = "Enter code"
	codeBox.PlaceholderColor3 = Colors.Grey
	codeBox.Text = ""
	codeBox.TextColor3 = Colors.TextDark
	codeBox.ClearTextOnFocus = false
	codeBox.TextXAlignment = Enum.TextXAlignment.Left
	codeBox.Parent = boxFrame
	codeBox.FocusLost:Connect(function(enter)
		if enter then
			redeem()
		end
	end)

	redeemBtn, redeemCaption = C.Button(body, {
		name = "Redeem",
		text = "REDEEM",
		color = Colors.Blue,
		size = UDim2.fromOffset(150, Theme.MinTouch),
		position = UDim2.new(1, -8, 0, y),
		anchor = Vector2.new(1, 0),
		onClick = redeem,
	})
end

function SettingsPanel:Start()
	DataController:OnChanged("settings", function()
		-- server state arrived; drop optimistic values it confirmed
		local data = DataController:Get()
		local settings = if data and typeof(data.settings) == "table" then data.settings else {}
		for key, value in pending do
			if settings[key] == value then
				pending[key] = nil
			end
		end
		refresh()
	end)
	C.OnPanelOpened("Settings", refresh)
	refresh()
end

return SettingsPanel
