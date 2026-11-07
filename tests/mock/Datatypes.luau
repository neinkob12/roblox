--!nocheck
-- Pure-Luau stand-ins for Roblox datatypes: Vector3, Vector2, CFrame, Color3, UDim, UDim2,
-- TweenInfo, NumberRange, NumberSequence(+Keypoint), ColorSequence(+Keypoint), Random, Rect,
-- BrickColor, Font, PhysicalProperties, Ray, Enum.
-- Every value has a metatable field __type so the mocked typeof() reports the Roblox name.
-- Values are immutable, like in Roblox.

local D = {}

local function readonly(t, k)
	error(`{k} cannot be assigned to`, 2)
end

local function fuzzy(a, b, eps)
	return math.abs(a - b) <= (eps or 1e-5)
end

---------------------------------------------------------------- Vector3
local V3 = { __type = "Vector3" }
local V3methods = {}
local function v3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3)
end
V3.__index = function(self, k)
	local m = V3methods[k]
	if m then
		return m
	end
	if k == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
	elseif k == "Unit" then
		local m2 = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
		if m2 == 0 then
			return v3(0 / 0, 0 / 0, 0 / 0)
		end
		return v3(self.X / m2, self.Y / m2, self.Z / m2)
	elseif k == "x" then
		return self.X
	elseif k == "y" then
		return self.Y
	elseif k == "z" then
		return self.Z
	elseif k == "magnitude" then
		return self.Magnitude
	elseif k == "unit" then
		return self.Unit
	end
	error(`{k} is not a valid member of Vector3`, 2)
end
V3.__newindex = readonly
V3.__add = function(a, b)
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3.__sub = function(a, b)
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3.__mul = function(a, b)
	if type(a) == "number" then
		return v3(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b)
	if type(b) == "number" then
		return v3(a.X / b, a.Y / b, a.Z / b)
	elseif type(a) == "number" then
		return v3(a / b.X, a / b.Y, a / b.Z)
	end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3.__idiv = function(a, b)
	if type(b) == "number" then
		return v3(a.X // b, a.Y // b, a.Z // b)
	end
	return v3(a.X // b.X, a.Y // b.Y, a.Z // b.Z)
end
V3.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
V3.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3.__tostring = function(a)
	return `{a.X}, {a.Y}, {a.Z}`
end
function V3methods.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function V3methods.Cross(a, b)
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function V3methods.Lerp(a, b, t)
	return a + (b - a) * t
end
function V3methods.Min(a, ...)
	local x, y, z = a.X, a.Y, a.Z
	for _, o in { ... } do
		x, y, z = math.min(x, o.X), math.min(y, o.Y), math.min(z, o.Z)
	end
	return v3(x, y, z)
end
function V3methods.Max(a, ...)
	local x, y, z = a.X, a.Y, a.Z
	for _, o in { ... } do
		x, y, z = math.max(x, o.X), math.max(y, o.Y), math.max(z, o.Z)
	end
	return v3(x, y, z)
end
function V3methods.Abs(a)
	return v3(math.abs(a.X), math.abs(a.Y), math.abs(a.Z))
end
function V3methods.Floor(a)
	return v3(math.floor(a.X), math.floor(a.Y), math.floor(a.Z))
end
function V3methods.Ceil(a)
	return v3(math.ceil(a.X), math.ceil(a.Y), math.ceil(a.Z))
end
function V3methods.Sign(a)
	return v3(math.sign(a.X), math.sign(a.Y), math.sign(a.Z))
end
function V3methods.FuzzyEq(a, b, eps)
	return fuzzy(a.X, b.X, eps) and fuzzy(a.Y, b.Y, eps) and fuzzy(a.Z, b.Z, eps)
end
function V3methods.Angle(a, b)
	local d = a:Dot(b) / (a.Magnitude * b.Magnitude)
	return math.acos(math.clamp(d, -1, 1))
end
V3methods.lerp = V3methods.Lerp
V3methods.Dot = V3methods.Dot

D.Vector3 = {
	new = v3,
	zero = v3(0, 0, 0),
	one = v3(1, 1, 1),
	xAxis = v3(1, 0, 0),
	yAxis = v3(0, 1, 0),
	zAxis = v3(0, 0, 1),
	isVector3 = function(v)
		return getmetatable(v) == V3
	end,
}
function D.Vector3.FromNormalId(n)
	local name = n.Name
	if name == "Top" then
		return v3(0, 1, 0)
	elseif name == "Bottom" then
		return v3(0, -1, 0)
	elseif name == "Front" then
		return v3(0, 0, -1)
	elseif name == "Back" then
		return v3(0, 0, 1)
	elseif name == "Left" then
		return v3(-1, 0, 0)
	end
	return v3(1, 0, 0)
end
function D.Vector3.FromAxis(a)
	local name = a.Name
	if name == "X" then
		return v3(1, 0, 0)
	elseif name == "Y" then
		return v3(0, 1, 0)
	end
	return v3(0, 0, 1)
end
D.isVector3 = D.Vector3.isVector3

---------------------------------------------------------------- Vector2
local V2 = { __type = "Vector2" }
local V2methods = {}
local function v2(x, y)
	return setmetatable({ X = x or 0, Y = y or 0 }, V2)
end
V2.__index = function(self, k)
	local m = V2methods[k]
	if m then
		return m
	end
	if k == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y)
	elseif k == "Unit" then
		local m2 = math.sqrt(self.X * self.X + self.Y * self.Y)
		return v2(self.X / m2, self.Y / m2)
	end
	error(`{k} is not a valid member of Vector2`, 2)
end
V2.__newindex = readonly
V2.__add = function(a, b)
	return v2(a.X + b.X, a.Y + b.Y)
end
V2.__sub = function(a, b)
	return v2(a.X - b.X, a.Y - b.Y)
end
V2.__mul = function(a, b)
	if type(a) == "number" then
		return v2(a * b.X, a * b.Y)
	elseif type(b) == "number" then
		return v2(a.X * b, a.Y * b)
	end
	return v2(a.X * b.X, a.Y * b.Y)
end
V2.__div = function(a, b)
	if type(b) == "number" then
		return v2(a.X / b, a.Y / b)
	end
	return v2(a.X / b.X, a.Y / b.Y)
end
V2.__unm = function(a)
	return v2(-a.X, -a.Y)
end
V2.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
V2.__tostring = function(a)
	return `{a.X}, {a.Y}`
end
function V2methods.Dot(a, b)
	return a.X * b.X + a.Y * b.Y
end
function V2methods.Cross(a, b)
	return a.X * b.Y - a.Y * b.X
end
function V2methods.Lerp(a, b, t)
	return a + (b - a) * t
end
function V2methods.Min(a, b)
	return v2(math.min(a.X, b.X), math.min(a.Y, b.Y))
end
function V2methods.Max(a, b)
	return v2(math.max(a.X, b.X), math.max(a.Y, b.Y))
end
function V2methods.Abs(a)
	return v2(math.abs(a.X), math.abs(a.Y))
end
function V2methods.FuzzyEq(a, b, eps)
	return fuzzy(a.X, b.X, eps) and fuzzy(a.Y, b.Y, eps)
end
D.Vector2 = { new = v2, zero = v2(0, 0), one = v2(1, 1), xAxis = v2(1, 0), yAxis = v2(0, 1) }

---------------------------------------------------------------- CFrame
-- Stored as position + rotation matrix rows (m00..m22). Columns are RightVector, UpVector, -LookVector.
local CF = { __type = "CFrame" }
local CFmethods = {}
local function cf(x, y, z, m00, m01, m02, m10, m11, m12, m20, m21, m22)
	return setmetatable({
		_x = x,
		_y = y,
		_z = z,
		_r = { m00, m01, m02, m10, m11, m12, m20, m21, m22 },
	}, CF)
end
local function cfIdentityAt(x, y, z)
	return cf(x, y, z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
end
local function rotMul(a, b)
	local r = {}
	for i = 0, 2 do
		for j = 0, 2 do
			r[i * 3 + j + 1] = a[i * 3 + 1] * b[j + 1] + a[i * 3 + 2] * b[3 + j + 1] + a[i * 3 + 3] * b[6 + j + 1]
		end
	end
	return r
end
local function rotVec(r, x, y, z)
	return r[1] * x + r[2] * y + r[3] * z, r[4] * x + r[5] * y + r[6] * z, r[7] * x + r[8] * y + r[9] * z
end
local function fromRot(x, y, z, r)
	return cf(x, y, z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
end
local function transpose(r)
	return { r[1], r[4], r[7], r[2], r[5], r[8], r[3], r[6], r[9] }
end
local function rx(a)
	local c, s = math.cos(a), math.sin(a)
	return { 1, 0, 0, 0, c, -s, 0, s, c }
end
local function ry(a)
	local c, s = math.cos(a), math.sin(a)
	return { c, 0, s, 0, 1, 0, -s, 0, c }
end
local function rz(a)
	local c, s = math.cos(a), math.sin(a)
	return { c, -s, 0, s, c, 0, 0, 0, 1 }
end
local function quatToRot(qx, qy, qz, qw)
	local n = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
	if n == 0 then
		return { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
	end
	qx, qy, qz, qw = qx / n, qy / n, qz / n, qw / n
	return {
		1 - 2 * (qy * qy + qz * qz),
		2 * (qx * qy - qz * qw),
		2 * (qx * qz + qy * qw),
		2 * (qx * qy + qz * qw),
		1 - 2 * (qx * qx + qz * qz),
		2 * (qy * qz - qx * qw),
		2 * (qx * qz - qy * qw),
		2 * (qy * qz + qx * qw),
		1 - 2 * (qx * qx + qy * qy),
	}
end
local function rotToQuat(r)
	local m00, m01, m02, m10, m11, m12, m20, m21, m22 = table.unpack(r)
	local tr = m00 + m11 + m22
	local qx, qy, qz, qw
	if tr > 0 then
		local s = math.sqrt(tr + 1) * 2
		qw = 0.25 * s
		qx = (m21 - m12) / s
		qy = (m02 - m20) / s
		qz = (m10 - m01) / s
	elseif m00 > m11 and m00 > m22 then
		local s = math.sqrt(1 + m00 - m11 - m22) * 2
		qw = (m21 - m12) / s
		qx = 0.25 * s
		qy = (m01 + m10) / s
		qz = (m02 + m20) / s
	elseif m11 > m22 then
		local s = math.sqrt(1 + m11 - m00 - m22) * 2
		qw = (m02 - m20) / s
		qx = (m01 + m10) / s
		qy = 0.25 * s
		qz = (m12 + m21) / s
	else
		local s = math.sqrt(1 + m22 - m00 - m11) * 2
		qw = (m10 - m01) / s
		qx = (m02 + m20) / s
		qy = (m12 + m21) / s
		qz = 0.25 * s
	end
	return qx, qy, qz, qw
end
local function lookAtRot(eye, target, up)
	up = up or v3(0, 1, 0)
	local look = target - eye
	if look.Magnitude < 1e-9 then
		return { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
	end
	look = look.Unit
	local right = look:Cross(up)
	if right.Magnitude < 1e-9 then
		right = look:Cross(v3(0, 0, 1))
		if right.Magnitude < 1e-9 then
			right = v3(1, 0, 0)
		end
	end
	right = right.Unit
	local up2 = right:Cross(look).Unit
	local back = -look
	return { right.X, up2.X, back.X, right.Y, up2.Y, back.Y, right.Z, up2.Z, back.Z }
end

CF.__index = function(self, k)
	local m = CFmethods[k]
	if m then
		return m
	end
	local r = self._r
	if k == "Position" or k == "p" then
		return v3(self._x, self._y, self._z)
	elseif k == "X" or k == "x" then
		return self._x
	elseif k == "Y" or k == "y" then
		return self._y
	elseif k == "Z" or k == "z" then
		return self._z
	elseif k == "LookVector" or k == "lookVector" then
		return v3(-r[3], -r[6], -r[9])
	elseif k == "RightVector" or k == "XVector" or k == "rightVector" then
		return v3(r[1], r[4], r[7])
	elseif k == "UpVector" or k == "YVector" or k == "upVector" then
		return v3(r[2], r[5], r[8])
	elseif k == "ZVector" then
		return v3(r[3], r[6], r[9])
	elseif k == "Rotation" then
		return fromRot(0, 0, 0, r)
	end
	error(`{k} is not a valid member of CFrame`, 2)
end
CF.__newindex = readonly
CF.__mul = function(a, b)
	if getmetatable(b) == CF then
		local x, y, z = rotVec(a._r, b._x, b._y, b._z)
		return fromRot(a._x + x, a._y + y, a._z + z, rotMul(a._r, b._r))
	elseif getmetatable(b) == V3 then
		local x, y, z = rotVec(a._r, b.X, b.Y, b.Z)
		return v3(a._x + x, a._y + y, a._z + z)
	end
	error("invalid CFrame multiplication", 2)
end
CF.__add = function(a, b)
	return fromRot(a._x + b.X, a._y + b.Y, a._z + b.Z, a._r)
end
CF.__sub = function(a, b)
	return fromRot(a._x - b.X, a._y - b.Y, a._z - b.Z, a._r)
end
CF.__eq = function(a, b)
	if a._x ~= b._x or a._y ~= b._y or a._z ~= b._z then
		return false
	end
	for i = 1, 9 do
		if a._r[i] ~= b._r[i] then
			return false
		end
	end
	return true
end
CF.__tostring = function(a)
	return `{a._x}, {a._y}, {a._z}, {table.concat(a._r, ", ")}`
end
function CFmethods.Inverse(a)
	local t = transpose(a._r)
	local x, y, z = rotVec(t, -a._x, -a._y, -a._z)
	return fromRot(x, y, z, t)
end
CFmethods.inverse = CFmethods.Inverse
function CFmethods.Lerp(a, b, t)
	local ax, ay, az, aw = rotToQuat(a._r)
	local bx, by, bz, bw = rotToQuat(b._r)
	local dot = ax * bx + ay * by + az * bz + aw * bw
	if dot < 0 then
		bx, by, bz, bw, dot = -bx, -by, -bz, -bw, -dot
	end
	local qx, qy, qz, qw
	if dot > 0.9995 then
		qx, qy, qz, qw = ax + (bx - ax) * t, ay + (by - ay) * t, az + (bz - az) * t, aw + (bw - aw) * t
	else
		local th = math.acos(dot)
		local s = math.sin(th)
		local wa, wb = math.sin((1 - t) * th) / s, math.sin(t * th) / s
		qx, qy, qz, qw = ax * wa + bx * wb, ay * wa + by * wb, az * wa + bz * wb, aw * wa + bw * wb
	end
	return fromRot(
		a._x + (b._x - a._x) * t,
		a._y + (b._y - a._y) * t,
		a._z + (b._z - a._z) * t,
		quatToRot(qx, qy, qz, qw)
	)
end
CFmethods.lerp = CFmethods.Lerp
function CFmethods.ToWorldSpace(a, ...)
	local out = {}
	for i, c in { ... } do
		out[i] = a * c
	end
	return table.unpack(out)
end
function CFmethods.ToObjectSpace(a, ...)
	local inv = a:Inverse()
	local out = {}
	for i, c in { ... } do
		out[i] = inv * c
	end
	return table.unpack(out)
end
function CFmethods.PointToWorldSpace(a, ...)
	local out = {}
	for i, v in { ... } do
		out[i] = a * v
	end
	return table.unpack(out)
end
function CFmethods.PointToObjectSpace(a, ...)
	local inv = a:Inverse()
	local out = {}
	for i, v in { ... } do
		out[i] = inv * v
	end
	return table.unpack(out)
end
function CFmethods.VectorToWorldSpace(a, ...)
	local out = {}
	for i, v in { ... } do
		out[i] = v3(rotVec(a._r, v.X, v.Y, v.Z))
	end
	return table.unpack(out)
end
function CFmethods.VectorToObjectSpace(a, ...)
	local t = transpose(a._r)
	local out = {}
	for i, v in { ... } do
		out[i] = v3(rotVec(t, v.X, v.Y, v.Z))
	end
	return table.unpack(out)
end
function CFmethods.GetComponents(a)
	local r = a._r
	return a._x, a._y, a._z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]
end
CFmethods.components = CFmethods.GetComponents
function CFmethods.ToEulerAnglesXYZ(a)
	local r = a._r
	local y = math.asin(math.clamp(r[3], -1, 1))
	local x = math.atan2(-r[6], r[9])
	local z = math.atan2(-r[2], r[1])
	return x, y, z
end
CFmethods.toEulerAnglesXYZ = CFmethods.ToEulerAnglesXYZ
function CFmethods.ToEulerAnglesYXZ(a)
	local r = a._r
	local x = math.asin(math.clamp(-r[6], -1, 1))
	local y = math.atan2(r[3], r[9])
	local z = math.atan2(r[4], r[5])
	return x, y, z
end
CFmethods.ToOrientation = CFmethods.ToEulerAnglesYXZ
function CFmethods.ToAxisAngle(a)
	local qx, qy, qz, qw = rotToQuat(a._r)
	local angle = 2 * math.acos(math.clamp(qw, -1, 1))
	local s = math.sqrt(1 - qw * qw)
	if s < 1e-6 then
		return v3(1, 0, 0), angle
	end
	return v3(qx / s, qy / s, qz / s), angle
end
function CFmethods.Orthonormalize(a)
	return a
end
function CFmethods.FuzzyEq(a, b, eps)
	if not (fuzzy(a._x, b._x, eps) and fuzzy(a._y, b._y, eps) and fuzzy(a._z, b._z, eps)) then
		return false
	end
	for i = 1, 9 do
		if not fuzzy(a._r[i], b._r[i], eps) then
			return false
		end
	end
	return true
end

D.CFrame = {}
function D.CFrame.new(...)
	local n = select("#", ...)
	local a = { ... }
	if n == 0 then
		return cfIdentityAt(0, 0, 0)
	elseif n == 1 then
		local p = a[1]
		return cfIdentityAt(p.X, p.Y, p.Z)
	elseif n == 2 then
		local p, t = a[1], a[2]
		return fromRot(p.X, p.Y, p.Z, lookAtRot(p, t))
	elseif n == 3 then
		return cfIdentityAt(a[1], a[2], a[3])
	elseif n == 7 then
		return fromRot(a[1], a[2], a[3], quatToRot(a[4], a[5], a[6], a[7]))
	elseif n == 12 then
		return cf(table.unpack(a))
	end
	error("invalid arguments to CFrame.new", 2)
end
function D.CFrame.lookAt(at, target, up)
	return fromRot(at.X, at.Y, at.Z, lookAtRot(at, target, up))
end
function D.CFrame.lookAlong(at, dir, up)
	return D.CFrame.lookAt(at, at + dir, up)
end
function D.CFrame.Angles(x, y, z)
	return fromRot(0, 0, 0, rotMul(rotMul(rx(x or 0), ry(y or 0)), rz(z or 0)))
end
D.CFrame.fromEulerAnglesXYZ = D.CFrame.Angles
function D.CFrame.fromEulerAnglesYXZ(x, y, z)
	return fromRot(0, 0, 0, rotMul(rotMul(ry(y or 0), rx(x or 0)), rz(z or 0)))
end
D.CFrame.fromOrientation = D.CFrame.fromEulerAnglesYXZ
function D.CFrame.fromEulerAngles(x, y, z)
	return D.CFrame.Angles(x, y, z)
end
function D.CFrame.fromAxisAngle(axis, angle)
	local u = axis.Unit
	local s = math.sin(angle / 2)
	return fromRot(0, 0, 0, quatToRot(u.X * s, u.Y * s, u.Z * s, math.cos(angle / 2)))
end
function D.CFrame.fromMatrix(pos, vx, vy, vz)
	vz = vz or vx:Cross(vy).Unit
	return cf(pos.X, pos.Y, pos.Z, vx.X, vy.X, vz.X, vx.Y, vy.Y, vz.Y, vx.Z, vy.Z, vz.Z)
end
D.CFrame.identity = cfIdentityAt(0, 0, 0)

---------------------------------------------------------------- Color3
local C3 = { __type = "Color3" }
local C3methods = {}
local function c3(r, g, b)
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, C3)
end
C3.__index = function(_, k)
	local m = C3methods[k]
	if m then
		return m
	end
	if k == "r" or k == "g" or k == "b" then
		return rawget(_, string.upper(k))
	end
	error(`{k} is not a valid member of Color3`, 2)
end
C3.__newindex = readonly
C3.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end
C3.__tostring = function(a)
	return `{a.R}, {a.G}, {a.B}`
end
function C3methods.Lerp(a, b, t)
	return c3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end
function C3methods.ToHSV(c)
	local r, g, b = c.R, c.G, c.B
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local d = mx - mn
	local h = 0
	if d > 0 then
		if mx == r then
			h = ((g - b) / d) % 6
		elseif mx == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h /= 6
	end
	local s = if mx == 0 then 0 else d / mx
	return h, s, mx
end
function C3methods.ToHex(c)
	return string.format(
		"%02X%02X%02X",
		math.floor(c.R * 255 + 0.5),
		math.floor(c.G * 255 + 0.5),
		math.floor(c.B * 255 + 0.5)
	)
end
D.Color3 = { new = c3 }
function D.Color3.fromRGB(r, g, b)
	return c3((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end
function D.Color3.fromHSV(h, s, v)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	i = i % 6
	if i == 0 then
		return c3(v, t, p)
	elseif i == 1 then
		return c3(q, v, p)
	elseif i == 2 then
		return c3(p, v, t)
	elseif i == 3 then
		return c3(p, q, v)
	elseif i == 4 then
		return c3(t, p, v)
	end
	return c3(v, p, q)
end
function D.Color3.fromHex(hex)
	hex = string.gsub(hex, "#", "")
	return D.Color3.fromRGB(
		tonumber(string.sub(hex, 1, 2), 16),
		tonumber(string.sub(hex, 3, 4), 16),
		tonumber(string.sub(hex, 5, 6), 16)
	)
end
D.Color3.toHSV = C3methods.ToHSV

---------------------------------------------------------------- UDim / UDim2
local UD = { __type = "UDim" }
UD.__index = function(_, k)
	error(`{k} is not a valid member of UDim`, 2)
end
UD.__newindex = readonly
local function udim(s, o)
	return setmetatable({ Scale = s or 0, Offset = o or 0 }, UD)
end
UD.__add = function(a, b)
	return udim(a.Scale + b.Scale, a.Offset + b.Offset)
end
UD.__sub = function(a, b)
	return udim(a.Scale - b.Scale, a.Offset - b.Offset)
end
UD.__eq = function(a, b)
	return a.Scale == b.Scale and a.Offset == b.Offset
end
UD.__tostring = function(a)
	return `{a.Scale}, {a.Offset}`
end
D.UDim = { new = udim }

local U2 = { __type = "UDim2" }
local U2methods = {}
local function udim2(xs, xo, ys, yo)
	return setmetatable({ X = udim(xs, xo), Y = udim(ys, yo) }, U2)
end
U2.__index = function(self, k)
	local m = U2methods[k]
	if m then
		return m
	end
	if k == "Width" then
		return rawget(self, "X")
	elseif k == "Height" then
		return rawget(self, "Y")
	end
	error(`{k} is not a valid member of UDim2`, 2)
end
U2.__newindex = readonly
U2.__add = function(a, b)
	return udim2(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset)
end
U2.__sub = function(a, b)
	return udim2(a.X.Scale - b.X.Scale, a.X.Offset - b.X.Offset, a.Y.Scale - b.Y.Scale, a.Y.Offset - b.Y.Offset)
end
U2.__unm = function(a)
	return udim2(-a.X.Scale, -a.X.Offset, -a.Y.Scale, -a.Y.Offset)
end
U2.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
U2.__tostring = function(a)
	return `\{{a.X}}, \{{a.Y}}`
end
function U2methods.Lerp(a, b, t)
	local function l(x, y)
		return x + (y - x) * t
	end
	return udim2(l(a.X.Scale, b.X.Scale), l(a.X.Offset, b.X.Offset), l(a.Y.Scale, b.Y.Scale), l(a.Y.Offset, b.Y.Offset))
end
D.UDim2 = {}
function D.UDim2.new(a, b, c, d)
	if getmetatable(a) == UD then
		return udim2(a.Scale, a.Offset, b.Scale, b.Offset)
	end
	return udim2(a, b, c, d)
end
function D.UDim2.fromScale(x, y)
	return udim2(x, 0, y, 0)
end
function D.UDim2.fromOffset(x, y)
	return udim2(0, x, 0, y)
end

---------------------------------------------------------------- simple records
local function record(typeName, fields)
	local mt = { __type = typeName }
	mt.__index = function(_, k)
		error(`{k} is not a valid member of {typeName}`, 2)
	end
	mt.__newindex = readonly
	mt.__tostring = function()
		return typeName
	end
	return setmetatable(fields, mt)
end

D.TweenInfo = {}
function D.TweenInfo.new(time, style, dir, repeatCount, reverses, delayTime)
	return record("TweenInfo", {
		Time = time or 1,
		EasingStyle = style or D.Enum.EasingStyle.Quad,
		EasingDirection = dir or D.Enum.EasingDirection.Out,
		RepeatCount = repeatCount or 0,
		Reverses = reverses or false,
		DelayTime = delayTime or 0,
	})
end

D.NumberRange = {}
function D.NumberRange.new(min, max)
	return record("NumberRange", { Min = min, Max = max or min })
end

D.NumberSequenceKeypoint = {}
function D.NumberSequenceKeypoint.new(t, v, e)
	return record("NumberSequenceKeypoint", { Time = t, Value = v, Envelope = e or 0 })
end
D.NumberSequence = {}
function D.NumberSequence.new(a, b)
	local kps
	if type(a) == "table" then
		kps = a
	else
		kps = { D.NumberSequenceKeypoint.new(0, a), D.NumberSequenceKeypoint.new(1, b or a) }
	end
	return record("NumberSequence", { Keypoints = kps })
end

D.ColorSequenceKeypoint = {}
function D.ColorSequenceKeypoint.new(t, c)
	assert(getmetatable(c) == C3, "ColorSequenceKeypoint.new expects a Color3")
	return record("ColorSequenceKeypoint", { Time = t, Value = c })
end
D.ColorSequence = {}
function D.ColorSequence.new(a, b)
	local kps
	if getmetatable(a) == C3 then
		kps = { D.ColorSequenceKeypoint.new(0, a), D.ColorSequenceKeypoint.new(1, b or a) }
	else
		kps = a
	end
	assert(type(kps) == "table" and #kps >= 2, "ColorSequence.new needs at least 2 keypoints")
	return record("ColorSequence", { Keypoints = kps })
end

D.Rect = {}
function D.Rect.new(a, b, c, d)
	if type(a) == "number" then
		return record("Rect", { Min = v2(a, b), Max = v2(c, d), Width = c - a, Height = d - b })
	end
	return record("Rect", { Min = a, Max = b, Width = b.X - a.X, Height = b.Y - a.Y })
end

D.PhysicalProperties = {}
function D.PhysicalProperties.new(density, friction, elasticity, fw, ew)
	return record("PhysicalProperties", {
		Density = density,
		Friction = friction or 0.3,
		Elasticity = elasticity or 0.5,
		FrictionWeight = fw or 1,
		ElasticityWeight = ew or 1,
	})
end

D.Ray = {}
function D.Ray.new(origin, dir)
	return record("Ray", { Origin = origin, Direction = dir })
end

D.BrickColor = {}
local function brick(name)
	return record("BrickColor", { Name = name, Color = c3(0.6, 0.6, 0.6), Number = 194 })
end
function D.BrickColor.new(name)
	return brick(tostring(name))
end
function D.BrickColor.random()
	return brick("Medium stone grey")
end
for _, n in { "White", "Black", "Red", "Blue", "Green", "Yellow", "Gray", "DarkGray" } do
	D.BrickColor[n] = function()
		return brick(n)
	end
end

D.Font = {}
function D.Font.new(family, weight, style)
	return record("Font", { Family = family, Weight = weight, Style = style, Bold = false })
end
function D.Font.fromEnum(e)
	return D.Font.new("rbxasset://fonts/families/" .. e.Name .. ".json")
end
function D.Font.fromName(name, weight, style)
	return D.Font.new("rbxasset://fonts/families/" .. name .. ".json", weight, style)
end
function D.Font.fromId(id, weight, style)
	return D.Font.new("rbxassetid://" .. tostring(id), weight, style)
end

---------------------------------------------------------------- Random
-- Deterministic xorshift-ish generator so runs are reproducible.
local RandomMT = { __type = "Random" }
local RandomMethods = {}
RandomMT.__index = RandomMethods
local function nextFloat(self)
	-- Park-Miller minimal standard
	self._s = (self._s * 48271) % 2147483647
	return (self._s - 1) / 2147483646
end
function RandomMethods.NextNumber(self, min, max)
	min = min or 0
	max = max or 1
	return min + (max - min) * nextFloat(self)
end
function RandomMethods.NextInteger(self, min, max)
	assert(type(min) == "number" and type(max) == "number", "NextInteger needs min and max")
	if max < min then
		error("invalid argument #2 to 'NextInteger' (interval is empty)", 2)
	end
	return min + math.floor(nextFloat(self) * (max - min + 1))
end
function RandomMethods.NextUnitVector(self)
	local z = self:NextNumber(-1, 1)
	local a = self:NextNumber(0, 2 * math.pi)
	local r = math.sqrt(1 - z * z)
	return v3(r * math.cos(a), r * math.sin(a), z)
end
function RandomMethods.Shuffle(self, t)
	for i = #t, 2, -1 do
		local j = self:NextInteger(1, i)
		t[i], t[j] = t[j], t[i]
	end
end
function RandomMethods.Clone(self)
	return setmetatable({ _s = self._s }, RandomMT)
end
local seedCounter = 12345
D.Random = {}
function D.Random.new(seed)
	if seed == nil then
		seedCounter += 7919
		seed = seedCounter
	end
	local s = math.floor(math.abs(seed)) % 2147483646 + 1
	return setmetatable({ _s = s }, RandomMT)
end

---------------------------------------------------------------- Enum
-- Enum.<Type>.<Item> is created lazily, so any enum name works. Value is a stable counter per type.
local EnumItemMT = { __type = "EnumItem" }
EnumItemMT.__index = function(self, k)
	if k == "IsA" then
		return function(_, typeName)
			return rawget(self, "_typeName") == typeName
		end
	end
	error(`{k} is not a valid member of EnumItem`, 2)
end
EnumItemMT.__newindex = readonly
EnumItemMT.__tostring = function(self)
	return `Enum.{rawget(self, "_typeName")}.{rawget(self, "Name")}`
end

local EnumTypeMT = { __type = "Enum" }
local enumTypes = {}
EnumTypeMT.__index = function(self, k)
	if k == "GetEnumItems" then
		return function()
			local out = {}
			for _, item in rawget(self, "_items") do
				table.insert(out, item)
			end
			table.sort(out, function(a, b)
				return a.Value < b.Value
			end)
			return out
		end
	elseif k == "FromName" then
		return function(_, name)
			return self[name]
		end
	elseif k == "FromValue" then
		return function(_, value)
			for _, item in rawget(self, "_items") do
				if item.Value == value then
					return item
				end
			end
			return nil
		end
	end
	local items = rawget(self, "_items")
	local item = items[k]
	if not item then
		local count = rawget(self, "_count") + 1
		rawset(self, "_count", count)
		item = setmetatable({ Name = k, Value = count - 1, _typeName = rawget(self, "_name") }, EnumItemMT)
		rawset(item, "EnumType", self)
		items[k] = item
	end
	return item
end
EnumTypeMT.__newindex = readonly
EnumTypeMT.__tostring = function(self)
	return rawget(self, "_name")
end
D.Enum = setmetatable({}, {
	__type = "Enums",
	__index = function(_, k)
		local t = enumTypes[k]
		if not t then
			t = setmetatable({ _name = k, _items = {}, _count = 0 }, EnumTypeMT)
			enumTypes[k] = t
		end
		return t
	end,
	__newindex = readonly,
})
-- Pre-seed enums whose order matters for comparisons or defaults.
for _, n in { "Begin", "Change", "End", "Cancel", "None" } do
	local _ = D.Enum.UserInputState[n]
end
for _, n in { "Begin", "Playing", "Paused", "Completed", "Cancelled", "Delayed" } do
	local _ = D.Enum.PlaybackState[n]
end

---------------------------------------------------------------- typeof
function D.typeof(v)
	local t = type(v)
	if t == "table" then
		local mt = getmetatable(v)
		if type(mt) == "table" then
			local name = rawget(mt, "__type")
			if name then
				return name
			end
		end
	end
	return typeof(v)
end

return D
