--!strict
-- C3: all client audio. Server-authoritative game, so this only LISTENS:
--   remotes   Notify(kind), PlaySound(name)
--   reveals   DiscoveryController / CratesPanel call PlayDiscovery / Play inside their RevealQueue item
--   data      cash up (coin / cash collect), cowsBought up (buy), stats.merges up (merge),
--             upgrades level up, rebirths up, canMilk up (can fill), dairyQueue up (deposit)
--   world     workspace TruckActive, EventId, your plot's stalls (ambient moos) and tank (pipe loop)
--   UI        every GuiButton in PlayerGui clicks (set attribute NoClickSound = true to opt out)
--
-- Respects data.settings.music / sfx / voice by muting the SoundGroups Music / SFX / Voice.
-- Sounds whose id is still rbxassetid://0 are skipped silently (see docs/SOUND_UPLOAD.md).
--
-- API for other client modules:
--   SoundController:Play(name, parent?)   parent = BasePart/Attachment for 3D, nil for 2D
--   SoundController:PlayVoice(tier)
--   SoundController:PlayDiscovery(tier)   fanfare + voice, call from inside the queued reveal

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)
local DataController = require(script.Parent.DataController)

local player = Players.LocalPlayer
local Tuning = Sounds.Tuning

local SoundController = {}

local groups: { [string]: SoundGroup } = {}
local enabled: { [string]: boolean } = { Music = true, SFX = true, Voice = true }
local lastPlayed: { [string]: number } = {}

local SETTING_TO_GROUP: { [string]: string } = { music = "Music", sfx = "SFX", voice = "Voice" }

---------------------------------------------------------------------------
-- core

local function makeSound(name: string, parent: Instance?): Sound?
	local def = Sounds.Get(name)
	if not def or not Sounds.HasId(def) then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = def.id
	s.Volume = def.volume
	s.Looped = def.looped
	s.SoundGroup = groups[def.group]
	if parent then
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 8
		s.RollOffMaxDistance = Tuning.StallRollOff
	end
	s.Parent = parent or SoundService
	return s
end

function SoundController:Play(name: string, parent: Instance?): Sound?
	local def = Sounds.Get(name)
	if not def or not Sounds.HasId(def) then
		return nil
	end
	if not enabled[def.group] then
		return nil
	end
	-- one-shots only: music and loops are owned by this controller (playlist, pipe loop)
	if def.looped or def.group == "Music" then
		return nil
	end
	-- never stack the exact same sound in the same frame burst
	local now = os.clock()
	if now - (lastPlayed[name] or 0) < 0.06 then
		return nil
	end
	lastPlayed[name] = now

	local s = makeSound(name, parent)
	if not s then
		return nil
	end
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	task.delay(15, function()
		if s.Parent then
			s:Destroy()
		end
	end)
	return s
end

function SoundController:PlayVoice(tier: number)
	SoundController:Play(`Voice{tier}`)
end

-- "NEW COW!" moment: fanfare, then the cow's name shout. Call when the reveal overlay appears.
function SoundController:PlayDiscovery(tier: number)
	SoundController:Play("NewCowFanfare")
	task.delay(Tuning.VoiceAfterFanfare, function()
		SoundController:PlayVoice(tier)
	end)
end

local function play(name: string, parent: Instance?)
	SoundController:Play(name, parent)
end

local function throttled(name: string, gap: number)
	if os.clock() - (lastPlayed[name] or 0) >= gap then
		play(name)
	end
end

---------------------------------------------------------------------------
-- music

local musicTracks: { [string]: Sound } = {}
local musicIndex = 0
local currentMusic: Sound? = nil

local function fadeTo(s: Sound, volume: number)
	TweenService:Create(s, TweenInfo.new(Sounds.MusicFadeSeconds), { Volume = volume }):Play()
end

local function playNextTrack()
	local list = Sounds.Playlist
	for _ = 1, #list do
		musicIndex = musicIndex % #list + 1
		local name = list[musicIndex]
		local s = musicTracks[name]
		local def = Sounds.Get(name)
		if s and def then
			currentMusic = s
			s.TimePosition = 0
			s.Volume = 0
			s:Play()
			fadeTo(s, def.volume)
			return
		end
	end
	currentMusic = nil
end

local function setupMusic()
	for _, name in Sounds.Playlist do
		if not musicTracks[name] then
			local s = makeSound(name, nil)
			if s then
				s.Looped = false -- the playlist handles repeats
				musicTracks[name] = s
				s.Ended:Connect(function()
					if currentMusic == s and enabled.Music then
						playNextTrack()
					end
				end)
			end
		end
	end
	if enabled.Music then
		playNextTrack()
	end
end

local function onMusicToggled(on: boolean)
	local s = currentMusic
	if on then
		if s then
			s:Resume()
		else
			playNextTrack()
		end
	elseif s then
		s:Pause()
	end
end

---------------------------------------------------------------------------
-- settings

local function applySettings(settings: any)
	if typeof(settings) ~= "table" then
		return
	end
	for key, groupName in SETTING_TO_GROUP do
		local value = settings[key]
		local on = if typeof(value) == "boolean" then value else true
		local was = enabled[groupName]
		enabled[groupName] = on
		local g = groups[groupName]
		if g then
			g.Volume = if on then (Sounds.GroupVolume[groupName :: any] or 1) else 0
		end
		if groupName == "Music" and was ~= on then
			onMusicToggled(on)
		end
	end
end

---------------------------------------------------------------------------
-- data diffs (first value of every key is only recorded, never played)

local prev: { [string]: number } = {}
local prevUpgrades: { [string]: number } = {}
local lastBig = 0 -- os.clock() of the last "big" cash sound, so the coin blip stays quiet

local function num(v: any): number?
	return if typeof(v) == "number" then v else nil
end

-- returns old value (nil the first time) and stores the new one
local function swap(key: string, value: number): number?
	local old = prev[key]
	prev[key] = value
	return old
end

local function onCash(v: number)
	local old = swap("cash", v)
	if old and v > old then
		-- wait a beat: a collect / sell often replicates dairyCash in the same burst
		task.delay(0.15, function()
			if os.clock() - lastBig > 0.4 then
				throttled("Coin", Tuning.CoinMinGap)
			end
		end)
	end
end

local function onDairyCash(v: number)
	local old = swap("dairyCash", v)
	if old and old > 0 and v < old then
		lastBig = os.clock()
		play("CashCollect")
	end
end

local function onChanged(key: string, value: any)
	if key == "settings" then
		applySettings(value)
		return
	end
	if key == "stats" then
		local merges = if typeof(value) == "table" then num(value.merges) else nil
		if merges then
			local old = swap("merges", merges)
			if old and merges > old then
				lastBig = os.clock()
				play("Merge")
			end
		end
		return
	end
	if key == "upgrades" then
		if typeof(value) ~= "table" then
			return
		end
		local first = next(prevUpgrades) == nil
		local leveled = false
		for id, level in value do
			if typeof(id) == "string" and typeof(level) == "number" then
				local old = prevUpgrades[id]
				if not first and old and level > old then
					leveled = true
				end
				prevUpgrades[id] = level
			end
		end
		if leveled then
			lastBig = os.clock()
			play("Upgrade")
		end
		return
	end

	local v = num(value)
	if not v then
		return
	end
	if key == "cash" then
		onCash(v)
	elseif key == "dairyCash" then
		onDairyCash(v)
	elseif key == "cowsBought" then
		local old = swap(key, v)
		if old and v > old then
			lastBig = os.clock()
			play("BuyCow")
		end
	elseif key == "rebirths" then
		local old = swap(key, v)
		if old and v > old then
			lastBig = os.clock()
			play("Rebirth")
		end
	elseif key == "canMilk" then
		local old = swap(key, v)
		if old and v > old then
			throttled("CanFill", Tuning.CanFillMinGap)
		end
	elseif key == "dairyQueue" then
		local old = swap(key, v)
		if old and v > old then
			play("DepositSplash")
		end
	end
end

---------------------------------------------------------------------------
-- world: my plot (moos + pipe loop)

local function myPlot(): Instance?
	local id = player:GetAttribute("PlotId")
	local plots = workspace:FindFirstChild("Plots")
	if typeof(id) ~= "number" or not plots then
		return nil
	end
	return plots:FindFirstChild(`Plot{id}`)
end

local function rootPart(): BasePart?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	return if hrp and hrp:IsA("BasePart") then hrp else nil
end

local function mooLoop()
	local rng = Random.new()
	while true do
		task.wait(rng:NextNumber(Tuning.MooMinSeconds, Tuning.MooMaxSeconds))
		local plot = myPlot()
		local stalls = plot and plot:FindFirstChild("Stalls")
		local hrp = rootPart()
		if stalls and hrp and enabled.SFX then
			local candidates: { BasePart } = {}
			for _, stall in stalls:GetChildren() do
				if stall:IsA("BasePart") and stall:FindFirstChild("Cow") then
					if (stall.Position - hrp.Position).Magnitude <= Tuning.MooHearDistance then
						table.insert(candidates, stall)
					end
				end
			end
			if #candidates > 0 then
				local stall = candidates[rng:NextInteger(1, #candidates)]
				local moo = Sounds.Moos[rng:NextInteger(1, #Sounds.Moos)]
				local s = SoundController:Play(moo, stall)
				if s then
					s.PlaybackSpeed = rng:NextNumber(0.9, 1.15)
				end
			end
		end
	end
end

local pipeSound: Sound? = nil
local pipePlot: Instance? = nil

local function updatePipe()
	local plot = myPlot()
	if plot ~= pipePlot then
		pipePlot = plot
		if pipeSound then
			pipeSound:Destroy()
			pipeSound = nil
		end
		local tank = plot and plot:FindFirstChild("Tank")
		local anchor: Instance? = if tank
			then (tank:FindFirstChild("Shell") or tank:FindFirstChildWhichIsA("BasePart"))
			else nil
		if not anchor and plot then
			anchor = plot:FindFirstChild("TankTap")
		end
		if anchor and anchor:IsA("BasePart") then
			pipeSound = makeSound("MilkPipe", anchor)
		end
	end
	local s = pipeSound
	if s then
		local mps = player:GetAttribute("MilkPerSecond")
		local flowing = typeof(mps) == "number" and mps > 0
		if flowing and not s.IsPlaying then
			s:Play()
		elseif not flowing and s.IsPlaying then
			s:Stop()
		end
	end
end

---------------------------------------------------------------------------
-- UI clicks

local function hookButton(inst: Instance)
	if inst:IsA("GuiButton") then
		inst.Activated:Connect(function()
			if not inst:GetAttribute("NoClickSound") then
				play("UiClick")
			end
		end)
	end
end

---------------------------------------------------------------------------
-- lifecycle

function SoundController:Init()
	for name, volume in Sounds.GroupVolume do
		local g = SoundService:FindFirstChild(name)
		if not (g and g:IsA("SoundGroup")) then
			g = Instance.new("SoundGroup")
			g.Name = name
			g.Parent = SoundService
		end
		local sg = g :: SoundGroup
		sg.Volume = volume
		groups[name] = sg
	end
end

function SoundController:Start()
	Net.Event("Notify").OnClientEvent:Connect(function(_text: any, kind: any)
		if kind == "error" then
			play("ErrorBuzz")
		elseif kind == "rare" then
			throttled("RareSparkle", 1)
		end
	end)

	-- CowDiscovered / CrateOpened sounds are NOT played here: the visuals are serialized by
	-- Lib/RevealQueue, so DiscoveryController and CratesPanel call PlayDiscovery / Play from
	-- inside their queued reveal (the fanfare never spoils a crate spin).

	Net.Event("PlaySound").OnClientEvent:Connect(function(name: any)
		if typeof(name) == "string" then
			play(name)
		end
	end)

	DataController.Changed:Connect(onChanged)
	local data = DataController:Get()
	if data then
		for key, value in data do
			onChanged(key, value)
		end
	end

	-- world attributes
	local truckWas = workspace:GetAttribute("TruckActive") == true
	workspace:GetAttributeChangedSignal("TruckActive"):Connect(function()
		local now = workspace:GetAttribute("TruckActive") == true
		if now and not truckWas then
			play("TruckHorn")
		end
		truckWas = now
	end)
	local eventWas = workspace:GetAttribute("EventId")
	workspace:GetAttributeChangedSignal("EventId"):Connect(function()
		local now = workspace:GetAttribute("EventId")
		if typeof(now) == "string" and now ~= "" and now ~= eventWas then
			play("EventFanfare")
		end
		eventWas = now
	end)

	-- UI buttons
	local gui = player:WaitForChild("PlayerGui")
	for _, inst in gui:GetDescendants() do
		hookButton(inst)
	end
	gui.DescendantAdded:Connect(hookButton)

	-- plot sounds
	player:GetAttributeChangedSignal("PlotId"):Connect(updatePipe)
	player:GetAttributeChangedSignal("MilkPerSecond"):Connect(updatePipe)
	updatePipe()
	task.spawn(mooLoop)

	setupMusic()
end

return SoundController
