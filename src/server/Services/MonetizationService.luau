--!strict
-- B3: Monetization. Gamepasses (player attributes) and developer products (the ONE ProcessReceipt).
-- Owner: Monetization session (B3). Nobody else may set MarketplaceService.ProcessReceipt.
--
-- Gamepasses: on join we check UserOwnsGamePassAsync (pcall + retry) for every pass with id ~= 0
-- and set Player attributes Pass_DoubleCash / Pass_AutoMerge / Pass_AutoSell (false by default).
-- PromptGamePassPurchaseFinished applies a new purchase instantly, no rejoin needed.
--
-- Dev products follow the ProfileStore receipt pattern: grant once per PurchaseId, remember the id in
-- data.purchases (last Products.PurchaseIdCacheSize ids), profile:Save(), and only return
-- PurchaseGranted once the id is in profile.LastSavedData. Otherwise NotProcessedYet (Roblox retries).
--
--   MonetizationService:OwnsPass(player, passKey) -> boolean
--   MonetizationService:DebugGrantProduct(player, productKey) -> string   (Studio only, fake receipt)
--   MonetizationService:DebugSetPass(player, passKey, owned)               (Studio only)

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Products = require(ReplicatedStorage.Shared.Config.Products)
local Format = require(ReplicatedStorage.Shared.Format)
local Multipliers = require(ReplicatedStorage.Shared.Multipliers)
local DataService = require(script.Parent.DataService)
local Notify = require(script.Parent.Parent.Util.Notify)

local SAVE_WAIT_TIMEOUT = 60 -- seconds to wait for the save before telling Roblox to retry later

local MonetizationService = {}

-- Gamepasses ------------------------------------------------------------------------------

local function setPass(player: Player, key: string, owned: boolean)
	local pass = Products.Passes[key]
	if pass then
		player:SetAttribute(pass.attribute, owned)
	end
end

local function checkPass(player: Player, key: string)
	local pass = Products.Passes[key]
	if not pass or pass.id == 0 then
		return
	end
	for attempt = 1, Products.PassCheckRetries do
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
		end)
		if player.Parent ~= Players then
			return
		end
		if ok then
			if owns then
				setPass(player, key, true)
			end
			return
		end
		warn(`[Monetization] UserOwnsGamePassAsync failed for {key} (attempt {attempt}): {owns}`)
		task.wait(2 * attempt)
	end
end

local function onPlayerAdded(player: Player)
	for _, pass in Products.Passes do
		-- default false so UI and gameplay can read a boolean right away; never downgrade a true
		if player:GetAttribute(pass.attribute) == nil then
			player:SetAttribute(pass.attribute, false)
		end
	end
	for key in Products.Passes do
		task.spawn(checkPass, player, key)
	end
end

local function onPassPurchaseFinished(player: Player, passId: number, wasPurchased: boolean)
	if not wasPurchased then
		return
	end
	local key = Products.PassKeyById[passId]
	if not key then
		return
	end
	setPass(player, key, true)
	Notify.To(player, `Thanks! {Products.Passes[key].name} is now active!`, "success")
end

function MonetizationService:OwnsPass(player: Player, passKey: string): boolean
	local pass = Products.Passes[passKey]
	return pass ~= nil and player:GetAttribute(pass.attribute) == true
end

-- Dev product grants ------------------------------------------------------------------------
-- Each grant runs synchronously, must not yield, and errors are caught (then nothing is recorded).

local function grantCash(player: Player, data: any, key: string)
	local entry = Products.DevProducts[key]
	local amount =
		Products.CashPackAmount(Multipliers.MilkPerSecond(player, data), Multipliers.Cash(player, data), entry)
	DataService:AddCash(player, amount)
	Notify.To(player, `+{Format.Cash(amount)} from {entry.name}!`, "success")
end

local GRANTS: { [string]: (Player, any) -> () } = {
	CashSmall = function(player, data)
		grantCash(player, data, "CashSmall")
	end,
	CashMedium = function(player, data)
		grantCash(player, data, "CashMedium")
	end,
	CashLarge = function(player, data)
		grantCash(player, data, "CashLarge")
	end,
	PremiumCrate = function(player, data)
		local crateModule = script.Parent:FindFirstChild("CrateService")
		local crateService: any = nil
		if crateModule and crateModule:IsA("ModuleScript") then
			crateService = require(script.Parent.CrateService)
		end
		if crateService and type(crateService.GiveCrate) == "function" then
			-- opens immediately with better odds, fires CrateOpened(tier, "premium") for the spin UI
			crateService:GiveCrate(player, true)
		else
			data.crates = (data.crates or 0) + 1
			DataService:Replicate(player, "crates")
			Notify.To(player, "You got a Premium Milk Crate!", "success")
		end
	end,
	Boost3x = function(player, data)
		local entry = Products.DevProducts.Boost3x
		local now = os.time()
		data.boosts = data.boosts or {}
		local existing = data.boosts[Products.Boost3xKey]
		local base = now
		if existing and type(existing.expires) == "number" and existing.expires > now then
			base = existing.expires -- stack time on an active boost
		end
		data.boosts[Products.Boost3xKey] = {
			kind = "cash",
			mult = Products.Boost3xMult,
			expires = base + (entry.boostSeconds or 0),
		}
		DataService:Replicate(player, "boosts")
		local minutes = math.floor(((base + (entry.boostSeconds or 0)) - now) / 60 + 0.5)
		Notify.To(player, `3x Cash active for {minutes} min!`, "success")
	end,
}

-- Receipts ------------------------------------------------------------------------------------

local function savedHas(profile: any, purchaseId: string): boolean
	local saved = profile.LastSavedData
	local ids = saved and saved.purchases
	return type(ids) == "table" and table.find(ids, purchaseId) ~= nil
end

-- ProfileStore receipt pattern. Returns the decision for Roblox.
local function processPurchase(player: Player, purchaseId: string, productKey: string): Enum.ProductPurchaseDecision
	local data = DataService:WaitFor(player)
	local profile = DataService:GetProfile(player)
	if not data or not profile or profile:IsActive() ~= true then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if type(data.purchases) ~= "table" then
		data.purchases = {}
	end
	local ids: { string } = data.purchases

	if table.find(ids, purchaseId) == nil then
		local grant = GRANTS[productKey]
		if not grant then
			warn(`[Monetization] no grant function for {productKey}`)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local ok, err = pcall(grant :: any, player, data)
		if not ok then
			warn(`[Monetization] grant {productKey} failed: {err}`)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		while #ids >= Products.PurchaseIdCacheSize do
			table.remove(ids, 1)
		end
		table.insert(ids, purchaseId)
	end

	-- Wait until the purchase id is confirmed saved
	local result: Enum.ProductPurchaseDecision? = nil
	if savedHas(profile, purchaseId) then
		result = Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if result == nil then
		local connection = profile.OnAfterSave:Connect(function()
			if savedHas(profile, purchaseId) then
				result = Enum.ProductPurchaseDecision.PurchaseGranted
			end
		end)
		profile:Save()
		local started = os.clock()
		while result == nil and profile:IsActive() == true and os.clock() - started < SAVE_WAIT_TIMEOUT do
			task.wait()
		end
		connection:Disconnect()
		-- the final save on session end may have included it
		if result == nil and savedHas(profile, purchaseId) then
			result = Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end
	return result or Enum.ProductPurchaseDecision.NotProcessedYet
end

local function processReceipt(receiptInfo: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local productKey = Products.ProductKeyById[receiptInfo.ProductId]
	if not productKey then
		warn(`[Monetization] unknown ProductId {receiptInfo.ProductId}; paste it into Config/Products.luau`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, decision = pcall(processPurchase, player, tostring(receiptInfo.PurchaseId), productKey)
	if not ok then
		warn(`[Monetization] receipt error: {decision}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return decision
end

-- Studio-only debug helpers (run from the Studio command bar on the server) -----------------

function MonetizationService:DebugGrantProduct(player: Player, productKey: string): string
	if not RunService:IsStudio() then
		return "Studio only"
	end
	if not Products.DevProducts[productKey] then
		return `Unknown product {productKey}`
	end
	local decision = processPurchase(player, "debug-" .. HttpService:GenerateGUID(false), productKey)
	return decision.Name
end

function MonetizationService:DebugSetPass(player: Player, passKey: string, owned: boolean)
	if not RunService:IsStudio() then
		return
	end
	setPass(player, passKey, owned)
end

-- Lifecycle ---------------------------------------------------------------------------------

function MonetizationService:Init()
	MarketplaceService.ProcessReceipt = processReceipt
end

function MonetizationService:Start()
	local missing = {}
	for key, pass in Products.Passes do
		if pass.id == 0 then
			table.insert(missing, key)
		end
	end
	for key, product in Products.DevProducts do
		if product.id == 0 then
			table.insert(missing, key)
		end
	end
	if #missing > 0 then
		table.sort(missing)
		warn(
			`[Monetization] Products not configured (id = 0): {table.concat(missing, ", ")}. See docs/MONETIZATION_SETUP.md`
		)
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(onPassPurchaseFinished)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return MonetizationService
