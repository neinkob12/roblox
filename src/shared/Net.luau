--!strict
-- Every remote in the game is declared HERE and only here. Server creates them, client waits.
-- Adding a remote: add its name to the right list in your PR. Never create remotes elsewhere.
--
-- Rule: the client only REQUESTS. The server validates everything (cash, distance, cooldowns).

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EVENTS = {
	-- server -> client
	"DataChanged", -- (key: string, value: any) one top-level key of the player's data changed
	"DataInit", -- (data: table) full data snapshot on join
	"Notify", -- (text: string, kind: "info" | "success" | "error" | "rare")
	"PlaySound", -- (soundId: string) play a named sound from Config/Sounds (added later)
	"CowDiscovered", -- (tier: number) first time this player got this tier
	"CrateOpened", -- (tier: number, source: string) result of a crate roll, for the spin animation
	"OfflineEarnings", -- (milk: number, seconds: number) welcome back popup
	"Fx", -- (kind: string, payload: table) server-triggered juice, rendered by FxController. Kinds and payloads are documented in src/shared/Fx.luau

	-- client -> server
	"RequestUpgrade", -- (upgradeId: string)
	"RequestRebirth", -- ()
	"RequestOpenCrate", -- ()
	"RequestBuyCrate", -- ()
	"RequestClaimQuest", -- (questId: string)
	"RequestSetting", -- (name: string, value: boolean)
	-- wave 5 pets / eggs / nests (F1 server, F2 client; see docs/CONTRACTS.md section 11)
	"RequestBuyEgg", -- (eggId: string) cash purchase, goes into the first free nest; gated by PaidRandomRestricted
	"RequestClaimFreeEgg", -- () free Pasture egg every Eggs.FreeEggSeconds (earnable path, never gated)
	"RequestHatch", -- (nestKey: string) hatch a ready egg in that nest
	"RequestEquipPet", -- (petUid: string, equip: boolean)
	"RequestMergePets", -- (petId: string, variant: string) 5 same -> next variant
	"PetHatched", -- server -> client (petUid: string, petId: string, variant: string) for the reveal
	"RequestTutorialStep", -- (step: number) C4 TutorialService validates (only forward, max +1)
	"RequestDailyClaim", -- () E1 DailyService: claim today's login reward (20h cooldown, 48h streak reset)
	"RequestIndexClaim", -- (count: number) E1 IndexRewardService: claim the Index milestone at `count` cows discovered
}

local FUNCTIONS = {
	"GetData", -- () -> data | nil   client pulls its snapshot once (avoids missing DataInit on join)
	"RedeemCode", -- (code: string) -> (ok: boolean, message: string)
}

local Net = {}
local folder: Folder

if RunService:IsServer() then
	folder = Instance.new("Folder")
	folder.Name = "Net"
	for _, name in EVENTS do
		local r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = folder
	end
	for _, name in FUNCTIONS do
		local r = Instance.new("RemoteFunction")
		r.Name = name
		r.Parent = folder
	end
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild("Net") :: Folder
end

function Net.Event(name: string): RemoteEvent
	local r = folder:WaitForChild(name, 10)
	assert(r and r:IsA("RemoteEvent"), "Unknown RemoteEvent: " .. name)
	return r
end

function Net.Function(name: string): RemoteFunction
	local r = folder:WaitForChild(name, 10)
	assert(r and r:IsA("RemoteFunction"), "Unknown RemoteFunction: " .. name)
	return r
end

return Net
