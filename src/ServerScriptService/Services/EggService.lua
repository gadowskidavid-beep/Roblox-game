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
EggService._hatchLock = {}
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

local function isValidBatchCount(value)
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
		and value % 1 == 0
		and VALID_BATCH_COUNTS[value] == true
end

function EggService.init(dataService, currencyService, petService, upgradeTreeService)
	EggService._dataService = dataService
	EggService._currencyService = currencyService
	EggService._petService = petService
	EggService._upgradeTreeService = upgradeTreeService
end

function EggService.setQuestService(questService)
	EggService._questService = questService
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

	local selected = data.hatchPreferences.preferredBatchCount
	if not isValidBatchCount(selected) then
		selected = 1
	elseif selected > maximum then
		selected = highestAllowedBatchCount(maximum)
	end
	data.hatchPreferences.preferredBatchCount = selected
	return selected
end

local function validateRequestedCount(player, requestedCount, maximum)
	if not isValidBatchCount(requestedCount) then
		return nil, "Invalid hatch count"
	end
	maximum = maximum or getMaximumBatchCount(player)
	if requestedCount > maximum then
		return nil, "Multi-Open upgrade required"
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
	local count, countError = validateRequestedCount(player, requestedCount, maximum)
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

local function defaultStationValidator(player, eggType)
	local character = player and player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return false
	end
	local workspaceService = game:GetService("Workspace")
	local stations = workspaceService:FindFirstChild("EggStations")
	if not stations then
		return false
	end
	for _, station in ipairs(stations:GetChildren()) do
		if station:IsA("BasePart") and station.Name == "EggModel" then
			local tag = station:FindFirstChild("PromptEggType")
			local prompt = station:FindFirstChild("HatchPrompt")
			if tag and tag:IsA("StringValue") and tag.Value == eggType
				and prompt and prompt:IsA("ProximityPrompt") then
				local allowedDistance = math.max(1, prompt.MaxActivationDistance) + 2
				if (station.Position - rootPart.Position).Magnitude <= allowedDistance then
					return true
				end
			end
		end
	end
	return false
end

local function isNearStation(player, eggType)
	if type(EggService._stationValidator) == "function" then
		return EggService._stationValidator(player, eggType) == true
	end
	return defaultStationValidator(player, eggType)
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
	local inventoryRestored = true
	if transaction.prepared and transaction.prepared.mutationStarted then
		inventoryRestored = EggService._petService.rollbackHatchBatch(transaction.prepared) == true
	end
	local currencyRestored = true
	if transaction.spent and transaction.totalCost > 0 then
		currencyRestored = EggService._currencyService.creditRaw(
			transaction.player,
			"coins",
			transaction.totalCost
		) == true
		transaction.spent = false
	end
	return inventoryRestored and currencyRestored
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
function EggService.purchaseAndHatch(player, eggType, requestedCount, options)
	if not player or type(eggType) ~= "string" then
		return nil, "Invalid parameters"
	end
	options = type(options) == "table" and options or {
		bypassStation = options == true,
	}
	local preferredCount = EggService.getSelectedBatchCount(player)
	local count = requestedCount == nil and preferredCount or requestedCount
	local validatedCount, countError = validateRequestedCount(player, count)
	if not validatedCount then
		return nil, countError
	end
	if options.bypassStation ~= true and not isNearStation(player, eggType) then
		return nil, "Move closer to this egg station"
	end

	local lockKey = player.UserId or player
	if EggService._hatchLock[lockKey] then
		return nil, "Already hatching eggs"
	end
	EggService._hatchLock[lockKey] = true

	local transaction = {
		player = player,
		eggType = eggType,
		count = validatedCount,
		prepared = nil,
		spent = false,
		totalCost = 0,
	}

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

		local prepared, prepareError = EggService._petService.prepareHatchBatch(
			player,
			eggType,
			validatedCount
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

		local committed, commitError = EggService._petService.commitHatchBatch(player, prepared)
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
	EggService._hatchLock[lockKey] = nil

	if not rollbackSucceeded then
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

-- Compatibility API for explicitly free server rewards. Auto-hatch does not use
-- this path; it pays the same total price as a manual batch.
function EggService.hatchFree(player, eggType)
	return EggService.purchaseAndHatch(player, eggType, 1, {
		bypassStation = true,
		skipCharge = true,
	})
end

function EggService.onPlayerRemoving(player)
	if not player then return end
	local key = player.UserId or player
	EggService._hatchLock[key] = nil
end

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
