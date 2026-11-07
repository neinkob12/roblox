--!strict
-- B2 CodesService: the RedeemCode RemoteFunction.
--
--   RedeemCode (client -> server, RemoteFunction): (code: string) -> (ok: boolean, message: string)
--     Codes live in Config/Codes, are case-insensitive (trimmed + uppercased), optional expiry,
--     and each player can redeem each code once (data.redeemedCodes[CODE] = true).
--
--   Rewards are granted by server/Util/Rewards (Rewards.Grant), shared with QuestService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Codes = require(ReplicatedStorage.Shared.Config.Codes)
local DataService = require(script.Parent.DataService)
local Notify = require(script.Parent.Parent.Util.Notify)
local Debounce = require(script.Parent.Parent.Util.Debounce)
local Rewards = require(script.Parent.Parent.Util.Rewards)

local CodesService = {}

local function normalize(code: string): string
	return string.upper((string.gsub(code, "%s", "")))
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
	-- Rewards.Grant validates before changing anything, so a nil result means nothing was given
	local text = Rewards.Grant(player, def.reward, "code_" .. code)
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
