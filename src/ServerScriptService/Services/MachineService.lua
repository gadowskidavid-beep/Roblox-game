--[[
	MachineService.lua - Dormant QOF-15 machine transaction foundation.
	Owns validated Gold/Rainbow payment, pet consumption, chance rolls, rollback,
	and post-commit quest semantics. Public activation remains fail-closed until a
	future QOF injects an authoritative world/proximity validator and enables the
	BalanceConfig runtime gate.
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
end

function MachineService.setQuestService(questService)
	MachineService._questService = questService
end

-- A future world-owning service must inject a validator that checks the exact
-- runtime station and player proximity. Nil/non-function always means denied.
function MachineService.setActivationValidator(validator)
	MachineService._activationValidator = type(validator) == "function" and validator or nil
end

function MachineService.setRandomSource(randomSource)
	MachineService._randomSource = type(randomSource) == "function" and randomSource or math.random
end

function MachineService.setTransactionHook(hook)
	MachineService._transactionHook = type(hook) == "function" and hook or nil
end

local function rollbackTechnicalFailure(prepared, spendTransaction)
	local petRolledBack = true
	local currencyRolledBack = true
	if prepared and prepared.mutationStarted then
		local callSucceeded, rollbackSucceeded = pcall(
			MachineService._petService.rollbackVariantConversion,
			prepared
		)
		petRolledBack = callSucceeded and rollbackSucceeded == true
	end
	if spendTransaction then
		local callSucceeded, rollbackSucceeded = pcall(
			MachineService._currencyService.rollbackSpendTransaction,
			spendTransaction
		)
		currencyRolledBack = callSucceeded and rollbackSucceeded == true
	end
	return petRolledBack and currencyRolledBack
end

local function executeTransaction(player, machine, machineType, petInstanceIds, transactionState)
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
	-- The callback receives a disposable facts DTO, never the canonical balance
	-- definition or the private transaction snapshot consumed below.
	local activationFacts = {
		machineId = machine.id,
		zoneId = machine.zoneId,
	}
	local activationOk, activationAllowed, activationError = pcall(
		MachineService._activationValidator,
		player,
		machine.id,
		activationFacts
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
		machine.cost.amount
	)
	if not spendTransaction then
		return nil, "Not enough diamonds"
	end
	transactionState.spendTransaction = spendTransaction

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
		success
	)
	if not committed then
		local restored = rollbackTechnicalFailure(prepared, spendTransaction)
		transactionState.prepared = nil
		transactionState.spendTransaction = nil
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
		local restored = rollbackTechnicalFailure(prepared, spendTransaction)
		transactionState.prepared = nil
		transactionState.spendTransaction = nil
		return nil, restored and "Conversion failed safely" or "Conversion rollback failed"
	end
	spendTransaction = nil
	transactionState.spendTransaction = nil
	transactionState.prepared = nil
	prepared.transactionCommitted = true

	-- Notifications are deliberately post-commit and protected. A transport or
	-- quest event failure must never turn a completed economic transaction into a
	-- retryable failure or attempt an impossible partial rollback.
	pcall(MachineService._petService.replicateInventory, player)
	if success and machineType == "Gold" and MachineService._questService then
		pcall(MachineService._questService.incrementStat, player, "goldenPetsConverted", 1)
	end
	return result
end

function MachineService.attemptConversion(player, machineId, petInstanceIds)
	if BalanceConfig.Machines.RuntimeEnabled ~= true then
		return nil, "Machines are not available"
	end
	if not player or not isFiniteNumber(player.UserId) or player.UserId % 1 ~= 0 then
		return nil, "Invalid player"
	end
	local machine, machineType = resolveMachine(machineId)
	if not machine then
		return nil, "Unknown machine"
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
		or not MachineService._petService then
		return nil, "Machine service unavailable"
	end
	if MachineService._playerLocks[player.UserId] then
		return nil, "Machine conversion already in progress"
	end

	MachineService._playerLocks[player.UserId] = true
	local transactionState = {}
	local ok, result, transactionError = xpcall(function()
		return executeTransaction(player, machine, machineType, ids, transactionState)
	end, debug.traceback)
	MachineService._playerLocks[player.UserId] = nil

	if not ok then
		local restored = rollbackTechnicalFailure(
			transactionState.prepared,
			transactionState.spendTransaction
		)
		return nil, restored and "Conversion failed safely" or "Conversion rollback failed"
	end
	return result, transactionError
end

function MachineService.cleanup(player)
	if player and isFiniteNumber(player.UserId) then
		MachineService._playerLocks[player.UserId] = nil
	end
end

MachineService.onPlayerRemoving = MachineService.cleanup

return MachineService
