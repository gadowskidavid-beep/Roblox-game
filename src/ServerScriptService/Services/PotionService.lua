--[[
	PotionService.lua - QOF-26 authoritative Potion state and concurrency owner.
	Every Potion mutation shares one exact-identity per-player lease. Shiny hatch
	reservations retain that lease through commit/rollback so no drink, Auto-Drink,
	upgrade, Shop inventory addition, reconciliation, or selection can interleave.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BalanceConfig = require(game.ReplicatedStorage.Shared.BalanceConfig)

local PotionService = {}

local CONTRACT_VERSION = 1
local CATALOG_ORDER = {
	"LuckPotion",
	"MegaLuckPotion",
	"SpeedPotion",
	"CoinPotion",
	"ShinyPotion",
}
local MAX_INVENTORY = BalanceConfig.Potions.Persistence.MaxInventoryPerPotion
local MAX_TIMED_SECONDS = BalanceConfig.Potions.Persistence.MaxTimedBuffSeconds
local MAX_SHINY_CHARGES = BalanceConfig.Potions.Upgrades.MaxShinyCharges
local RECONCILE_INTERVAL = 1

PotionService._dataService = nil
PotionService._currencyService = nil
PotionService._profileTransactionService = nil
PotionService._movementRefresh = nil
PotionService._potionLeases = {}
PotionService._leaseGenerations = {}
PotionService._stateRevisions = {}
PotionService._pendingShinyCharges = {}
PotionService._activeTransactions = {}
PotionService._transactionHook = nil
PotionService._running = false
PotionService._shuttingDown = false

local function isFiniteNumber(value)
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
end

local function deepCopy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, child in pairs(value) do
		result[deepCopy(key)] = deepCopy(child)
	end
	return result
end

local function exactRequest(request, fields)
	if type(request) ~= "table" or getmetatable(request) ~= nil then return false end
	local count = 0
	for key in pairs(request) do
		if not fields[key] then return false end
		count = count + 1
	end
	local expected = 0
	for _ in pairs(fields) do expected = expected + 1 end
	return count == expected
end

local function validIdentifier(value)
	return type(value) == "string" and #value > 0 and #value <= 64
end

local function getData(player)
	if not player or not PotionService._dataService then return nil end
	return PotionService._dataService.getPlayerData(player)
end

local function userKey(player)
	return player and player.UserId
end

local function currentRevision(player)
	local key = userKey(player)
	return key and PotionService._stateRevisions[key] or 0
end

local function bumpRevision(player)
	local key = userKey(player)
	if not key then return 0 end
	local revision = (PotionService._stateRevisions[key] or 0) + 1
	PotionService._stateRevisions[key] = revision
	return revision
end

local function sourceExpiresAt(source)
	if type(source) ~= "table" or not isFiniteNumber(source.expiresAt) then return nil end
	return math.floor(source.expiresAt)
end

local function timedTypeIsActive(state, now)
	if type(state) ~= "table" or type(state.sources) ~= "table" then return false end
	for _, source in pairs(state.sources) do
		local expiresAt = sourceExpiresAt(source)
		if expiresAt and expiresAt > now then return true end
	end
	return false
end

local function buffTypeIsActive(buffType, state, now)
	if buffType == "shinyChance" then
		return type(state) == "table"
			and isFiniteNumber(state.charges)
			and math.floor(state.charges) > 0
	end
	return timedTypeIsActive(state, now)
end

local function countActiveTypes(activeBuffs, now)
	local count = 0
	if type(activeBuffs) == "table" then
		for buffType, state in pairs(activeBuffs) do
			if buffTypeIsActive(buffType, state, now) then count = count + 1 end
		end
	end
	return count
end

local function cleanupExpired(data, now)
	if type(data.activeBuffs) ~= "table" then
		data.activeBuffs = {}
		return true, false
	end
	local changed = false
	local speedChanged = false
	for buffType, state in pairs(data.activeBuffs) do
		if buffType == "shinyChance" then
			local charges = type(state) == "table" and state.charges or nil
			if not isFiniteNumber(charges) or charges % 1 ~= 0 or charges <= 0
				or charges > MAX_SHINY_CHARGES then
				data.activeBuffs[buffType] = nil
				changed = true
			end
		elseif type(state) ~= "table" or type(state.sources) ~= "table" then
			data.activeBuffs[buffType] = nil
			changed = true
			if buffType == "speed" then speedChanged = true end
		else
			for sourceId, source in pairs(state.sources) do
				local potion = BalanceConfig.Potions.Catalog[sourceId]
				local expiresAt = sourceExpiresAt(source)
				if not potion or potion.buffType ~= buffType or not potion.durationSeconds
					or not expiresAt or expiresAt <= now then
					state.sources[sourceId] = nil
					changed = true
					if buffType == "speed" then speedChanged = true end
				end
			end
			if next(state.sources) == nil then data.activeBuffs[buffType] = nil end
		end
	end
	return changed, speedChanged
end

local function durationMultiplier(data)
	local upgrades = type(data.potionUpgrades) == "table" and data.potionUpgrades or {}
	local level = isFiniteNumber(upgrades.durationLevel) and math.floor(upgrades.durationLevel) or 0
	local definition = BalanceConfig.Potions.Upgrades.Duration[level]
	return definition and definition.multiplier or 1
end

local function maxSlots(data)
	local upgrades = type(data.potionUpgrades) == "table" and data.potionUpgrades or {}
	local slots = isFiniteNumber(upgrades.slots) and math.floor(upgrades.slots)
		or BalanceConfig.Potions.Upgrades.BaseSlots
	return math.clamp(slots, BalanceConfig.Potions.Upgrades.BaseSlots,
		BalanceConfig.Potions.Upgrades.MaxSlots)
end

local function resolveConsumeAvailability(data, potionId, now)
	local potion = BalanceConfig.Potions.Catalog[potionId]
	if not potion then return false, "Unknown potion" end
	local count = type(data.potionInventory) == "table" and data.potionInventory[potionId] or nil
	if not isFiniteNumber(count) or count < 1 or count % 1 ~= 0 or count > MAX_INVENTORY then
		return false, "No potion available"
	end
	local activeBuffs = type(data.activeBuffs) == "table" and data.activeBuffs or {}
	local typeState = activeBuffs[potion.buffType]
	local existingTypeActive = buffTypeIsActive(potion.buffType, typeState, now)
	if potion.durationSeconds then
		local source = type(typeState) == "table" and type(typeState.sources) == "table"
			and typeState.sources[potionId] or nil
		local oldExpiry = sourceExpiresAt(source)
		if oldExpiry and oldExpiry >= now + MAX_TIMED_SECONDS then
			return false, "Maximum timed duration reached (30 days)"
		end
	else
		local currentCharges = type(typeState) == "table" and typeState.charges or 0
		if not isFiniteNumber(currentCharges) or currentCharges < 0 or currentCharges % 1 ~= 0 then
			return false, "Invalid Shiny charge state"
		end
		-- Never consume a Potion if its complete charge grant does not fit. Clamping
		-- would silently destroy paid charges at 28/29/30.
		if currentCharges + potion.hatchCharges > MAX_SHINY_CHARGES then
			return false, "Maximum Shiny charges reached (" .. tostring(MAX_SHINY_CHARGES) .. ")"
		end
	end
	if not existingTypeActive and countActiveTypes(activeBuffs, now) >= maxSlots(data) then
		return false, "No active potion slots available"
	end
	return true, nil
end

local function upgradeOffers(data)
	local upgrades = type(data.potionUpgrades) == "table" and data.potionUpgrades or {
		slots = BalanceConfig.Potions.Upgrades.BaseSlots,
		durationLevel = 0,
		autoDrink = false,
	}
	local slots = isFiniteNumber(upgrades.slots) and math.floor(upgrades.slots)
		or BalanceConfig.Potions.Upgrades.BaseSlots
	local durationLevel = isFiniteNumber(upgrades.durationLevel)
		and math.floor(upgrades.durationLevel) or 0
	local slotOffer = nil
	for _, level in ipairs(BalanceConfig.Potions.Upgrades.PotionSlots) do
		if level.slots == slots + 1 then
			slotOffer = { target = level.slots, cost = deepCopy(level.cost) }
			break
		end
	end
	local durationDef = BalanceConfig.Potions.Upgrades.Duration[durationLevel + 1]
	local autoDrinkOffer = nil
	if upgrades.autoDrink ~= true then
		autoDrinkOffer = { target = true, cost = deepCopy(BalanceConfig.Potions.Upgrades.AutoDrink.cost) }
	end
	return {
		PotionSlot = slotOffer,
		Duration = durationDef and {
			target = durationLevel + 1,
			multiplier = durationDef.multiplier,
			cost = deepCopy(durationDef.cost),
		} or nil,
		AutoDrink = autoDrinkOffer,
	}
end

local function buildActiveBuffDto(data, now)
	local result = {}
	for buffType, state in pairs(type(data.activeBuffs) == "table" and data.activeBuffs or {}) do
		if buffType == "shinyChance" and buffTypeIsActive(buffType, state, now) then
			result[buffType] = {
				charges = math.floor(state.charges),
				multiplier = BalanceConfig.Potions.Catalog.ShinyPotion.multiplier,
			}
		elseif timedTypeIsActive(state, now) then
			local sources = {}
			local effectiveMultiplier = 1
			for sourceId, source in pairs(state.sources) do
				local expiresAt = sourceExpiresAt(source)
				local potion = BalanceConfig.Potions.Catalog[sourceId]
				if expiresAt and expiresAt > now and potion and potion.buffType == buffType then
					sources[sourceId] = { expiresAt = expiresAt, multiplier = potion.multiplier }
					effectiveMultiplier = math.max(effectiveMultiplier, potion.multiplier)
				end
			end
			result[buffType] = { sources = sources, effectiveMultiplier = effectiveMultiplier }
		end
	end
	return result
end

local function fireState(player, state)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local event = remotes and remotes:FindFirstChild("PotionStateUpdated")
	if event then
		pcall(function() event:FireClient(player, deepCopy(state)) end)
	end
end

local function invokeHook(stage, context)
	if type(PotionService._transactionHook) == "function" then
		PotionService._transactionHook(stage, context)
	end
end

function PotionService.init(dataService, currencyService, profileTransactionService)
	PotionService._dataService = dataService
	PotionService._currencyService = currencyService
	PotionService._profileTransactionService = profileTransactionService
	PotionService._shuttingDown = false
end

function PotionService.setMovementRefreshCallback(callback)
	PotionService._movementRefresh = callback
end

-- Pure snapshot: this method never initializes profile fields, expires sources,
-- changes revisions, refreshes movement, or emits events.
function PotionService.getState(player)
	local data = getData(player)
	local now = os.time()
	if type(data) ~= "table" then
		return {
			contractVersion = CONTRACT_VERSION,
			stateRevision = currentRevision(player),
			serverTime = now,
			catalogOrder = deepCopy(CATALOG_ORDER),
			potionInventory = {}, activeBuffs = {}, consumeAvailability = {},
			autoDrinkSelection = {},
			upgrades = { slots = 0, durationLevel = 0, durationMultiplier = 1, autoDrink = false },
			slots = { active = 0, maximum = 0 }, upgradeOffers = {},
			maxShinyCharges = MAX_SHINY_CHARGES,
		}
	end
	local inventorySource = type(data.potionInventory) == "table" and data.potionInventory or {}
	local selectionSource = type(data.autoDrinkSelection) == "table" and data.autoDrinkSelection or {}
	local upgrades = type(data.potionUpgrades) == "table" and data.potionUpgrades or {}
	local activeBuffs = type(data.activeBuffs) == "table" and data.activeBuffs or {}
	local inventory, selection, consumeAvailability = {}, {}, {}
	for _, potionId in ipairs(CATALOG_ORDER) do
		local count = inventorySource[potionId]
		if isFiniteNumber(count) and count > 0 then
			inventory[potionId] = math.min(MAX_INVENTORY, math.floor(count))
		end
		if selectionSource[potionId] == true then selection[potionId] = true end
		local canConsume, reason = resolveConsumeAvailability(data, potionId, now)
		consumeAvailability[potionId] = { canConsume = canConsume, reason = reason }
	end
	local durationLevel = isFiniteNumber(upgrades.durationLevel)
		and math.floor(upgrades.durationLevel) or 0
	local slots = maxSlots(data)
	return {
		contractVersion = CONTRACT_VERSION,
		stateRevision = currentRevision(player),
		serverTime = now,
		catalogOrder = deepCopy(CATALOG_ORDER),
		potionInventory = inventory,
		activeBuffs = buildActiveBuffDto(data, now),
		consumeAvailability = consumeAvailability,
		autoDrinkSelection = selection,
		upgrades = {
			slots = slots,
			durationLevel = durationLevel,
			durationMultiplier = durationMultiplier(data),
			autoDrink = upgrades.autoDrink == true,
		},
		slots = { active = countActiveTypes(activeBuffs, now), maximum = slots },
		upgradeOffers = upgradeOffers(data),
		maxShinyCharges = MAX_SHINY_CHARGES,
	}
end

local function acquireLease(player, owner, allowDuringShutdown)
	local key = userKey(player)
	if key == nil then return nil, "INVALID_PLAYER" end
	if PotionService._shuttingDown and allowDuringShutdown ~= true then
		return nil, "SERVICE_UNAVAILABLE"
	end
	if PotionService._potionLeases[key] ~= nil then return nil, "BUSY" end
	local profile = getData(player)
	if type(profile) ~= "table" then return nil, "INVALID_STATE" end
	local generation = (PotionService._leaseGenerations[key] or 0) + 1
	PotionService._leaseGenerations[key] = generation
	local lease = {
		player = player,
		profile = profile,
		userId = key,
		owner = owner,
		generation = generation,
	}
	PotionService._potionLeases[key] = lease
	return lease, nil
end

local function leaseIsCurrent(player, lease)
	local key = userKey(player)
	return type(lease) == "table"
		and key ~= nil
		and lease.player == player
		and lease.userId == key
		and PotionService._potionLeases[key] == lease
		and getData(player) == lease.profile
end

local function releaseLease(player, lease)
	if not leaseIsCurrent(player, lease) then return false end
	if lease.profileOwner then
		local coordinator = PotionService._profileTransactionService
		if type(coordinator) ~= "table" or type(coordinator.commit) ~= "function"
			or coordinator.commit(lease.profileOwner) ~= true then return false end
		lease.profileOwner = nil
	end
	PotionService._potionLeases[lease.userId] = nil
	return true
end

-- Direct Potion operations own the central QOF-25 profile boundary as well as
-- the local domain lease. The profile owner closes autosave/leave admission;
-- no profile mutation occurs before both owners have been acquired.
local function acquireOwnedLease(player, owner)
	local lease, leaseError = acquireLease(player, owner, false)
	if not lease then return nil, leaseError end
	local coordinator = PotionService._profileTransactionService
	if type(coordinator) ~= "table" or type(coordinator.begin) ~= "function"
		or type(coordinator.commit) ~= "function" then
		PotionService._potionLeases[lease.userId] = nil
		return nil, "SERVICE_UNAVAILABLE"
	end
	local profileOwner, ownerError = coordinator.begin(player, owner)
	if not profileOwner then
		PotionService._potionLeases[lease.userId] = nil
		return nil, ownerError or "BUSY"
	end
	if profileOwner.profile ~= lease.profile then
		coordinator.commit(profileOwner)
		PotionService._potionLeases[lease.userId] = nil
		return nil, "INVALID_STATE"
	end
	lease.profileOwner = profileOwner
	return lease, nil
end

-- ShopService uses this exact authority for Potion inventory purchases.
function PotionService.beginMutation(player, ownerName)
	return acquireLease(player, ownerName or "ExternalPotionMutation", false)
end

function PotionService.endMutation(player, lease)
	return releaseLease(player, lease)
end

function PotionService.isMutationCurrent(player, lease)
	return leaseIsCurrent(player, lease)
end

function PotionService.isPotionMutationIdle(player)
	local key = userKey(player)
	return key ~= nil and PotionService._potionLeases[key] == nil
		and PotionService._activeTransactions[key] == nil
end

local function publishMutation(player)
	local revision = bumpRevision(player)
	local state = PotionService.getState(player)
	state.stateRevision = revision
	fireState(player, state)
	return state
end

function PotionService.notifyInventoryChanged(player, lease)
	local ownedLease = lease
	local acquiredHere = false
	if ownedLease == nil then
		local leaseError
		ownedLease, leaseError = acquireOwnedLease(player, "PotionService.notifyInventoryChanged")
		if not ownedLease then return nil, leaseError end
		acquiredHere = true
	elseif not leaseIsCurrent(player, ownedLease) then
		return nil, "BUSY"
	end
	local state = publishMutation(player)
	if acquiredHere and not releaseLease(player, ownedLease) then return nil, "BUSY" end
	return state, nil
end

local function consumePotionLocked(player, lease, potionId, origin)
	if not leaseIsCurrent(player, lease) then return false, "BUSY" end
	if BalanceConfig.Potions.ConsumeRuntimeEnabled ~= true then
		return false, "Potion consumption is not available yet"
	end
	local potion = BalanceConfig.Potions.Catalog[potionId]
	if not potion then return false, "Unknown potion" end
	local data = lease.profile
	if type(data.potionInventory) ~= "table" or type(data.activeBuffs) ~= "table" then
		return false, "Invalid potion state"
	end
	local now = os.time()
	local canConsume, unavailableReason = resolveConsumeAvailability(data, potionId, now)
	if not canConsume then return false, unavailableReason end
	local count = data.potionInventory[potionId]
	local oldInventory = count
	local oldBuffState = deepCopy(data.activeBuffs[potion.buffType])
	local oldRevision = PotionService._stateRevisions[lease.userId]
	local context = { action = "consumePotion", potionId = potionId, origin = origin or "manual" }
	local state, committed
	local ok = pcall(function()
		if count == 1 then
			data.potionInventory[potionId] = nil
		else
			data.potionInventory[potionId] = count - 1
		end
		invokeHook("afterInventory", context)
		if potion.durationSeconds then
			local typeState = data.activeBuffs[potion.buffType]
			if type(typeState) ~= "table" or type(typeState.sources) ~= "table" then
				typeState = { sources = {} }
				data.activeBuffs[potion.buffType] = typeState
			end
			local oldExpiry = sourceExpiresAt(typeState.sources[potionId]) or now
			local duration = math.floor(potion.durationSeconds * durationMultiplier(data))
			typeState.sources[potionId] = {
				expiresAt = math.min(math.max(now, oldExpiry) + duration, now + MAX_TIMED_SECONDS),
			}
		else
			local typeState = data.activeBuffs[potion.buffType]
			local charges = type(typeState) == "table" and typeState.charges or 0
			if not isFiniteNumber(charges) or charges < 0
				or charges + potion.hatchCharges > MAX_SHINY_CHARGES then
				error("invalid charge state")
			end
			data.activeBuffs[potion.buffType] = { charges = math.floor(charges) + potion.hatchCharges }
		end
		invokeHook("afterBuff", context)
		local revision = bumpRevision(player)
		state = PotionService.getState(player)
		state.stateRevision = revision
		committed = true
	end)
	if not ok or not committed then
		data.potionInventory[potionId] = oldInventory
		data.activeBuffs[potion.buffType] = oldBuffState
		PotionService._stateRevisions[lease.userId] = oldRevision
		return false, "Potion consumption failed"
	end
	if potion.buffType == "speed" and PotionService._movementRefresh then
		pcall(PotionService._movementRefresh, player)
	end
	fireState(player, state)
	return true, nil, state
end

function PotionService.consume(player, request)
	if not exactRequest(request, { contractVersion = true, action = true, potionId = true })
		or request.contractVersion ~= CONTRACT_VERSION
		or request.action ~= "consumePotion"
		or not validIdentifier(request.potionId) then
		return false, "Invalid consume request"
	end
	local lease, leaseError = acquireOwnedLease(player, "PotionService.consume")
	if not lease then return false, leaseError end
	local ok, success, message, state = pcall(consumePotionLocked, player, lease,
		request.potionId, "manual")
	local released = releaseLease(player, lease)
	if not ok or not released then return false, "Potion action failed" end
	return success, message, state
end

local function resolveUpgrade(data, upgradeId)
	local upgrades = data.potionUpgrades
	if upgradeId == "PotionSlot" then
		for _, level in ipairs(BalanceConfig.Potions.Upgrades.PotionSlots) do
			if level.slots == upgrades.slots + 1 then
				return level.cost, function() upgrades.slots = level.slots end, "slots", upgrades.slots
			end
		end
		return nil, nil, nil, nil, "Potion slots are maxed"
	elseif upgradeId == "Duration" then
		local nextLevel = upgrades.durationLevel + 1
		local level = BalanceConfig.Potions.Upgrades.Duration[nextLevel]
		if level then
			return level.cost, function() upgrades.durationLevel = nextLevel end,
				"durationLevel", upgrades.durationLevel
		end
		return nil, nil, nil, nil, "Potion duration is maxed"
	elseif upgradeId == "AutoDrink" then
		if upgrades.autoDrink then return nil, nil, nil, nil, "Auto-Drink is already owned" end
		return BalanceConfig.Potions.Upgrades.AutoDrink.cost,
			function() upgrades.autoDrink = true end, "autoDrink", upgrades.autoDrink
	end
	return nil, nil, nil, nil, "Unknown potion upgrade"
end

local function finishActiveTransaction(transaction)
	local key = transaction.userId
	if transaction.lease and not releaseLease(transaction.player, transaction.lease) then return false end
	transaction.lease = nil
	if PotionService._activeTransactions[key] == transaction then
		PotionService._activeTransactions[key] = nil
	end
	return true
end

function PotionService.purchaseUpgrade(player, request)
	if not exactRequest(request, { contractVersion = true, action = true, upgradeId = true })
		or request.contractVersion ~= CONTRACT_VERSION
		or request.action ~= "purchasePotionUpgrade"
		or not validIdentifier(request.upgradeId) then
		return false, "Invalid upgrade request"
	end
	local lease, leaseError = acquireLease(player, "PotionService.purchaseUpgrade", false)
	if not lease then return false, leaseError end
	local data = lease.profile
	if type(data.potionUpgrades) ~= "table" or not PotionService._currencyService then
		releaseLease(player, lease)
		return false, "Invalid potion state"
	end
	local cost, mutate, field, oldValue, unavailable = resolveUpgrade(data, request.upgradeId)
	if not cost then
		releaseLease(player, lease)
		return false, unavailable
	end
	local spendTransaction = PotionService._currencyService.beginSpendTransaction(
		player, cost.currency, cost.amount, "PotionService.purchaseUpgrade")
	if type(spendTransaction) ~= "table" then
		releaseLease(player, lease)
		return false, "Not enough " .. tostring(cost.currency)
	end
	local key = lease.userId
	local transaction = {
		player = player, userId = key, profile = data, upgrades = data.potionUpgrades,
		lease = lease, field = field, oldValue = oldValue,
		oldRevision = PotionService._stateRevisions[key], writtenValue = nil,
		writtenRevision = nil, spendTransaction = spendTransaction,
		domainRestored = false, executing = true, committed = false, rolledBack = false,
	}
	PotionService._activeTransactions[key] = transaction

	local function rollbackPurchase(currentSpendTransaction)
		if transaction.committed then return finishActiveTransaction(transaction) end
		if transaction.rolledBack then return finishActiveTransaction(transaction) end
		if transaction.executing or currentSpendTransaction ~= transaction.spendTransaction then return false end
		if not transaction.domainRestored then
			local domainOk, domainRestored = pcall(function()
				if not leaseIsCurrent(transaction.player, transaction.lease)
					or getData(transaction.player) ~= transaction.profile
					or transaction.profile.potionUpgrades ~= transaction.upgrades then return false end
				local currentValue = transaction.upgrades[transaction.field]
				if currentValue ~= transaction.oldValue then
					if transaction.writtenValue == nil or currentValue ~= transaction.writtenValue then return false end
					transaction.upgrades[transaction.field] = transaction.oldValue
				end
				local currentStoredRevision = PotionService._stateRevisions[key]
				if currentStoredRevision ~= transaction.oldRevision then
					if currentStoredRevision ~= transaction.writtenRevision then return false end
					PotionService._stateRevisions[key] = transaction.oldRevision
				end
				return true
			end)
			if not domainOk or domainRestored ~= true then return false end
			transaction.domainRestored = true
		end
		local currencyOk, currencyCanceled = pcall(
			PotionService._currencyService.rollbackSpendTransaction, transaction.spendTransaction)
		if not currencyOk or currencyCanceled ~= true then return false end
		transaction.spendTransaction = nil
		transaction.rolledBack = true
		return finishActiveTransaction(transaction)
	end
	transaction.settle = function()
		if transaction.executing then return false end
		if transaction.committed then return finishActiveTransaction(transaction) end
		return rollbackPurchase(transaction.spendTransaction)
	end

	local registerOk, registered = pcall(PotionService._currencyService.setSpendSettler,
		spendTransaction, rollbackPurchase)
	if not registerOk or registered ~= true then
		transaction.executing = false
		if rollbackPurchase(spendTransaction) then return false, "Potion upgrade purchase failed" end
		local recoveryOk, recoveryRegistered = pcall(PotionService._currencyService.setSpendSettler,
			spendTransaction, rollbackPurchase)
		if not recoveryOk or recoveryRegistered ~= true then
			return false, "Potion upgrade rollback failed"
		end
		return false, "Potion upgrade rollback failed"
	end

	local state
	local context = { action = "purchasePotionUpgrade", upgradeId = request.upgradeId }
	local ok = pcall(function()
		invokeHook("afterSpend", context)
		mutate()
		transaction.writtenValue = transaction.upgrades[field]
		invokeHook("afterUpgrade", context)
		transaction.writtenRevision = bumpRevision(player)
		state = PotionService.getState(player)
		state.stateRevision = transaction.writtenRevision
		if PotionService._currencyService.commitSpendTransaction(spendTransaction) ~= true then
			error("currency commit failed")
		end
		transaction.spendTransaction = nil
		transaction.committed = true
	end)
	transaction.executing = false
	if not ok or not transaction.committed then
		if not rollbackPurchase(spendTransaction) then return false, "Potion upgrade rollback failed" end
		return false, "Potion upgrade purchase failed"
	end
	if not finishActiveTransaction(transaction) then return false, "Potion upgrade finalization failed" end
	fireState(player, state)
	return true, nil, state
end

function PotionService.setAutoDrinkSelection(player, request)
	if not exactRequest(request, {
		contractVersion = true, action = true, potionId = true, selected = true,
	}) or request.contractVersion ~= CONTRACT_VERSION
		or request.action ~= "setAutoDrinkSelection"
		or not validIdentifier(request.potionId)
		or type(request.selected) ~= "boolean"
		or not BalanceConfig.Potions.Catalog[request.potionId] then
		return false, "Invalid Auto-Drink request"
	end
	local lease, leaseError = acquireOwnedLease(player, "PotionService.setAutoDrinkSelection")
	if not lease then return false, leaseError end
	local data = lease.profile
	if type(data.potionUpgrades) ~= "table" or data.potionUpgrades.autoDrink ~= true then
		releaseLease(player, lease)
		return false, "Auto-Drink upgrade required"
	end
	if type(data.autoDrinkSelection) ~= "table" then
		releaseLease(player, lease)
		return false, "Invalid Auto-Drink state"
	end
	data.autoDrinkSelection[request.potionId] = request.selected and true or nil
	local state = publishMutation(player)
	if not releaseLease(player, lease) then return false, "Potion action failed" end
	return true, nil, state
end

function PotionService.getMultiplier(player, buffType)
	local data = getData(player)
	if type(data) ~= "table" or type(data.activeBuffs) ~= "table" then return 1 end
	local now = os.time()
	local state = data.activeBuffs[buffType]
	if not timedTypeIsActive(state, now) then return 1 end
	local multiplier = 1
	for sourceId, source in pairs(state.sources) do
		local potion = BalanceConfig.Potions.Catalog[sourceId]
		local expiresAt = sourceExpiresAt(source)
		if potion and potion.buffType == buffType and expiresAt and expiresAt > now then
			multiplier = math.max(multiplier, potion.multiplier)
		end
	end
	return multiplier
end

function PotionService.beginShinyChargeTransaction(player, requestedCount)
	if not isFiniteNumber(requestedCount) or requestedCount < 1 or requestedCount % 1 ~= 0 then
		return nil, 0, "INVALID_REQUEST"
	end
	local lease, leaseError = acquireLease(player, "EggService.ShinyReservation", false)
	if not lease then return nil, 0, leaseError end
	local activeBuffs = lease.profile.activeBuffs
	local state = type(activeBuffs) == "table" and activeBuffs.shinyChance or nil
	local charges = type(state) == "table" and state.charges or 0
	if not isFiniteNumber(charges) or charges <= 0 or charges % 1 ~= 0
		or charges > MAX_SHINY_CHARGES then
		releaseLease(player, lease)
		return nil, 0, nil
	end
	local reserved = math.min(math.floor(charges), requestedCount)
	local handle = {}
	PotionService._pendingShinyCharges[handle] = {
		player = player, profile = lease.profile, activeBuffs = activeBuffs,
		lease = lease, reserved = reserved,
	}
	local remaining = math.floor(charges) - reserved
	activeBuffs.shinyChance = remaining > 0 and { charges = remaining } or nil
	return handle, reserved, nil
end

function PotionService.rollbackShinyChargeTransaction(handle)
	local pending = PotionService._pendingShinyCharges[handle]
	if not pending or not leaseIsCurrent(pending.player, pending.lease)
		or getData(pending.player) ~= pending.profile
		or pending.profile.activeBuffs ~= pending.activeBuffs then return false end
	local state = pending.activeBuffs.shinyChance
	local currentCharges = type(state) == "table" and state.charges or 0
	if not isFiniteNumber(currentCharges) or currentCharges < 0 or currentCharges % 1 ~= 0
		or currentCharges + pending.reserved > MAX_SHINY_CHARGES then return false end
	local restored = currentCharges + pending.reserved
	pending.activeBuffs.shinyChance = restored > 0 and { charges = restored } or nil
	if not releaseLease(pending.player, pending.lease) then return false end
	PotionService._pendingShinyCharges[handle] = nil
	return true
end

function PotionService.commitShinyChargeTransaction(handle)
	local pending = PotionService._pendingShinyCharges[handle]
	if not pending or not leaseIsCurrent(pending.player, pending.lease)
		or getData(pending.player) ~= pending.profile then return false end
	local revision = bumpRevision(pending.player)
	local state = PotionService.getState(pending.player)
	state.stateRevision = revision
	if not releaseLease(pending.player, pending.lease) then
		PotionService._stateRevisions[pending.lease.userId] = revision - 1
		return false
	end
	PotionService._pendingShinyCharges[handle] = nil
	fireState(pending.player, state)
	return true
end

local function shouldAutoDrink(data, potionId, now)
	local potion = BalanceConfig.Potions.Catalog[potionId]
	local count = type(data.potionInventory) == "table" and data.potionInventory[potionId] or 0
	if not potion or not isFiniteNumber(count) or count < 1 then return false end
	local state = type(data.activeBuffs) == "table" and data.activeBuffs[potion.buffType] or nil
	if potion.durationSeconds then
		local source = type(state) == "table" and type(state.sources) == "table"
			and state.sources[potionId] or nil
		local expiresAt = sourceExpiresAt(source)
		return not expiresAt or expiresAt <= now
	end
	local charges = type(state) == "table" and state.charges or 0
	return isFiniteNumber(charges) and charges <= 0
end

local function processAutoDrinkLocked(player, lease)
	if not leaseIsCurrent(player, lease) then return false, "BUSY" end
	local data = lease.profile
	if type(data.potionUpgrades) ~= "table" or data.potionUpgrades.autoDrink ~= true
		or type(data.autoDrinkSelection) ~= "table" then return false, nil end
	local consumed = false
	for _, potionId in ipairs(CATALOG_ORDER) do
		if data.autoDrinkSelection[potionId] == true and shouldAutoDrink(data, potionId, os.time()) then
			local success = consumePotionLocked(player, lease, potionId, "auto")
			if success then consumed = true end
		end
	end
	return consumed, nil
end

function PotionService.processAutoDrink(player)
	local lease, leaseError = acquireOwnedLease(player, "PotionService.AutoDrink")
	if not lease then return false, leaseError end
	local ok, consumed, message = pcall(processAutoDrinkLocked, player, lease)
	local released = releaseLease(player, lease)
	if not ok or not released then return false, "Potion action failed" end
	return consumed, message
end

function PotionService.reconcilePlayer(player, allowAutoDrink)
	local lease, leaseError = acquireOwnedLease(player, "PotionService.reconcile")
	if not lease then return false, leaseError end
	local changed, speedChanged = cleanupExpired(lease.profile, os.time())
	if changed then publishMutation(player) end
	if speedChanged and PotionService._movementRefresh then
		pcall(PotionService._movementRefresh, player)
	end
	local consumed = false
	if allowAutoDrink == true then consumed = processAutoDrinkLocked(player, lease) == true end
	local released = releaseLease(player, lease)
	if not released then return false, "Potion action failed" end
	return changed or consumed, nil
end

function PotionService.onPlayerAdded(player)
	local key = userKey(player)
	if key ~= nil then PotionService._stateRevisions[key] = 0 end
	local lease = select(1, acquireOwnedLease(player, "PotionService.join"))
	if lease then
		local data = lease.profile
		local changed = false
		if type(data.potionInventory) ~= "table" then data.potionInventory = {}; changed = true end
		if type(data.activeBuffs) ~= "table" then data.activeBuffs = {}; changed = true end
		if type(data.potionUpgrades) ~= "table" then
			data.potionUpgrades = {
				slots = BalanceConfig.Potions.Upgrades.BaseSlots,
				durationLevel = 0, autoDrink = false,
			}
			changed = true
		end
		if type(data.autoDrinkSelection) ~= "table" then data.autoDrinkSelection = {}; changed = true end
		local expired, speedChanged = cleanupExpired(data, os.time())
		if changed or expired then publishMutation(player) end
		if speedChanged and PotionService._movementRefresh then pcall(PotionService._movementRefresh, player) end
		processAutoDrinkLocked(player, lease)
		releaseLease(player, lease)
	end
end

function PotionService.cleanup(player)
	local key = userKey(player)
	if key == nil then return false end
	local transaction = PotionService._activeTransactions[key]
	if transaction then
		if transaction.executing or type(transaction.settle) ~= "function"
			or transaction.settle() ~= true then return false end
	end
	-- Shiny handles are owned exclusively by EggService. Potion lifecycle must
	-- never choose rollback for an executing or post-PONR Hatch; Egg settles the
	-- handle first and this service only verifies that none remain.
	for _, pending in pairs(PotionService._pendingShinyCharges) do
		if pending.player == player then return false end
	end
	if PotionService._potionLeases[key] ~= nil then return false end
	PotionService._stateRevisions[key] = nil
	PotionService._leaseGenerations[key] = nil
	return true
end

PotionService.onPlayerRemoving = PotionService.cleanup

function PotionService.beginShutdown()
	PotionService._shuttingDown = true
	PotionService._running = false
end

function PotionService.prepareForShutdown()
	PotionService.beginShutdown()
	local settled = true
	local transactions = {}
	for _, transaction in pairs(PotionService._activeTransactions) do
		table.insert(transactions, transaction)
	end
	for _, transaction in ipairs(transactions) do
		if transaction.executing or type(transaction.settle) ~= "function"
			or transaction.settle() ~= true then settled = false end
	end
	return settled
end

function PotionService.step()
	if PotionService._shuttingDown then return end
	for _, player in ipairs(Players:GetPlayers()) do PotionService.reconcilePlayer(player, true) end
end

function PotionService.start()
	if PotionService._running or PotionService._shuttingDown then return false end
	PotionService._running = true
	task.spawn(function()
		while PotionService._running do
			task.wait(RECONCILE_INTERVAL)
			if PotionService._running then PotionService.step() end
		end
	end)
	return true
end

return PotionService
