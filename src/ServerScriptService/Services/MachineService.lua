--[[
	MachineService.lua - QOF-17 server-authoritative machine transactions.
	Owns shared Gold/Rainbow payment, pet consumption, chance rolls, rollback,
	and Gold-only post-commit quest semantics. Both machine definitions use this
	same transaction path; machine-specific economics remain server-owned.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BalanceConfig = require(ReplicatedStorage.Shared.BalanceConfig)

local MachineService = {}

MachineService._dataService = nil
MachineService._currencyService = nil
MachineService._petService = nil
MachineService._questService = nil
MachineService._activationValidator = nil
MachineService._randomSource = math.random
MachineService._transactionHook = nil
MachineService._playerLocks = {}
MachineService._activeTransactions = {}
MachineService._shuttingDown = false

local function isFiniteNumber(value)
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
end

local function resolveMachine(machineId)
	if type(machineId) ~= "string" then
		return nil
	end
	for machineType, definition in pairs(BalanceConfig.Machines) do
		if type(definition) == "table" and definition.id == machineId
			and type(definition.cost) == "table" then
			-- Never retain or expose the mutable canonical balance table. The
			-- transaction consumes only this scalar snapshot.
			return {
				RuntimeEnabled = definition.RuntimeEnabled == true,
				id = definition.id,
				zoneId = definition.zoneId,
				inputVariant = definition.inputVariant,
				outputVariant = definition.outputVariant,
				cost = {
					currency = definition.cost.currency,
					amount = definition.cost.amount,
				},
			}, machineType
		end
	end
	return nil
end

local function validateDenseUniqueIds(petInstanceIds)
	if type(petInstanceIds) ~= "table" then
		return nil, "Invalid pet IDs"
	end
	-- This check must precede pairs, #, and indexing so hostile metamethods can
	-- never execute outside the protected transaction boundary.
	if getmetatable(petInstanceIds) ~= nil then
		return nil, "Pet IDs must be a plain dense list"
	end

	local count = 0
	for key in next, petInstanceIds do
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 then
			return nil, "Pet IDs must be a dense list"
		end
		count = count + 1
	end
	if count < BalanceConfig.Machines.MinInputs or count > BalanceConfig.Machines.MaxInputs then
		return nil, "Must provide between 1 and 7 pets"
	end
	if rawlen(petInstanceIds) ~= count then
		return nil, "Pet IDs must be a dense list"
	end

	local seen = {}
	local copy = {}
	for index = 1, count do
		local petId = rawget(petInstanceIds, index)
		if type(petId) ~= "string" or petId == "" or #petId > 128 then
			return nil, "Invalid pet ID in list"
		end
		if seen[petId] then
			return nil, "Duplicate pet ID in list"
		end
		seen[petId] = true
		copy[index] = petId
	end
	return copy
end

local function hasUnlockedZone(data, zoneId)
	if type(data) ~= "table" or type(data.unlockedZones) ~= "table" then
		return false
	end
	for _, unlockedZoneId in ipairs(data.unlockedZones) do
		if unlockedZoneId == zoneId then
			return true
		end
	end
	return false
end

local function safeHook(stage, context)
	if MachineService._transactionHook then
		MachineService._transactionHook(stage, context)
	end
end

function MachineService.init(dataService, currencyService, petService)
	MachineService._dataService = dataService
	MachineService._currencyService = currencyService
	MachineService._petService = petService
	MachineService._questService = nil
	MachineService._activationValidator = nil
	MachineService._randomSource = math.random
	MachineService._transactionHook = nil
	MachineService._playerLocks = {}
	MachineService._activeTransactions = {}
	MachineService._shuttingDown = false
end

function MachineService.setQuestService(questService)
	MachineService._questService = questService
end

-- The world-owning service injects a validator over its private station
-- registry. Nil/non-function always means denied.
function MachineService.setActivationValidator(validator)
	MachineService._activationValidator = type(validator) == "function" and validator or nil
end

function MachineService.setRandomSource(randomSource)
	MachineService._randomSource = type(randomSource) == "function" and randomSource or math.random
end

function MachineService.setTransactionHook(hook)
	MachineService._transactionHook = type(hook) == "function" and hook or nil
end

local function restoreTransaction(transactionState)
	if transactionState.committed then
		return true
	end
	local prepared = transactionState.prepared
	if prepared then
		if prepared.mutationStarted then
			local callSucceeded, rollbackSucceeded = pcall(
				MachineService._petService.rollbackVariantConversion,
				prepared,
				transactionState.inventoryLease
			)
			if not callSucceeded or rollbackSucceeded ~= true then
				return false
			end
		end
		transactionState.prepared = nil
	end
	if transactionState.spendTransaction then
		local callSucceeded, rollbackSucceeded = pcall(
			MachineService._currencyService.rollbackSpendTransaction,
			transactionState.spendTransaction
		)
		if not callSucceeded or rollbackSucceeded ~= true then
			return false
		end
		transactionState.spendTransaction = nil
	end
	return true
end

local function executeTransaction(player, machine, machineType, activationToken, petInstanceIds, transactionState)
	local data = MachineService._dataService and MachineService._dataService.getPlayerData(player)
	if type(data) ~= "table" then
		return nil, "No player data"
	end
	if not hasUnlockedZone(data, machine.zoneId) then
		return nil, "Machine zone is locked"
	end

	local inputCount = #petInstanceIds
	local chance = BalanceConfig.Machines.SuccessChanceByInput[inputCount]
	if not isFiniteNumber(chance) or chance < 0 or chance > 1 then
		return nil, "Machine configuration unavailable"
	end
	-- The validator receives only scalar request identity. Station instances,
	-- ancestry, prompt integrity, profile unlocks, and distance remain private to
	-- ZoneService's registry and cannot be supplied or rewritten by the caller.
	local activationOk, activationAllowed, activationError = pcall(
		MachineService._activationValidator,
		player,
		machine.id,
		activationToken
	)
	if not activationOk or activationAllowed ~= true then
		return nil, activationOk and (activationError or "Machine activation denied") or "Machine activation denied"
	end

	local prepared, prepareError = MachineService._petService.prepareVariantConversion(
		player,
		petInstanceIds,
		machine.inputVariant,
		machine.outputVariant
	)
	if not prepared then
		return nil, prepareError
	end
	transactionState.prepared = prepared

	local spendTransaction = MachineService._currencyService.beginSpendTransaction(
		player,
		machine.cost.currency,
		machine.cost.amount,
		"MachineService"
	)
	if not spendTransaction then
		return nil, "Not enough diamonds"
	end
	transactionState.spendTransaction = spendTransaction
	local settlerRegistered = MachineService._currencyService.setSpendSettler(
		spendTransaction,
		function(currentSpendTransaction)
			if transactionState.executing
				or currentSpendTransaction ~= transactionState.spendTransaction then
				return false
			end
			return restoreTransaction(transactionState)
		end
	)
	if settlerRegistered ~= true then
		error("Unable to register machine spend settler")
	end

	local context = {
		player = player,
		machineId = machine.id,
		inputCount = inputCount,
		prepared = prepared,
	}
	safeHook("afterSpend", context)

	local roll = MachineService._randomSource()
	if not isFiniteNumber(roll) or roll < 0 or roll > 1 then
		error("Machine RNG returned an invalid roll")
	end
	local success = roll <= chance

	local committed, commitError = MachineService._petService.commitVariantConversion(
		player,
		prepared,
		success,
		transactionState.inventoryLease
	)
	if not committed then
		local restored = restoreTransaction(transactionState)
		if not restored then
			return nil, "Conversion rollback failed"
		end
		return nil, commitError or "Conversion failed safely"
	end
	safeHook("afterPetMutation", context)

	local result = {
		success = success,
		machineId = machine.id,
		chance = chance,
		cost = machine.cost.amount,
		currency = machine.cost.currency,
		outputPet = success and prepared.outputPet or nil,
		isNewDiscovery = success and prepared.isNewDiscovery or false,
	}
	safeHook("beforeCommit", context)

	if MachineService._currencyService.commitSpendTransaction(spendTransaction) ~= true then
		local restored = restoreTransaction(transactionState)
		return nil, restored and "Conversion failed safely" or "Conversion rollback failed"
	end
	spendTransaction = nil
	transactionState.spendTransaction = nil
	prepared.transactionCommitted = true
	transactionState.prepared = nil
	transactionState.committed = true

	-- Notifications are deliberately post-commit and protected. A transport or
	-- quest event failure must never turn a completed economic transaction into a
	-- retryable failure or attempt an impossible partial rollback.
	pcall(MachineService._petService.replicateInventory, player)
	if success and machineType == "Gold" and MachineService._questService then
		pcall(MachineService._questService.incrementStat, player, "goldenPetsConverted", 1)
	end
	return result
end

function MachineService.attemptConversion(player, machineId, activationToken, petInstanceIds)
	if BalanceConfig.Machines.RuntimeEnabled ~= true then
		return nil, "Machines are not available"
	end
	if MachineService._shuttingDown then
		return nil, "Machines are not available"
	end
	if not player or not isFiniteNumber(player.UserId) or player.UserId % 1 ~= 0 then
		return nil, "Invalid player"
	end
	local machine, machineType = resolveMachine(machineId)
	if not machine then
		return nil, "Unknown machine"
	end
	-- Per-definition dormancy is checked before token/list validation, profile
	-- access, world validation, pet preparation, RNG, or currency work.
	if machine.RuntimeEnabled ~= true then
		return nil, "Machine is not available"
	end
	if type(activationToken) ~= "string" or activationToken == "" or #activationToken > 128 then
		return nil, "Invalid machine activation"
	end
	local ids, idsError = validateDenseUniqueIds(petInstanceIds)
	if not ids then
		return nil, idsError
	end
	if type(MachineService._activationValidator) ~= "function" then
		return nil, "Machine activation unavailable"
	end
	if not MachineService._dataService
		or not MachineService._currencyService
		or not MachineService._petService
		or type(MachineService._currencyService.beginSpendTransaction) ~= "function"
		or type(MachineService._currencyService.setSpendSettler) ~= "function"
		or type(MachineService._currencyService.commitSpendTransaction) ~= "function"
		or type(MachineService._currencyService.rollbackSpendTransaction) ~= "function"
		or type(MachineService._petService.beginInventoryMutation) ~= "function"
		or type(MachineService._petService.endInventoryMutation) ~= "function" then
		return nil, "Machine service unavailable"
	end
	if MachineService._playerLocks[player.UserId] then
		return nil, "Machine conversion already in progress"
	end

	local inventoryLease = MachineService._petService.beginInventoryMutation(player, "MachineService")
	if not inventoryLease then
		return nil, "Pet inventory mutation already in progress"
	end
	MachineService._playerLocks[player.UserId] = true
	local transactionState = {
		player = player,
		inventoryLease = inventoryLease,
		executing = true,
	}
	MachineService._activeTransactions[player.UserId] = transactionState
	local ok, result, transactionError = xpcall(function()
		return executeTransaction(player, machine, machineType, activationToken, ids, transactionState)
	end, debug.traceback)
	if not ok then
		local restored = restoreTransaction(transactionState)
		result = nil
		transactionError = restored and "Conversion failed safely" or "Conversion rollback failed"
	end
	transactionState.executing = false

	local unresolved = transactionState.prepared ~= nil
		or transactionState.spendTransaction ~= nil
	if not unresolved then
		-- Lease release is post-commit bookkeeping. It must never turn an already
		-- committed currency/pet conversion into a retryable client error. Keep a
		-- terminal record if release itself fails so lifecycle cleanup can retry it.
		local releaseOk, released = pcall(
			MachineService._petService.endInventoryMutation,
			player,
			inventoryLease,
			transactionState.committed == true
		)
		if releaseOk and released == true then
			MachineService._activeTransactions[player.UserId] = nil
			MachineService._playerLocks[player.UserId] = nil
		end
	end
	return result, transactionError
end

function MachineService.cleanup(player)
	if not player or not isFiniteNumber(player.UserId) or player.UserId % 1 ~= 0 then
		return false
	end
	local userId = player.UserId
	local transactionState = MachineService._activeTransactions[userId]
	if transactionState then
		if transactionState.executing then
			return false
		end
		if not restoreTransaction(transactionState) then
			return false
		end
		local releaseOk, released = pcall(
			MachineService._petService.endInventoryMutation,
			player,
			transactionState.inventoryLease,
			transactionState.committed == true
		)
		if not releaseOk or released ~= true then
			return false
		end
		MachineService._activeTransactions[userId] = nil
	elseif MachineService._playerLocks[userId] ~= nil then
		return false
	end
	MachineService._playerLocks[userId] = nil
	return true
end

function MachineService.beginShutdown()
	MachineService._shuttingDown = true
end

function MachineService.prepareForShutdown()
	MachineService.beginShutdown()
	local transactions = {}
	for _, transactionState in pairs(MachineService._activeTransactions) do
		table.insert(transactions, transactionState)
	end
	local settled = true
	for _, transactionState in ipairs(transactions) do
		if transactionState.executing or not MachineService.cleanup(transactionState.player) then
			settled = false
		end
	end
	return settled
end

MachineService.onPlayerRemoving = MachineService.cleanup

return MachineService
