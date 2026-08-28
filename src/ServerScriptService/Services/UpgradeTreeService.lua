--[[
	UpgradeTreeService.lua - Server-authoritative QOF-07 tree purchases and effects.
	The client sends only an upgrade ID. Costs, currencies, prerequisites, runtime
	availability, and effective entitlements are resolved from BalanceConfig.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BalanceConfig = require(game.ReplicatedStorage.Shared.BalanceConfig)

local UpgradeTreeService = {}

UpgradeTreeService._dataService = nil
UpgradeTreeService._currencyService = nil
UpgradeTreeService._purchaseLocks = {}
UpgradeTreeService._transactionHook = nil

local purchasableById = {}
local availableIds = {}

local function registerPurchasable(level, effectType, variant)
	assert(purchasableById[level.id] == nil, "duplicate purchasable tree ID: " .. level.id)
	purchasableById[level.id] = {
		id = level.id,
		cost = level.cost,
		requireIds = level.requireIds or {},
		effectType = effectType,
		variant = variant,
	}
	availableIds[level.id] = true
end

if BalanceConfig.Hatch.EggQualityRuntimeEnabled then
	for _, level in ipairs(BalanceConfig.Hatch.EggQuality) do
		registerPurchasable(level, "EggQuality")
	end
end

if BalanceConfig.Hatch.DirectVariantUpgradesRuntimeEnabled then
	for variant, levels in pairs(BalanceConfig.Hatch.DirectVariantUpgrades) do
		for _, level in ipairs(levels) do
			registerPurchasable(level, "DirectVariant", variant)
		end
	end
end

local function copyBooleanMap(input)
	local output = {}
	if type(input) ~= "table" then
		return output
	end
	for key, value in pairs(input) do
		if type(key) == "string" and value == true then
			output[key] = true
		end
	end
	return output
end

local function copyAvailableIds()
	return copyBooleanMap(availableIds)
end

local function neutralEntitlements()
	return {
		eggQualityMultiplier = 1,
		directVariantMultipliers = {
			Golden = 1,
			Rainbow = 1,
			Shiny = 1,
		},
		multiOpenCount = 1,
	}
end

local function applyHighestContiguousLevel(levels, purchased, valueKey)
	local value = 1
	for _, level in ipairs(levels) do
		if purchased[level.id] ~= true then
			break
		end
		value = level[valueKey]
	end
	return value
end

-- Pure resolver used by gameplay and tests. Unknown IDs never grant an effect;
-- skipped/corrupt levels stop at the highest complete contiguous chain.
function UpgradeTreeService.resolveEntitlements(purchased)
	purchased = type(purchased) == "table" and purchased or {}
	local entitlements = neutralEntitlements()

	if BalanceConfig.Hatch.EggQualityRuntimeEnabled then
		entitlements.eggQualityMultiplier = applyHighestContiguousLevel(
			BalanceConfig.Hatch.EggQuality,
			purchased,
			"rarityMultiplier"
		)
	end

	if BalanceConfig.Hatch.DirectVariantUpgradesRuntimeEnabled then
		for variant, levels in pairs(BalanceConfig.Hatch.DirectVariantUpgrades) do
			entitlements.directVariantMultipliers[variant] = applyHighestContiguousLevel(
				levels,
				purchased,
				"multiplier"
			)
		end
	end

	-- Multi-Open purchases may exist in legacy saves, but QOF-08 owns their
	-- runtime effect and purchase activation.
	return entitlements
end

function UpgradeTreeService.init(dataService, currencyService)
	UpgradeTreeService._dataService = dataService
	UpgradeTreeService._currencyService = currencyService
end

function UpgradeTreeService.getEntitlements(player)
	if not player or not UpgradeTreeService._dataService then
		return neutralEntitlements()
	end
	local data = UpgradeTreeService._dataService.getPlayerData(player)
	if not data then
		return neutralEntitlements()
	end
	return UpgradeTreeService.resolveEntitlements(data.upgradeTreePurchases)
end

function UpgradeTreeService.getState(player)
	local data = player
		and UpgradeTreeService._dataService
		and UpgradeTreeService._dataService.getPlayerData(player)
	if not data then
		return {
			currency = { coins = 0, diamonds = 0 },
			purchased = {},
			available = copyAvailableIds(),
			entitlements = neutralEntitlements(),
		}
	end

	return {
		currency = {
			coins = type(data.coins) == "number" and data.coins or 0,
			diamonds = type(data.diamonds) == "number" and data.diamonds or 0,
		},
		purchased = copyBooleanMap(data.upgradeTreePurchases),
		available = copyAvailableIds(),
		entitlements = UpgradeTreeService.resolveEntitlements(data.upgradeTreePurchases),
	}
end

local function fireUpdate(player)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local event = remotes and remotes:FindFirstChild("UpgradeTreeUpdated")
	if event then
		pcall(function()
			event:FireClient(player, UpgradeTreeService.getState(player))
		end)
	end
end

local function runTransactionHook(stage, transaction)
	if type(UpgradeTreeService._transactionHook) == "function" then
		UpgradeTreeService._transactionHook(stage, transaction)
	end
end

local function purchaseUnlocked(player, upgradeId, transaction)
	local definition = purchasableById[upgradeId]
	if not definition then
		return false, "Upgrade not available yet", UpgradeTreeService.getState(player)
	end

	local data = UpgradeTreeService._dataService.getPlayerData(player)
	if not data then
		return false, "No player data", UpgradeTreeService.getState(player)
	end

	if type(data.upgradeTreePurchases) ~= "table" then
		data.upgradeTreePurchases = {}
	end
	if data.upgradeTreePurchases[upgradeId] == true then
		return false, "Already purchased", UpgradeTreeService.getState(player)
	end

	for _, requiredId in ipairs(definition.requireIds) do
		if data.upgradeTreePurchases[requiredId] ~= true then
			return false, "Missing prerequisite", UpgradeTreeService.getState(player)
		end
	end

	local cost = definition.cost
	transaction.data = data
	transaction.currency = cost.currency
	transaction.amount = cost.amount
	transaction.previousValue = data.upgradeTreePurchases[upgradeId]
	local spent = UpgradeTreeService._currencyService.spend(
		player,
		cost.currency,
		cost.amount
	)
	if not spent then
		return false, "Not enough " .. cost.currency, UpgradeTreeService.getState(player)
	end
	transaction.spent = true
	runTransactionHook("afterSpend", transaction)

	-- Both mutations are rollback-tracked until the authoritative state has been
	-- constructed. Client replication happens only after this commit point.
	data.upgradeTreePurchases[upgradeId] = true
	transaction.entitlementSet = true
	runTransactionHook("afterEntitlement", transaction)
	local state = UpgradeTreeService.getState(player)
	transaction.committed = true
	fireUpdate(player)
	return true, "Purchased " .. upgradeId, state
end

function UpgradeTreeService.purchase(player, upgradeId)
	if not player or type(upgradeId) ~= "string" or #upgradeId == 0 or #upgradeId > 64 then
		return false, "Invalid upgrade", UpgradeTreeService.getState(player)
	end
	if not UpgradeTreeService._dataService or not UpgradeTreeService._currencyService then
		return false, "Service unavailable", UpgradeTreeService.getState(player)
	end

	local lockKey = player.UserId or player
	if UpgradeTreeService._purchaseLocks[lockKey] then
		return false, "Purchase already in progress", UpgradeTreeService.getState(player)
	end
	UpgradeTreeService._purchaseLocks[lockKey] = true

	local transaction = {
		player = player,
		upgradeId = upgradeId,
		spent = false,
		entitlementSet = false,
		committed = false,
	}
	local callSucceeded, purchaseSucceeded, message, state = pcall(
		purchaseUnlocked,
		player,
		upgradeId,
		transaction
	)
	UpgradeTreeService._purchaseLocks[lockKey] = nil

	if not callSucceeded then
		if transaction.entitlementSet and transaction.data then
			transaction.data.upgradeTreePurchases[upgradeId] = transaction.previousValue
		end
		local rollbackSucceeded = true
		if transaction.spent then
			rollbackSucceeded = UpgradeTreeService._currencyService.creditRaw(
				player,
				transaction.currency,
				transaction.amount
			) == true
		end
		if not rollbackSucceeded then
			return false, "Purchase rollback failed", UpgradeTreeService.getState(player)
		end
		return false, "Purchase failed safely", UpgradeTreeService.getState(player)
	end
	return purchaseSucceeded, message, state
end

return UpgradeTreeService
