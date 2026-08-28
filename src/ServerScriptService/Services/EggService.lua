--[[
	EggService.lua - Atomic server-authoritative egg batch orchestration.
	QOF-08 validates station proximity, entitlement-selected batch size, total
	price and total capacity before committing any result. Client animation never
	delays the authoritative transaction.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(game.ReplicatedStorage.Shared.Config)
local PetData = require(game.ReplicatedStorage.Shared.PetData)

local EggService = {}

EggService._dataService = nil
EggService._currencyService = nil
EggService._petService = nil
EggService._questService = nil
EggService._upgradeTreeService = nil
EggService._potionService = nil
EggService._hatchLock = {}
EggService._activeTransactions = {}
EggService._shuttingDown = false
EggService._transactionHook = nil
EggService._stationValidator = nil
EggService._nextBatchId = 0

local BATCH_COUNT_TIERS = { 1, 2, 5, 10 }
local VALID_BATCH_COUNTS = {
	[1] = true,
	[2] = true,
	[5] = true,
	[10] = true,
}

local function isFiniteNumber(value)
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
end

local function isValidBatchCount(value)
	return isFiniteNumber(value)
		and value % 1 == 0
		and VALID_BATCH_COUNTS[value] == true
end

local function isValidTransactionCount(value, maximum)
	return isFiniteNumber(value)
		and value % 1 == 0
		and value >= 1
		and value <= maximum
end

function EggService.init(dataService, currencyService, petService, upgradeTreeService)
	EggService._dataService = dataService
	EggService._currencyService = currencyService
	EggService._petService = petService
	EggService._upgradeTreeService = upgradeTreeService
	EggService._hatchLock = {}
	EggService._activeTransactions = {}
	EggService._shuttingDown = false
end

function EggService.setPotionService(potionService)
	EggService._potionService = potionService
end

function EggService.setQuestService(questService)
	EggService._questService = questService
end

function EggService.setStationAuthority(authority)
	if type(authority) == "table" and type(authority.validateManual) == "function" then
		EggService._stationValidator = authority.validateManual
	else
		EggService._stationValidator = nil
	end
end

local function isUnlockedZone(data, zoneId)
	for _, unlockedId in ipairs(data.unlockedZones or {}) do
		if unlockedId == zoneId then
			return true
		end
	end
	return false
end

local function getMaximumBatchCount(player)
	if not EggService._upgradeTreeService then
		return 1
	end
	local entitlements = EggService._upgradeTreeService.getEntitlements(player)
	local count = type(entitlements) == "table" and entitlements.multiOpenCount or 1
	if isValidBatchCount(count) then
		return count
	end
	return 1
end

local function highestAllowedBatchCount(maximum)
	for index = #BATCH_COUNT_TIERS, 1, -1 do
		local count = BATCH_COUNT_TIERS[index]
		if count <= maximum then
			return count
		end
	end
	return 1
end

local function getPlayerData(player)
	if not player or not EggService._dataService then
		return nil
	end
	return EggService._dataService.getPlayerData(player)
end

local function reconcilePreferredBatchCount(player, maximum)
	local data = getPlayerData(player)
	if not data then
		return 1
	end
	if type(data.hatchPreferences) ~= "table" then
		data.hatchPreferences = { preferredBatchCount = 1 }
	end

	-- QOF-18 repairs only structurally invalid persisted values. A valid tier that
	-- later loses entitlement is preserved and must pause Auto-Hatch rather than
	-- silently mutating or executing a smaller paid batch.
	local selected = data.hatchPreferences.preferredBatchCount
	if not isValidBatchCount(selected) then
		selected = 1
	end
	data.hatchPreferences.preferredBatchCount = selected
	return selected
end

local function validatePreferredCount(player, requestedCount, maximum)
	if not isValidBatchCount(requestedCount) then
		return nil, "Invalid hatch count"
	end
	maximum = maximum or getMaximumBatchCount(player)
	if requestedCount > maximum then
		return nil, "Multi-Open upgrade required"
	end
	return requestedCount, nil
end

local function validateTransactionCount(player, requestedCount, maximum)
	maximum = maximum or getMaximumBatchCount(player)
	if not isFiniteNumber(requestedCount) or requestedCount % 1 ~= 0 or requestedCount < 1 then
		return nil, "Invalid hatch count"
	end
	if requestedCount > maximum then
		return nil, "Multi-Open upgrade required"
	end
	if not isValidTransactionCount(requestedCount, maximum) then
		return nil, "Invalid hatch count"
	end
	return requestedCount, nil
end

function EggService.getSelectedBatchCount(player)
	if not player then
		return 1
	end
	local maximum = getMaximumBatchCount(player)
	return reconcilePreferredBatchCount(player, maximum)
end

function EggService.getBatchState(player)
	local maximum = player and getMaximumBatchCount(player) or 1
	return {
		selectedCount = player and reconcilePreferredBatchCount(player, maximum) or 1,
		maximumCount = maximum,
		availableCounts = { 1, 2, 5, 10 },
	}
end

function EggService.setSelectedBatchCount(player, requestedCount)
	if not player then
		return false, "Invalid player", EggService.getBatchState(player)
	end
	local maximum = getMaximumBatchCount(player)
	reconcilePreferredBatchCount(player, maximum)
	local count, countError = validatePreferredCount(player, requestedCount, maximum)
	if not count then
		return false, countError, EggService.getBatchState(player)
	end
	local data = getPlayerData(player)
	if not data then
		return false, "No player data", EggService.getBatchState(player)
	end
	data.hatchPreferences.preferredBatchCount = count
	return true, nil, EggService.getBatchState(player)
end

local function isNearStation(player, eggType)
	-- QOF-18 requires the private registry authority for every manual quote and
	-- purchase. A partial world bootstrap must never fall back to replicated
	-- names, tags, prompts, or client-visible distances.
	return type(EggService._stationValidator) == "function"
		and EggService._stationValidator(player, eggType) == true
end

local function getManualQuoteContext(player, eggType)
	if not player or type(eggType) ~= "string" or eggType == "" then
		return nil, "Invalid parameters"
	end
	local eggDef = PetData.Eggs[eggType]
	if not eggDef then
		return nil, "Unknown egg type: " .. tostring(eggType)
	end
	local data = getPlayerData(player)
	if not data or type(data.pets) ~= "table" then
		return nil, "No player data"
	end
	if not isUnlockedZone(data, eggDef.zone) then
		return nil, "Zone not unlocked for this egg type"
	end
	local eggCost = Config.EggCosts[eggDef.zone]
	local unitCost = eggCost and eggCost.Coins
	if not isFiniteNumber(unitCost) or unitCost < 0 or unitCost % 1 ~= 0 then
		return nil, "No valid coin cost for egg zone"
	end
	if not isNearStation(player, eggType) then
		return nil, "Move closer to this egg station"
	end

	local entitlementCap = getMaximumBatchCount(player)
	local maximumInventory = EggService._petService.getMaxInventory(player)
	if not isFiniteNumber(maximumInventory) then
		maximumInventory = #data.pets
	end
	local freeSlots = math.max(0, math.floor(maximumInventory) - #data.pets)
	local coins = isFiniteNumber(data.coins) and math.max(0, math.floor(data.coins)) or 0
	local affordableCount = unitCost == 0 and entitlementCap or math.floor(coins / unitCost)
	local feasibleMax = math.max(0, math.min(entitlementCap, freeSlots, affordableCount, 10))

	return {
		eggType = eggType,
		zone = eggDef.zone,
		unitCost = unitCost,
		entitlementCap = entitlementCap,
		freeSlots = freeSlots,
		coins = coins,
		feasibleMax = feasibleMax,
		x1 = {
			count = 1,
			available = feasibleMax >= 1,
			totalCost = unitCost,
			intent = { mode = "Fixed", count = 1 },
		},
		x3 = {
			count = 3,
			available = entitlementCap >= 3 and feasibleMax >= 3,
			totalCost = unitCost * 3,
			intent = { mode = "Fixed", count = 3 },
		},
		max = {
			count = feasibleMax,
			available = feasibleMax >= 1,
			totalCost = unitCost * feasibleMax,
			intent = { mode = "Max" },
		},
	}, nil
end

-- Server-authoritative manual purchase quote. It intentionally does not read or
-- mutate hatchPreferences; those preferences belong only to the later Auto-Hatch flow.
function EggService.getHatchPurchaseOptions(player, eggType)
	return getManualQuoteContext(player, eggType)
end

local function validateStrictIntent(intent)
	if type(intent) ~= "table" or getmetatable(intent) ~= nil then
		return nil, "Invalid hatch intent"
	end
	if intent.mode == "Fixed" then
		local keyCount = 0
		for key in pairs(intent) do
			if key ~= "mode" and key ~= "count" then
				return nil, "Invalid hatch intent"
			end
			keyCount = keyCount + 1
		end
		if keyCount ~= 2 or (intent.count ~= 1 and intent.count ~= 3) then
			return nil, "Invalid hatch intent"
		end
		return intent.count, nil
	elseif intent.mode == "Max" then
		local keyCount = 0
		for key in pairs(intent) do
			if key ~= "mode" then
				return nil, "Invalid hatch intent"
			end
			keyCount = keyCount + 1
		end
		if keyCount ~= 1 then
			return nil, "Invalid hatch intent"
		end
		return "Max", nil
	end
	return nil, "Invalid hatch intent"
end

local purchaseAndHatchUnlocked

local function withHatchLock(player, callback)
	if not player then
		return nil, "Invalid parameters"
	end
	if EggService._shuttingDown then
		return nil, "Hatching is unavailable"
	end
	local lockKey = player.UserId or player
	if EggService._hatchLock[lockKey] then
		return nil, "Already hatching eggs"
	end
	EggService._hatchLock[lockKey] = true
	local callSucceeded, result, hatchError = pcall(callback)
	if EggService._activeTransactions[lockKey] == nil then
		EggService._hatchLock[lockKey] = nil
	end
	if not callSucceeded then
		return nil, "Hatch failed safely"
	end
	return result, hatchError
end

function EggService.purchaseFromIntent(player, eggType, intent)
	local selection, intentError = validateStrictIntent(intent)
	if not selection then
		return nil, intentError
	end

	-- Confirmation is serialized before Max is resolved. Quote resolution,
	-- entitlement/capacity validation, debit, and inventory commit therefore share
	-- one hatch critical section instead of trusting an earlier client quote.
	return withHatchLock(player, function()
		local quote, quoteError = getManualQuoteContext(player, eggType)
		if not quote then
			return nil, quoteError
		end

		local count
		if selection == "Max" then
			count = quote.feasibleMax
		elseif selection == 3 then
			if not quote.x3.available then
				return nil, "x3 hatch option unavailable"
			end
			count = 3
		else
			if not quote.x1.available then
				return nil, "x1 hatch option unavailable"
			end
			count = 1
		end
		if count < 1 then
			return nil, "No feasible hatch purchase"
		end

		return purchaseAndHatchUnlocked(player, eggType, count, {
			bypassStation = false,
			consumeShinyCharges = true,
		})
	end)
end

local function runTransactionHook(stage, transaction)
	if type(EggService._transactionHook) == "function" then
		EggService._transactionHook(stage, transaction)
	end
end

local function makeBatchId(player)
	EggService._nextBatchId = EggService._nextBatchId + 1
	return tostring(player.UserId or "player") .. ":" .. tostring(EggService._nextBatchId)
end

local function rollbackTransaction(transaction)
	if transaction.committed then return true end
	local inventoryRestored = true
	if transaction.prepared then
		if transaction.prepared.mutationStarted then
			local ok, restored = pcall(
				EggService._petService.rollbackHatchBatch,
				transaction.prepared,
				transaction.inventoryLease
			)
			inventoryRestored = ok and restored == true
		end
		if inventoryRestored then
			transaction.prepared = nil
		end
	end
	local chargesRestored = true
	if transaction.shinyChargeTransaction then
		local ok, restored = pcall(
			EggService._potionService.rollbackShinyChargeTransaction,
			transaction.shinyChargeTransaction
		)
		chargesRestored = ok and restored == true
		if chargesRestored then
			transaction.shinyChargeTransaction = nil
		end
	end
	local currencyRestored = true
	if transaction.spent and transaction.totalCost > 0 then
		local ok, restored = pcall(
			EggService._currencyService.creditRaw,
			transaction.player,
			"coins",
			transaction.totalCost
		)
		currencyRestored = ok and restored == true
		if currencyRestored then
			transaction.spent = false
		end
	end
	return inventoryRestored and chargesRestored and currencyRestored
end

local function settleTransaction(transaction)
	if transaction.executing then return false end
	if not rollbackTransaction(transaction) then return false end
	local ok, released = pcall(
		EggService._petService.endInventoryMutation,
		transaction.player,
		transaction.inventoryLease,
		transaction.committed == true
	)
	if not ok or released ~= true then return false end
	local userId = transaction.player.UserId or transaction.player
	if EggService._activeTransactions[userId] == transaction then
		EggService._activeTransactions[userId] = nil
		EggService._hatchLock[userId] = nil
	end
	return true
end

local function notifyCommittedBatch(player, result)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local startEvent = remotes:FindFirstChild("EggHatchStart")
		if startEvent then
			pcall(function()
				startEvent:FireClient(player, {
					batchId = result.batchId,
					eggType = result.eggType,
					count = result.count,
					totalCost = result.totalCost,
				})
			end)
		end
		local resultEvent = remotes:FindFirstChild("EggHatchResult")
		if resultEvent then
			pcall(function()
				resultEvent:FireClient(player, result)
			end)
		end
	end

	-- The result DTO is serialized before transient discovery flags are removed.
	-- Inventory replication and persistence never receive those presentation flags.
	for _, pet in ipairs(result.pets) do
		pet.isNewDiscovery = nil
	end
	pcall(EggService._petService.replicateInventory, player)
	if EggService._questService then
		pcall(EggService._questService.incrementStat, player, "hatchEggs", result.count)
	end
end

-- options is server-owned. Manual remote calls pass { bypassStation = false };
-- auto-hatch passes true and still pays the full batch price.
purchaseAndHatchUnlocked = function(player, eggType, requestedCount, options)
	if not player or type(eggType) ~= "string" then
		return nil, "Invalid parameters"
	end
	options = type(options) == "table" and options or {
		bypassStation = options == true,
	}
	-- Explicit transaction counts (including manual x3/Max quantities) never
	-- reconcile or mutate the persisted Auto-Hatch preference.
	local count = requestedCount
	if count == nil then
		count = EggService.getSelectedBatchCount(player)
	end
	local validatedCount, countError = validateTransactionCount(player, count)
	if not validatedCount then
		return nil, countError
	end
	if options.bypassStation ~= true and not isNearStation(player, eggType) then
		return nil, "Move closer to this egg station"
	end
	if EggService._shuttingDown then
		return nil, "Hatching is unavailable"
	end

	local inventoryLease = EggService._petService.beginInventoryMutation(player, "EggService")
	if not inventoryLease then
		return nil, "Pet inventory mutation already in progress"
	end
	local userId = player.UserId or player
	local transaction = {
		player = player,
		userId = userId,
		inventoryLease = inventoryLease,
		executing = true,
		eggType = eggType,
		count = validatedCount,
		prepared = nil,
		shinyChargeTransaction = nil,
		shinyBoostCount = 0,
		spent = false,
		totalCost = 0,
		committed = false,
	}
	EggService._activeTransactions[userId] = transaction

	local function performTransaction()
		local eggDef = PetData.Eggs[eggType]
		if not eggDef then
			return nil, "Unknown egg type: " .. tostring(eggType)
		end
		local data = EggService._dataService.getPlayerData(player)
		if not data then
			return nil, "No player data"
		end
		if not isUnlockedZone(data, eggDef.zone) then
			return nil, "Zone not unlocked for this egg type"
		end
		local hasSpace, capacityError = EggService._petService.canAddPets(player, validatedCount)
		if not hasSpace then
			return nil, capacityError
		end
		local eggCost = Config.EggCosts[eggDef.zone]
		local unitCost = eggCost and eggCost.Coins
		if type(unitCost) ~= "number" or unitCost < 0 or unitCost % 1 ~= 0 then
			return nil, "No valid coin cost for egg zone"
		end

		local consumeShinyCharges = options.consumeShinyCharges
		if consumeShinyCharges == nil then
			consumeShinyCharges = options.bypassStation ~= true and options.skipCharge ~= true
		end
		if consumeShinyCharges == true and EggService._potionService then
			transaction.shinyChargeTransaction, transaction.shinyBoostCount =
				EggService._potionService.beginShinyChargeTransaction(player, validatedCount)
		end

		local prepared, prepareError = EggService._petService.prepareHatchBatch(
			player,
			eggType,
			validatedCount,
			{ shinyBoostCount = transaction.shinyBoostCount }
		)
		if not prepared then
			return nil, prepareError
		end
		transaction.prepared = prepared
		runTransactionHook("afterPrepare", transaction)

		transaction.totalCost = options.skipCharge == true and 0 or unitCost * validatedCount
		if transaction.totalCost > 0 then
			local spent = EggService._currencyService.spend(player, "coins", transaction.totalCost)
			if not spent then
				return nil, "Not enough coins for x" .. tostring(validatedCount)
			end
			transaction.spent = true
			runTransactionHook("afterSpend", transaction)
		end

		local committed, commitError = EggService._petService.commitHatchBatch(
			player,
			prepared,
			transaction.inventoryLease
		)
		if not committed then
			return nil, commitError
		end
		runTransactionHook("afterInventory", transaction)
		return {
			batchId = makeBatchId(player),
			eggType = eggType,
			count = validatedCount,
			totalCost = transaction.totalCost,
			pets = prepared.pets,
		}, nil
	end

	local callSucceeded, result, hatchError = pcall(performTransaction)
	local rollbackSucceeded = true
	if not callSucceeded or not result then
		rollbackSucceeded = rollbackTransaction(transaction)
	end

	if callSucceeded and result and transaction.shinyChargeTransaction then
		local commitOk, committed = pcall(
			EggService._potionService.commitShinyChargeTransaction,
			transaction.shinyChargeTransaction
		)
		if commitOk and committed == true then
			transaction.shinyChargeTransaction = nil
		else
			result = nil
			hatchError = "Hatch failed safely"
			rollbackSucceeded = rollbackTransaction(transaction)
		end
	end

	if callSucceeded and result then
		transaction.committed = true
		transaction.prepared = nil
		transaction.spent = false
	end
	transaction.executing = false
	local settled = rollbackSucceeded and settleTransaction(transaction)

	if not rollbackSucceeded or not settled then
		-- Currency/pet commit is final. A post-commit lease-release failure retains
		-- the owner for lifecycle retry but never turns a paid hatch into a retry.
		if transaction.committed and result then
			notifyCommittedBatch(player, result)
			return result, nil
		end
		return nil, "Hatch rollback failed"
	end
	if not callSucceeded then
		return nil, "Hatch failed safely"
	end
	if not result then
		return nil, hatchError
	end

	notifyCommittedBatch(player, result)
	return result, nil
end

function EggService.purchaseAndHatch(player, eggType, requestedCount, options)
	return withHatchLock(player, function()
		return purchaseAndHatchUnlocked(player, eggType, requestedCount, options)
	end)
end

-- Compatibility API for explicitly free server rewards. Auto-hatch does not use
-- this path; it pays the same total price as a manual batch.
function EggService.hatchFree(player, eggType)
	return EggService.purchaseAndHatch(player, eggType, 1, {
		bypassStation = true,
		skipCharge = true,
	})
end

function EggService.cleanup(player)
	if not player then return false end
	local key = player.UserId or player
	local transaction = EggService._activeTransactions[key]
	if transaction then
		return settleTransaction(transaction)
	end
	if EggService._hatchLock[key] ~= nil then
		-- An ownerless hatch lock is never guessed stale.
		return false
	end
	return true
end

function EggService.beginShutdown()
	EggService._shuttingDown = true
end

function EggService.prepareForShutdown()
	EggService.beginShutdown()
	local settled = true
	local transactions = {}
	for _, transaction in pairs(EggService._activeTransactions) do
		table.insert(transactions, transaction)
	end
	for _, transaction in ipairs(transactions) do
		if not settleTransaction(transaction) then settled = false end
	end
	return settled
end

EggService.onPlayerRemoving = EggService.cleanup

function EggService.getAvailableEggs(player)
	if not player then
		return {}
	end
	local data = EggService._dataService.getPlayerData(player)
	if not data then
		return {}
	end
	local available = {}
	for eggType, eggDef in pairs(PetData.Eggs) do
		if isUnlockedZone(data, eggDef.zone) then
			table.insert(available, {
				eggType = eggType,
				name = eggDef.name,
				zone = eggDef.zone,
				cost = Config.EggCosts[eggDef.zone],
			})
		end
	end
	return available
end

return EggService
