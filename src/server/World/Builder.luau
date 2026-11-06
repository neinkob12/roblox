--!strict
-- Small helpers for building the map out of plain Parts (no Toolbox, no meshes).
-- Library only (no Init/Start). Owner: A1 World & Map.
--
-- Conventions used by every World module:
--   * Every part is Anchored, SmoothPlastic, smooth surfaces.
--   * Decor parts (Builder.decor) have CanCollide = false and CanTouch = false.
--   * Pipes (Builder.pipe) are cylinders whose local +X axis points in the flow
--     direction (from point a to point b).

local Builder = {}

Builder.partCount = 0

Builder.Font = Enum.Font.FredokaOne

export type Props = { [string]: any }

local function apply(inst: Instance, props: Props)
	local parent = props.Parent
	for key, value in props do
		if key ~= "Parent" then
			(inst :: any)[key] = value
		end
	end
	if parent then
		inst.Parent = parent
	end
end

-- Creates an anchored part. props may contain any BasePart property plus Parent.
-- Pass className = "SpawnLocation" / "WedgePart" etc. for other part classes.
function Builder.part(props: Props, className: string?): BasePart
	local p = Instance.new(className or "Part") :: BasePart
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	-- Shape first so Size is not clamped afterwards
	local shape = props.Shape
	if shape ~= nil and p:IsA("Part") then
		p.Shape = shape
	end
	apply(p, props)
	Builder.partCount += 1
	return p
end

-- Decorative part: never blocks the player and never fires Touched.
function Builder.decor(props: Props): BasePart
	local p = Builder.part(props)
	p.CanCollide = false
	p.CanTouch = false
	return p
end

-- Builds a CFrame at `pos` whose +X axis points along `dir` (any direction, also vertical).
function Builder.axisCFrame(pos: Vector3, dir: Vector3): CFrame
	local x = dir.Unit
	local ref = if math.abs(x.Y) > 0.9 then Vector3.zAxis else Vector3.yAxis
	local y = (ref - x * ref:Dot(x)).Unit
	return CFrame.fromMatrix(pos, x, y)
end

-- Cylinder from world point a to world point b. +X axis = flow direction a -> b.
function Builder.pipe(a: Vector3, b: Vector3, diameter: number, props: Props): BasePart
	local delta = b - a
	local p = Builder.decor(props)
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(delta.Magnitude, diameter, diameter)
	p.CFrame = Builder.axisCFrame((a + b) / 2, delta)
	return p
end

-- Ball joint (hides the seams where pipes bend).
function Builder.ball(pos: Vector3, diameter: number, props: Props): BasePart
	local p = Builder.decor(props)
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(diameter, diameter, diameter)
	p.CFrame = CFrame.new(pos)
	return p
end

-- Vertical-axis cylinder (disk, pillar, bottle...). `bottomCenter` is the center of the bottom face.
function Builder.vcyl(bottomCenter: Vector3, radius: number, height: number, props: Props): BasePart
	local p = Builder.part(props)
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(height, radius * 2, radius * 2)
	p.CFrame = CFrame.new(bottomCenter + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	return p
end

local function makeText(name: string, text: string, parent: Instance): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Builder.Font
	t.Text = text
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0
	t.TextStrokeColor3 = Color3.fromRGB(30, 30, 40)
	t.Parent = parent
	return t
end

-- BillboardGui with a TextLabel, e.g. pad labels: Builder.billboard(pad, "Label", "Text", "Buy x5", ...)
function Builder.billboard(
	adornee: BasePart,
	guiName: string,
	textName: string,
	text: string,
	widthStuds: number,
	heightStuds: number,
	offsetY: number
): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = guiName
	gui.Size = UDim2.fromScale(widthStuds, heightStuds) -- scale = studs for BillboardGui
	gui.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 150
	gui.ResetOnSpawn = false
	gui.Adornee = adornee
	makeText(textName, text, gui)
	gui.Parent = adornee
	return gui
end

-- Pad label per CONTRACTS: BillboardGui "Label" > TextLabel "Text".
function Builder.padLabel(pad: BasePart, text: string): BillboardGui
	return Builder.billboard(pad, "Label", "Text", text, 10, 2.5, 4)
end

-- SurfaceGui on the part's Front face. If textName is given, adds a TextLabel with that name.
function Builder.surface(part: BasePart, guiName: string, textName: string?, text: string?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = guiName
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Adornee = part
	if textName then
		local label = makeText(textName, text or "", gui)
		label.Size = UDim2.fromScale(0.94, 0.86)
		label.Position = UDim2.fromScale(0.03, 0.07)
	end
	gui.Parent = part
	return gui
end

function Builder.folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

return Builder
