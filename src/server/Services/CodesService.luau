--!strict
-- B2 CodesService: the RedeemCode RemoteFunction + the shared reward helper.
--
--   RedeemCode (client -> server, RemoteFunction): (code: string) -> (ok: boolean, message: string)
--     Codes live in Config/Codes, are case-insensitive (trimmed + uppercased), optional expiry,
--     and each player can redeem each code once (data.redeemedCodes[CODE] = true).
--
--   CodesService:GrantReward(player, reward, sourceId) -> string?   (returns a short text, nil on failure)
--     reward = { kind = "cash", amount }                  -> DataService:AddCash
--            | { kind = "crates", amount }                -> data.crates += amount
--            | { kind = "boost", boostKind, mult, seconds } -> data.boosts[sourceId]
--     Used by QuestService too, so all reward granting lives in one place.
--
--   CodesService:GrantBoost(player, boostId, kind, mult, seconds)
--     Same boostId again extends the remaining time instead of stacking. Expired boosts are pruned.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Format = require(ReplicatedStorage.Shared.Format)
local Codes = require(ReplicatedStorage.Shared.Config.Codes)
local DataService = require(script.Parent.DataService)
local Notify = require(script.Parent.Parent.Util.Notify)
local Debounce = require(script.Parent.Parent.Util.Debounce)

local CodesService = {}

local function normalize(code: string): string
	return string.upper((string.gsub(code, "%s", "")))
end

function CodesService:GrantBoost(player: Player, boostId: string, kind: string, mult: number, seconds: number)
	local data = DataService:Get(player)
	if not data or (kind ~= "cash" and kind ~= "production") or mult <= 0 or seconds <= 0 then
		return
	end
	data.boosts = data.boosts or {}
	local now = os.time()
	for id, b in data.boosts do
		if b.expires <= now then
			data.boosts[id] = nil
		end
	end
	local existing = data.boosts[boostId]
	if existing and existing.kind == kind and existing.mult == mult then
		existing.expires += seconds
	else
		data.boosts[boostId] = { kind = kind, mult = mult, expires = now + seconds }
	end
	DataService:Replicate(player, "boosts")
end

function CodesService:GrantReward(player: Player, reward: { [string]: any }, sourceId: string): string?
	local data = DataService:Get(player)
	if not data then
		return nil
	end
	if reward.kind == "cash" then
		local amount = tonumber(reward.amount) or 0
		if amount <= 0 then
			return nil
		end
		DataService:AddCash(player, amount)
		return `+{Format.Cash(amount)}`
	elseif reward.kind == "crates" then
		local amount = math.floor(tonumber(reward.amount) or 0)
		if amount <= 0 then
			return nil
		end
		data.crates = (data.crates or 0) + amount
		DataService:Replicate(player, "crates")
		return `+{amount} Mystery Milk Crate{if amount == 1 then "" else "s"}`
	elseif reward.kind == "boost" then
		local kind = reward.boostKind
		local mult = tonumber(reward.mult) or 0
		local seconds = tonumber(reward.seconds) or 0
		if typeof(kind) ~= "string" or mult <= 0 or seconds <= 0 then
			return nil
		end
		CodesService:GrantBoost(player, sourceId, kind, mult, seconds)
		local what = if kind == "cash" then "Cash" else "Milk"
		return `{Format.Number(mult)}x {what} for {Format.Time(seconds)}`
	end
	return nil
end

local function redeem(player: Player, raw: any): (boolean, string)
	if typeof(raw) ~= "string" or #raw == 0 or #raw > Codes.MaxLength * 2 then
		return false, "Invalid code"
	end
	if not Debounce.Try(player, "redeemCode", Codes.CooldownSeconds) then
		return false, "Slow down!"
	end
	local data = DataService:Get(player)
	if not data then
		return false, "Your farm is still loading"
	end
	local code = normalize(raw)
	if #code == 0 or #code > Codes.MaxLength then
		return false, "Invalid code"
	end
	local def = Codes.List[code]
	if not def then
		return false, "That code doesn't exist"
	end
	if def.expires and os.time() > def.expires then
		return false, "That code has expired"
	end
	data.redeemedCodes = data.redeemedCodes or {}
	if data.redeemedCodes[code] then
		return false, "You already redeemed this code"
	end
	-- GrantReward validates before changing anything, so a nil result means nothing was given
	local text = CodesService:GrantReward(player, def.reward, "code_" .. code)
	if not text then
		warn(`[CodesService] code {code} has an invalid reward`)
		return false, "Code is broken, tell the devs!"
	end
	data.redeemedCodes[code] = true
	DataService:Replicate(player, "redeemedCodes")
	Notify.To(player, `Code redeemed: {text}`, "success")
	return true, text
end

function CodesService:Start()
	Net.Function("RedeemCode").OnServerInvoke = function(player: Player, code: any)
		local ok, okRedeem, message = pcall(redeem, player, code)
		if not ok then
			warn(`[CodesService] redeem failed: {okRedeem}`)
			return false, "Something went wrong"
		end
		return okRedeem, message
	end
end

return CodesService
