--!strict
-- C3: every sound in the game. name -> { id, file, volume, looped, group }.
--
--   id      "rbxassetid://0" until the human uploads the file (docs/SOUND_UPLOAD.md).
--           SoundController silently skips any sound whose id is still 0.
--   file    source mp3 in the repo (regenerate with `python3 sound/generate.py`)
--   volume  0..1 base volume (the SoundGroup volume is multiplied on top)
--   looped  true for music and the pipe loop
--   group   "Music" | "SFX" | "Voice"  (muted by data.settings.music / sfx / voice)
--
-- Voice lines: "Voice<tier>" is the dramatic shout of that cow's name (Config/Cows.luau).
-- Server code can play any of these on one client with Net "PlaySound"(name).

export type Group = "Music" | "SFX" | "Voice"

export type SoundDef = {
	id: string,
	file: string,
	volume: number,
	looped: boolean,
	group: Group,
}

local Sounds = {}

-- PASTE IDS HERE (see docs/SOUND_UPLOAD.md). Only the number changes.
Sounds.List = {
	-- music
	MusicFarm = {
		id = "rbxassetid://0",
		file = "sound/music/music_farm_loop.mp3",
		volume = 0.35,
		looped = false,
		group = "Music",
	},
	MusicCalm = {
		id = "rbxassetid://0",
		file = "sound/music/music_farm_calm.mp3",
		volume = 0.35,
		looped = false,
		group = "Music",
	},

	-- sfx
	Moo1 = { id = "rbxassetid://0", file = "sound/sfx/sfx_moo_1.mp3", volume = 0.6, looped = false, group = "SFX" },
	Moo2 = { id = "rbxassetid://0", file = "sound/sfx/sfx_moo_2.mp3", volume = 0.6, looped = false, group = "SFX" },
	Moo3 = { id = "rbxassetid://0", file = "sound/sfx/sfx_moo_3.mp3", volume = 0.6, looped = false, group = "SFX" },
	MilkPipe = {
		id = "rbxassetid://0",
		file = "sound/sfx/sfx_milk_pipe_loop.mp3",
		volume = 0.25,
		looped = true,
		group = "SFX",
	},
	CanFill = {
		id = "rbxassetid://0",
		file = "sound/sfx/sfx_can_fill.mp3",
		volume = 0.5,
		looped = false,
		group = "SFX",
	},
	DepositSplash = {
		id = "rbxassetid://0",
		file = "sound/sfx/sfx_deposit_splash.mp3",
		volume = 0.6,
		looped = false,
		group = "SFX",
	},
	CashCollect = {
		id = "rbxassetid://0",
		file = "sound/sfx/sfx_cash_collect.mp3",
		volume = 0.7,
		looped = false,
		group = "SFX",
	},
	Coin = { id = "rbxassetid://0", file = "sound/sfx/sfx_coin.mp3", volume = 0.35, looped = false, group = "SFX" },
	BuyCow = { id = "rbxassetid://0", file = "sound/sfx/sfx_buy_cow.mp3", volume = 0.6, looped = false, group = "SFX" },
	Merge = { id = "rbxassetid://0", file = "sound/sfx/sfx_merge.mp3", volume = 0.7, looped = false, group = "SFX" },
	CrateSpin = {
		id = "rbxassetid://0",
		file = "sound/sfx/sfx_crate_spin.mp3",
		volume = 0.6,
		looped = false,
		group = "SFX",
	},
	CrateReveal = {
		id = "rbxassetid://0",
		file = "sound/sfx/sfx_crate_reveal.mp3",
		volume = 0.7,
		looped = false,
		group = "SFX",
	},
	RareSparkle = {
		id = "rbxassetid://0",
		file = "sound/sfx/sfx_rare_sparkle.mp3",
		volume = 0.6,
		looped = false,
		group = "SFX",
	},
	Rebirth = { id = "rbxassetid://0", file = "sound/sfx/sfx_rebirth.mp3", volume = 0.8, looped = false, group = "SFX" },
	Upgrade = { id = "rbxassetid://0", file = "sound/sfx/sfx_upgrade.mp3", volume = 0.6, looped = false, group = "SFX" },
	ErrorBuzz = {
		id = "rbxassetid://0",
		file = "sound/sfx/sfx_error_buzz.mp3",
		volume = 0.4,
		looped = false,
		group = "SFX",
	},
	UiClick = {
		id = "rbxassetid://0",
		file = "sound/sfx/sfx_ui_click.mp3",
		volume = 0.3,
		looped = false,
		group = "SFX",
	},
	TruckHorn = {
		id = "rbxassetid://0",
		file = "sound/sfx/sfx_truck_horn.mp3",
		volume = 0.7,
		looped = false,
		group = "SFX",
	},
	EventFanfare = {
		id = "rbxassetid://0",
		file = "sound/sfx/sfx_event_fanfare.mp3",
		volume = 0.7,
		looped = false,
		group = "SFX",
	},
	NewCowFanfare = {
		id = "rbxassetid://0",
		file = "sound/sfx/sfx_newcow_fanfare.mp3",
		volume = 0.7,
		looped = false,
		group = "SFX",
	},
} :: { [string]: SoundDef }

-- voice lines, one per cow tier (generated from Config/Cows.luau names)
local VOICE_IDS: { string } = {
	"rbxassetid://0", -- 1
	"rbxassetid://0", -- 2
	"rbxassetid://0", -- 3
	"rbxassetid://0", -- 4
	"rbxassetid://0", -- 5
	"rbxassetid://0", -- 6
	"rbxassetid://0", -- 7
	"rbxassetid://0", -- 8
	"rbxassetid://0", -- 9
	"rbxassetid://0", -- 10
	"rbxassetid://0", -- 11
	"rbxassetid://0", -- 12
	"rbxassetid://0", -- 13
	"rbxassetid://0", -- 14
	"rbxassetid://0", -- 15
	"rbxassetid://0", -- 16
	"rbxassetid://0", -- 17
	"rbxassetid://0", -- 18
}
for tier, id in VOICE_IDS do
	Sounds.List[`Voice{tier}`] = {
		id = id,
		file = string.format("sound/voice/voice_tier_%02d.mp3", tier),
		volume = 0.9,
		looped = false,
		group = "Voice",
	}
end

-- SoundGroup base volumes (a setting set to false mutes the group)
Sounds.GroupVolume = {
	Music = 0.6,
	SFX = 0.8,
	Voice = 1,
} :: { [Group]: number }

-- Music playlist, played in order and repeated
Sounds.Playlist = { "MusicFarm", "MusicCalm", "MusicFarm" }
Sounds.MusicFadeSeconds = 1.5

Sounds.Moos = { "Moo1", "Moo2", "Moo3" }

Sounds.Tuning = {
	CrateRevealDelay = 3.7, -- matches the crate reel in UI/CratesPanel (3.6s spin)
	VoiceAfterFanfare = 0.5, -- seconds between the new-cow fanfare and the voice shout
	CoinMinGap = 0.25, -- coin blip throttle on frequent small cash increases
	CanFillMinGap = 1.0,
	MooMinSeconds = 6, -- random gap between ambient moos at your stalls
	MooMaxSeconds = 14,
	MooHearDistance = 70, -- studs: only moo when your character is this close to your stalls
	StallRollOff = 60, -- 3D max distance for stall/tank sounds
}

function Sounds.Get(name: string): SoundDef?
	return Sounds.List[name]
end

-- true when the id is a real uploaded asset (not "rbxassetid://0" or empty)
function Sounds.HasId(def: SoundDef?): boolean
	if not def then
		return false
	end
	local n = tonumber(string.match(def.id, "%d+") or "0")
	return n ~= nil and n > 0
end

return Sounds
