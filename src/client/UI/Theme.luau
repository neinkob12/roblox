--!strict
-- B1: Colors, fonts and sizes for every screen. Pure data (no Init/Start).
--
-- Layout is designed at a REFERENCE resolution (iPhone landscape, ~900x420 logical px) in
-- plain pixel offsets. Components.Screen() adds a UIScale that maps the reference size to
-- the real viewport, so everything stays proportional on phones, tablets and PC.

local Theme = {}

Theme.ReferenceSize = Vector2.new(900, 420)
Theme.MinScale = 0.7
Theme.MaxScale = 1.6
Theme.MinTouch = 56 -- reference px; * MinScale (0.79 on iPhone landscape) stays >= 44 real px

Theme.Font = Enum.Font.FredokaOne
Theme.TitleFont = Enum.Font.LuckiestGuy

Theme.Colors = {
	Text = Color3.fromRGB(255, 255, 255),
	TextDark = Color3.fromRGB(40, 30, 50),
	Stroke = Color3.fromRGB(25, 15, 35),

	Green = Color3.fromRGB(80, 210, 90),
	GreenDark = Color3.fromRGB(40, 150, 55),
	Red = Color3.fromRGB(235, 70, 70),
	RedDark = Color3.fromRGB(170, 40, 45),
	Blue = Color3.fromRGB(70, 160, 255),
	BlueDark = Color3.fromRGB(40, 105, 200),
	Yellow = Color3.fromRGB(255, 205, 50),
	YellowDark = Color3.fromRGB(215, 150, 20),
	Purple = Color3.fromRGB(175, 95, 255),
	PurpleDark = Color3.fromRGB(115, 55, 195),
	Orange = Color3.fromRGB(255, 145, 50),
	OrangeDark = Color3.fromRGB(205, 95, 25),
	Pink = Color3.fromRGB(255, 110, 180),
	PinkDark = Color3.fromRGB(200, 60, 130),
	Grey = Color3.fromRGB(150, 150, 160),
	GreyDark = Color3.fromRGB(95, 95, 105),

	Panel = Color3.fromRGB(255, 245, 225),
	PanelDark = Color3.fromRGB(235, 215, 180),
	Card = Color3.fromRGB(255, 255, 255),
	Chip = Color3.fromRGB(30, 25, 45),
	Milk = Color3.fromRGB(245, 250, 255),
	Cash = Color3.fromRGB(120, 255, 120),
}

-- Notify kinds -> background color
Theme.NotifyColors = {
	info = Theme.Colors.Blue,
	success = Theme.Colors.Green,
	error = Theme.Colors.Red,
	rare = Theme.Colors.Purple,
}

Theme.Rainbow = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 70)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 190, 40)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(90, 230, 90)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(60, 190, 255)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(170, 90, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 70, 70)),
})

Theme.Corner = 14
Theme.StrokeThickness = 3

return Theme
