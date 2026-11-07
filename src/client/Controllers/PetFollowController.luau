--!strict
-- F2: Renders the equipped pets of EVERY player, client side.
--   Source: player attribute EquippedPets = "id:variant,id:variant" (set by F1 PetService).
--   Pets float in a ring behind their owner's character and hover-bob. One Heartbeat loop
--   moves every pet; pets more than CULL_DISTANCE studs from the camera are skipped.
--   Rainbow pets cycle the color of their RainbowPart parts (PetModels.RainbowColor).
--   With Settings > Reduce motion on, the bob is much smaller.
--   Models are rebuilt when the attribute changes and removed when the player leaves.
--
-- Public: PetFollowController.Parse(attr) -> { { id, variant } } (also used by PetsPanel).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PetModels = require(ReplicatedStorage.Shared.PetModels)
local Safe = require(ReplicatedStorage.Shared.Safe)
local C = require(script.Parent.Parent.Lib.UiKit)

local CULL_DISTANCE = 150
local RING_RADIUS = 4.2
local RING_SPREAD = math.rad(140) -- total arc behind the character
local HOVER = 1.2 -- studs above the ground under the root
local BOB = 0.35
local BOB_REDUCED = 0.08
local FOLLOW_SPEED = 9 -- higher = snappier
local MAX_PETS = 8 -- per player, defensive cap on attribute garbage

type PetEntry = {
	model: Model,
	rainbow: { BasePart },
	offsets: { number },
	cf: CFrame?,
	phase: number,
}
type Owner = { pets: { PetEntry }, conn: RBXScriptConnection? }

local PetFollowController = {}

local owners: { [Player]: Owner } = {}
local folder: Folder

export type Equipped = { id: string, variant: string }

function PetFollowController.Parse(attr: any): { Equipped }
	local out: { Equipped } = {}
	if typeof(attr) ~= "string" or attr == "" then
		return out
	end
	for item in string.gmatch(attr, "[^,]+") do
		local id, variant = string.match(item, "^%s*([%w_%-]+):?([%w_]*)%s*$")
		if id and #out < MAX_PETS then
			table.insert(out, { id = id, variant = if variant and variant ~= "" then variant else "normal" })
		end
	end
	return out
end

local function clear(owner: Owner)
	for _, p in owner.pets do
		p.model:Destroy()
	end
	table.clear(owner.pets)
end

local function rebuild(player: Player)
	local owner = owners[player]
	if not owner then
		return
	end
	clear(owner)
	for i, e in PetFollowController.Parse(player:GetAttribute("EquippedPets")) do
		local ok, model = pcall(PetModels.Build, e.id, e.variant)
		if ok and model then
			model.Name = `{player.Name}_Pet{i}`
			local rainbow: { BasePart } = {}
			local offsets: { number } = {}
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d:GetAttribute("RainbowPart") then
					table.insert(rainbow, d)
					local o = d:GetAttribute("RainbowOffset")
					table.insert(offsets, if typeof(o) == "number" then o else 0)
				end
			end
			model.Parent = folder
			table.insert(owner.pets, { model = model, rainbow = rainbow, offsets = offsets, cf = nil, phase = i * 1.3 })
		else
			warn(`[PetFollow] could not build pet {e.id}: {model}`)
		end
	end
end

local function track(player: Player)
	if owners[player] then
		return
	end
	local owner: Owner = { pets = {}, conn = nil }
	owners[player] = owner
	owner.conn = player:GetAttributeChangedSignal("EquippedPets"):Connect(function()
		rebuild(player)
	end)
	rebuild(player)
end

local function untrack(player: Player)
	local owner = owners[player]
	if not owner then
		return
	end
	owners[player] = nil
	if owner.conn then
		owner.conn:Disconnect()
	end
	clear(owner)
end

-- Target CFrame of pet i of n behind a character root (character front = LookVector).
local function slot(rootCF: CFrame, i: number, n: number): CFrame
	local a = if n <= 1 then 0 else -RING_SPREAD / 2 + RING_SPREAD * (i - 1) / (n - 1)
	-- +Z in root space is behind the character
	local offset = Vector3.new(math.sin(a) * RING_RADIUS, 0, math.cos(a) * RING_RADIUS)
	local pos = rootCF:PointToWorldSpace(offset)
	local look = rootCF.LookVector
	return CFrame.lookAt(pos, pos + Vector3.new(look.X, 0, look.Z))
end

local function step(dt: number)
	local cam = workspace.CurrentCamera
	local camPos = if cam then cam.CFrame.Position else nil
	local t = os.clock()
	local bob = if C.ReduceMotion() then BOB_REDUCED else BOB
	local alpha = 1 - math.exp(-FOLLOW_SPEED * dt)
	for player, owner in owners do
		local n = #owner.pets
		if n == 0 then
			continue
		end
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			continue
		end
		local rootCF = root.CFrame
		if camPos and (rootCF.Position - camPos).Magnitude > CULL_DISTANCE then
			continue
		end
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local groundY = rootCF.Position.Y - root.Size.Y / 2 - (if hum then hum.HipHeight else 2)
		for i, pet in owner.pets do
			local target = slot(rootCF, i, n)
			local y = groundY + HOVER + math.sin(t * 2.6 + pet.phase) * bob
			target = target.Rotation + Vector3.new(target.Position.X, y, target.Position.Z)
			local cur = pet.cf
			local nextCF = if cur and (cur.Position - target.Position).Magnitude < 60
				then cur:Lerp(target, alpha)
				else target
			pet.cf = nextCF
			pet.model:PivotTo(nextCF)
			for k, part in pet.rainbow do
				part.Color = PetModels.RainbowColor(t, pet.offsets[k])
			end
		end
	end
end

function PetFollowController:Init()
	local f = Instance.new("Folder")
	f.Name = "ClientPets"
	f.Parent = workspace
	folder = f
end

function PetFollowController:Start()
	for _, p in Players:GetPlayers() do
		track(p)
	end
	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(untrack)
	RunService.Heartbeat:Connect(function(dt)
		Safe.Run("PetFollow step", step, dt)
	end)
end

return PetFollowController
