--[[
	PotionService.lua - QOF-14 server-authoritative potion state owner.
	Purchases remain in ShopService. This service owns consumption, persistent
	absolute-time effects, upgrades, online Auto-Drink, and Shiny hatch charges.
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
PotionService._movementRefresh = nil
PotionService._mutationLocks = {}
PotionService._stateRevisions = {}
PotionService._pendingShinyCharges = setmetatable({}, { __mode = "k" })
PotionService._transactionHook = nil
PotionService._running = false

local function isFiniteNumber(value)
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
end

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, child in pairs(value) do
		result[deepCopy(key)] = deepCopy(child)
	end
	return result
end

local function exactRequest(request, fields)
	if type(request) ~= "table" or getmetatable(request) ~= nil then
		return false
	end
	local count = 0
	for key in pairs(request) do
		if not fields[key] then
			return false
		end
		count = count + 1
	end
	local expected = 0
	for _ in pairs(fields) do
		expected = expected + 1
	end
	return count == expected
end

local function validIdentifier(value)
	return type(value) == "string" and #value > 0 and #value <= 64
end

local function getData(player)
	if not player or not PotionService._dataService then
		return nil
	end
	return PotionService._dataService.getPlayerData(player)
end

local function currentRevision(player)
	local key = player and player.UserId
	return key and PotionService._stateRevisions[key] or 0
end

local function bumpRevision(player)
	local key = player and player.UserId
	if not key then return 0 end
	local revision = (PotionService._stateRevisions[key] or 0) + 1
	PotionService._stateRevisions[key] = revision
	return revision
end

local function sourceExpiresAt(source)
	if type(source) ~= "table" or not isFiniteNumber(source.expiresAt) then
		return nil
	end
	return math.floor(source.expiresAt)
end

local function timedTypeIsActive(state, now)
	if type(state) ~= "table" or type(state.sources) ~= "table" then
		return false
	end
	for _, source in pairs(state.sources) do
		local expiresAt = sourceExpiresAt(source)
		if expiresAt and expiresAt > now then
			return true
		end
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
			if buffTypeIsActive(buffType, state, now) then
				count = count + 1
			end
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
			if not isFiniteNumber(charges) or math.floor(charges) <= 0 then
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
			if next(state.sources) == nil then
				data.activeBuffs[buffType] = nil
			end
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
	return math.clamp(
		slots,
		BalanceConfig.Potions.Upgrades.BaseSlots,
		BalanceConfig.Potions.Upgrades.MaxSlots
	)
end

local function resolveConsumeAvailability(data, potionId, now)
	local potion = BalanceConfig.Potions.Catalog[potionId]
	if not potion then
		return false, "Unknown potion"
	end
	local count = type(data.potionInventory) == "table" and data.potionInventory[potionId] or nil
	if not isFiniteNumber(count) or count < 1 or count % 1 ~= 0 or count > MAX_INVENTORY then
		return false, "No potion available"
	end

	local typeState = type(data.activeBuffs) == "table" and data.activeBuffs[potion.buffType] or nil
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
		if not isFiniteNumber(currentCharges) or currentCharges < 0 then
			return false, "Invalid Shiny charge state"
		end
		if currentCharges >= MAX_SHINY_CHARGES then
			return false, "Maximum Shiny charges reached (" .. tostring(MAX_SHINY_CHARGES) .. ")"
		end
	end
	if not existingTypeActive and countActiveTypes(data.activeBuffs, now) >= maxSlots(data) then
		return false, "No active potion slots available"
	end
	return true, nil
end

local function upgradeOffers(data)
	local upgrades = data.potionUpgrades
	local slotOffer = nil
	for _, level in ipairs(BalanceConfig.Potions.Upgrades.PotionSlots) do
		if level.slots == upgrades.slots + 1 then
			slotOffer = { target = level.slots, cost = deepCopy(level.cost) }
			break
		end
	end
	local durationDef = BalanceConfig.Potions.Upgrades.Duration[upgrades.durationLevel + 1]
	local autoDrinkOffer = nil
	if upgrades.autoDrink ~= true then
		autoDrinkOffer = {
			target = true,
			cost = deepCopy(BalanceConfig.Potions.Upgrades.AutoDrink.cost),
		}
	end
	return {
		PotionSlot = slotOffer,
		Duration = durationDef and {
			target = upgrades.durationLevel + 1,
			multiplier = durationDef.multiplier,
			cost = deepCopy(durationDef.cost),
		} or nil,
		AutoDrink = autoDrinkOffer,
	}
end

local function buildActiveBuffDto(data, now)
	local result = {}
	for buffType, state in pairs(data.activeBuffs or {}) do
		if buffType == "shinyChance" and buffTypeIsActive(buffType, state, now) then
			result[buffType] = {
				charges = math.min(MAX_SHINY_CHARGES, math.floor(state.charges)),
				multiplier = BalanceConfig.Potions.Catalog.ShinyPotion.multiplier,
			}
		elseif timedTypeIsActive(state, now) then
			local sources = {}
			local effectiveMultiplier = 1
			for sourceId, source in pairs(state.sources) do
				local expiresAt = sourceExpiresAt(source)
				local potion = BalanceConfig.Potions.Catalog[sourceId]
				if expiresAt and expiresAt > now and potion and potion.buffType == buffType then
					sources[sourceId] = {
						expiresAt = expiresAt,
						multiplier = potion.multiplier,
					}
					effectiveMultiplier = math.max(effectiveMultiplier, potion.multiplier)
				end
			end
			result[buffType] = {
				sources = sources,
				effectiveMultiplier = effectiveMultiplier,
			}
		end
	end
	return result
end

local function fireState(player, state)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local event = remotes and remotes:FindFirstChild("PotionStateUpdated")
	if event then
		pcall(function()
			event:FireClient(player, deepCopy(state))
		end)
	end
end

local function invokeHook(stage, context)
	if type(PotionService._transactionHook) == "function" then
		PotionService._transactionHook(stage, context)
	end
end

function PotionService.init(dataService, currencyService)
	PotionService._dataService = dataService
	PotionService._currencyService = currencyService
end

function PotionService.setMovementRefreshCallback(callback)
	PotionService._movementRefresh = callback
end

function PotionService.getState(player)
	local data = getData(player)
	local now = os.time()
	if type(data) ~= "table" then
		return {
			contractVersion = CONTRACT_VERSION,
			stateRevision = currentRevision(player),
			serverTime = now,
			catalogOrder = deepCopy(CATALOG_ORDER),
			potionInventory = {},
			activeBuffs = {},
			consumeAvailability = {},
			autoDrinkSelection = {},
			upgrades = { slots = 0, durationLevel = 0, durationMultiplier = 1, autoDrink = false },
			slots = { active = 0, maximum = 0 },
			upgradeOffers = {},
		}
	end
	if type(data.potionInventory) ~= "table" then data.potionInventory = {} end
	if type(data.potionUpgrades) ~= "table" then
		data.potionUpgrades = {
			slots = BalanceConfig.Potions.Upgrades.BaseSlots,
			durationLevel = 0,
			autoDrink = false,
		}
	end
	if type(data.autoDrinkSelection) ~= "table" then data.autoDrinkSelection = {} end
	local expiredChanged, speedChanged = cleanupExpired(data, now)
	if expiredChanged then
		bumpRevision(player)
	end
	if speedChanged and PotionService._movementRefresh then
		pcall(PotionService._movementRefresh, player)
	end
	local slots = maxSlots(data)
	local inventory = {}
	local selection = {}
	local consumeAvailability = {}
	for _, potionId in ipairs(CATALOG_ORDER) do
		local count = data.potionInventory[potionId]
		if isFiniteNumber(count) and count > 0 then
			inventory[potionId] = math.min(MAX_INVENTORY, math.floor(count))
		end
		if data.autoDrinkSelection[potionId] == true then
			selection[potionId] = true
		end
		local canConsume, reason = resolveConsumeAvailability(data, potionId, now)
		consumeAvailability[potionId] = {
			canConsume = canConsume,
			reason = reason,
		}
	end
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
			durationLevel = math.floor(data.potionUpgrades.durationLevel or 0),
			durationMultiplier = durationMultiplier(data),
			autoDrink = data.potionUpgrades.autoDrink == true,
		},
		slots = {
			active = countActiveTypes(data.activeBuffs, now),
			maximum = slots,
		},
		upgradeOffers = upgradeOffers(data),
		maxShinyCharges = MAX_SHINY_CHARGES,
	}
end

local function consumePotionLocked(player, potionId, origin)
	if BalanceConfig.Potions.ConsumeRuntimeEnabled ~= true then
		return false, "Potion consumption is not available yet"
	end
	local potion = BalanceConfig.Potions.Catalog[potionId]
	if not potion then
		return false, "Unknown potion"
	end
	local data = getData(player)
	if type(data) ~= "table" or type(data.potionInventory) ~= "table"
		or type(data.activeBuffs) ~= "table" then
		return false, "Invalid potion state"
	end
	local now = os.time()
	cleanupExpired(data, now)
	local canConsume, unavailableReason = resolveConsumeAvailability(data, potionId, now)
	if not canConsume then
		return false, unavailableReason
	end
	local count = data.potionInventory[potionId]

	local oldInventory = data.potionInventory[potionId]
	local oldBuffState = deepCopy(data.activeBuffs[potion.buffType])
	local context = { action = "consumePotion", potionId = potionId, origin = origin or "manual" }
	local state = nil
	local committed = false
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
			local oldSource = typeState.sources[potionId]
			local oldExpiry = sourceExpiresAt(oldSource) or now
			local duration = math.floor(potion.durationSeconds * durationMultiplier(data))
			typeState.sources[potionId] = {
				expiresAt = math.min(math.max(now, oldExpiry) + duration, now + MAX_TIMED_SECONDS),
			}
		else
			local typeState = data.activeBuffs[potion.buffType]
			local charges = type(typeState) == "table" and typeState.charges or 0
			if not isFiniteNumber(charges) or charges < 0 then
				error("invalid charge state")
			end
			if charges >= MAX_SHINY_CHARGES then
				error("maximum shiny charges")
			end
			data.activeBuffs[potion.buffType] = {
				charges = math.min(MAX_SHINY_CHARGES, math.floor(charges) + potion.hatchCharges),
			}
		end
		invokeHook("afterBuff", context)
		state = PotionService.getState(player)
		state.stateRevision = bumpRevision(player)
		committed = true
	end)
	if not ok or not committed then
		data.potionInventory[potionId] = oldInventory
		data.activeBuffs[potion.buffType] = oldBuffState
		return false, "Potion consumption failed"
	end
	if potion.buffType == "speed" and PotionService._movementRefresh then
		pcall(PotionService._movementRefresh, player)
	end
	fireState(player, state)
	return true, nil, state
end

local function withMutationLock(player, callback)
	if not player or player.UserId == nil then
		return false, "Invalid player"
	end
	local key = player.UserId
	if PotionService._mutationLocks[key] then
		return false, "Potion action already in progress"
	end
	PotionService._mutationLocks[key] = true
	local ok, success, message, state = pcall(callback)
	PotionService._mutationLocks[key] = nil
	if not ok then
		return false, "Potion action failed"
	end
	return success, message, state
end

function PotionService.consume(player, request)
	if not exactRequest(request, { contractVersion = true, action = true, potionId = true })
		or request.contractVersion ~= CONTRACT_VERSION
		or request.action ~= "consumePotion"
		or not validIdentifier(request.potionId) then
		return false, "Invalid consume request"
	end
	return withMutationLock(player, function()
		return consumePotionLocked(player, request.potionId, "manual")
	end)
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
		if upgrades.autoDrink then
			return nil, nil, nil, nil, "Auto-Drink is already owned"
		end
		return BalanceConfig.Potions.Upgrades.AutoDrink.cost,
			function() upgrades.autoDrink = true end, "autoDrink", upgrades.autoDrink
	end
	return nil, nil, nil, nil, "Unknown potion upgrade"
end

function PotionService.purchaseUpgrade(player, request)
	if not exactRequest(request, { contractVersion = true, action = true, upgradeId = true })
		or request.contractVersion ~= CONTRACT_VERSION
		or request.action ~= "purchasePotionUpgrade"
		or not validIdentifier(request.upgradeId) then
		return false, "Invalid upgrade request"
	end
	return withMutationLock(player, function()
		local data = getData(player)
		if type(data) ~= "table" or type(data.potionUpgrades) ~= "table"
			or not PotionService._currencyService then
			return false, "Invalid potion state"
		end
		local cost, mutate, field, oldValue, unavailable = resolveUpgrade(data, request.upgradeId)
		if not cost then
			return false, unavailable
		end
		local spendTransaction = PotionService._currencyService.beginSpendTransaction(
			player,
			cost.currency,
			cost.amount,
			"PotionService.purchaseUpgrade"
		)
		if type(spendTransaction) ~= "table" then
			return false, "Not enough " .. tostring(cost.currency)
		end

		local userId = player.UserId
		local transaction = {
			player = player,
			data = data,
			upgrades = data.potionUpgrades,
			field = field,
			oldValue = oldValue,
			oldRevision = PotionService._stateRevisions[userId],
			writtenValue = nil,
			writtenRevision = nil,
			dtoBuildStarted = false,
			spendTransaction = spendTransaction,
			domainRestored = false,
			committed = false,
			rolledBack = false,
		}

		local function rollbackPurchase(currentSpendTransaction)
			if transaction.committed or transaction.rolledBack then
				return true
		end
			if currentSpendTransaction ~= transaction.spendTransaction then
				return false
			end

			if not transaction.domainRestored then
				local domainOk, domainRestored = pcall(function()
					local currentData = getData(transaction.player)
					if currentData ~= transaction.data
						or currentData.potionUpgrades ~= transaction.upgrades then
						return false
					end

					local currentValue = transaction.upgrades[transaction.field]
					if currentValue ~= transaction.oldValue then
						if transaction.writtenValue == nil
							or currentValue ~= transaction.writtenValue then
							return false
						end
						transaction.upgrades[transaction.field] = transaction.oldValue
					end

					local currentStoredRevision = PotionService._stateRevisions[userId]
					if currentStoredRevision ~= transaction.oldRevision then
						local ownedRevision = transaction.writtenRevision
						if ownedRevision == nil and transaction.dtoBuildStarted then
							ownedRevision = (transaction.oldRevision or 0) + 1
						end
						if currentStoredRevision ~= ownedRevision then
							return false
						end
						PotionService._stateRevisions[userId] = transaction.oldRevision
					end

					return transaction.upgrades[transaction.field] == transaction.oldValue
						and PotionService._stateRevisions[userId] == transaction.oldRevision
				end)
				if not domainOk or domainRestored ~= true then
					return false
				end
				-- A later cancellation retry must never reinterpret a newer Potion
				-- revision as this transaction's write (including an ABA match).
				transaction.domainRestored = true
			end

			local currencyOk, currencyCanceled = pcall(
				PotionService._currencyService.rollbackSpendTransaction,
				transaction.spendTransaction
			)
			if not currencyOk or currencyCanceled ~= true then
				return false
			end
			transaction.spendTransaction = nil
			transaction.rolledBack = true
			return true
		end

		local registerOk, settlerRegistered = pcall(
			PotionService._currencyService.setSpendSettler,
			spendTransaction,
			rollbackPurchase
		)
		if not registerOk or settlerRegistered ~= true then
			if rollbackPurchase(spendTransaction) then
				return false, "Potion upgrade purchase failed"
			end
			-- A transient registration fault plus a transient cancellation fault
			-- must still leave this exact closure owned for lifecycle retry.
			local recoveryOk, recoveryRegistered = pcall(
				PotionService._currencyService.setSpendSettler,
				spendTransaction,
				rollbackPurchase
			)
			if not recoveryOk or recoveryRegistered ~= true then
				return false, "Potion upgrade rollback failed"
			end
			return false, "Potion upgrade rollback failed"
		end

		local state = nil
		local context = { action = "purchasePotionUpgrade", upgradeId = request.upgradeId }
		local ok = pcall(function()
			invokeHook("afterSpend", context)
			mutate()
			transaction.writtenValue = transaction.upgrades[field]
			invokeHook("afterUpgrade", context)
			transaction.dtoBuildStarted = true
			state = PotionService.getState(player)
			transaction.writtenRevision = bumpRevision(player)
			state.stateRevision = transaction.writtenRevision
			if PotionService._currencyService.commitSpendTransaction(spendTransaction) ~= true then
				error("currency commit failed")
			end
			-- Currency commit is the point of no return. The paid upgrade can no
			-- longer become retryable because of postcommit replication.
			transaction.spendTransaction = nil
			transaction.committed = true
		end)
		if not ok or not transaction.committed then
			if not rollbackPurchase(spendTransaction) then
				return false, "Potion upgrade rollback failed"
			end
			return false, "Potion upgrade purchase failed"
		end
		fireState(player, state)
		return true, nil, state
	end)
end

function PotionService.setAutoDrinkSelection(player, request)
	if not exactRequest(request, {
		contractVersion = true,
		action = true,
		potionId = true,
		selected = true,
	}) or request.contractVersion ~= CONTRACT_VERSION
		or request.action ~= "setAutoDrinkSelection"
		or not validIdentifier(request.potionId)
		or type(request.selected) ~= "boolean"
		or not BalanceConfig.Potions.Catalog[request.potionId] then
		return false, "Invalid Auto-Drink request"
	end
	return withMutationLock(player, function()
		local data = getData(player)
		if type(data) ~= "table" or type(data.potionUpgrades) ~= "table"
			or data.potionUpgrades.autoDrink ~= true then
			return false, "Auto-Drink upgrade required"
		end
		if type(data.autoDrinkSelection) ~= "table" then data.autoDrinkSelection = {} end
		data.autoDrinkSelection[request.potionId] = request.selected and true or nil
		local state = PotionService.getState(player)
		state.stateRevision = bumpRevision(player)
		fireState(player, state)
		return true, nil, state
	end)
end

function PotionService.notifyInventoryChanged(player)
	local state = PotionService.getState(player)
	state.stateRevision = bumpRevision(player)
	fireState(player, state)
	return state
end

function PotionService.getMultiplier(player, buffType)
	local data = getData(player)
	if type(data) ~= "table" or type(data.activeBuffs) ~= "table" then
		return 1
	end
	local now = os.time()
	local state = data.activeBuffs[buffType]
	if not timedTypeIsActive(state, now) then
		return 1
	end
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
		return nil, 0
	end
	local data = getData(player)
	local state = data and type(data.activeBuffs) == "table" and data.activeBuffs.shinyChance or nil
	local charges = type(state) == "table" and state.charges or 0
	if not isFiniteNumber(charges) or charges <= 0 then
		return nil, 0
	end
	local reserved = math.min(math.floor(charges), requestedCount)
	local handle = {}
	PotionService._pendingShinyCharges[handle] = {
		player = player,
		profile = data,
		oldState = deepCopy(state),
		reserved = reserved,
	}
	local remaining = math.floor(charges) - reserved
	data.activeBuffs.shinyChance = remaining > 0 and { charges = remaining } or nil
	return handle, reserved
end

function PotionService.rollbackShinyChargeTransaction(handle)
	local pending = PotionService._pendingShinyCharges[handle]
	if not pending then return false end
	PotionService._pendingShinyCharges[handle] = nil
	if getData(pending.player) ~= pending.profile or type(pending.profile.activeBuffs) ~= "table" then
		return false
	end
	pending.profile.activeBuffs.shinyChance = deepCopy(pending.oldState)
	return true
end

function PotionService.commitShinyChargeTransaction(handle)
	local pending = PotionService._pendingShinyCharges[handle]
	if not pending then return false end
	local ok, state = pcall(PotionService.getState, pending.player)
	if not ok then return false end
	state.stateRevision = bumpRevision(pending.player)
	PotionService._pendingShinyCharges[handle] = nil
	fireState(pending.player, state)
	return true
end

local function shouldAutoDrink(data, potionId, now)
	local potion = BalanceConfig.Potions.Catalog[potionId]
	local count = type(data.potionInventory) == "table" and data.potionInventory[potionId] or 0
	if not potion or not isFiniteNumber(count) or count < 1 then
		return false
	end
	local state = type(data.activeBuffs) == "table" and data.activeBuffs[potion.buffType] or nil
	if potion.durationSeconds then
		local source = type(state) == "table" and type(state.sources) == "table"
			and state.sources[potionId] or nil
		local expiresAt = sourceExpiresAt(source)
		return not expiresAt or expiresAt <= now
	end
	local charges = type(state) == "table" and state.charges or 0
	return not isFiniteNumber(charges) or charges <= 0
end

function PotionService.processAutoDrink(player)
	local data = getData(player)
	if type(data) ~= "table" or type(data.potionUpgrades) ~= "table"
		or data.potionUpgrades.autoDrink ~= true
		or type(data.autoDrinkSelection) ~= "table" then
		return false
	end
	local consumed = false
	for _, potionId in ipairs(CATALOG_ORDER) do
		if data.autoDrinkSelection[potionId] == true and shouldAutoDrink(data, potionId, os.time()) then
			local success = withMutationLock(player, function()
				return consumePotionLocked(player, potionId, "auto")
			end)
			if success then consumed = true end
		end
	end
	return consumed
end

function PotionService.reconcilePlayer(player, allowAutoDrink)
	local data = getData(player)
	if type(data) ~= "table" then return false end
	local changed, speedChanged = cleanupExpired(data, os.time())
	if speedChanged and PotionService._movementRefresh then
		pcall(PotionService._movementRefresh, player)
	end
	if changed then
		bumpRevision(player)
		fireState(player, PotionService.getState(player))
	end
	if allowAutoDrink == true then
		PotionService.processAutoDrink(player)
	end
	return changed
end

function PotionService.onPlayerAdded(player)
	if player and player.UserId ~= nil then
		PotionService._stateRevisions[player.UserId] = 0
	end
	PotionService.reconcilePlayer(player, true)
end

function PotionService.onPlayerRemoving(player)
	if not player then return end
	PotionService._mutationLocks[player.UserId] = nil
	PotionService._stateRevisions[player.UserId] = nil
	for handle, pending in pairs(PotionService._pendingShinyCharges) do
		if pending.player == player then
			PotionService.rollbackShinyChargeTransaction(handle)
		end
	end
end

function PotionService.step()
	for _, player in ipairs(Players:GetPlayers()) do
		PotionService.reconcilePlayer(player, true)
	end
end

function PotionService.start()
	if PotionService._running then return end
	PotionService._running = true
	task.spawn(function()
		while PotionService._running do
			task.wait(RECONCILE_INTERVAL)
			PotionService.step()
		end
	end)
end

return PotionService
