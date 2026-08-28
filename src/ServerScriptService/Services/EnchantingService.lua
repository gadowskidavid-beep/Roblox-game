--[[
	EnchantingService.lua - QOF-19 Contract V1 server-authoritative pet enchanting.
	Owns strict request admission, per-player serialization, exact currency
	transactions, weighted rolls, optimistic concurrency, rollback, and state DTOs.
]]

local BalanceConfig = require(game.ReplicatedStorage.Shared.BalanceConfig)
local PetEnchantMath = require(game.ReplicatedStorage.Shared.PetEnchantMath)

local EnchantingService = {}

local CONTRACT_VERSION = 1
local COST_CURRENCY = BalanceConfig.Enchanting.RollCost.currency
local COST_AMOUNT = BalanceConfig.Enchanting.RollCost.amount
local MAX_SLOTS = BalanceConfig.Enchanting.MaxSlotsPerPet

EnchantingService.ReasonCodes = {
	INVALID_REQUEST = "INVALID_REQUEST",
	RUNTIME_DISABLED = "RUNTIME_DISABLED",
	SERVICE_UNAVAILABLE = "SERVICE_UNAVAILABLE",
	PROFILE_UNAVAILABLE = "PROFILE_UNAVAILABLE",
	PET_NOT_FOUND = "PET_NOT_FOUND",
	INVALID_PET_STATE = "INVALID_PET_STATE",
	STALE_STATE = "STALE_STATE",
	INSUFFICIENT_BALANCE = "INSUFFICIENT_BALANCE",
	BUSY = "BUSY",
	RATE_LIMITED = "RATE_LIMITED",
	TECHNICAL_FAILURE = "TECHNICAL_FAILURE",
	ROLLBACK_FAILED = "ROLLBACK_FAILED",
}

EnchantingService._dataService = nil
EnchantingService._currencyService = nil
EnchantingService._petService = nil
EnchantingService._randomSource = math.random
EnchantingService._transactionHook = nil
EnchantingService._playerLocks = {}
EnchantingService._activeTransactions = {}
EnchantingService._revisions = {}
EnchantingService._petIncarnations = {}
EnchantingService._shuttingDown = false

local function isFiniteInteger(value)
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
		and value % 1 == 0
end

local function validPlayer(player)
	return player ~= nil and isFiniteInteger(player.UserId)
end

local function validPetInstanceId(value)
	return type(value) == "string" and value ~= "" and #value <= 128
end

local function exactRequest(request, action, allowedFields, expectedCount)
	if type(request) ~= "table" or getmetatable(request) ~= nil then
		return false
	end
	local count = 0
	for key in pairs(request) do
		if allowedFields[key] ~= true then
			return false
		end
		count = count + 1
	end
	return count == expectedCount
		and rawget(request, "contractVersion") == CONTRACT_VERSION
		and rawget(request, "action") == action
end

local function requestIsGet(request)
	return exactRequest(request, "GET_STATE", {
		contractVersion = true,
		action = true,
		petInstanceId = true,
	}, 3) and validPetInstanceId(rawget(request, "petInstanceId"))
end

local function requestIsRoll(request)
	if not exactRequest(request, "ROLL", {
		contractVersion = true,
		action = true,
		petInstanceId = true,
		expectedStateRevision = true,
		expectedEnchantId = true,
	}, 5) then
		return false
	end
	local expectedEnchantId = rawget(request, "expectedEnchantId")
	return validPetInstanceId(rawget(request, "petInstanceId"))
		and isFiniteInteger(rawget(request, "expectedStateRevision"))
		and rawget(request, "expectedStateRevision") >= 0
		and (expectedEnchantId == false
			or PetEnchantMath.normalizeEnchantId(expectedEnchantId) == expectedEnchantId)
end

local function dependenciesReady()
	return type(EnchantingService._dataService) == "table"
		and type(EnchantingService._dataService.getPlayerData) == "function"
		and type(EnchantingService._currencyService) == "table"
		and type(EnchantingService._currencyService.beginSpendTransaction) == "function"
		and type(EnchantingService._currencyService.commitSpendTransaction) == "function"
		and type(EnchantingService._currencyService.rollbackSpendTransaction) == "function"
		and type(EnchantingService._petService) == "table"
		and type(EnchantingService._petService.replicateInventory) == "function"
		and type(EnchantingService._petService.beginInventoryMutation) == "function"
		and type(EnchantingService._petService.isInventoryMutationCurrent) == "function"
		and type(EnchantingService._petService.endInventoryMutation) == "function"
end

local function currentRevision(userId, petInstanceId, pet)
	local byPet = EnchantingService._revisions[userId]
	local revision = byPet and byPet[petInstanceId] or 0
	if pet then
		local incarnations = EnchantingService._petIncarnations[userId]
		if not incarnations then
			incarnations = {}
			EnchantingService._petIncarnations[userId] = incarnations
		end
		local previousPet = incarnations[petInstanceId]
		if previousPet ~= nil and previousPet ~= pet then
			revision = revision + 1
			byPet = byPet or {}
			EnchantingService._revisions[userId] = byPet
			byPet[petInstanceId] = revision
		end
		incarnations[petInstanceId] = pet
	end
	return revision
end

local function bumpRevision(userId, petInstanceId, pet)
	local byPet = EnchantingService._revisions[userId]
	if not byPet then
		byPet = {}
		EnchantingService._revisions[userId] = byPet
	end
	local revision = (byPet[petInstanceId] or 0) + 1
	byPet[petInstanceId] = revision
	local incarnations = EnchantingService._petIncarnations[userId]
	if not incarnations then
		incarnations = {}
		EnchantingService._petIncarnations[userId] = incarnations
	end
	incarnations[petInstanceId] = pet
	return revision
end

local function findPet(data, petInstanceId)
	if type(data) ~= "table" or type(data.pets) ~= "table" then
		return nil, nil
	end
	for index, pet in ipairs(data.pets) do
		if type(pet) == "table" and pet.id == petInstanceId then
			return pet, index
		end
	end
	return nil, nil
end

local function stateAvailability(player, data, pet, enchantId)
	local reasons = EnchantingService.ReasonCodes
	if BalanceConfig.Enchanting.RuntimeEnabled ~= true then
		return false, reasons.RUNTIME_DISABLED
	end
	if EnchantingService._shuttingDown then
		return false, reasons.SERVICE_UNAVAILABLE
	end
	if not dependenciesReady() then
		return false, reasons.SERVICE_UNAVAILABLE
	end
	if not validPlayer(player) or type(data) ~= "table" or type(data.pets) ~= "table" then
		return false, reasons.PROFILE_UNAVAILABLE
	end
	if not pet then
		return false, reasons.PET_NOT_FOUND
	end
	if rawget(pet, "enchantId") ~= nil and not enchantId then
		return false, reasons.INVALID_PET_STATE
	end
	if type(data[COST_CURRENCY]) ~= "number" or data[COST_CURRENCY] < COST_AMOUNT then
		return false, reasons.INSUFFICIENT_BALANCE
	end
	return true, nil
end

local function buildState(player, petInstanceId)
	local data = dependenciesReady() and EnchantingService._dataService.getPlayerData(player) or nil
	local pet = findPet(data, petInstanceId)
	local enchantId = pet and PetEnchantMath.normalizeEnchantId(rawget(pet, "enchantId")) or nil
	local available, unavailableReason = stateAvailability(player, data, pet, enchantId)
	local userId = validPlayer(player) and player.UserId or nil
	return {
		contractVersion = CONTRACT_VERSION,
		stateRevision = userId and currentRevision(userId, petInstanceId, pet) or 0,
		runtimeEnabled = BalanceConfig.Enchanting.RuntimeEnabled == true
			and not EnchantingService._shuttingDown
			and dependenciesReady(),
		pet = {
			instanceId = pet and pet.id or petInstanceId,
			enchantId = enchantId or false,
		},
		economy = {
			currency = COST_CURRENCY,
			price = COST_AMOUNT,
		},
		maxSlotsPerPet = MAX_SLOTS,
		outcomes = PetEnchantMath.getPublicPool(),
		availability = {
			canRoll = available,
			reason = unavailableReason,
		},
		isReroll = enchantId ~= nil,
	}
end

local function invokeHook(stage, context)
	if type(EnchantingService._transactionHook) == "function" then
		EnchantingService._transactionHook(stage, context)
	end
end

local function chooseEnchantId()
	local roll = EnchantingService._randomSource(1, 100)
	if not isFiniteInteger(roll) or roll < 1 or roll > 100 then
		error("Enchanting RNG returned an invalid integer roll")
	end
	local cumulative = 0
	for _, definition in ipairs(PetEnchantMath.getPublicPool()) do
		cumulative = cumulative + definition.weight
		if roll <= cumulative then
			return definition.id
		end
	end
	error("Enchanting pool did not cover the integer roll")
end

local function petStillMatches(transaction)
	if not EnchantingService._petService.isInventoryMutationCurrent(
		transaction.player,
		transaction.inventoryLease
	) then
		return false
	end
	local data = EnchantingService._dataService.getPlayerData(transaction.player)
	if data ~= transaction.data or data.pets ~= transaction.petsTable
		or data.pets[transaction.petIndex] ~= transaction.pet then
		return false
	end
	if transaction.pet.id ~= transaction.petInstanceId then
		return false
	end
	local present = rawget(transaction.pet, "enchantId") ~= nil
	return present == transaction.oldEnchantPresent
		and rawget(transaction.pet, "enchantId") == transaction.oldEnchantId
		and currentRevision(
			transaction.userId,
			transaction.petInstanceId,
			transaction.pet
		) == transaction.expectedRevision
end

local function restoreTransaction(transaction)
	if transaction.committed then
		return true
	end
	local petRestored = true
	local currencyRestored = true
	if transaction.mutationStarted then
		local ok, restored = pcall(function()
			local currentData = EnchantingService._dataService.getPlayerData(transaction.player)
			if currentData ~= transaction.data or currentData.pets ~= transaction.petsTable
				or currentData.pets[transaction.petIndex] ~= transaction.pet then
				return false
			end
			local currentPresent = rawget(transaction.pet, "enchantId") ~= nil
			local currentEnchantId = rawget(transaction.pet, "enchantId")
			if currentPresent == transaction.oldEnchantPresent
				and currentEnchantId == transaction.oldEnchantId then
				return true
			end
			if currentEnchantId ~= transaction.writtenEnchantId then
				return false
			end
			if transaction.oldEnchantPresent then
				transaction.pet.enchantId = transaction.oldEnchantId
			else
				transaction.pet.enchantId = nil
			end
			return (rawget(transaction.pet, "enchantId") ~= nil) == transaction.oldEnchantPresent
				and rawget(transaction.pet, "enchantId") == transaction.oldEnchantId
		end)
		petRestored = ok and restored == true
		if petRestored then
			transaction.mutationStarted = false
		end
	end
	if transaction.spendTransaction then
		local ok, restored = pcall(
			EnchantingService._currencyService.rollbackSpendTransaction,
			transaction.spendTransaction
		)
		currencyRestored = ok and restored == true
		if currencyRestored then
			transaction.spendTransaction = nil
		end
	end
	return petRestored and currencyRestored
end

local function executeRoll(player, request, transaction)
	local reasons = EnchantingService.ReasonCodes
	local data = EnchantingService._dataService.getPlayerData(player)
	if type(data) ~= "table" or type(data.pets) ~= "table" then
		return false, reasons.PROFILE_UNAVAILABLE
	end
	local pet, petIndex = findPet(data, request.petInstanceId)
	if not pet then
		return false, reasons.PET_NOT_FOUND
	end
	local oldEnchantId = PetEnchantMath.normalizeEnchantId(rawget(pet, "enchantId"))
	local oldEnchantPresent = rawget(pet, "enchantId") ~= nil
	if oldEnchantPresent and not oldEnchantId then
		return false, reasons.INVALID_PET_STATE
	end
	local expectedEnchantId = nil
	if request.expectedEnchantId ~= false then
		expectedEnchantId = request.expectedEnchantId
	end
	local revision = currentRevision(player.UserId, request.petInstanceId, pet)
	if request.expectedStateRevision ~= revision
		or oldEnchantPresent ~= (request.expectedEnchantId ~= false)
		or oldEnchantId ~= expectedEnchantId then
		return false, reasons.STALE_STATE
	end

	transaction.player = player
	transaction.userId = player.UserId
	transaction.data = data
	transaction.petsTable = data.pets
	transaction.pet = pet
	transaction.petIndex = petIndex
	transaction.petInstanceId = request.petInstanceId
	transaction.oldEnchantPresent = oldEnchantPresent
	transaction.oldEnchantId = oldEnchantId
	transaction.expectedRevision = revision

	local spendTransaction = EnchantingService._currencyService.beginSpendTransaction(
		player,
		COST_CURRENCY,
		COST_AMOUNT
	)
	if not spendTransaction then
		return false, reasons.INSUFFICIENT_BALANCE
	end
	transaction.spendTransaction = spendTransaction
	invokeHook("afterSpend", transaction)

	local rolledEnchantId = chooseEnchantId()
	transaction.rolledEnchantId = rolledEnchantId
	invokeHook("afterRoll", transaction)

	if not petStillMatches(transaction) then
		local restored = restoreTransaction(transaction)
		return false, restored and reasons.STALE_STATE or reasons.ROLLBACK_FAILED
	end

	transaction.writtenEnchantId = rolledEnchantId
	transaction.mutationStarted = true
	pet.enchantId = rolledEnchantId
	invokeHook("afterMutation", transaction)
	invokeHook("beforeCommit", transaction)

	local commitOk, committed = pcall(
		EnchantingService._currencyService.commitSpendTransaction,
		spendTransaction
	)
	if not commitOk or committed ~= true then
		local restored = restoreTransaction(transaction)
		return false, restored and reasons.TECHNICAL_FAILURE or reasons.ROLLBACK_FAILED
	end
	transaction.spendTransaction = nil
	transaction.mutationStarted = false
	transaction.committed = true
	-- Currency commit is the point of no return. Everything below is best-effort
	-- bookkeeping/replication and must never turn the paid roll into a retry.
	pcall(bumpRevision, player.UserId, request.petInstanceId, pet)
	pcall(EnchantingService._petService.replicateInventory, player)
	return true, nil
end

function EnchantingService.init(dataService, currencyService, petService)
	EnchantingService._dataService = dataService
	EnchantingService._currencyService = currencyService
	EnchantingService._petService = petService
	EnchantingService._randomSource = math.random
	EnchantingService._transactionHook = nil
	EnchantingService._playerLocks = {}
	EnchantingService._activeTransactions = {}
	EnchantingService._revisions = {}
	EnchantingService._petIncarnations = {}
	EnchantingService._shuttingDown = false
end

function EnchantingService.setRandomSource(randomSource)
	EnchantingService._randomSource = type(randomSource) == "function" and randomSource or math.random
end

function EnchantingService.setTransactionHook(hook)
	EnchantingService._transactionHook = type(hook) == "function" and hook or nil
end

function EnchantingService.getState(player, petInstanceId)
	if not validPetInstanceId(petInstanceId) then
		petInstanceId = ""
	end
	return buildState(player, petInstanceId)
end

function EnchantingService.getStateFromRequest(player, request)
	local petInstanceId = type(request) == "table" and rawget(request, "petInstanceId") or ""
	if not validPlayer(player) or not requestIsGet(request) then
		return false, EnchantingService.ReasonCodes.INVALID_REQUEST, buildState(player, petInstanceId)
	end
	return true, nil, buildState(player, request.petInstanceId)
end

function EnchantingService.roll(player, request)
	local reasons = EnchantingService.ReasonCodes
	local petInstanceId = type(request) == "table" and rawget(request, "petInstanceId") or ""
	if not validPlayer(player) or not requestIsRoll(request) then
		return false, reasons.INVALID_REQUEST, buildState(player, petInstanceId)
	end
	if BalanceConfig.Enchanting.RuntimeEnabled ~= true then
		return false, reasons.RUNTIME_DISABLED, buildState(player, petInstanceId)
	end
	if EnchantingService._shuttingDown then
		return false, reasons.SERVICE_UNAVAILABLE, buildState(player, petInstanceId)
	end
	if not dependenciesReady() then
		return false, reasons.SERVICE_UNAVAILABLE, buildState(player, petInstanceId)
	end
	if EnchantingService._playerLocks[player.UserId] then
		return false, reasons.BUSY, buildState(player, petInstanceId)
	end

	local inventoryLease = EnchantingService._petService.beginInventoryMutation(
		player,
		"EnchantingService"
	)
	if not inventoryLease then
		return false, reasons.BUSY, buildState(player, petInstanceId)
	end

	EnchantingService._playerLocks[player.UserId] = true
	local transaction = {
		player = player,
		userId = player.UserId,
		inventoryLease = inventoryLease,
		executing = true,
	}
	EnchantingService._activeTransactions[player.UserId] = transaction
	local ok, success, reason = xpcall(function()
		return executeRoll(player, request, transaction)
	end, debug.traceback)
	if not ok then
		local restored = restoreTransaction(transaction)
		success = false
		reason = restored and reasons.TECHNICAL_FAILURE or reasons.ROLLBACK_FAILED
	end
	transaction.executing = false

	local unresolved = transaction.mutationStarted == true
		or transaction.spendTransaction ~= nil
	if not unresolved then
		-- Exact lease identity makes stale-finally release impossible. A committed
		-- roll advances the central in-memory inventory incarnation. Lease cleanup
		-- itself is post-commit: if it fails, retain a settleable committed record
		-- while still returning the successful paid result.
		local releaseOk, released = pcall(
			EnchantingService._petService.endInventoryMutation,
			player,
			inventoryLease,
			transaction.committed == true
		)
		if releaseOk and released == true then
			EnchantingService._activeTransactions[player.UserId] = nil
			EnchantingService._playerLocks[player.UserId] = nil
		end
	end
	local stateOk, state = pcall(buildState, player, petInstanceId)
	if not stateOk then
		-- State refresh is post-commit presentation. In particular, a successful
		-- currency commit must remain an unambiguous success even if profile lookup
		-- or DTO construction fails afterwards.
		return success, reason, nil
	end
	return success, reason, state
end

function EnchantingService.cleanup(player)
	if not validPlayer(player) then
		return false
	end
	local userId = player.UserId
	local transaction = EnchantingService._activeTransactions[userId]
	if transaction then
		if transaction.executing then
			return false
		end
		if not restoreTransaction(transaction) then
			return false
		end
		local releaseOk, released = pcall(
			EnchantingService._petService.endInventoryMutation,
			player,
			transaction.inventoryLease,
			transaction.committed == true
		)
		if not releaseOk or released ~= true then
			return false
		end
		EnchantingService._activeTransactions[userId] = nil
	elseif EnchantingService._playerLocks[userId] ~= nil then
		-- Never guess that a lock is stale: clearing an ownerless lock can create
		-- an ABA release while work is still in flight.
		return false
	end
	EnchantingService._playerLocks[userId] = nil
	EnchantingService._revisions[userId] = nil
	EnchantingService._petIncarnations[userId] = nil
	return true
end

function EnchantingService.beginShutdown()
	EnchantingService._shuttingDown = true
end

function EnchantingService.prepareForShutdown()
	EnchantingService.beginShutdown()
	local transactions = {}
	for _, transaction in pairs(EnchantingService._activeTransactions) do
		table.insert(transactions, transaction)
	end
	local settled = true
	for _, transaction in ipairs(transactions) do
		if transaction.executing or not EnchantingService.cleanup(transaction.player) then
			settled = false
		end
	end
	return settled
end

EnchantingService.onPlayerRemoving = EnchantingService.cleanup

return EnchantingService
