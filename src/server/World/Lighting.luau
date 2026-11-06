--!strict
-- Bright, saturated afternoon look. Owner: A1 World & Map.

local Lighting = game:GetService("Lighting")

local LightingSetup = {}

local function replace(className: string, name: string): Instance
	local old = Lighting:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local inst = Instance.new(className)
	inst.Name = name
	return inst
end

function LightingSetup:Init()
	Lighting.ClockTime = 14
	Lighting.GeographicLatitude = 30
	Lighting.Brightness = 3
	Lighting.Ambient = Color3.fromRGB(105, 105, 115)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 160)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 247, 230)
	Lighting.ColorShift_Bottom = Color3.new(0, 0, 0)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25
	Lighting.FogStart = 0
	Lighting.FogEnd = 100000
	Lighting.ExposureCompensation = 0.1

	local atmosphere = replace("Atmosphere", "Atmosphere") :: Atmosphere
	atmosphere.Density = 0.22
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(199, 222, 255)
	atmosphere.Decay = Color3.fromRGB(120, 160, 210)
	atmosphere.Glare = 0
	atmosphere.Haze = 0.6
	atmosphere.Parent = Lighting

	local sky = replace("Sky", "Sky") :: Sky
	sky.CelestialBodiesShown = true
	sky.SunAngularSize = 14
	sky.MoonAngularSize = 8
	sky.StarCount = 0
	sky.Parent = Lighting

	local cc = replace("ColorCorrectionEffect", "FarmColor") :: ColorCorrectionEffect
	cc.Saturation = 0.18
	cc.Contrast = 0.06
	cc.Brightness = 0.02
	cc.TintColor = Color3.fromRGB(255, 252, 245)
	cc.Parent = Lighting

	local bloom = replace("BloomEffect", "FarmBloom") :: BloomEffect
	bloom.Intensity = 0.35
	bloom.Size = 24
	bloom.Threshold = 1.6
	bloom.Parent = Lighting
end

return LightingSetup
