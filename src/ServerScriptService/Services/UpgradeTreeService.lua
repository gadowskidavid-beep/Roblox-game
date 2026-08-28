--[[
	UpgradeTreeService.lua - Server-authoritative tree purchases and effects.
	QOF-12 adds Movement Speed and Magnet to the existing hatch/capacity entitlements.
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

if BalanceConfig.Hatch.MultiOpenRuntimeEnabled then
	for _, level in ipairs(BalanceConfig.Hatch.MultiOpen) do
		registerPurchasable(level, "MultiOpen")
	end
end

if BalanceConfig.Hatch.DirectVariantUpgradesRuntimeEnabled then
	for variant, levels in pairs(BalanceConfig.Hatch.DirectVariantUpgrades) do
		for _, level in ipairs(levels) do
			registerPurchasable(level, "DirectVariant", variant)
		end
	end
end

if BalanceConfig.CoreUpgrades.SpeedRuntimeEnabled then
	for _, level in ipairs(BalanceConfig.CoreUpgrades.Speed) do
		registerPurchasable(level, "MovementSpeed")
	end
end

if BalanceConfig.CoreUpgrades.MagnetRuntimeEnabled then
	for _, level in ipairs(BalanceConfig.CoreUpgrades.Magnet) do
		registerPurchasable(level, "Magnet")
	end
end

if BalanceConfig.CoreUpgrades.StorageRuntimeEnabled then
	for _, level in ipairs(BalanceConfig.CoreUpgrades.Storage) do
		registerPurchasable(level, "Storage")
	end
end

if BalanceConfig.CoreUpgrades.PetEquipSlotsRuntimeEnabled then
	for _, level in ipairs(BalanceConfig.CoreUpgrades.PetEquipSlots) do
		registerPurchasable(level, "PetEquipSlots")
	end
end

if BalanceConfig.CoreUpgrades.DoubleLuckRuntimeEnabled then
	registerPurchasable(BalanceConfig.CoreUpgrades.DoubleLuck, "DoubleLuck")
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
		generalLuckMultiplier = 1,
		movementSpeedMultiplier = 1,
		magnetRangeMultiplier = 1,
		storageBonusSlots = 0,
		petEquipBonusSlots = 0,
	}
end

local function applyHighestContiguousLevel(levels, purchased, valueKey, neutralValue)
	local value = neutralValue
	for _, level in ipairs(levels) do
		if purchased[level.id] ~= true then
			break
		end
		local prerequisitesMet = true
		for _, requiredId in ipairs(level.requireIds or {}) do
			if purchased[requiredId] ~= true then
				prerequisitesMet = false
				break
			end
		end
		if not prerequisitesMet then
			break
		end
		value = level[valueKey]
	end
	return value
end

-- Capacity branches reuse legacy purchase IDs. Their effects are grandfathered
-- from the highest contiguous branch prefix even when an old save predates the
-- external Eggs II root prerequisite. New purchases still use purchaseUnlocked,
-- which enforces every canonical requireId before charging.
local function applyGrandfatheredCapacityPrefix(levels, purchased, valueKey, neutralValue)
	local value = neutralValue
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
			"rarityMultiplier",
			1
		)
	end

	if BalanceConfig.Hatch.DirectVariantUpgradesRuntimeEnabled then
		for variant, levels in pairs(BalanceConfig.Hatch.DirectVariantUpgrades) do
			entitlements.directVariantMultipliers[variant] = applyHighestContiguousLevel(
				levels,
				purchased,
				"multiplier",
				1
			)
		end
	end

	if BalanceConfig.Hatch.MultiOpenRuntimeEnabled then
		-- The imported tree is one strict chain: Eggs I -> II -> III -> IV -> V.
		-- Sparse or forged legacy flags stop at the last fully contiguous stage.
		local eggQualityComplete = true
		for _, level in ipairs(BalanceConfig.Hatch.EggQuality) do
			if purchased[level.id] ~= true then
				eggQualityComplete = false
				break
			end
		end
		if eggQualityComplete then
			entitlements.multiOpenCount = applyHighestContiguousLevel(
				BalanceConfig.Hatch.MultiOpen,
				purchased,
				"eggCount",
				1
			)
		end
	end

	if BalanceConfig.CoreUpgrades.DoubleLuckRuntimeEnabled then
		entitlements.generalLuckMultiplier = applyHighestContiguousLevel(
			{ BalanceConfig.CoreUpgrades.DoubleLuck },
			purchased,
			"multiplier",
			1
		)
	end

	if BalanceConfig.CoreUpgrades.SpeedRuntimeEnabled then
		entitlements.movementSpeedMultiplier = applyHighestContiguousLevel(
			BalanceConfig.CoreUpgrades.Speed,
			purchased,
			"multiplier",
			1
		)
	end

	if BalanceConfig.CoreUpgrades.MagnetRuntimeEnabled then
		entitlements.magnetRangeMultiplier = applyHighestContiguousLevel(
			BalanceConfig.CoreUpgrades.Magnet,
			purchased,
			"multiplier",
			1
		)
	end

	if BalanceConfig.CoreUpgrades.StorageRuntimeEnabled then
		entitlements.storageBonusSlots = applyGrandfatheredCapacityPrefix(
			BalanceConfig.CoreUpgrades.Storage,
			purchased,
			"bonusSlots",
			0
		)
	end

	if BalanceConfig.CoreUpgrades.PetEquipSlotsRuntimeEnabled then
		entitlements.petEquipBonusSlots = applyGrandfatheredCapacityPrefix(
			BalanceConfig.CoreUpgrades.PetEquipSlots,
			purchased,
			"bonusSlots",
			0
		)
	end

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

local function buildState(data)
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

function UpgradeTreeService.getState(player)
	local data = player
		and UpgradeTreeService._dataService
		and UpgradeTreeService._dataService.getPlayerData(player)
	return buildState(data)
end

local function fireUpdate(player, state)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local event = remotes and remotes:FindFirstChild("UpgradeTreeUpdated")
	if event then
		pcall(function()
			event:FireClient(player, state)
		end)
	end
end

local function runTransactionHook(stage, transaction)
	if type(UpgradeTreeService._transactionHook) == "function" then
		UpgradeTreeService._transactionHook(stage, transaction)
	end
end

local function releasePurchaseLock(transaction)
	if transaction.lockHeld
		and UpgradeTreeService._purchaseLocks[transaction.lockKey] == transaction then
		UpgradeTreeService._purchaseLocks[transaction.lockKey] = nil
		transaction.lockHeld = false
	end
end

-- Restore only values still owned by this transaction. A failed restoration or
-- currency rollback deliberately retains both the central owner and local lock
-- so the registered lifecycle settler can retry without overwriting newer data.
local function restoreTransaction(transaction)
	if transaction.committed then
		return true
	end

	if not transaction.entitlementRestored then
		if transaction.purchasesInstalled then
			if transaction.data.upgradeTreePurchases ~= transaction.purchases then
				return false
			end
			transaction.data.upgradeTreePurchases = transaction.previousPurchases
			transaction.purchasesInstalled = false
			transaction.entitlementSet = false
		elseif transaction.entitlementSet then
			if transaction.data.upgradeTreePurchases ~= transaction.purchases
				or transaction.purchases[transaction.upgradeId] ~= true then
				return false
			end
			transaction.purchases[transaction.upgradeId] = transaction.previousValue
			transaction.entitlementSet = false
		end
		transaction.entitlementRestored = true
	end

	if transaction.spendTransaction then
		local rollbackCallSucceeded, rollbackSucceeded = pcall(
			UpgradeTreeService._currencyService.rollbackSpendTransaction,
			transaction.spendTransaction
		)
		if not rollbackCallSucceeded or rollbackSucceeded ~= true then
			return false
		end
		transaction.spendTransaction = nil
	end

	releasePurchaseLock(transaction)
	return true
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

	local purchases = type(data.upgradeTreePurchases) == "table"
		and data.upgradeTreePurchases
		or nil
	local validationPurchases = purchases or {}
	if validationPurchases[upgradeId] == true then
		return false, "Already purchased", UpgradeTreeService.getState(player)
	end

	-- Grandfathered capacity flags grant their historical effects, but never
	-- bypass the modern Eggs II gate for any newly purchased branch level.
	if (definition.effectType == "Storage" or definition.effectType == "PetEquipSlots")
		and validationPurchases["Eggs II"] ~= true then
		return false, "Missing prerequisite", UpgradeTreeService.getState(player)
	end

	for _, requiredId in ipairs(definition.requireIds) do
		if validationPurchases[requiredId] ~= true then
			return false, "Missing prerequisite", UpgradeTreeService.getState(player)
		end
	end

	local cost = definition.cost
	transaction.data = data
	transaction.currency = cost.currency
	transaction.amount = cost.amount
	transaction.purchases = purchases
	transaction.previousPurchases = data.upgradeTreePurchases
	transaction.previousValue = validationPurchases[upgradeId]
	transaction.spendTransaction = UpgradeTreeService._currencyService.beginSpendTransaction(
		player,
		cost.currency,
		cost.amount,
		"UpgradeTreeService"
	)
	if not transaction.spendTransaction then
		return false, "Not enough " .. cost.currency, UpgradeTreeService.getState(player)
	end

	local settlerRegistered = UpgradeTreeService._currencyService.setSpendSettler(
		transaction.spendTransaction,
		function(currentSpendTransaction)
			if currentSpendTransaction ~= transaction.spendTransaction then
				return false
			end
			return restoreTransaction(transaction)
		end
	)
	if settlerRegistered ~= true then
		error("Unable to register purchase settler")
	end
	transaction.settlerRegistered = true

	-- Every operation after reservation now has a centrally retained rollback.
	-- Verify that the profile validated before begin is still the owned profile.
	if UpgradeTreeService._dataService.getPlayerData(player) ~= data then
		error("Player profile changed during purchase")
	end
	runTransactionHook("afterSpend", transaction)

	-- Install/modify the entitlement only after the rollback closure is retained
	-- by the central owner, and reject an unexpected profile-table replacement.
	if purchases then
		if data.upgradeTreePurchases ~= purchases
			or purchases[upgradeId] ~= transaction.previousValue then
			error("Upgrade purchases changed during purchase")
		end
	else
		if data.upgradeTreePurchases ~= transaction.previousPurchases then
			error("Upgrade purchases changed during purchase")
		end
		purchases = {}
		data.upgradeTreePurchases = purchases
		transaction.purchases = purchases
		transaction.purchasesInstalled = true
	end
	purchases[upgradeId] = true
	transaction.entitlementSet = true
	runTransactionHook("afterEntitlement", transaction)

	-- Build the complete post-purchase DTO while the debit is still silent. The
	-- projected balance becomes live exactly once at the following commit PONR.
	local state = buildState(data)
	state.currency[cost.currency] = state.currency[cost.currency] - cost.amount
	transaction.state = state
	runTransactionHook("afterState", transaction)

	if UpgradeTreeService._currencyService.commitSpendTransaction(
		transaction.spendTransaction
	) ~= true then
		error("Currency commit failed")
	end

	-- Currency commit is the point of no return. Everything after this point is
	-- terminal/best-effort and must never enter compensation.
	transaction.committed = true
	transaction.spendTransaction = nil
	transaction.entitlementSet = false
	transaction.purchasesInstalled = false
	releasePurchaseLock(transaction)
	fireUpdate(player, state)
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

	local transaction = {
		player = player,
		upgradeId = upgradeId,
		lockKey = lockKey,
		lockHeld = true,
		entitlementSet = false,
		entitlementRestored = false,
		purchasesInstalled = false,
		committed = false,
	}
	UpgradeTreeService._purchaseLocks[lockKey] = transaction

	local callSucceeded, purchaseSucceeded, message, state = pcall(
		purchaseUnlocked,
		player,
		upgradeId,
		transaction
	)

	if not callSucceeded then
		if transaction.committed then
			releasePurchaseLock(transaction)
			return true, "Purchased " .. upgradeId, transaction.state
		end
		if not restoreTransaction(transaction) then
			return false, "Purchase rollback failed", UpgradeTreeService.getState(player)
		end
		return false, "Purchase failed safely", UpgradeTreeService.getState(player)
	end

	if not purchaseSucceeded then
		releasePurchaseLock(transaction)
	end
	return purchaseSucceeded, message, state
end

return UpgradeTreeService
