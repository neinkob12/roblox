--!nocheck
-- Roblox services and context-aware classes (Player, RemoteEvent, RemoteFunction, Tween...).
-- One instance tree is shared by the fake server and all fake clients (a "perfect replication"
-- simplification). Behavior that differs per side (RunService:IsServer, Players.LocalPlayer,
-- OnClientEvent) looks at the context of the running thread.

local S = require("./Scheduler")
local Signal = require("./Signal")
local D = require("./Datatypes")
local Inst = require("./Instance")

local serde = require("@lune/serde")

local Vector3, Vector2, CFrame, Color3, Enum = D.Vector3, D.Vector2, D.CFrame, D.Color3, D.Enum
local simple, I, NIL = Inst.simple, Inst.I, Inst.NIL

local M = {}
M.state = {
	server = nil, -- server context
	clients = {}, -- [Player] = client context
	game = nil,
	ownedPasses = {}, -- [userId] = { [passId] = true }
	friends = {}, -- [userId] = { [userId] = true }
	prompts = {}, -- recorded MarketplaceService prompts
	kicked = {}, -- [userId] = message
	bindToClose = {},
	stores = {}, -- in-memory DataStores
	device = "phone",
}
local state = M.state

local function ctx()
	return S.current()
end

local function requireServer(what)
	if not ctx().isServer then
		error(`{what} can only be called from the server`, 3)
	end
end
local function requireClient(what)
	if not ctx().isClient then
		error(`{what} can only be called from the client`, 3)
	end
end

-- Remote payloads are copied like Roblox serializes them: tables become new tables (no
-- metatables), functions and threads become nil, Instances pass by reference.
local function copyArg(v, seen)
	local t = type(v)
	if t == "function" or t == "thread" then
		return nil
	end
	if t ~= "table" then
		return v
	end
	if Inst.is(v) then
		return v
	end
	local mt = getmetatable(v)
	if mt and rawget(mt, "__type") then
		return v -- immutable datatype
	end
	seen = seen or {}
	if seen[v] then
		error("Tables with cyclic references cannot be sent over remotes", 4)
	end
	seen[v] = true
	local out = {}
	for k, x in v do
		out[copyArg(k, seen)] = copyArg(x, seen)
	end
	seen[v] = nil
	return out
end
M.copyArg = copyArg
local function copyArgs(...)
	local n = select("#", ...)
	local a = { ... }
	for i = 1, n do
		a[i] = copyArg(a[i])
	end
	return a, n
end

local function isPlayer(v)
	return Inst.is(v) and I(v).className == "Player"
end

---------------------------------------------------------------- DataModel
simple("ServiceProvider", "Instance", {}, { creatable = false })
local serviceClasses = {}
local function service(name, props, extra)
	extra = extra or {}
	extra.creatable = false
	serviceClasses[name] = true
	return simple(name, extra.super or "Instance", props or {}, extra)
end
M.serviceClasses = serviceClasses

local function getService(self, name)
	local found = self:FindFirstChildOfClass(name)
	if found then
		return found
	end
	if not serviceClasses[name] then
		error(`'{tostring(name)}' is not a valid Service name`, 2)
	end
	local s = Inst.create(name)
	s.Name = name
	s.Parent = self
	return s
end

simple("DataModel", "ServiceProvider", {
	PlaceId = 1234567,
	GameId = 7654321,
	JobId = "",
	PlaceVersion = 1,
	CreatorId = 0,
	CreatorType = Enum.CreatorType.User,
	PrivateServerId = "",
	PrivateServerOwnerId = 0,
	Genre = Enum.Genre.All,
}, {
	creatable = false,
	events = { "Loaded", "Close" },
	getters = {
		Workspace = function(self)
			return getService(self, "Workspace")
		end,
		workspace = function(self)
			return getService(self, "Workspace")
		end,
		Lighting = function(self)
			return getService(self, "Lighting")
		end,
	},
	methods = {
		GetService = getService,
		service = getService,
		FindService = function(self, name)
			return self:FindFirstChildOfClass(name)
		end,
		BindToClose = function(_, fn)
			requireServer("BindToClose")
			table.insert(state.bindToClose, { fn = fn, ctx = ctx() })
		end,
		IsLoaded = function()
			return true
		end,
		GetJobsInfo = function()
			return {}
		end,
	},
})

---------------------------------------------------------------- simple services
-- Workspace class already exists (from Instance.luau); add methods
Inst.extend("Workspace", {
	getters = {
		CurrentCamera = function(self, d)
			local cam = d.props.CurrentCamera
			if not cam then
				cam = Inst.create("Camera")
				cam.Name = "Camera"
				cam.Parent = self
				d.props.CurrentCamera = cam
			end
			return cam
		end,
		Terrain = function(self, d)
			local t = self:FindFirstChildOfClass("Terrain")
			if not t then
				t = Inst.create("Terrain")
				t.Name = "Terrain"
				t.Parent = self
			end
			return t
		end,
	},
	setters = {
		CurrentCamera = function(self, d, v)
			d.props.CurrentCamera = v
		end,
	},
	methods = {
		GetServerTimeNow = function()
			return S.epoch + S.now
		end,
		Raycast = function()
			return nil
		end,
		Blockcast = function()
			return nil
		end,
		Spherecast = function()
			return nil
		end,
		GetPartBoundsInBox = function()
			return {}
		end,
		GetPartBoundsInRadius = function()
			return {}
		end,
		GetPartsInPart = function()
			return {}
		end,
		FindPartOnRay = function()
			return nil
		end,
		GetRealPhysicsFPS = function()
			return 60
		end,
	},
})
serviceClasses.Workspace = true

service("ReplicatedStorage")
service("ReplicatedFirst", nil, { methods = { RemoveDefaultLoadingScreen = function() end } })
service("ServerScriptService", { LoadStringEnabled = false })
service("ServerStorage")
service("StarterPack")
service("StarterPlayer", {
	CharacterWalkSpeed = 16,
	CharacterJumpPower = 50,
	CharacterJumpHeight = 7.2,
	CharacterUseJumpPower = false,
	CameraMaxZoomDistance = 128,
	CameraMinZoomDistance = 0.5,
	AutoJumpEnabled = true,
	LoadCharacterAppearance = true,
	EnableMouseLockOption = true,
	DevTouchMovementMode = Enum.DevTouchMovementMode.UserChoice,
	DevComputerMovementMode = Enum.DevComputerMovementMode.UserChoice,
})
simple("StarterPlayerScripts", "Instance", {}, { creatable = false })
simple("StarterCharacterScripts", "Instance", {}, { creatable = false })
service("Teams", nil, {
	methods = {
		GetTeams = function(self)
			return self:GetChildren()
		end,
	},
})
simple("Team", "Instance", { TeamColor = D.BrickColor.new("White"), AutoAssignable = true }, {
	events = { "PlayerAdded", "PlayerRemoved" },
	methods = {
		GetPlayers = function()
			return {}
		end,
	},
})
service("Lighting", {
	Ambient = Color3.fromRGB(70, 70, 70),
	Brightness = 2,
	ClockTime = 14,
	ColorShift_Bottom = Color3.new(0, 0, 0),
	ColorShift_Top = Color3.new(0, 0, 0),
	EnvironmentDiffuseScale = 0,
	EnvironmentSpecularScale = 0,
	ExposureCompensation = 0,
	FogColor = Color3.fromRGB(192, 192, 192),
	FogEnd = 100000,
	FogStart = 0,
	GeographicLatitude = 41.73,
	GlobalShadows = true,
	OutdoorAmbient = Color3.fromRGB(128, 128, 128),
	ShadowSoftness = 0.2,
	TimeOfDay = "14:00:00",
	Technology = Enum.Technology.ShadowMap,
}, {
	events = { "LightingChanged" },
	methods = {
		GetMinutesAfterMidnight = function(self)
			return self.ClockTime * 60
		end,
		SetMinutesAfterMidnight = function(self, m)
			self.ClockTime = m / 60
		end,
		GetSunDirection = function()
			return Vector3.new(0, 1, 0)
		end,
		GetMoonDirection = function()
			return Vector3.new(0, -1, 0)
		end,
	},
})
service("SoundService", {
	RespectFilteringEnabled = true,
	AmbientReverb = Enum.ReverbType.NoReverb,
	DistanceFactor = 3.33,
	DopplerScale = 1,
	RolloffScale = 1,
	VolumetricAudio = Enum.VolumetricAudio.Automatic,
}, {
	methods = {
		PlayLocalSound = function(_, sound)
			if sound then
				sound:Play()
			end
		end,
		GetListener = function()
			return Enum.ListenerType.Camera, nil
		end,
		SetListener = function() end,
	},
})
service("Chat", { LoadDefaultChat = true, BubbleChatEnabled = true })
service("StarterGui", { ShowDevelopmentGui = true, ResetPlayerGuiOnSpawn = true }, {
	init = function(_, d)
		d.core = {}
		d.coreSet = {}
	end,
	methods = {
		SetCoreGuiEnabled = function(self, t, enabled)
			assert(D.typeof(t) == "EnumItem", "SetCoreGuiEnabled expects an Enum.CoreGuiType")
			I(self).core[t.Name] = enabled
		end,
		GetCoreGuiEnabled = function(self, t)
			local v = I(self).core[t.Name]
			if v == nil then
				return true
			end
			return v
		end,
		SetCore = function(self, name, value)
			I(self).coreSet[name] = value
		end,
		GetCore = function(self, name)
			return I(self).coreSet[name]
		end,
	},
})
service("GuiService", {
	AutoSelectGuiEnabled = true,
	GuiNavigationEnabled = true,
	SelectedObject = NIL,
	MenuIsOpen = false,
	TouchControlsEnabled = true,
}, {
	events = { "MenuOpened", "MenuClosed" },
	getters = {
		TopbarInset = function()
			return D.Rect.new(0, 0, 844, 36)
		end,
		PreferredTransparency = function()
			return 1
		end,
		ReducedMotionEnabled = function()
			return false
		end,
	},
	methods = {
		GetGuiInset = function()
			return Vector2.new(0, 36), Vector2.new(0, 0)
		end,
		IsTenFootInterface = function()
			return false
		end,
		CloseInspectMenu = function() end,
	},
})
service("UserInputService", {
	MouseBehavior = Enum.MouseBehavior.Default,
	MouseIconEnabled = true,
	MouseDeltaSensitivity = 1,
	ModalEnabled = false,
	OverrideMouseIconBehavior = Enum.OverrideMouseIconBehavior.None,
}, {
	events = {
		"InputBegan",
		"InputEnded",
		"InputChanged",
		"TouchStarted",
		"TouchEnded",
		"TouchMoved",
		"TouchTap",
		"TouchTapInWorld",
		"TouchLongPress",
		"TouchPinch",
		"TouchSwipe",
		"TouchPan",
		"LastInputTypeChanged",
		"JumpRequest",
		"WindowFocused",
		"WindowFocusReleased",
		"TextBoxFocused",
		"TextBoxFocusReleased",
		"GamepadConnected",
		"GamepadDisconnected",
	},
	getters = {
		TouchEnabled = function()
			return state.device == "phone"
		end,
		KeyboardEnabled = function()
			return state.device ~= "phone"
		end,
		MouseEnabled = function()
			return state.device ~= "phone"
		end,
		GamepadEnabled = function()
			return false
		end,
		AccelerometerEnabled = function()
			return state.device == "phone"
		end,
		GyroscopeEnabled = function()
			return false
		end,
		VREnabled = function()
			return false
		end,
		PreferredInput = function()
			return if state.device == "phone" then Enum.PreferredInput.Touch else Enum.PreferredInput.KeyboardAndMouse
		end,
	},
	methods = {
		GetLastInputType = function()
			return if state.device == "phone" then Enum.UserInputType.Touch else Enum.UserInputType.MouseButton1
		end,
		IsKeyDown = function()
			return false
		end,
		IsMouseButtonPressed = function()
			return false
		end,
		GetKeysPressed = function()
			return {}
		end,
		GetMouseLocation = function()
			return Vector2.new(422, 195)
		end,
		GetMouseDelta = function()
			return Vector2.zero
		end,
		GetFocusedTextBox = function()
			return nil
		end,
		GetConnectedGamepads = function()
			return {}
		end,
		GetNavigationGamepads = function()
			return {}
		end,
		GetGamepadConnected = function()
			return false
		end,
		GetPlatform = function()
			return if state.device == "phone" then Enum.Platform.IOS else Enum.Platform.Windows
		end,
		GetStringForKeyCode = function(_, k)
			return k.Name
		end,
		GetDeviceRotation = function()
			return nil, CFrame.identity
		end,
	},
})
service("ContextActionService", nil, {
	events = { "LocalToolEquipped", "LocalToolUnequipped" },
	methods = {
		BindAction = function() end,
		BindActionAtPriority = function() end,
		UnbindAction = function() end,
		UnbindAllActions = function() end,
		SetTitle = function() end,
		SetImage = function() end,
		SetPosition = function() end,
		SetDescription = function() end,
		GetButton = function()
			return nil
		end,
		GetAllBoundActionInfo = function()
			return {}
		end,
	},
})
service("HapticService", nil, {
	methods = {
		IsVibrationSupported = function()
			return false
		end,
		IsMotorSupported = function()
			return false
		end,
		SetMotor = function() end,
	},
})
service("VRService", { VREnabled = false })
service("ContentProvider", { RequestQueueSize = 0, BaseUrl = "https://www.roblox.com/" }, {
	methods = {
		PreloadAsync = function(_, list, cb)
			if cb then
				for _, a in list do
					cb(if type(a) == "string" then a else "", Enum.AssetFetchStatus.Success)
				end
			end
		end,
	},
})
service("Debris", { MaxItems = 1000 }, {
	methods = {
		AddItem = function(_, inst, t)
			S.task.delay(t or 10, function()
				if Inst.is(inst) then
					inst:Destroy()
				end
			end)
		end,
	},
})
service("CollectionService", nil, {
	events = { "TagAdded", "TagRemoved" },
	methods = {
		GetTagged = function(_, tag)
			local out = {}
			for _, x in Inst.descendants(state.game) do
				if I(x).tags[tag] then
					table.insert(out, x)
				end
			end
			return out
		end,
		AddTag = function(_, inst, tag)
			inst:AddTag(tag)
		end,
		RemoveTag = function(_, inst, tag)
			inst:RemoveTag(tag)
		end,
		HasTag = function(_, inst, tag)
			return inst:HasTag(tag)
		end,
		GetTags = function(_, inst)
			return inst:GetTags()
		end,
		GetInstanceAddedSignal = function(self, tag)
			return Inst.getSignal(self, "Added:" .. tag)
		end,
		GetInstanceRemovedSignal = function(self, tag)
			return Inst.getSignal(self, "Removed:" .. tag)
		end,
		GetAllTags = function()
			return {}
		end,
	},
})
service("PhysicsService", nil, {
	init = function(_, d)
		d.groups = { Default = true }
	end,
	methods = {
		RegisterCollisionGroup = function(self, name)
			I(self).groups[name] = true
		end,
		CreateCollisionGroup = function(self, name)
			I(self).groups[name] = true
			return 1
		end,
		UnregisterCollisionGroup = function(self, name)
			I(self).groups[name] = nil
		end,
		IsCollisionGroupRegistered = function(self, name)
			return I(self).groups[name] == true
		end,
		CollisionGroupSetCollidable = function(self, a, b)
			if not I(self).groups[a] or not I(self).groups[b] then
				error(`CollisionGroupSetCollidable: collision group not registered ({a}, {b})`, 2)
			end
		end,
		CollisionGroupsAreCollidable = function()
			return true
		end,
		GetRegisteredCollisionGroups = function(self)
			local out = {}
			for n in I(self).groups do
				table.insert(out, { name = n, mask = 0 })
			end
			return out
		end,
		GetMaxCollisionGroups = function()
			return 32
		end,
		SetPartCollisionGroup = function(_, part, name)
			part.CollisionGroup = name
		end,
	},
})
service("TextService", nil, {
	methods = {
		GetTextSize = function(_, text, size)
			return Vector2.new(#text * size * 0.5, size)
		end,
		FilterStringAsync = function(_, text)
			local r = Inst.create("TextFilterResult")
			I(r).text = text
			return r
		end,
		GetTextBoundsAsync = function(_, params)
			return Vector2.new(#(params.Text or "") * (params.Size or 14) * 0.5, params.Size or 14)
		end,
	},
})
simple("TextFilterResult", "Instance", {}, {
	creatable = false,
	methods = {
		GetNonChatStringForBroadcastAsync = function(self)
			return I(self).text
		end,
		GetNonChatStringForUserAsync = function(self)
			return I(self).text
		end,
		GetChatForUserAsync = function(self)
			return I(self).text
		end,
	},
})
service("LocalizationService", { RobloxLocaleId = "en-us", SystemLocaleId = "en-us" }, {
	methods = {
		GetCountryRegionForPlayerAsync = function()
			return "US"
		end,
		GetTranslatorForPlayerAsync = function()
			error("no localization table in tests", 2)
		end,
	},
})
service("PolicyService", nil, {
	methods = {
		GetPolicyInfoForPlayerAsync = function()
			return {
				AreAdsAllowed = true,
				ArePaidRandomItemsRestricted = false,
				AllowedExternalLinkReferences = {},
				IsContentSharingAllowed = true,
				IsPaidItemTradingAllowed = true,
				IsSubjectToChinaPolicies = false,
			}
		end,
	},
})
service("SocialService", nil, {
	events = { "GameInvitePromptClosed" },
	methods = {
		CanSendGameInviteAsync = function()
			return false
		end,
		PromptGameInvite = function() end,
	},
})
service("BadgeService", nil, {
	methods = {
		AwardBadge = function()
			return true
		end,
		UserHasBadgeAsync = function()
			return false
		end,
		GetBadgeInfoAsync = function()
			return { Name = "Badge", IsEnabled = true }
		end,
	},
})
service("GroupService", nil, {
	methods = {
		GetGroupInfoAsync = function(_, id)
			return { Id = id, Name = "Group", Owner = { Id = 1 }, Roles = {} }
		end,
		GetGroupsAsync = function()
			return {}
		end,
	},
})
service("TeleportService", nil, {
	events = { "TeleportInitFailed", "LocalPlayerArrivedFromTeleport" },
	methods = {
		Teleport = function() end,
		TeleportAsync = function() end,
		GetLocalPlayerTeleportData = function()
			return nil
		end,
	},
})
service("AnalyticsService", nil, {
	methods = {
		LogEconomyEvent = function() end,
		LogCustomEvent = function() end,
		LogOnboardingFunnelStepEvent = function() end,
		LogProgressionEvent = function() end,
		LogFunnelStepEvent = function() end,
		LogProgressionStartEvent = function() end,
		LogProgressionCompleteEvent = function() end,
		LogProgressionFailEvent = function() end,
	},
})
service("ProximityPromptService", { Enabled = true, MaxPromptsVisible = 16 }, {
	events = { "PromptTriggered", "PromptShown", "PromptHidden", "PromptButtonHoldBegan", "PromptButtonHoldEnded" },
})
service("InsertService", nil, {
	methods = {
		LoadAsset = function()
			error("InsertService is not allowed (no Toolbox/free models)", 2)
		end,
	},
})
service("AssetService", nil, {
	methods = {
		CreateEditableImage = function()
			error("EditableImage not mocked", 2)
		end,
	},
})
service("HttpService", { HttpEnabled = false }, {
	init = function(_, d)
		d.guid = 0
	end,
	methods = {
		GenerateGUID = function(self, wrap)
			local d = I(self)
			d.guid += 1
			local g = string.format("%08X-0000-4000-8000-%012X", d.guid, d.guid)
			if wrap == false then
				return g
			end
			return "{" .. g .. "}"
		end,
		JSONEncode = function(_, v)
			return serde.encode("json", v)
		end,
		JSONDecode = function(_, s)
			return serde.decode("json", s)
		end,
		UrlEncode = function(_, s)
			return (string.gsub(s, "[^%w%-_%.~]", function(c)
				return string.format("%%%02X", string.byte(c))
			end))
		end,
		GetAsync = function()
			error("Http requests are not enabled. Enable via game settings", 2)
		end,
		PostAsync = function()
			error("Http requests are not enabled. Enable via game settings", 2)
		end,
		RequestAsync = function()
			error("Http requests are not enabled. Enable via game settings", 2)
		end,
	},
})

---------------------------------------------------------------- RunService
service("RunService", nil, {
	events = {
		"Heartbeat",
		"Stepped",
		"RenderStepped",
		"PreSimulation",
		"PostSimulation",
		"PreRender",
		"PreAnimation",
	},
	init = function(self, d)
		local onlyClients = {
			filter = function(c)
				return c.isClient == true
			end,
		}
		d.signals.RenderStepped = Signal.new("RenderStepped", onlyClients)
		d.signals.PreRender = Signal.new("PreRender", onlyClients)
		d.bound = {} -- [ctx] = { name -> {prio, fn} }
	end,
	methods = {
		IsServer = function()
			return ctx().isServer == true
		end,
		IsClient = function()
			return ctx().isClient == true
		end,
		IsStudio = function()
			return true
		end,
		IsRunning = function()
			return true
		end,
		IsRunMode = function()
			return false
		end,
		IsEdit = function()
			return false
		end,
		BindToRenderStep = function(self, name, prio, fn)
			requireClient("BindToRenderStep")
			local d = I(self)
			local c = ctx()
			d.bound[c] = d.bound[c] or {}
			d.bound[c][name] = { prio = prio, fn = fn }
		end,
		UnbindFromRenderStep = function(self, name)
			local d = I(self)
			local c = ctx()
			if d.bound[c] then
				d.bound[c][name] = nil
			end
		end,
	},
})

function M.frameHook(runService)
	return function(dt)
		local d = I(runService)
		local s = d.signals
		if s.PreAnimation then
			s.PreAnimation:Fire(dt)
		end
		if s.Stepped then
			s.Stepped:Fire(S.now, dt)
		end
		if s.PreSimulation then
			s.PreSimulation:Fire(dt)
		end
		for c, list in d.bound do
			local items = {}
			for name, b in list do
				table.insert(items, b)
			end
			table.sort(items, function(a, b)
				return a.prio < b.prio
			end)
			for _, b in items do
				S.spawnIn(c, b.fn, dt)
			end
		end
		s.RenderStepped:Fire(dt)
		s.PreRender:Fire(dt)
		if s.PostSimulation then
			s.PostSimulation:Fire(dt)
		end
		if s.Heartbeat then
			s.Heartbeat:Fire(dt)
		end
	end
end

---------------------------------------------------------------- TweenService
simple("TweenBase", "Instance", { PlaybackState = Enum.PlaybackState.Begin }, {
	creatable = false,
	events = { "Completed" },
})
simple("Tween", "TweenBase", { TweenInfo = NIL, Instance = NIL }, {
	creatable = false,
	methods = {
		Play = function(self)
			local d = I(self)
			if d.playing then
				return
			end
			d.playing = true
			d.gen = (d.gen or 0) + 1
			local gen = d.gen
			local info = d.info
			local target = d.target
			Inst.rawSet(self, "PlaybackState", Enum.PlaybackState.Playing)
			-- instant: jump to the goal, then report Completed when the tween would have ended
			for prop, value in d.goals do
				if not I(target).destroyed then
					target[prop] = value
				end
			end
			if info.RepeatCount < 0 then
				return -- infinite tween never completes
			end
			local total = info.DelayTime + info.Time * (info.RepeatCount + 1) * (if info.Reverses then 2 else 1)
			S.task.delay(total, function()
				if d.gen ~= gen or not d.playing then
					return
				end
				d.playing = false
				Inst.rawSet(self, "PlaybackState", Enum.PlaybackState.Completed)
				Inst.fire(self, "Completed", Enum.PlaybackState.Completed)
			end)
		end,
		Pause = function(self)
			local d = I(self)
			d.playing = false
			d.gen = (d.gen or 0) + 1
			Inst.rawSet(self, "PlaybackState", Enum.PlaybackState.Paused)
		end,
		Cancel = function(self)
			local d = I(self)
			local was = d.playing
			d.playing = false
			d.gen = (d.gen or 0) + 1
			Inst.rawSet(self, "PlaybackState", Enum.PlaybackState.Cancelled)
			if was then
				Inst.fire(self, "Completed", Enum.PlaybackState.Cancelled)
			end
		end,
	},
})
service("TweenService", nil, {
	methods = {
		Create = function(_, inst, info, goals)
			if not Inst.is(inst) then
				error("TweenService:Create: argument #1 must be an Instance", 2)
			end
			if D.typeof(info) ~= "TweenInfo" then
				error("TweenService:Create: argument #2 must be a TweenInfo", 2)
			end
			if type(goals) ~= "table" then
				error("TweenService:Create: argument #3 must be a table", 2)
			end
			for prop, value in goals do
				local ok, current = pcall(function()
					return inst[prop]
				end)
				if not ok then
					error(`TweenService:Create no property named '{prop}' for object '{inst.Name}'`, 2)
				end
				local tc, tv = D.typeof(current), D.typeof(value)
				if current ~= nil and tc ~= tv then
					error(
						`TweenService:Create property named '{prop}' cannot be tweened due to type mismatch (property is a '{tc}', but given type is '{tv}')`,
						2
					)
				end
				if tv ~= "number" and tv ~= "Vector3" and tv ~= "Vector2" and tv ~= "CFrame" and tv ~= "Color3" and tv ~= "UDim2" and tv ~= "UDim" and tv ~= "boolean" and tv ~= "EnumItem" and tv ~= "Rect" and tv ~= "NumberRange" then
					error(`TweenService:Create property named '{prop}' cannot be tweened (type {tv})`, 2)
				end
			end
			local tween = Inst.create("Tween")
			local d = I(tween)
			d.info, d.target, d.goals = info, inst, table.clone(goals)
			Inst.rawSet(tween, "TweenInfo", info)
			Inst.rawSet(tween, "Instance", inst)
			return tween
		end,
		GetValue = function(_, alpha)
			return alpha
		end,
		SmoothDamp = function(_, current, target)
			return target, 0
		end,
	},
})

---------------------------------------------------------------- Players
simple("Player", "Instance", {
	UserId = 0,
	DisplayName = "",
	Character = NIL,
	RespawnLocation = NIL,
	Team = NIL,
	TeamColor = D.BrickColor.new("White"),
	Neutral = true,
	AccountAge = 365,
	MembershipType = Enum.MembershipType.None,
	CameraMode = Enum.CameraMode.Classic,
	CameraMaxZoomDistance = 128,
	CameraMinZoomDistance = 0.5,
	AutoJumpEnabled = true,
	CanLoadCharacterAppearance = true,
	CharacterAppearanceId = 0,
	DevComputerMovementMode = Enum.DevComputerMovementMode.UserChoice,
	DevTouchMovementMode = Enum.DevTouchMovementMode.UserChoice,
	DevEnableMouseLock = true,
	FollowUserId = 0,
	HasVerifiedBadge = false,
	LocaleId = "en-us",
	ReplicationFocus = NIL,
	HealthDisplayDistance = 100,
	NameDisplayDistance = 100,
	GameplayPaused = false,
}, {
	creatable = false,
	events = { "CharacterAdded", "CharacterRemoving", "CharacterAppearanceLoaded", "Chatted", "Idled", "OnTeleport" },
	methods = {
		Kick = function(self, message)
			if I(self).leaving or self.Parent == nil then
				return -- kicking a player who is already leaving does nothing
			end
			state.kicked[self.UserId] = message or ""
			S.log("warn", ctx(), `Player {self.Name} kicked: {message}`)
			if M.removePlayer then
				S.task.defer(M.removePlayer, self)
			end
		end,
		LoadCharacter = function(self)
			requireServer("LoadCharacter")
			M.spawnCharacter(self)
		end,
		LoadCharacterAsync = function(self)
			M.spawnCharacter(self)
		end,
		IsFriendsWith = function(self, userId)
			local f = state.friends[self.UserId]
			return f ~= nil and f[userId] == true
		end,
		GetRankInGroup = function()
			return 0
		end,
		GetRoleInGroup = function()
			return "Guest"
		end,
		IsInGroup = function()
			return false
		end,
		GetFriendsOnline = function()
			return {}
		end,
		GetNetworkPing = function()
			return 0.05
		end,
		GetJoinData = function()
			return {}
		end,
		GetMouse = function(self)
			requireClient("GetMouse")
			local d = I(self)
			if not d.mouse then
				d.mouse = Inst.create("PlayerMouse")
			end
			return d.mouse
		end,
		DistanceFromCharacter = function(self, pos)
			local char = self.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if not root then
				return 0
			end
			return (root.Position - pos).Magnitude
		end,
		ClearCharacterAppearance = function() end,
		RequestStreamAroundAsync = function() end,
		SetSuperSafeChat = function() end,
		HasAppearanceLoaded = function()
			return true
		end,
	},
})
simple("PlayerMouse", "Instance", {
	Hit = CFrame.identity,
	Origin = CFrame.identity,
	Target = NIL,
	TargetFilter = NIL,
	UnitRay = D.Ray.new(Vector3.zero, Vector3.zAxis),
	X = 0,
	Y = 0,
	Icon = "",
	ViewSizeX = 844,
	ViewSizeY = 390,
}, {
	creatable = false,
	events = { "Button1Down", "Button1Up", "Button2Down", "Button2Up", "Move", "WheelForward", "WheelBackward", "Idle" },
})

service("Players", {
	MaxPlayers = 8,
	PreferredPlayers = 8,
	CharacterAutoLoads = true,
	RespawnTime = 5,
	BubbleChat = true,
	ClassicChat = false,
	UseStrafingAnimations = false,
}, {
	events = { "PlayerAdded", "PlayerRemoving", "PlayerMembershipChanged", "UserSubscriptionStatusChanged" },
	getters = {
		LocalPlayer = function()
			return ctx().player
		end,
	},
	methods = {
		GetPlayers = function(self)
			local out = {}
			for _, c in self:GetChildren() do
				if I(c).className == "Player" then
					table.insert(out, c)
				end
			end
			return out
		end,
		GetPlayerByUserId = function(self, id)
			for _, p in self:GetPlayers() do
				if p.UserId == id then
					return p
				end
			end
			return nil
		end,
		GetPlayerFromCharacter = function(self, char)
			if char == nil then
				return nil
			end
			for _, p in self:GetPlayers() do
				if p.Character == char then
					return p
				end
			end
			return nil
		end,
		GetNameFromUserIdAsync = function(self, id)
			local p = self:GetPlayerByUserId(id)
			S.task.wait()
			if p then
				return p.Name
			end
			if type(id) ~= "number" or id <= 0 then
				error("Players:GetNameFromUserIdAsync() failed: Unknown user", 2)
			end
			return "User" .. tostring(id)
		end,
		GetUserIdFromNameAsync = function(self, name)
			for _, p in self:GetPlayers() do
				if p.Name == name then
					return p.UserId
				end
			end
			error("Players:GetUserIdFromNameAsync() failed: Unknown user", 2)
		end,
		GetUserThumbnailAsync = function(_, id)
			return `rbxthumb://type=AvatarHeadShot&id={id}&w=150&h=150`, true
		end,
		GetFriendsAsync = function(self, id)
			return M.makePages({ {} })
		end,
		GetHumanoidDescriptionFromUserId = function()
			return Inst.create("HumanoidDescription")
		end,
		CreateHumanoidModelFromUserId = function()
			return M.buildRig("Rig")
		end,
		CreateHumanoidModelFromDescription = function()
			return M.buildRig("Rig")
		end,
		BanAsync = function() end,
		UnbanAsync = function() end,
	},
})

function M.makePages(pages)
	local p = Inst.create("Pages")
	I(p).pages = pages
	I(p).index = 1
	return p
end
simple("Pages", "Instance", {}, {
	creatable = false,
	getters = {
		IsFinished = function(_, d)
			return d.index >= #d.pages
		end,
	},
	methods = {
		GetCurrentPage = function(self)
			local d = I(self)
			return d.pages[d.index] or {}
		end,
		AdvanceToNextPageAsync = function(self)
			local d = I(self)
			S.task.wait()
			if d.index >= #d.pages then
				error("No more pages", 2)
			end
			d.index += 1
		end,
	},
})
simple("DataStorePages", "Pages", {}, { creatable = false })
simple("DataStoreVersionPages", "Pages", {}, { creatable = false })
simple("DataStoreKeyPages", "Pages", {}, { creatable = false })

-- R15-ish rig: Model with HumanoidRootPart (PrimaryPart), Head, Torso and a Humanoid.
function M.buildRig(name)
	local char = Inst.create("Model")
	char.Name = name
	local root = Inst.create("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.CanCollide = false
	root.Parent = char
	local torso = Inst.create("Part")
	torso.Name = "UpperTorso"
	torso.Size = Vector3.new(2, 2, 1)
	torso.Parent = char
	local head = Inst.create("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2, 1, 1)
	head.CFrame = CFrame.new(0, 1.5, 0)
	head.Parent = char
	local hum = Inst.create("Humanoid")
	hum.Name = "Humanoid"
	hum.Parent = char
	local animator = Inst.create("Animator")
	animator.Name = "Animator"
	animator.Parent = hum
	char.PrimaryPart = root
	return char
end

function M.spawnCharacter(player)
	local old = player.Character
	if old then
		Inst.fire(player, "CharacterRemoving", old)
		old:Destroy()
	end
	local char = M.buildRig(player.Name)
	local spawnCF = CFrame.new(0, 5, 0)
	local spawn = player.RespawnLocation
	if not spawn then
		local map = state.game.Workspace:FindFirstChild("Map")
		spawn = map and map:FindFirstChild("LobbySpawn")
	end
	if spawn and Inst.is(spawn) and I(spawn).r.isa.BasePart then
		spawnCF = spawn.CFrame * CFrame.new(0, spawn.Size.Y / 2 + 3, 0)
	end
	char:PivotTo(spawnCF)
	player.Character = char
	char.Parent = state.game.Workspace
	Inst.fire(player, "CharacterAdded", char)
	S.task.defer(function()
		Inst.fire(player, "CharacterAppearanceLoaded", char)
	end)
	return char
end

---------------------------------------------------------------- Remotes
local function clientSignal(d, player)
	d.clientSignals = d.clientSignals or {}
	local s = d.clientSignals[player]
	if not s then
		s = Signal.new("OnClientEvent")
		d.clientSignals[player] = s
	end
	return s
end

simple("BaseRemoteEvent", "Instance", {}, { creatable = false })
simple("RemoteEvent", "BaseRemoteEvent", {}, {
	events = { "OnServerEvent" },
	getters = {
		OnClientEvent = function(self, d)
			local c = ctx()
			if not c.isClient then
				error("OnClientEvent can only be used on the client", 2)
			end
			return clientSignal(d, c.player)
		end,
	},
	methods = {
		FireServer = function(self, ...)
			local c = ctx()
			if not c.isClient then
				error("FireServer can only be called from the client", 2)
			end
			local args, n = copyArgs(...)
			local player = c.player
			local sig = Inst.getSignal(self, "OnServerEvent")
			S.deferIn(state.server, function()
				if player.Parent == nil then
					return
				end
				sig:Fire(player, table.unpack(args, 1, n))
			end)
			M.stats.toServer += 1
		end,
		FireClient = function(self, player, ...)
			requireServer("FireClient")
			if not isPlayer(player) then
				error("FireClient: player argument must be a Player object", 2)
			end
			local args, n = copyArgs(...)
			local d = I(self)
			local c = state.clients[player]
			M.stats.toClient += 1
			if not c then
				return -- player has no running client (left)
			end
			S.deferIn(c, function()
				clientSignal(d, player):Fire(table.unpack(args, 1, n))
			end)
		end,
		FireAllClients = function(self, ...)
			requireServer("FireAllClients")
			local d = I(self)
			for player, c in state.clients do
				local args, n = copyArgs(...)
				M.stats.toClient += 1
				S.deferIn(c, function()
					clientSignal(d, player):Fire(table.unpack(args, 1, n))
				end)
			end
		end,
	},
})
simple("UnreliableRemoteEvent", "RemoteEvent", {})
M.stats = { toServer = 0, toClient = 0 }

local function invokeAcross(targetCtx, fn, ...)
	local caller = coroutine.running()
	local args, n = copyArgs(...)
	local result
	local waiting = false
	S.deferIn(targetCtx, function()
		local r = table.pack(pcall(fn, table.unpack(args, 1, n)))
		result = r
		if waiting then
			S.resume(caller)
		end
	end)
	waiting = true
	S.yield()
	if not result[1] then
		error(result[2], 0)
	end
	local out = {}
	for i = 2, result.n do
		out[i - 1] = copyArg(result[i])
	end
	return table.unpack(out, 1, result.n - 1)
end

simple("RemoteFunction", "Instance", {}, {
	setters = {
		OnServerInvoke = function(self, d, fn)
			requireServer("OnServerInvoke")
			d.onServer = fn
		end,
		OnClientInvoke = function(self, d, fn)
			requireClient("OnClientInvoke")
			d.onClient = d.onClient or {}
			d.onClient[ctx().player] = fn
		end,
	},
	getters = {
		OnServerInvoke = function(_, d)
			error("OnServerInvoke is a callback member of RemoteFunction; you can only set the callback value, get is not available", 2)
		end,
	},
	methods = {
		InvokeServer = function(self, ...)
			local c = ctx()
			if not c.isClient then
				error("InvokeServer can only be called from the client", 2)
			end
			local d = I(self)
			local start = S.now
			while not d.onServer do
				S.task.wait()
				if S.now - start > 30 then
					error(`InvokeServer({self.Name}): server never set OnServerInvoke`, 2)
				end
			end
			local player = c.player
			M.stats.toServer += 1
			return invokeAcross(state.server, function(...)
				return d.onServer(player, ...)
			end, ...)
		end,
		InvokeClient = function(self, player, ...)
			requireServer("InvokeClient")
			local d = I(self)
			local fn = d.onClient and d.onClient[player]
			if not fn then
				error("InvokeClient: client has no OnClientInvoke", 2)
			end
			return invokeAcross(state.clients[player], fn, ...)
		end,
	},
})

---------------------------------------------------------------- DataStoreService (in memory)
-- Values must be serializable the same way Roblox requires: strings/numbers/booleans/tables
-- (arrays or string-keyed dictionaries, not mixed), no Instances, functions or NaN.
local function checkStorable(v, path, seen)
	local t = type(v)
	if t == "nil" or t == "boolean" or t == "string" then
		return
	end
	if t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			error(`104: Cannot store {tostring(v)} in data store at {path}`, 0)
		end
		return
	end
	if t ~= "table" or getmetatable(v) ~= nil then
		error(`104: Cannot store {D.typeof(v)} in data store at {path}`, 0)
	end
	seen = seen or {}
	if seen[v] then
		error(`104: Cyclic table at {path}`, 0)
	end
	seen[v] = true
	local hasString, hasNumber = false, false
	local count = 0
	for k, x in v do
		count += 1
		if type(k) == "string" then
			hasString = true
		elseif type(k) == "number" then
			hasNumber = true
		else
			error(`104: Cannot store a table with {type(k)} keys at {path}`, 0)
		end
		checkStorable(x, `{path}.{tostring(k)}`, seen)
	end
	if hasString and hasNumber then
		error(`104: Cannot store mixed table (array + dictionary keys) at {path}`, 0)
	end
	if hasNumber and count ~= #v then
		error(`104: Cannot store sparse array at {path}`, 0)
	end
	seen[v] = nil
end
M.checkStorable = checkStorable

local function deepCopy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = deepCopy(x)
	end
	return out
end
M.deepCopy = deepCopy

local function keyInfo(entry)
	local ki = Inst.create("DataStoreKeyInfo")
	I(ki).entry = entry
	return ki
end
simple("DataStoreKeyInfo", "Instance", {}, {
	creatable = false,
	getters = {
		Version = function(_, d)
			return tostring(d.entry.version)
		end,
		CreatedTime = function(_, d)
			return d.entry.created
		end,
		UpdatedTime = function(_, d)
			return d.entry.updated
		end,
	},
	methods = {
		GetMetadata = function(self)
			return I(self).entry.metadata or {}
		end,
		GetUserIds = function(self)
			return I(self).entry.userIds or {}
		end,
	},
})
simple("DataStoreSetOptions", "Instance", {}, {
	methods = {
		SetMetadata = function(self, m)
			I(self).metadata = m
		end,
		GetMetadata = function(self)
			return I(self).metadata or {}
		end,
	},
})
simple("DataStoreOptions", "Instance", { AllScopes = false }, {
	methods = {
		SetExperimentalFeatures = function() end,
	},
})
simple("DataStoreGetOptions", "Instance", { UseCache = true })
simple("DataStoreIncrementOptions", "Instance", {}, { methods = { SetMetadata = function() end } })

local function storeData(d)
	local key = d.storeName .. "\0" .. (d.scope or "global") .. (if d.ordered then "\0ordered" else "")
	state.stores[key] = state.stores[key] or {}
	return state.stores[key]
end

local function dsWrite(d, key, value, userIds, metadata)
	checkStorable(value, key)
	if d.ordered and value ~= nil and (type(value) ~= "number" or value ~= math.floor(value)) then
		error("OrderedDataStore values must be integers", 0)
	end
	local data = storeData(d)
	local entry = data[key]
	local now = math.floor((S.epoch + S.now) * 1000)
	if not entry then
		entry = { version = 0, created = now, versions = {} }
		data[key] = entry
	end
	entry.version += 1
	entry.updated = now
	entry.value = deepCopy(value)
	entry.userIds = userIds
	entry.metadata = metadata
	table.insert(entry.versions, { version = entry.version, value = deepCopy(value), time = now })
	return entry
end

local dsMethods = {
	GetAsync = function(self, key)
		local d = I(self)
		S.task.wait()
		local entry = storeData(d)[key]
		if not entry or entry.value == nil then
			return nil, nil
		end
		return deepCopy(entry.value), keyInfo(entry)
	end,
	SetAsync = function(self, key, value, userIds, options)
		local d = I(self)
		S.task.wait()
		local entry = dsWrite(d, key, value, userIds, options and I(options).metadata)
		return tostring(entry.version)
	end,
	UpdateAsync = function(self, key, fn)
		local d = I(self)
		S.task.wait()
		local entry = storeData(d)[key]
		local old = entry and deepCopy(entry.value)
		local new, userIds, metadata = fn(old, entry and keyInfo(entry))
		if new == nil then
			return nil, nil
		end
		entry = dsWrite(d, key, new, userIds, metadata)
		return deepCopy(new), keyInfo(entry)
	end,
	IncrementAsync = function(self, key, delta)
		local d = I(self)
		S.task.wait()
		local entry = storeData(d)[key]
		local old = (entry and entry.value) or 0
		if type(old) ~= "number" then
			error("IncrementAsync: value is not a number", 2)
		end
		local nv = old + (delta or 1)
		entry = dsWrite(d, key, nv)
		return nv, keyInfo(entry)
	end,
	RemoveAsync = function(self, key)
		local d = I(self)
		S.task.wait()
		local data = storeData(d)
		local entry = data[key]
		if not entry then
			return nil
		end
		local old = entry.value
		entry.value = nil
		return old, keyInfo(entry)
	end,
	GetVersionAsync = function(self, key, version)
		local d = I(self)
		S.task.wait()
		local entry = storeData(d)[key]
		if not entry then
			return nil
		end
		for _, v in entry.versions do
			if tostring(v.version) == tostring(version) then
				return deepCopy(v.value), keyInfo(entry)
			end
		end
		return nil
	end,
	ListVersionsAsync = function(self, key, sortDirection)
		local d = I(self)
		S.task.wait()
		local entry = storeData(d)[key]
		local list = {}
		if entry then
			for _, v in entry.versions do
				table.insert(list, { Version = tostring(v.version), CreatedTime = v.time, IsDeleted = false })
			end
		end
		if sortDirection and sortDirection.Name == "Descending" then
			local rev = {}
			for i = #list, 1, -1 do
				table.insert(rev, list[i])
			end
			list = rev
		end
		local p = M.makePages({ list })
		return p
	end,
	ListKeysAsync = function(self)
		local d = I(self)
		local list = {}
		for k in storeData(d) do
			table.insert(list, { KeyName = k })
		end
		return M.makePages({ list })
	end,
}
simple("GlobalDataStore", "Instance", {}, { creatable = false, methods = dsMethods })
simple("DataStore", "GlobalDataStore", {}, { creatable = false })
simple("OrderedDataStore", "GlobalDataStore", {}, {
	creatable = false,
	methods = {
		GetSortedAsync = function(self, ascending, pageSize, minValue, maxValue)
			local d = I(self)
			S.task.wait()
			assert(type(pageSize) == "number" and pageSize > 0 and pageSize <= 100, "GetSortedAsync: pageSize must be 1..100")
			local list = {}
			for k, entry in storeData(d) do
				local v = entry.value
				if v ~= nil and (minValue == nil or v >= minValue) and (maxValue == nil or v <= maxValue) then
					table.insert(list, { key = k, value = v })
				end
			end
			table.sort(list, function(a, b)
				if ascending then
					return a.value < b.value
				end
				return a.value > b.value
			end)
			local pages = {}
			for i = 1, math.max(#list, 1), pageSize do
				table.insert(pages, table.move(list, i, math.min(i + pageSize - 1, #list), 1, {}))
			end
			local p = M.makePages(pages)
			return p
		end,
	},
})

service("DataStoreService", { AutomaticRetry = true }, {
	init = function(_, d)
		d.cache = {}
	end,
	methods = {
		GetDataStore = function(self, name, scope, options)
			requireServer("GetDataStore")
			assert(type(name) == "string" and #name > 0, "GetDataStore: name must be a non-empty string")
			local d = I(self)
			local key = name .. "\0" .. tostring(scope or "global")
			local ds = d.cache[key]
			if not ds then
				ds = Inst.create("DataStore")
				ds.Name = name
				I(ds).storeName = name
				I(ds).scope = scope
				d.cache[key] = ds
			end
			return ds
		end,
		GetGlobalDataStore = function(self)
			return self:GetDataStore("__global")
		end,
		GetOrderedDataStore = function(self, name, scope)
			requireServer("GetOrderedDataStore")
			local d = I(self)
			local key = "ordered\0" .. name .. "\0" .. tostring(scope or "global")
			local ds = d.cache[key]
			if not ds then
				ds = Inst.create("OrderedDataStore")
				ds.Name = name
				I(ds).storeName = name
				I(ds).scope = scope
				I(ds).ordered = true
				d.cache[key] = ds
			end
			return ds
		end,
		GetRequestBudgetForRequestType = function()
			return 100
		end,
		ListDataStoresAsync = function()
			return M.makePages({ {} })
		end,
	},
})

service("MemoryStoreService", nil, {
	methods = {
		GetSortedMap = function()
			error("MemoryStoreService not mocked", 2)
		end,
		GetQueue = function()
			error("MemoryStoreService not mocked", 2)
		end,
	},
})

---------------------------------------------------------------- MessagingService
service("MessagingService", nil, {
	init = function(_, d)
		d.subs = {}
	end,
	methods = {
		SubscribeAsync = function(self, topic, cb)
			requireServer("SubscribeAsync")
			local d = I(self)
			S.task.wait()
			local entry = { cb = cb, ctx = ctx(), connected = true }
			d.subs[topic] = d.subs[topic] or {}
			table.insert(d.subs[topic], entry)
			local conn = Inst.create("MessagingConnection")
			I(conn).entry = entry
			return conn
		end,
		PublishAsync = function(self, topic, message)
			requireServer("PublishAsync")
			checkStorable(message, "message")
			local d = I(self)
			S.task.wait()
			for _, e in d.subs[topic] or {} do
				if e.connected then
					S.deferIn(e.ctx, e.cb, { Data = deepCopy(message), Sent = S.epoch + S.now })
				end
			end
		end,
	},
})
simple("MessagingConnection", "Instance", {}, {
	creatable = false,
	getters = {
		Connected = function(_, d)
			return d.entry.connected
		end,
	},
	methods = {
		Disconnect = function(self)
			I(self).entry.connected = false
		end,
	},
})

---------------------------------------------------------------- MarketplaceService
service("MarketplaceService", { ProcessReceipt = NIL }, {
	events = {
		"PromptGamePassPurchaseFinished",
		"PromptProductPurchaseFinished",
		"PromptPurchaseFinished",
		"PromptPremiumPurchaseFinished",
		"PromptBundlePurchaseFinished",
		"PromptSubscriptionPurchaseFinished",
	},
	setters = {
		ProcessReceipt = function(self, d, fn)
			requireServer("ProcessReceipt")
			d.props.ProcessReceipt = fn
		end,
	},
	methods = {
		UserOwnsGamePassAsync = function(_, userId, passId)
			requireServer("UserOwnsGamePassAsync")
			S.task.wait()
			local owned = state.ownedPasses[userId]
			return owned ~= nil and owned[passId] == true
		end,
		PlayerOwnsAsset = function()
			return false
		end,
		PlayerOwnsBundle = function()
			return false
		end,
		PromptGamePassPurchase = function(_, player, id)
			table.insert(state.prompts, { kind = "pass", player = player, id = id })
		end,
		PromptProductPurchase = function(_, player, id)
			table.insert(state.prompts, { kind = "product", player = player, id = id })
		end,
		PromptPurchase = function(_, player, id)
			table.insert(state.prompts, { kind = "asset", player = player, id = id })
		end,
		PromptPremiumPurchase = function(_, player)
			table.insert(state.prompts, { kind = "premium", player = player })
		end,
		PromptSubscriptionPurchase = function(_, player, id)
			table.insert(state.prompts, { kind = "subscription", player = player, id = id })
		end,
		GetProductInfo = function(_, id, infoType)
			S.task.wait()
			return {
				Name = "Product " .. tostring(id),
				Description = "",
				PriceInRobux = 49,
				ProductId = id,
				AssetId = id,
				IsForSale = true,
				IconImageAssetId = 0,
			}
		end,
		GetDeveloperProductsAsync = function()
			return M.makePages({ {} })
		end,
	},
})

---------------------------------------------------------------- TextChatService
service("TextChatService", {
	ChatVersion = Enum.ChatVersion.TextChatService,
	CreateDefaultCommands = true,
	CreateDefaultTextChannels = true,
}, {
	events = { "MessageReceived", "SendingMessage", "BubbleDisplayed" },
	init = function(self)
		-- children are created after the DataModel exists (see M.newGame)
	end,
	methods = {
		CanUserChatAsync = function()
			return true
		end,
		CanUsersChatAsync = function()
			return true
		end,
		DisplayBubble = function() end,
	},
})
simple("TextChatCommand", "Instance", {
	PrimaryAlias = "",
	SecondaryAlias = "",
	Enabled = true,
	AutocompleteVisible = true,
}, { events = { "Triggered" } })
simple("TextChannel", "Instance", {}, {
	events = { "MessageReceived", "ShouldDeliverCallback" },
	methods = {
		SendAsync = function() end,
		DisplaySystemMessage = function() end,
		AddUserAsync = function() end,
	},
})
simple("TextSource", "Instance", { UserId = 0, CanSend = true }, { creatable = false })
simple("ChatWindowConfiguration", "Instance", { Enabled = true }, { creatable = false })
simple("ChatInputBarConfiguration", "Instance", { Enabled = true, TargetTextChannel = NIL }, { creatable = false })
simple("BubbleChatConfiguration", "Instance", { Enabled = true }, { creatable = false })

---------------------------------------------------------------- game construction
function M.newGame()
	local game = Inst.create("DataModel")
	game.Name = "Game"
	state.game = game
	-- the services every place has, in the usual order
	for _, name in {
		"Workspace",
		"Players",
		"Lighting",
		"ReplicatedFirst",
		"ReplicatedStorage",
		"ServerScriptService",
		"ServerStorage",
		"StarterGui",
		"StarterPack",
		"StarterPlayer",
		"Teams",
		"SoundService",
		"Chat",
		"TextChatService",
		"RunService",
	} do
		getService(game, name)
	end
	local sp = game:GetService("StarterPlayer")
	local sps = Inst.create("StarterPlayerScripts")
	sps.Name = "StarterPlayerScripts"
	sps.Parent = sp
	local scs = Inst.create("StarterCharacterScripts")
	scs.Name = "StarterCharacterScripts"
	scs.Parent = sp
	local tcs = game:GetService("TextChatService")
	for _, cls in { "ChatWindowConfiguration", "ChatInputBarConfiguration", "BubbleChatConfiguration" } do
		local x = Inst.create(cls)
		x.Name = cls
		x.Parent = tcs
	end
	local channels = Inst.create("Folder")
	channels.Name = "TextChannels"
	channels.Parent = tcs
	local general = Inst.create("TextChannel")
	general.Name = "RBXGeneral"
	general.Parent = channels
	local _ = game.Workspace.CurrentCamera
	table.insert(S.frameHooks, M.frameHook(game:GetService("RunService")))
	return game
end

return M
