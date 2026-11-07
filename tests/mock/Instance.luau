--!nocheck
-- Instance tree mock: classes with inheritance, default properties, computed properties,
-- events, attributes, Parent/Changed/ChildAdded bookkeeping, Destroy, Clone, WaitForChild.
--
-- Reading a property that is neither set nor has a default raises
-- "X is not a valid member of Class", like Roblox. That catches typos in child names.
-- Writing is permissive (any property name is accepted).

local S = require("./Scheduler")
local Signal = require("./Signal")
local D = require("./Datatypes")

local Vector3, Vector2, CFrame, Color3, UDim, UDim2, Enum =
	D.Vector3, D.Vector2, D.CFrame, D.Color3, D.UDim, D.UDim2, D.Enum

local M = {}

local InstMT = { __type = "Instance" }
local internal: { [any]: any } = setmetatable({}, { __mode = "k" })
M.internal = internal

local classes = {}
local resolvedCache = {}
M.classes = classes

-- Stats about mock gaps, printed at the end of a run.
M.unknownReads = {}

local NIL = newproxy(false) -- default value meaning "nil, but this property exists"
M.NIL = NIL

function M.defineClass(name: string, def)
	def = def or {}
	def.name = name
	def.props = def.props or {}
	def.methods = def.methods or {}
	def.events = def.events or {}
	def.getters = def.getters or {}
	def.setters = def.setters or {}
	classes[name] = def
	table.clear(resolvedCache)
	return def
end

function M.extend(name: string, part)
	local def = classes[name] or M.defineClass(name, { super = part.super })
	for _, key in { "props", "methods", "getters", "setters" } do
		if part[key] then
			for k, v in part[key] do
				def[key][k] = v
			end
		end
	end
	if part.events then
		for _, e in part.events do
			table.insert(def.events, e)
		end
	end
	if part.creatable ~= nil then
		def.creatable = part.creatable
	end
	if part.init then
		def.init = part.init
	end
	table.clear(resolvedCache)
	return def
end

local function resolve(className: string)
	local r = resolvedCache[className]
	if r then
		return r
	end
	local chain = {}
	local c = classes[className]
	while c do
		table.insert(chain, 1, c)
		c = c.super and classes[c.super]
	end
	r = { props = {}, methods = {}, events = {}, getters = {}, setters = {}, isa = {}, inits = {} }
	for _, def in chain do
		r.isa[def.name] = true
		for k, v in def.props do
			r.props[k] = v
		end
		for k, v in def.methods do
			r.methods[k] = v
		end
		for _, e in def.events do
			r.events[e] = true
		end
		for k, v in def.getters do
			r.getters[k] = v
		end
		for k, v in def.setters do
			r.setters[k] = v
		end
		if def.init then
			table.insert(r.inits, def.init)
		end
	end
	resolvedCache[className] = r
	return r
end
M.resolve = resolve

local function I(inst)
	local d = internal[inst]
	if not d then
		error("not an Instance", 3)
	end
	return d
end
M.I = I

function M.is(v)
	return type(v) == "table" and getmetatable(v) == InstMT
end
local isInstance = M.is

---------------------------------------------------------------- events helpers
local function getSignal(inst, name)
	local d = internal[inst]
	local s = d.signals[name]
	if not s then
		s = Signal.new(`{d.className}.{name}`)
		d.signals[name] = s
	end
	return s
end
M.getSignal = getSignal

local function fireIfExists(inst, name, ...)
	local d = internal[inst]
	local s = d and d.signals[name]
	if s then
		s:Fire(...)
	end
end
M.fire = fireIfExists

local function propChanged(inst, prop, value)
	local d = internal[inst]
	if d.isValue and prop == "Value" then
		fireIfExists(inst, "Changed", value)
	elseif not d.isValue then
		fireIfExists(inst, "Changed", prop)
	end
	local ps = d.propSignals[prop]
	if ps then
		ps:Fire()
	end
end
M.propChanged = propChanged

---------------------------------------------------------------- construction
function M.new(className: string, parent: any?)
	local def = classes[className]
	if not def or def.creatable == false then
		error(`Unable to create an Instance of type "{className}"`, 2)
	end
	return M.create(className, parent)
end

-- create bypasses the creatable check (used for services, players, characters)
function M.create(className: string, parent: any?)
	if not classes[className] then
		error(`[mock] unknown class {className}`, 2)
	end
	local inst = setmetatable({}, InstMT)
	local r = resolve(className)
	internal[inst] = {
		className = className,
		r = r,
		name = className,
		parent = nil,
		children = {},
		props = {},
		attrs = {},
		signals = {},
		propSignals = {},
		attrSignals = {},
		tags = {},
		destroyed = false,
		isValue = r.isa.ValueBase == true,
		id = M.nextId(),
	}
	for _, init in r.inits do
		init(inst, internal[inst])
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local idCounter = 0
function M.nextId()
	idCounter += 1
	return idCounter
end

---------------------------------------------------------------- tree helpers
local function isAncestorOf(a, b)
	local p = internal[b].parent
	while p do
		if p == a then
			return true
		end
		p = internal[p].parent
	end
	return false
end

local function descendants(inst, out)
	for _, c in internal[inst].children do
		table.insert(out, c)
		descendants(c, out)
	end
	return out
end
M.descendants = function(inst)
	return descendants(inst, {})
end

local function setParent(inst, newParent)
	local d = internal[inst]
	if newParent ~= nil and not isInstance(newParent) then
		error(`Unable to assign property Parent. Instance expected, got {D.typeof(newParent)}`, 3)
	end
	if d.parentLocked then
		error(
			`The Parent property of {d.name} is locked, current parent: {if d.parent
				then internal[d.parent].name
				else "NULL"}, new parent {if newParent then internal[newParent].name else "NULL"}`,
			3
		)
	end
	local old = d.parent
	if old == newParent then
		return
	end
	if newParent and (newParent == inst or isAncestorOf(inst, newParent)) then
		error(`Attempt to set parent of {d.name} to {internal[newParent].name} would result in circular reference`, 3)
	end
	local moving = descendants(inst, { inst })
	if old then
		-- DescendantRemoving fires on old ancestors before removal
		local a = old
		while a do
			for _, x in moving do
				fireIfExists(a, "DescendantRemoving", x)
			end
			a = internal[a].parent
		end
		local list = internal[old].children
		for i, c in list do
			if c == inst then
				table.remove(list, i)
				break
			end
		end
		d.parent = nil
		fireIfExists(old, "ChildRemoved", inst)
	end
	d.parent = newParent
	if newParent then
		table.insert(internal[newParent].children, inst)
	end
	for _, x in moving do
		fireIfExists(x, "AncestryChanged", inst, newParent)
	end
	propChanged(inst, "Parent")
	if newParent then
		fireIfExists(newParent, "ChildAdded", inst)
		local a = newParent
		while a do
			for _, x in moving do
				fireIfExists(a, "DescendantAdded", x)
			end
			a = internal[a].parent
		end
	end
end

---------------------------------------------------------------- metatable
InstMT.__index = function(inst, key)
	local d = internal[inst]
	local r = d.r
	local m = r.methods[key]
	if m then
		return m
	end
	local g = r.getters[key]
	if g then
		return g(inst, d)
	end
	local v = d.props[key]
	if v ~= nil then
		return v
	end
	local def = r.props[key]
	if def ~= nil then
		if def == NIL then
			return nil
		end
		return def
	end
	if r.events[key] then
		return getSignal(inst, key)
	end
	if type(key) == "string" then
		for _, c in d.children do
			if internal[c].name == key then
				return c
			end
		end
	end
	local k = `{d.className}.{tostring(key)}`
	M.unknownReads[k] = (M.unknownReads[k] or 0) + 1
	error(`{tostring(key)} is not a valid member of {d.className} "{M.fullName(inst)}"`, 2)
end

InstMT.__newindex = function(inst, key, value)
	local d = internal[inst]
	local r = d.r
	local setter = r.setters[key]
	if setter then
		setter(inst, d, value)
		return
	end
	if r.methods[key] or r.events[key] or r.getters[key] then
		error(`{key} cannot be assigned to ({d.className})`, 2)
	end
	local old = d.props[key]
	if old == nil then
		local def = r.props[key]
		if def ~= NIL then
			old = def
		end
	end
	d.props[key] = value
	if old ~= value then
		propChanged(inst, key, value)
	end
end

InstMT.__tostring = function(inst)
	return internal[inst].name
end

-- Set a property without firing Changed (internal use)
function M.rawSet(inst, key, value)
	internal[inst].props[key] = value
end

function M.fullName(inst)
	local parts = {}
	local x = inst
	while x do
		local d = internal[x]
		if d.className == "DataModel" then
			break
		end
		table.insert(parts, 1, d.name)
		x = d.parent
	end
	return table.concat(parts, ".")
end

---------------------------------------------------------------- attributes
local ATTR_TYPES = {
	string = true,
	boolean = true,
	number = true,
	UDim = true,
	UDim2 = true,
	Vector2 = true,
	Vector3 = true,
	Color3 = true,
	CFrame = true,
	NumberRange = true,
	NumberSequence = true,
	ColorSequence = true,
	Rect = true,
	BrickColor = true,
	Font = true,
	EnumItem = true,
}

---------------------------------------------------------------- Instance base class
M.defineClass("Instance", {
	creatable = false,
	props = { Archivable = true },
	events = {
		"Changed",
		"ChildAdded",
		"ChildRemoved",
		"DescendantAdded",
		"DescendantRemoving",
		"AncestryChanged",
		"Destroying",
		"AttributeChanged",
	},
	getters = {
		Name = function(_, d)
			return d.name
		end,
		Parent = function(_, d)
			return d.parent
		end,
		ClassName = function(_, d)
			return d.className
		end,
	},
	setters = {
		Name = function(inst, d, v)
			v = tostring(v)
			if d.name ~= v then
				d.name = v
				propChanged(inst, "Name")
			end
		end,
		Parent = function(inst, _, v)
			setParent(inst, v)
		end,
	},
	methods = {
		IsA = function(self, name)
			return I(self).r.isa[name] == true
		end,
		GetChildren = function(self)
			return table.clone(I(self).children)
		end,
		GetDescendants = function(self)
			return descendants(self, {})
		end,
		FindFirstChild = function(self, name, recursive)
			for _, c in I(self).children do
				if internal[c].name == name then
					return c
				end
			end
			if recursive then
				for _, c in descendants(self, {}) do
					if internal[c].name == name then
						return c
					end
				end
			end
			return nil
		end,
		FindFirstChildOfClass = function(self, cls)
			for _, c in I(self).children do
				if internal[c].className == cls then
					return c
				end
			end
			return nil
		end,
		FindFirstChildWhichIsA = function(self, cls, recursive)
			local list = if recursive then descendants(self, {}) else I(self).children
			for _, c in list do
				if internal[c].r.isa[cls] then
					return c
				end
			end
			return nil
		end,
		FindFirstDescendant = function(self, name)
			for _, c in descendants(self, {}) do
				if internal[c].name == name then
					return c
				end
			end
			return nil
		end,
		FindFirstAncestor = function(self, name)
			local p = I(self).parent
			while p do
				if internal[p].name == name then
					return p
				end
				p = internal[p].parent
			end
			return nil
		end,
		FindFirstAncestorOfClass = function(self, cls)
			local p = I(self).parent
			while p do
				if internal[p].className == cls then
					return p
				end
				p = internal[p].parent
			end
			return nil
		end,
		FindFirstAncestorWhichIsA = function(self, cls)
			local p = I(self).parent
			while p do
				if internal[p].r.isa[cls] then
					return p
				end
				p = internal[p].parent
			end
			return nil
		end,
		WaitForChild = function(self, name, timeout)
			local found = self:FindFirstChild(name)
			if found then
				return found
			end
			local start = S.now
			local warned = false
			while true do
				S.task.wait()
				found = self:FindFirstChild(name)
				if found then
					return found
				end
				if timeout and S.now - start >= timeout then
					return nil
				end
				if not timeout and not warned and S.now - start >= 5 then
					warned = true
					S.log(
						"warn",
						S.current(),
						`Infinite yield possible on '{M.fullName(self)}:WaitForChild("{name}")'`
					)
				end
			end
		end,
		IsDescendantOf = function(self, other)
			return other ~= nil and isAncestorOf(other, self)
		end,
		IsAncestorOf = function(self, other)
			return other ~= nil and isAncestorOf(self, other)
		end,
		GetFullName = function(self)
			return M.fullName(self)
		end,
		GetDebugId = function(self)
			return tostring(I(self).id)
		end,
		Destroy = function(self)
			local d = I(self)
			if d.destroyed then
				return
			end
			fireIfExists(self, "Destroying")
			for _, c in table.clone(d.children) do
				c:Destroy()
			end
			d.parentLocked = false
			setParent(self, nil)
			d.parentLocked = true
			d.destroyed = true
			for _, s in d.signals do
				for _, c in table.clone(s._conns) do
					c:Disconnect()
				end
			end
		end,
		Remove = function(self)
			self.Parent = nil
		end,
		ClearAllChildren = function(self)
			for _, c in table.clone(I(self).children) do
				c:Destroy()
			end
		end,
		Clone = function(self)
			return M.clone(self)
		end,
		GetAttribute = function(self, name)
			return I(self).attrs[name]
		end,
		GetAttributes = function(self)
			return table.clone(I(self).attrs)
		end,
		SetAttribute = function(self, name, value)
			local d = I(self)
			if type(name) ~= "string" then
				error("Attribute name must be a string", 2)
			end
			if value ~= nil and not ATTR_TYPES[D.typeof(value)] then
				error(`{D.typeof(value)} is not a supported attribute type`, 2)
			end
			if type(value) == "number" and value ~= value then
				-- Roblox allows NaN attributes; keep it, but it is almost always a bug
				S.log("warn", S.current(), `[mock] SetAttribute("{name}", NaN) on {M.fullName(self)}`)
			end
			local old = d.attrs[name]
			d.attrs[name] = value
			if old ~= value then
				fireIfExists(self, "AttributeChanged", name)
				local s = d.attrSignals[name]
				if s then
					s:Fire()
				end
			end
		end,
		GetAttributeChangedSignal = function(self, name)
			local d = I(self)
			local s = d.attrSignals[name]
			if not s then
				s = Signal.new(`AttributeChanged:{name}`)
				d.attrSignals[name] = s
			end
			return s
		end,
		GetPropertyChangedSignal = function(self, prop)
			local d = I(self)
			local s = d.propSignals[prop]
			if not s then
				s = Signal.new(`PropertyChanged:{prop}`)
				d.propSignals[prop] = s
			end
			return s
		end,
		AddTag = function(self, tag)
			I(self).tags[tag] = true
		end,
		RemoveTag = function(self, tag)
			I(self).tags[tag] = nil
		end,
		HasTag = function(self, tag)
			return I(self).tags[tag] == true
		end,
		GetTags = function(self)
			local out = {}
			for t in I(self).tags do
				table.insert(out, t)
			end
			return out
		end,
	},
})

function M.clone(inst)
	local d = internal[inst]
	if d.props.Archivable == false then
		return nil
	end
	local copy = M.create(d.className)
	local cd = internal[copy]
	cd.name = d.name
	for k, v in d.props do
		cd.props[k] = v
	end
	for k, v in d.attrs do
		cd.attrs[k] = v
	end
	for k in d.tags do
		cd.tags[k] = true
	end
	if d.source then
		cd.source = d.source
		cd.path = d.path
	end
	for _, c in d.children do
		local cc = M.clone(c)
		if cc then
			cc.Parent = copy
		end
	end
	return copy
end

---------------------------------------------------------------- helpers for class definitions
local function simple(name, super, props, extra)
	local def = extra or {}
	def.super = super
	def.props = props or {}
	return M.defineClass(name, def)
end
M.simple = simple

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

---------------------------------------------------------------- 3D world
simple("PVInstance", "Instance", {}, { creatable = false })

-- position/rotation helpers for parts
local function partCF(d)
	return d.props.CFrame or CFrame.identity
end

simple("BasePart", "PVInstance", {
	Size = Vector3.new(4, 1, 2),
	Anchored = false,
	CanCollide = true,
	CanTouch = true,
	CanQuery = true,
	CastShadow = true,
	Locked = false,
	Massless = false,
	Transparency = 0,
	Reflectance = 0,
	Color = Color3.fromRGB(163, 162, 165),
	Material = Enum.Material.Plastic,
	MaterialVariant = "",
	TopSurface = Enum.SurfaceType.Smooth,
	BottomSurface = Enum.SurfaceType.Smooth,
	FrontSurface = Enum.SurfaceType.Smooth,
	BackSurface = Enum.SurfaceType.Smooth,
	LeftSurface = Enum.SurfaceType.Smooth,
	RightSurface = Enum.SurfaceType.Smooth,
	CollisionGroup = "Default",
	AssemblyLinearVelocity = Vector3.zero,
	AssemblyAngularVelocity = Vector3.zero,
	Velocity = Vector3.zero,
	RootPriority = 0,
	CustomPhysicalProperties = NIL,
	PivotOffset = CFrame.identity,
	Shape = Enum.PartType.Block,
}, {
	creatable = false,
	events = { "Touched", "TouchEnded" },
	getters = {
		CFrame = function(_, d)
			return partCF(d)
		end,
		Position = function(_, d)
			return partCF(d).Position
		end,
		Orientation = function(_, d)
			local x, y, z = partCF(d):ToOrientation()
			return Vector3.new(math.deg(x), math.deg(y), math.deg(z))
		end,
		Rotation = function(_, d)
			local x, y, z = partCF(d):ToEulerAnglesXYZ()
			return Vector3.new(math.deg(x), math.deg(y), math.deg(z))
		end,
		BrickColor = function(_, d)
			return D.BrickColor.new("Medium stone grey")
		end,
		Mass = function(_, d)
			local s = d.props.Size or Vector3.new(4, 1, 2)
			return s.X * s.Y * s.Z * 0.7
		end,
		AssemblyMass = function(inst, d)
			return inst.Mass
		end,
		AssemblyRootPart = function(inst)
			return inst
		end,
		ExtentsCFrame = function(_, d)
			return partCF(d)
		end,
	},
	setters = {
		CFrame = function(inst, d, v)
			assert(D.typeof(v) == "CFrame", `Unable to assign property CFrame. CFrame expected, got {D.typeof(v)}`)
			local old = d.props.CFrame
			d.props.CFrame = v
			if old ~= v then
				propChanged(inst, "CFrame")
				propChanged(inst, "Position")
			end
		end,
		Position = function(inst, d, v)
			assert(
				D.typeof(v) == "Vector3",
				`Unable to assign property Position. Vector3 expected, got {D.typeof(v)}`
			)
			local cf = partCF(d)
			d.props.CFrame = cf.Rotation + v
			propChanged(inst, "Position")
			propChanged(inst, "CFrame")
		end,
		Orientation = function(inst, d, v)
			local cf = partCF(d)
			d.props.CFrame = CFrame.new(cf.Position)
				* CFrame.fromOrientation(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
			propChanged(inst, "Orientation")
		end,
		Rotation = function(inst, d, v)
			local cf = partCF(d)
			d.props.CFrame = CFrame.new(cf.Position) * CFrame.Angles(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
			propChanged(inst, "Rotation")
		end,
		BrickColor = function(inst, d, v)
			d.props.Color = v.Color
		end,
		Size = function(inst, d, v)
			assert(D.typeof(v) == "Vector3", `Unable to assign property Size. Vector3 expected, got {D.typeof(v)}`)
			-- Roblox clamps part sizes to a minimum of 0.001
			d.props.Size = Vector3.new(math.max(v.X, 0.001), math.max(v.Y, 0.001), math.max(v.Z, 0.001))
			propChanged(inst, "Size")
		end,
	},
	methods = {
		GetTouchingParts = function()
			return {}
		end,
		GetConnectedParts = function()
			return {}
		end,
		GetMass = function(self)
			return self.Mass
		end,
		ApplyImpulse = function() end,
		ApplyAngularImpulse = function() end,
		SetNetworkOwner = function() end,
		SetNetworkOwnershipAuto = function() end,
		GetNetworkOwner = function()
			return nil
		end,
		CanSetNetworkOwnership = function()
			return true
		end,
		BreakJoints = function() end,
		GetPivot = function(self)
			return self.CFrame * self.PivotOffset
		end,
		PivotTo = function(self, cf)
			self.CFrame = cf * self.PivotOffset:Inverse()
		end,
		GetVelocityAtPosition = function()
			return Vector3.zero
		end,
	},
})
simple("Part", "BasePart", {})
simple("WedgePart", "BasePart", {})
simple("CornerWedgePart", "BasePart", {})
simple("TrussPart", "BasePart", {})
simple("MeshPart", "BasePart", { MeshId = "", TextureID = "" })
simple("UnionOperation", "BasePart", {}, { creatable = false })
simple("SpawnLocation", "Part", { Neutral = true, AllowTeamChangeOnTouch = false, Duration = 10, Enabled = true })
simple("Seat", "Part", { Disabled = false, Occupant = NIL })
simple("VehicleSeat", "BasePart", { Occupant = NIL })
simple("Terrain", "BasePart", {}, { creatable = false })

-- Model pivot math
local function modelParts(model)
	local out = {}
	for _, x in descendants(model, {}) do
		if internal[x].r.isa.BasePart then
			table.insert(out, x)
		end
	end
	return out
end
M.modelParts = modelParts

local function boundingBox(model)
	local parts = modelParts(model)
	if #parts == 0 then
		return CFrame.identity, Vector3.zero
	end
	local minV, maxV
	for _, p in parts do
		local cf, size = p.CFrame, p.Size
		local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local w = cf * Vector3.new(hx * sx, hy * sy, hz * sz)
					minV = if minV then minV:Min(w) else w
					maxV = if maxV then maxV:Max(w) else w
				end
			end
		end
	end
	return CFrame.new((minV + maxV) / 2), maxV - minV
end

local function modelPivot(model, d)
	local pp = d.props.PrimaryPart
	if pp and internal[pp] and not internal[pp].destroyed then
		return pp.CFrame * (d.props.PivotOffset or CFrame.identity)
	end
	if d.props.WorldPivot then
		return d.props.WorldPivot
	end
	local cf = boundingBox(model)
	return cf
end

simple("Model", "PVInstance", {
	PrimaryPart = NIL,
	LevelOfDetail = Enum.ModelLevelOfDetail.Automatic,
	ModelStreamingMode = Enum.ModelStreamingMode.Default,
}, {
	getters = {
		WorldPivot = function(inst, d)
			return modelPivot(inst, d)
		end,
	},
	setters = {
		PrimaryPart = function(inst, d, v)
			if v ~= nil and not (isInstance(v) and internal[v].r.isa.BasePart) then
				error("Unable to assign property PrimaryPart. BasePart expected", 3)
			end
			d.props.PrimaryPart = v
			propChanged(inst, "PrimaryPart")
		end,
	},
	methods = {
		GetPivot = function(self)
			return modelPivot(self, I(self))
		end,
		PivotTo = function(self, cf)
			local d = I(self)
			local current = modelPivot(self, d)
			local delta = cf * current:Inverse()
			for _, p in modelParts(self) do
				p.CFrame = delta * p.CFrame
			end
			if d.props.WorldPivot then
				d.props.WorldPivot = cf
			end
		end,
		SetPrimaryPartCFrame = function(self, cf)
			assert(self.PrimaryPart, "Model:SetPrimaryPartCFrame() failed because no PrimaryPart has been set")
			self:PivotTo(cf)
		end,
		GetPrimaryPartCFrame = function(self)
			return self.PrimaryPart and self.PrimaryPart.CFrame
		end,
		GetBoundingBox = function(self)
			return boundingBox(self)
		end,
		GetExtentsSize = function(self)
			local _, size = boundingBox(self)
			return size
		end,
		MoveTo = function(self, pos)
			local cf = modelPivot(self, I(self))
			self:PivotTo(cf.Rotation + pos)
		end,
		TranslateBy = function(self, v)
			self:PivotTo(modelPivot(self, I(self)) + v)
		end,
		GetScale = function(self)
			return I(self).scale or 1
		end,
		ScaleTo = function(self, s)
			I(self).scale = s
		end,
	},
})
M.extend("Model", {
	setters = {
		WorldPivot = function(inst, d, v)
			d.props.WorldPivot = v
		end,
	},
})

simple("WorldRoot", "Model", {}, { creatable = false })
simple("Workspace", "WorldRoot", {
	Gravity = 196.2,
	FallenPartsDestroyHeight = -500,
	StreamingEnabled = false,
	FilteringEnabled = true,
	DistributedGameTime = 0,
}, { creatable = false })

simple("Folder", "Instance", {})
simple("Configuration", "Instance", {})
simple("Camera", "PVInstance", {
	CFrame = CFrame.new(0, 20, 20),
	Focus = CFrame.identity,
	FieldOfView = 70,
	CameraType = Enum.CameraType.Custom,
	CameraSubject = NIL,
	ViewportSize = Vector2.new(844, 390), -- iPhone landscape
	NearPlaneZ = -0.1,
	HeadLocked = true,
}, {
	methods = {
		WorldToViewportPoint = function(self, p)
			return Vector3.new(422, 195, 10), true
		end,
		WorldToScreenPoint = function(self, p)
			return Vector3.new(422, 195, 10), true
		end,
		ScreenPointToRay = function(self, x, y)
			return D.Ray.new(self.CFrame.Position, self.CFrame.LookVector)
		end,
		ViewportPointToRay = function(self, x, y)
			return D.Ray.new(self.CFrame.Position, self.CFrame.LookVector)
		end,
		GetPivot = function(self)
			return self.CFrame
		end,
		PivotTo = function(self, cf)
			self.CFrame = cf
		end,
	},
})

simple("Attachment", "Instance", {
	CFrame = CFrame.identity,
	Visible = false,
	Axis = Vector3.xAxis,
	SecondaryAxis = Vector3.yAxis,
}, {
	getters = {
		Position = function(_, d)
			return (d.props.CFrame or CFrame.identity).Position
		end,
		WorldPosition = function(inst, d)
			local p = d.parent
			local cf = d.props.CFrame or CFrame.identity
			if p and internal[p].r.isa.BasePart then
				return (p.CFrame * cf).Position
			end
			return cf.Position
		end,
		WorldCFrame = function(inst, d)
			local p = d.parent
			local cf = d.props.CFrame or CFrame.identity
			if p and internal[p].r.isa.BasePart then
				return p.CFrame * cf
			end
			return cf
		end,
		Orientation = function()
			return Vector3.zero
		end,
	},
	setters = {
		Position = function(inst, d, v)
			d.props.CFrame = (d.props.CFrame or CFrame.identity).Rotation + v
		end,
		WorldPosition = function(inst, d, v)
			d.props.CFrame = CFrame.new(v)
		end,
		Orientation = function(inst, d, v)
			local cf = d.props.CFrame or CFrame.identity
			d.props.CFrame = CFrame.new(cf.Position)
				* CFrame.fromOrientation(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
		end,
	},
})

local jointProps = { Part0 = NIL, Part1 = NIL, C0 = CFrame.identity, C1 = CFrame.identity, Enabled = true }
simple("JointInstance", "Instance", jointProps, { creatable = false })
simple("Weld", "JointInstance", {})
simple("Motor6D", "JointInstance", { CurrentAngle = 0, DesiredAngle = 0, MaxVelocity = 0 })
simple("Snap", "JointInstance", {})
simple("WeldConstraint", "Instance", { Part0 = NIL, Part1 = NIL, Enabled = true, Active = true })
simple("NoCollisionConstraint", "Instance", { Part0 = NIL, Part1 = NIL, Enabled = true })
local constraintProps = { Attachment0 = NIL, Attachment1 = NIL, Enabled = true, Visible = false, Color = NIL }
for _, n in {
	"RopeConstraint",
	"RodConstraint",
	"SpringConstraint",
	"HingeConstraint",
	"BallSocketConstraint",
	"AlignPosition",
	"AlignOrientation",
	"LinearVelocity",
	"AngularVelocity",
	"VectorForce",
	"Torque",
} do
	simple(n, "Instance", table.clone(constraintProps))
end
for _, n in { "BodyVelocity", "BodyPosition", "BodyGyro", "BodyForce", "BodyAngularVelocity" } do
	simple(n, "Instance", {
		Velocity = Vector3.zero,
		MaxForce = Vector3.zero,
		Position = Vector3.zero,
		P = 10000,
		D = 500,
		CFrame = CFrame.identity,
	})
end

-- lights & effects
local lightProps = { Brightness = 1, Color = WHITE, Enabled = true, Range = 8, Shadows = false }
simple("Light", "Instance", lightProps, { creatable = false })
simple("PointLight", "Light", {})
simple("SpotLight", "Light", { Angle = 90, Face = Enum.NormalId.Front })
simple("SurfaceLight", "Light", { Angle = 90, Face = Enum.NormalId.Front })

local emitterProps = {
	Enabled = true,
	Rate = 5,
	Lifetime = D.NumberRange.new(5, 10),
	Speed = D.NumberRange.new(5),
	SpreadAngle = Vector2.zero,
	Size = D.NumberSequence.new(1),
	Transparency = D.NumberSequence.new(0),
	Color = D.ColorSequence.new(WHITE),
	LightEmission = 0,
	LightInfluence = 1,
	Texture = "rbxasset://textures/particles/sparkles_main.dds",
	Rotation = D.NumberRange.new(0),
	RotSpeed = D.NumberRange.new(0),
	Acceleration = Vector3.zero,
	Drag = 0,
	EmissionDirection = Enum.NormalId.Top,
	LockedToPart = false,
	ZOffset = 0,
	Shape = Enum.ParticleEmitterShape.Box,
	Brightness = 1,
	Squash = D.NumberSequence.new(0),
	TimeScale = 1,
	VelocityInheritance = 0,
	Orientation = Enum.ParticleOrientation.FacingCamera,
}
simple("ParticleEmitter", "Instance", emitterProps, {
	methods = {
		Emit = function() end,
		Clear = function() end,
	},
})
simple("Beam", "Instance", {
	Attachment0 = NIL,
	Attachment1 = NIL,
	Color = D.ColorSequence.new(WHITE),
	Transparency = D.NumberSequence.new(0.5),
	Width0 = 1,
	Width1 = 1,
	Enabled = true,
	FaceCamera = false,
	LightEmission = 0,
	Texture = "",
	TextureSpeed = 1,
	TextureLength = 1,
	Segments = 10,
	CurveSize0 = 0,
	CurveSize1 = 0,
})
simple("Trail", "Instance", {
	Attachment0 = NIL,
	Attachment1 = NIL,
	Color = D.ColorSequence.new(WHITE),
	Transparency = D.NumberSequence.new(0.5),
	Lifetime = 2,
	Enabled = true,
	FaceCamera = false,
	LightEmission = 0,
	WidthScale = D.NumberSequence.new(1),
	MinLength = 0.1,
	MaxLength = 0,
	Texture = "",
})
for _, n in { "Smoke", "Fire", "Sparkles" } do
	simple(n, "Instance", {
		Enabled = true,
		Color = WHITE,
		Size = 5,
		Heat = 9,
		Opacity = 0.5,
		RiseVelocity = 1,
		SecondaryColor = WHITE,
		SparkleColor = WHITE,
		TimeScale = 1,
	})
end
simple("Explosion", "Instance", {
	Position = Vector3.zero,
	BlastRadius = 4,
	BlastPressure = 500000,
	DestroyJointRadiusPercent = 1,
	Visible = true,
	ExplosionType = Enum.ExplosionType.Craters,
}, { events = { "Hit" } })
simple("Highlight", "Instance", {
	Adornee = NIL,
	Enabled = true,
	FillColor = Color3.new(1, 0, 0),
	FillTransparency = 0.5,
	OutlineColor = WHITE,
	OutlineTransparency = 0,
	DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
})
simple("SelectionBox", "Instance", {
	Adornee = NIL,
	Color3 = WHITE,
	LineThickness = 0.15,
	SurfaceColor3 = WHITE,
	SurfaceTransparency = 1,
	Transparency = 0,
	Visible = true,
})
simple("Decal", "Instance", { Texture = "", Color3 = WHITE, Transparency = 0, Face = Enum.NormalId.Front, ZIndex = 1 })
simple("Texture", "Decal", { StudsPerTileU = 2, StudsPerTileV = 2, OffsetStudsU = 0, OffsetStudsV = 0 })
simple("DataModelMesh", "Instance", { Scale = Vector3.one, Offset = Vector3.zero, VertexColor = Vector3.one }, {
	creatable = false,
})
simple("SpecialMesh", "DataModelMesh", { MeshType = Enum.MeshType.Head, MeshId = "", TextureId = "" })
simple("BlockMesh", "DataModelMesh", {})
simple("CylinderMesh", "DataModelMesh", {})

simple("ClickDetector", "Instance", { MaxActivationDistance = 32, CursorIcon = "" }, {
	events = { "MouseClick", "RightMouseClick", "MouseHoverEnter", "MouseHoverLeave" },
})
simple("ProximityPrompt", "Instance", {
	ActionText = "Interact",
	ObjectText = "",
	HoldDuration = 0,
	MaxActivationDistance = 10,
	Enabled = true,
	RequiresLineOfSight = true,
	KeyboardKeyCode = Enum.KeyCode.E,
	GamepadKeyCode = Enum.KeyCode.ButtonX,
	Style = Enum.ProximityPromptStyle.Default,
	UIOffset = Vector2.zero,
	ClickablePrompt = true,
	Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton,
}, {
	events = { "Triggered", "TriggerEnded", "PromptShown", "PromptHidden", "PromptButtonHoldBegan", "PromptButtonHoldEnded" },
	methods = {
		InputHoldBegin = function() end,
		InputHoldEnd = function() end,
	},
})

-- sound
simple("Sound", "Instance", {
	SoundId = "",
	Volume = 0.5,
	Looped = false,
	Playing = false,
	PlaybackSpeed = 1,
	TimePosition = 0,
	TimeLength = 1,
	IsLoaded = true,
	IsPlaying = false,
	RollOffMaxDistance = 10000,
	RollOffMinDistance = 10,
	RollOffMode = Enum.RollOffMode.Inverse,
	SoundGroup = NIL,
	PlayOnRemove = false,
}, {
	events = { "Ended", "Loaded", "Played", "Paused", "Resumed", "Stopped", "DidLoop" },
	methods = {
		Play = function(self)
			M.rawSet(self, "Playing", true)
			M.rawSet(self, "IsPlaying", true)
			fireIfExists(self, "Played", self.SoundId)
		end,
		Stop = function(self)
			M.rawSet(self, "Playing", false)
			M.rawSet(self, "IsPlaying", false)
			fireIfExists(self, "Stopped", self.SoundId)
		end,
		Pause = function(self)
			M.rawSet(self, "Playing", false)
			M.rawSet(self, "IsPlaying", false)
		end,
		Resume = function(self)
			M.rawSet(self, "Playing", true)
			M.rawSet(self, "IsPlaying", true)
		end,
	},
})
simple("SoundGroup", "Instance", { Volume = 0.5 })
for _, n in {
	"EqualizerSoundEffect",
	"ReverbSoundEffect",
	"ChorusSoundEffect",
	"CompressorSoundEffect",
	"PitchShiftSoundEffect",
	"EchoSoundEffect",
	"DistortionSoundEffect",
} do
	simple(n, "Instance", { Enabled = true, Priority = 0 })
end

-- post effects / atmosphere
simple("PostEffect", "Instance", { Enabled = true }, { creatable = false })
simple("BloomEffect", "PostEffect", { Intensity = 1, Size = 24, Threshold = 2 })
simple("BlurEffect", "PostEffect", { Size = 24 })
simple("ColorCorrectionEffect", "PostEffect", { Brightness = 0, Contrast = 0, Saturation = 0, TintColor = WHITE })
simple("SunRaysEffect", "PostEffect", { Intensity = 0.25, Spread = 1 })
simple("DepthOfFieldEffect", "PostEffect", { FarIntensity = 0.75, FocusDistance = 0.05, InFocusRadius = 10, NearIntensity = 0.75 })
simple("Atmosphere", "Instance", {
	Density = 0.395,
	Offset = 0,
	Color = Color3.fromRGB(199, 199, 199),
	Decay = Color3.fromRGB(106, 112, 125),
	Glare = 0,
	Haze = 0,
})
simple("Sky", "Instance", {
	SkyboxBk = "",
	SkyboxDn = "",
	SkyboxFt = "",
	SkyboxLf = "",
	SkyboxRt = "",
	SkyboxUp = "",
	SunAngularSize = 21,
	MoonAngularSize = 11,
	StarCount = 3000,
	CelestialBodiesShown = true,
	SunTextureId = "",
	MoonTextureId = "",
})
simple("Clouds", "Instance", { Cover = 0.5, Density = 0.7, Color = WHITE, Enabled = true })

-- values
local function valueClass(name, default)
	simple(name, "ValueBase", { Value = default })
end
simple("ValueBase", "Instance", {}, { creatable = false })
valueClass("IntValue", 0)
valueClass("NumberValue", 0)
valueClass("StringValue", "")
valueClass("BoolValue", false)
valueClass("ObjectValue", NIL)
valueClass("Vector3Value", Vector3.zero)
valueClass("CFrameValue", CFrame.identity)
valueClass("Color3Value", BLACK)
valueClass("IntConstrainedValue", 0)
M.extend("IntValue", {
	setters = {
		Value = function(inst, d, v)
			assert(type(v) == "number", `Unable to assign property Value. int64 expected, got {D.typeof(v)}`)
			v = if v >= 0 then math.floor(v) else math.ceil(v)
			local old = d.props.Value
			d.props.Value = v
			if old ~= v then
				propChanged(inst, "Value", v)
			end
		end,
	},
})
M.extend("StringValue", {
	setters = {
		Value = function(inst, d, v)
			assert(
				type(v) == "string" or type(v) == "number",
				`Unable to assign property Value. string expected, got {D.typeof(v)}`
			)
			v = tostring(v)
			local old = d.props.Value
			d.props.Value = v
			if old ~= v then
				propChanged(inst, "Value", v)
			end
		end,
	},
})
M.extend("NumberValue", {
	setters = {
		Value = function(inst, d, v)
			assert(type(v) == "number", `Unable to assign property Value. double expected, got {D.typeof(v)}`)
			local old = d.props.Value
			d.props.Value = v
			if old ~= v then
				propChanged(inst, "Value", v)
			end
		end,
	},
})

-- bindables
simple("BindableEvent", "Instance", {}, {
	events = { "Event" },
	methods = {
		Fire = function(self, ...)
			getSignal(self, "Event"):Fire(...)
		end,
	},
})
simple("BindableFunction", "Instance", {}, {
	methods = {
		Invoke = function(self, ...)
			local d = I(self)
			while not d.props.OnInvoke do
				S.task.wait()
			end
			return d.props.OnInvoke(...)
		end,
	},
})
M.extend("BindableFunction", {
	props = { OnInvoke = NIL },
})

-- scripts (sources are attached by the loader)
simple("LuaSourceContainer", "Instance", {}, { creatable = false })
simple("BaseScript", "LuaSourceContainer", { Disabled = false, Enabled = true, RunContext = Enum.RunContext.Legacy }, {
	creatable = false,
})
simple("Script", "BaseScript", {})
simple("LocalScript", "Script", {})
simple("ModuleScript", "LuaSourceContainer", {}, {
	getters = {
		Source = function(_, d)
			return d.source or ""
		end,
	},
})

---------------------------------------------------------------- GUI
simple("GuiBase", "Instance", {}, { creatable = false })
simple("GuiBase2d", "GuiBase", {
	AutoLocalize = true,
	RootLocalizationTable = NIL,
	SelectionGroup = false,
}, {
	creatable = false,
})

-- Absolute size/position computed from the parent chain (a LayerCollector gives the screen size).
local SCREEN = Vector2.new(844, 390)
M.SCREEN = SCREEN
local function absSize(inst)
	local d = internal[inst]
	if d.r.isa.ScreenGui then
		return SCREEN
	elseif d.r.isa.BillboardGui or d.r.isa.SurfaceGui then
		local s = d.props.Size
		if d.r.isa.SurfaceGui then
			return d.props.CanvasSize or Vector2.new(800, 600)
		end
		if s then
			return Vector2.new(s.X.Offset + s.X.Scale * 100, s.Y.Offset + s.Y.Scale * 100)
		end
		return Vector2.new(100, 100)
	elseif d.r.isa.GuiObject then
		local p = d.parent
		local pAbs = if p and internal[p].r.isa.GuiBase2d then absSize(p) else SCREEN
		local s = d.props.Size or UDim2.new()
		return Vector2.new(pAbs.X * s.X.Scale + s.X.Offset, pAbs.Y * s.Y.Scale + s.Y.Offset)
	end
	return Vector2.zero
end
local function absPos(inst)
	local d = internal[inst]
	if not d.r.isa.GuiObject then
		return Vector2.zero
	end
	local p = d.parent
	local pAbs, pPos = SCREEN, Vector2.zero
	if p and internal[p].r.isa.GuiBase2d then
		pAbs = absSize(p)
		pPos = absPos(p)
	end
	local pos = d.props.Position or UDim2.new()
	local anchor = d.props.AnchorPoint or Vector2.zero
	local size = absSize(inst)
	return pPos
		+ Vector2.new(pAbs.X * pos.X.Scale + pos.X.Offset, pAbs.Y * pos.Y.Scale + pos.Y.Offset)
		- Vector2.new(anchor.X * size.X, anchor.Y * size.Y)
end
M.extend("GuiBase2d", {
	getters = {
		AbsoluteSize = function(inst)
			return absSize(inst)
		end,
		AbsolutePosition = function(inst)
			return absPos(inst)
		end,
		AbsoluteRotation = function()
			return 0
		end,
	},
})

local guiObjectProps = {
	Active = false,
	AnchorPoint = Vector2.zero,
	AutomaticSize = Enum.AutomaticSize.None,
	BackgroundColor3 = Color3.fromRGB(163, 162, 165),
	BackgroundTransparency = 0,
	BorderColor3 = Color3.fromRGB(27, 42, 53),
	BorderMode = Enum.BorderMode.Outline,
	BorderSizePixel = 1,
	ClipsDescendants = false,
	Interactable = true,
	LayoutOrder = 0,
	Position = UDim2.new(),
	Rotation = 0,
	Selectable = false,
	Size = UDim2.new(),
	SizeConstraint = Enum.SizeConstraint.RelativeXY,
	Visible = true,
	ZIndex = 1,
	GuiState = Enum.GuiState.Idle,
	NextSelectionDown = NIL,
	NextSelectionUp = NIL,
	NextSelectionLeft = NIL,
	NextSelectionRight = NIL,
}
simple("GuiObject", "GuiBase2d", guiObjectProps, {
	creatable = false,
	events = {
		"InputBegan",
		"InputEnded",
		"InputChanged",
		"MouseEnter",
		"MouseLeave",
		"MouseMoved",
		"MouseWheelForward",
		"MouseWheelBackward",
		"TouchTap",
		"TouchLongPress",
		"TouchPan",
		"TouchPinch",
		"TouchSwipe",
		"SelectionGained",
		"SelectionLost",
	},
	methods = {
		TweenSize = function(self, size)
			self.Size = size
			return true
		end,
		TweenPosition = function(self, pos)
			self.Position = pos
			return true
		end,
		TweenSizeAndPosition = function(self, size, pos)
			self.Size = size
			self.Position = pos
			return true
		end,
	},
})
simple("Frame", "GuiObject", { Style = Enum.FrameStyle.Custom })
simple("CanvasGroup", "GuiObject", { GroupColor3 = WHITE, GroupTransparency = 0 })
simple("ScrollingFrame", "GuiObject", {
	CanvasSize = UDim2.new(0, 0, 2, 0),
	CanvasPosition = Vector2.zero,
	ScrollBarThickness = 12,
	ScrollBarImageColor3 = WHITE,
	ScrollBarImageTransparency = 0,
	ScrollingDirection = Enum.ScrollingDirection.XY,
	ScrollingEnabled = true,
	AutomaticCanvasSize = Enum.AutomaticSize.None,
	ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
	VerticalScrollBarInset = Enum.ScrollBarInset.None,
	HorizontalScrollBarInset = Enum.ScrollBarInset.None,
	TopImage = "",
	MidImage = "",
	BottomImage = "",
	VerticalScrollBarPosition = Enum.VerticalScrollBarPosition.Right,
}, {
	getters = {
		AbsoluteCanvasSize = function(inst)
			return absSize(inst)
		end,
		AbsoluteWindowSize = function(inst)
			return absSize(inst)
		end,
	},
})
simple("ViewportFrame", "GuiObject", {
	CurrentCamera = NIL,
	Ambient = Color3.fromRGB(200, 200, 200),
	LightColor = Color3.fromRGB(140, 140, 140),
	LightDirection = Vector3.new(-1, -1, -1),
	ImageColor3 = WHITE,
	ImageTransparency = 0,
})

local textProps = {
	Text = "",
	TextColor3 = BLACK,
	TextSize = 14,
	TextScaled = false,
	TextWrapped = false,
	TextTransparency = 0,
	TextStrokeColor3 = BLACK,
	TextStrokeTransparency = 1,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
	TextTruncate = Enum.TextTruncate.None,
	Font = Enum.Font.Legacy,
	FontFace = D.Font.new("rbxasset://fonts/families/LegacyArial.json"),
	RichText = false,
	LineHeight = 1,
	MaxVisibleGraphemes = -1,
	TextDirection = Enum.TextDirection.Auto,
}
local textGetters = {
	TextBounds = function(inst, d)
		local text = d.props.Text or ""
		local size = d.props.TextSize or 14
		return Vector2.new(#text * size * 0.5, size)
	end,
	TextFits = function()
		return true
	end,
	ContentText = function(_, d)
		return d.props.Text or ""
	end,
}
local textSetters = {
	Text = function(inst, d, v)
		if type(v) ~= "string" and type(v) ~= "number" then
			error(`Unable to assign property Text. string expected, got {D.typeof(v)}`, 3)
		end
		v = tostring(v)
		local old = d.props.Text
		d.props.Text = v
		if old ~= v then
			propChanged(inst, "Text")
		end
	end,
}
simple("TextLabel", "GuiObject", table.clone(textProps), { getters = textGetters, setters = textSetters })
local buttonEvents = { "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up", "MouseButton2Click", "MouseButton2Down", "MouseButton2Up" }
simple("GuiButton", "GuiObject", {
	AutoButtonColor = true,
	Modal = false,
	Selected = false,
	Style = Enum.ButtonStyle.Custom,
}, { creatable = false, events = buttonEvents })
M.extend("GuiObject", { props = { Selectable = false } })
simple("TextButton", "GuiButton", table.clone(textProps), { getters = textGetters, setters = textSetters })
M.extend("TextButton", { props = { Selectable = true } })
simple("TextBox", "GuiObject", table.clone(textProps), {
	getters = textGetters,
	setters = textSetters,
	events = { "FocusLost", "Focused", "ReturnPressedFromOnScreenKeyboard" },
	methods = {
		CaptureFocus = function() end,
		ReleaseFocus = function() end,
		IsFocused = function()
			return false
		end,
	},
})
M.extend("TextBox", {
	props = {
		PlaceholderText = "",
		PlaceholderColor3 = Color3.fromRGB(178, 178, 178),
		ClearTextOnFocus = true,
		MultiLine = false,
		TextEditable = true,
		CursorPosition = 1,
		SelectionStart = -1,
		ShowNativeInput = true,
	},
})
local imageProps = {
	Image = "",
	ImageColor3 = WHITE,
	ImageTransparency = 0,
	ImageRectOffset = Vector2.zero,
	ImageRectSize = Vector2.zero,
	ScaleType = Enum.ScaleType.Stretch,
	SliceCenter = D.Rect.new(0, 0, 0, 0),
	SliceScale = 1,
	TileSize = UDim2.fromScale(1, 1),
	ResampleMode = Enum.ResamplerMode.Default,
}
simple("ImageLabel", "GuiObject", table.clone(imageProps), { getters = { IsLoaded = function()
	return true
end } })
simple("ImageButton", "GuiButton", table.clone(imageProps), {
	getters = { IsLoaded = function()
		return true
	end },
})
M.extend("ImageButton", { props = { HoverImage = "", PressedImage = "" } })

simple("LayerCollector", "GuiBase2d", { Enabled = true, ResetOnSpawn = true, ZIndexBehavior = Enum.ZIndexBehavior.Global }, {
	creatable = false,
})
simple("ScreenGui", "LayerCollector", {
	DisplayOrder = 0,
	IgnoreGuiInset = false,
	ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	SafeAreaCompatibility = Enum.SafeAreaCompatibility.FullscreenExtension,
	ClipToDeviceSafeArea = true,
})
simple("BillboardGui", "LayerCollector", {
	Adornee = NIL,
	AlwaysOnTop = false,
	Active = false,
	ClipsDescendants = false,
	DistanceLowerLimit = 0,
	DistanceUpperLimit = -1,
	DistanceStep = 0,
	ExtentsOffset = Vector3.zero,
	ExtentsOffsetWorldSpace = Vector3.zero,
	LightInfluence = 1,
	MaxDistance = math.huge,
	Size = UDim2.new(),
	SizeOffset = Vector2.zero,
	StudsOffset = Vector3.zero,
	StudsOffsetWorldSpace = Vector3.zero,
	Brightness = 1,
	PlayerToHideFrom = NIL,
})
simple("SurfaceGuiBase", "LayerCollector", { Adornee = NIL, Face = Enum.NormalId.Front, Active = true }, { creatable = false })
simple("SurfaceGui", "SurfaceGuiBase", {
	AlwaysOnTop = false,
	Brightness = 1,
	CanvasSize = Vector2.new(800, 600),
	ClipsDescendants = true,
	LightInfluence = 1,
	PixelsPerStud = 50,
	SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
	ToolPunchThroughDistance = 0,
	ZOffset = 0,
	MaxDistance = 1000,
})

simple("UIComponent", "Instance", {}, { creatable = false })
simple("UIBase", "UIComponent", {}, { creatable = false })
simple("UICorner", "UIComponent", { CornerRadius = UDim.new(0, 8) })
simple("UIStroke", "UIComponent", {
	Color = BLACK,
	Thickness = 1,
	Transparency = 0,
	Enabled = true,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	LineJoinMode = Enum.LineJoinMode.Round,
})
simple("UIGradient", "UIComponent", {
	Color = D.ColorSequence.new(WHITE),
	Transparency = D.NumberSequence.new(0),
	Rotation = 0,
	Offset = Vector2.zero,
	Enabled = true,
})
simple("UIScale", "UIComponent", { Scale = 1 })
simple("UIPadding", "UIComponent", {
	PaddingTop = UDim.new(),
	PaddingBottom = UDim.new(),
	PaddingLeft = UDim.new(),
	PaddingRight = UDim.new(),
})
simple("UIConstraint", "UIComponent", {}, { creatable = false })
simple("UIAspectRatioConstraint", "UIConstraint", {
	AspectRatio = 1,
	AspectType = Enum.AspectType.FitWithinMaxSize,
	DominantAxis = Enum.DominantAxis.Width,
})
simple("UITextSizeConstraint", "UIConstraint", { MaxTextSize = 100, MinTextSize = 1 })
simple("UISizeConstraint", "UIConstraint", { MaxSize = Vector2.new(math.huge, math.huge), MinSize = Vector2.zero })
simple("UIFlexItem", "UIComponent", { FlexMode = Enum.UIFlexMode.None, GrowRatio = 0, ShrinkRatio = 0 })
simple("UILayout", "UIComponent", {}, {
	creatable = false,
	getters = {
		AbsoluteContentSize = function(inst, d)
			local p = d.parent
			if p and internal[p].r.isa.GuiBase2d then
				local count = 0
				for _, c in internal[p].children do
					if internal[c].r.isa.GuiObject then
						count += 1
					end
				end
				local s = absSize(p)
				return Vector2.new(s.X, count * 50)
			end
			return Vector2.zero
		end,
	},
})
simple("UIGridStyleLayout", "UILayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Left,
	VerticalAlignment = Enum.VerticalAlignment.Top,
	SortOrder = Enum.SortOrder.Name,
}, { creatable = false, methods = { ApplyLayout = function() end } })
simple("UIListLayout", "UIGridStyleLayout", {
	Padding = UDim.new(),
	Wraps = false,
	HorizontalFlex = Enum.UIFlexAlignment.None,
	VerticalFlex = Enum.UIFlexAlignment.None,
	ItemLineAlignment = Enum.ItemLineAlignment.Automatic,
})
simple("UIGridLayout", "UIGridStyleLayout", {
	CellSize = UDim2.new(0, 100, 0, 100),
	CellPadding = UDim2.new(0, 5, 0, 5),
	FillDirectionMaxCells = 0,
	StartCorner = Enum.StartCorner.TopLeft,
})
simple("UIPageLayout", "UIGridStyleLayout", { Animated = true, Circular = false, Padding = UDim.new() })
simple("UITableLayout", "UIGridStyleLayout", {})

---------------------------------------------------------------- characters
simple("Humanoid", "Instance", {
	Health = 100,
	MaxHealth = 100,
	WalkSpeed = 16,
	JumpPower = 50,
	JumpHeight = 7.2,
	UseJumpPower = true,
	HipHeight = 2,
	AutoRotate = true,
	PlatformStand = false,
	Sit = false,
	Jump = false,
	MoveDirection = Vector3.zero,
	DisplayName = "",
	DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer,
	HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged,
	NameDisplayDistance = 100,
	HealthDisplayDistance = 100,
	BreakJointsOnDeath = true,
	RequiresNeck = true,
	RigType = Enum.HumanoidRigType.R15,
	FloorMaterial = Enum.Material.Plastic,
	WalkToPoint = Vector3.zero,
	CameraOffset = Vector3.zero,
	EvaluateStateMachine = true,
}, {
	events = {
		"Died",
		"HealthChanged",
		"Running",
		"Jumping",
		"StateChanged",
		"MoveToFinished",
		"Seated",
		"Touched",
		"FreeFalling",
		"Climbing",
		"AnimationPlayed",
	},
	getters = {
		RootPart = function(inst, d)
			local char = d.parent
			return char and char:FindFirstChild("HumanoidRootPart")
		end,
		SeatPart = function()
			return nil
		end,
	},
	setters = {
		Health = function(inst, d, v)
			local max = d.props.MaxHealth or 100
			v = math.clamp(v, 0, max)
			local old = d.props.Health or 100
			d.props.Health = v
			if old ~= v then
				propChanged(inst, "Health")
				fireIfExists(inst, "HealthChanged", v)
				if v <= 0 and old > 0 then
					fireIfExists(inst, "Died")
				end
			end
		end,
	},
	methods = {
		TakeDamage = function(self, n)
			self.Health -= n
		end,
		MoveTo = function(self, pos)
			local root = self.RootPart
			if root then
				root.CFrame = root.CFrame.Rotation + pos
			end
			S.task.defer(function()
				fireIfExists(self, "MoveToFinished", true)
			end)
		end,
		Move = function() end,
		ChangeState = function() end,
		GetState = function()
			return Enum.HumanoidStateType.Running
		end,
		SetStateEnabled = function() end,
		GetStateEnabled = function()
			return true
		end,
		LoadAnimation = function(self, anim)
			local animator = self:FindFirstChildOfClass("Animator") or M.new("Animator", self)
			return animator:LoadAnimation(anim)
		end,
		GetPlayingAnimationTracks = function()
			return {}
		end,
		ApplyDescription = function() end,
		GetAppliedDescription = function(self)
			return M.new("HumanoidDescription")
		end,
		UnequipTools = function() end,
		EquipTool = function() end,
		AddAccessory = function() end,
		GetAccessories = function()
			return {}
		end,
		BuildRigFromAttachments = function() end,
	},
})
simple("HumanoidDescription", "Instance", { HeadColor = WHITE, BodyTypeScale = 0.3 })
simple("Animation", "Instance", { AnimationId = "" })
simple("AnimationTrack", "Instance", {
	IsPlaying = false,
	Length = 1,
	Looped = false,
	Priority = Enum.AnimationPriority.Core,
	Speed = 1,
	TimePosition = 0,
	WeightCurrent = 1,
	WeightTarget = 1,
	Animation = NIL,
}, {
	creatable = false,
	events = { "Stopped", "Ended", "DidLoop", "KeyframeReached" },
	methods = {
		Play = function(self)
			M.rawSet(self, "IsPlaying", true)
		end,
		Stop = function(self)
			M.rawSet(self, "IsPlaying", false)
			fireIfExists(self, "Stopped")
		end,
		AdjustSpeed = function(self, s)
			M.rawSet(self, "Speed", s)
		end,
		AdjustWeight = function() end,
		GetMarkerReachedSignal = function(self, name)
			return getSignal(self, "Marker:" .. tostring(name))
		end,
		GetTimeOfKeyframe = function()
			return 0
		end,
	},
})
simple("Animator", "Instance", {}, {
	events = { "AnimationPlayed" },
	methods = {
		LoadAnimation = function(self, anim)
			local track = M.create("AnimationTrack")
			M.rawSet(track, "Animation", anim)
			return track
		end,
		GetPlayingAnimationTracks = function()
			return {}
		end,
	},
})
simple("AnimationController", "Instance", {})
simple("Accessory", "Instance", {})
simple("Shirt", "Instance", { ShirtTemplate = "" })
simple("Pants", "Instance", { PantsTemplate = "" })
simple("BodyColors", "Instance", {})
simple("Tool", "Model", {
	CanBeDropped = true,
	Enabled = true,
	RequiresHandle = true,
	ToolTip = "",
	TextureId = "",
	ManualActivationOnly = false,
	Grip = CFrame.identity,
}, {
	events = { "Activated", "Deactivated", "Equipped", "Unequipped" },
})
simple("Backpack", "Instance", {}, { creatable = false })
simple("PlayerGui", "Instance", {
	ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor,
	SelectionImageObject = NIL,
}, {
	creatable = false,
	getters = {
		CurrentScreenOrientation = function()
			return Enum.ScreenOrientation.LandscapeRight
		end,
	},
	methods = {
		GetTopbarTransparency = function()
			return 0
		end,
		SetTopbarTransparency = function() end,
		GetGuiObjectsAtPosition = function()
			return {}
		end,
	},
})
simple("PlayerScripts", "Instance", {}, { creatable = false })
simple("StarterGear", "Instance", {}, { creatable = false })

return M
