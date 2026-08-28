--[[
	ShopService.lua - Server-authoritative shop purchases.
	QOF-13 purchases canonical potions into persistent inventory only. Potion
	consumption remains dormant; legacy transient buffs are read-only compatibility
	state until their owning migration removes them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PetData = require(game.ReplicatedStorage.Shared.PetData)
local Config = require(game.ReplicatedStorage.Shared.Config)
local BalanceConfig = require(game.ReplicatedStorage.Shared.BalanceConfig)
local ShopData = require(game.ReplicatedStorage.Shared.ShopData)

local ShopService = {}

local CONTRACT_VERSION = 2
local PURCHASE_MODE = "inventoryOnly"
local POTION_ACTION = "purchasePotion"
local POTION_QUANTITY = 1
local MAX_POTION_INVENTORY = BalanceConfig.Potions.Persistence.MaxInventoryPerPotion

-- References to other services
ShopService._dataService = nil
ShopService._currencyService = nil
ShopService._eggService = nil
ShopService._potionService = nil
ShopService._walkSpeedRefresh = nil

-- Legacy read-only timed buff compatibility state.
ShopService._activeBuffs = {}

-- One in-flight purchase per player. Tests may inject faults through
-- _transactionHook(stage, context) at afterSpend and afterMutation.
ShopService._purchaseLocks = {}
ShopService._transactionHook = nil

-- Compatibility alias. Potion purchases do not consult this legacy catalog.
ShopService.Items = ShopData.Items

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
	local copy = {}
	for key, child in pairs(value) do
		copy[deepCopy(key)] = deepCopy(child)
	end
	return copy
end

local function normalizeBoundedInteger(value, defaultValue, maximum)
	if not isFiniteNumber(value) then
		return defaultValue
	end
	return math.max(0, math.min(maximum, math.floor(value)))
end

local function normalizedPotionInventory(inventory)
	local result = {}
	if type(inventory) ~= "table" then
		return result
	end
	for potionId in pairs(BalanceConfig.Potions.Catalog) do
		local count = normalizeBoundedInteger(inventory[potionId], 0, MAX_POTION_INVENTORY)
		if count > 0 then
			result[potionId] = count
		end
	end
	return result
end

local function isExactPotionRequest(request)
	if type(request) ~= "table" then
		return false
	end
	local fieldCount = 0
	for key in pairs(request) do
		if key ~= "contractVersion" and key ~= "action" and key ~= "itemId" and key ~= "quantity" then
			return false
		end
		fieldCount = fieldCount + 1
	end
	return fieldCount == 4
		and request.contractVersion == CONTRACT_VERSION
		and request.action == POTION_ACTION
		and type(request.itemId) == "string"
		and #request.itemId > 0
		and #request.itemId <= 64
		and request.quantity == POTION_QUANTITY
end

local function fireShopUpdate(player, state)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local event = remotes and remotes:FindFirstChild("ShopBuffsUpdated")
	if event then
		-- A committed purchase is never rolled back because replication failed.
		pcall(function()
			event:FireClient(player, deepCopy(state))
		end)
	end
end

local function invokeTransactionHook(stage, context)
	if type(ShopService._transactionHook) == "function" then
		ShopService._transactionHook(stage, context)
	end
end

function ShopService.init(dataService, currencyService)
	ShopService._dataService = dataService
	ShopService._currencyService = currencyService

	-- QOF-18 is owned exclusively by AutoHatchService. This legacy highest-zone
	-- scheduler is intentionally never started, even while the new feature gate is
	-- active, so both loops cannot coexist during rolling deployments.
end

function ShopService.setPotionService(potionService)
	ShopService._potionService = potionService
end

function ShopService.setEggService(eggService)
	ShopService._eggService = eggService
end

-- MovementService owns the complete WalkSpeed formula. This callback exists only
-- for expiration of legacy transient speed state, never for inventory purchases.
function ShopService.setWalkSpeedRefreshCallback(callback)
	ShopService._walkSpeedRefresh = callback
end

local function removeExpiredBuffs(player, now)
	if not player then return nil end
	local userId = player.UserId
	local buffs = ShopService._activeBuffs[userId]
	if not buffs then return nil end

	local speedExpired = false
	for buffType, expiry in pairs(buffs) do
		if now >= expiry then
			buffs[buffType] = nil
			if buffType == "speed" then
				speedExpired = true
			end
		end
	end
	if next(buffs) == nil then
		ShopService._activeBuffs[userId] = nil
	end
	if speedExpired and ShopService._walkSpeedRefresh then
		task.spawn(ShopService._walkSpeedRefresh, player)
	end
	return buffs
end

local function getMaxExtraEquipSlots()
	local itemDef = ShopData.Items.ExtraEquipSlot
	return itemDef and itemDef.maxPurchases or Config.MaxExtraEquipSlots or 5
end

function ShopService.getActiveBuffs(player)
	if ShopService._potionService then
		local state = ShopService._potionService.getState(player)
		return state and state.activeBuffs or {}
	end
	if not player then
		return {}
	end

	local now = os.clock()
	local buffs = removeExpiredBuffs(player, now)
	if not buffs then
		return {}
	end

	local result = {}
	for buffType, expiry in pairs(buffs) do
		result[buffType] = math.ceil(expiry - now)
	end
	return result
end

local function snapshotActiveBuffs(player)
	if not player then
		return {}
	end
	local now = os.clock()
	local buffs = ShopService._activeBuffs[player.UserId]
	if not buffs then
		return {}
	end
	local result = {}
	for buffType, expiry in pairs(buffs) do
		if isFiniteNumber(expiry) and expiry > now then
			result[buffType] = math.ceil(expiry - now)
		end
	end
	return result
end

-- Return a fresh V2 client DTO. Every nested mutable field is independent from
-- the profile and from the event payload used after a committed purchase. The
-- legacy buffs projection is a pure snapshot and never mutates purchase state.
function ShopService.getShopState(player)
	local potionInventory = {}
	local extraEquipSlots = 0
	if player and ShopService._dataService then
		local data = ShopService._dataService.getPlayerData(player)
		if data then
			potionInventory = normalizedPotionInventory(data.potionInventory)
			if type(data.shopPurchases) == "table" then
				extraEquipSlots = normalizeBoundedInteger(
					data.shopPurchases.extraEquipSlots,
					0,
					getMaxExtraEquipSlots()
				)
			end
		end
	end

	return {
		contractVersion = CONTRACT_VERSION,
		purchaseMode = PURCHASE_MODE,
		potionInventory = potionInventory,
		maxPotionInventory = MAX_POTION_INVENTORY,
		purchases = { extraEquipSlots = extraEquipSlots },
		maxExtraEquipSlots = getMaxExtraEquipSlots(),
		buffs = snapshotActiveBuffs(player),
		potionState = ShopService._potionService and ShopService._potionService.getState(player) or nil,
	}
end

local function rollbackPendingPurchase(currencyTransaction, rollbackMutation)
	-- Never release the central profile owner until the Shop mutation has been
	-- restored. A failed undo leaves the registered settler available for the
	-- coordinator to retry later.
	local mutationRollbackCallOk, mutationRolledBack = pcall(rollbackMutation)
	if not mutationRollbackCallOk or mutationRolledBack ~= true then
		return false
	end
	local currencyRollbackCallOk, currencyRolledBack = pcall(function()
		return ShopService._currencyService.rollbackSpendTransaction(currencyTransaction)
	end)
	return currencyRollbackCallOk and currencyRolledBack == true
end

local function executePurchase(player, context, mutate, rollbackMutation)
	local beginCallOk, currencyTransaction = pcall(function()
		return ShopService._currencyService.beginSpendTransaction(
			player,
			context.currency,
			context.amount,
			"ShopService"
		)
	end)
	if not beginCallOk then
		return false, "Purchase failed"
	end
	if type(currencyTransaction) ~= "table" then
		return false, "Not enough " .. tostring(context.currency) .. " (need " .. tostring(context.amount) .. ")"
	end
	context.currencyTransaction = currencyTransaction

	local function settlePendingPurchase(currentCurrencyTransaction)
		return rollbackPendingPurchase(currentCurrencyTransaction, rollbackMutation)
	end
	local settlerCallOk, settlerRegistered = pcall(function()
		return ShopService._currencyService.setSpendSettler(
			currencyTransaction,
			settlePendingPurchase
		)
	end)
	if not settlerCallOk or settlerRegistered ~= true then
		if not settlePendingPurchase(currencyTransaction) then
			return false, "Purchase rollback failed"
		end
		return false, "Purchase failed"
	end

	local state = nil
	local transactionOk = pcall(function()
		invokeTransactionHook("afterSpend", context)
		mutate()
		invokeTransactionHook("afterMutation", context)
		-- Construct the complete authoritative DTO before the commit boundary. If
		-- this fails, both the profile mutation and reservation are rolled back.
		state = ShopService.getShopState(player)
		if ShopService._currencyService.commitSpendTransaction(currencyTransaction) ~= true then
			error("currency commit failed")
		end
		context.committed = true
	end)
	if not transactionOk then
		if not settlePendingPurchase(currencyTransaction) then
			return false, "Purchase rollback failed"
		end
		return false, "Purchase failed"
	end
	return true, nil, state
end

local function purchasePotion(player, request, data)
	if BalanceConfig.Potions.RuntimeEnabled ~= true then
		return false, "Potion purchases are not available yet"
	end
	local itemId = request.itemId
	local potion = BalanceConfig.Potions.Catalog[itemId]
	if not potion then
		return false, "Unknown potion"
	end
	if type(data.potionInventory) ~= "table" then
		return false, "Invalid potion inventory"
	end

	local oldValue = data.potionInventory[itemId]
	local count = oldValue == nil and 0 or oldValue
	if not isFiniteNumber(count) or count < 0 or count % 1 ~= 0 or count > MAX_POTION_INVENTORY then
		return false, "Invalid potion inventory"
	end
	if count >= MAX_POTION_INVENTORY then
		return false, "Maximum potion inventory reached (" .. tostring(MAX_POTION_INVENTORY) .. ")"
	end

	local cost = potion.cost
	if type(cost) ~= "table"
		or (cost.currency ~= "coins" and cost.currency ~= "diamonds")
		or not isFiniteNumber(cost.amount)
		or cost.amount <= 0
		or cost.amount % 1 ~= 0 then
		return false, "Invalid potion cost"
	end

	local context = {
		contractVersion = CONTRACT_VERSION,
		action = POTION_ACTION,
		itemId = itemId,
		quantity = POTION_QUANTITY,
		currency = cost.currency,
		amount = cost.amount,
	}
	return executePurchase(player, context, function()
		data.potionInventory[itemId] = count + POTION_QUANTITY
	end, function()
		-- Preserve absence rather than materializing a zero key on rollback.
		data.potionInventory[itemId] = oldValue
		return true
	end)
end

local function purchaseExtraEquipSlot(player, data)
	local itemDef = ShopData.Items.ExtraEquipSlot
	if not itemDef then
		return false, "Unknown item: ExtraEquipSlot"
	end
	if itemDef.currency ~= "diamonds" or not isFiniteNumber(itemDef.cost) or itemDef.cost <= 0 then
		return false, "Unsupported shop currency"
	end

	local hadPurchases = type(data.shopPurchases) == "table"
	if data.shopPurchases ~= nil and not hadPurchases then
		return false, "Invalid shop purchases"
	end
	local purchases = hadPurchases and data.shopPurchases or nil
	local oldValue = purchases and purchases.extraEquipSlots or nil
	local count = oldValue == nil and 0 or oldValue
	local maxPurchases = getMaxExtraEquipSlots()
	if not isFiniteNumber(count) or count < 0 or count % 1 ~= 0 then
		return false, "Invalid shop purchases"
	end
	if count >= maxPurchases then
		return false, "Maximum extra equip slots reached (" .. tostring(maxPurchases) .. ")"
	end

	local context = {
		contractVersion = 1,
		action = "purchaseLegacyItem",
		itemId = "ExtraEquipSlot",
		quantity = 1,
		currency = itemDef.currency,
		amount = itemDef.cost,
	}
	return executePurchase(player, context, function()
		if not hadPurchases then
			data.shopPurchases = {}
		end
		data.shopPurchases.extraEquipSlots = math.min(count + 1, maxPurchases)
	end, function()
		if not hadPurchases then
			data.shopPurchases = nil
		else
			data.shopPurchases.extraEquipSlots = oldValue
		end
		return true
	end)
end

-- Canonical potion purchases accept only the exact V2 DTO. ExtraEquipSlot is the
-- sole retained string purchase contract; AutoHatch remains specifically gated.
function ShopService.purchaseItem(player, request)
	if not player or player.UserId == nil then
		return false, "Invalid parameters"
	end
	if request == "AutoHatch" then
		return false, "Auto-Hatch is not available yet"
	end

	local purchaseKind = nil
	if request == "ExtraEquipSlot" then
		purchaseKind = "extraEquipSlot"
	elseif isExactPotionRequest(request) then
		purchaseKind = "potion"
	else
		return false, "Invalid purchase request"
	end

	local userId = player.UserId
	if ShopService._purchaseLocks[userId] then
		return false, "Purchase already in progress"
	end
	ShopService._purchaseLocks[userId] = true

	local success = false
	local message = nil
	local state = nil
	local callOk, callError = pcall(function()
		if not ShopService._dataService or not ShopService._currencyService then
			message = "Shop service unavailable"
			return
		end
		local data = ShopService._dataService.getPlayerData(player)
		if type(data) ~= "table" then
			message = "No player data"
			return
		end
		if purchaseKind == "potion" then
			success, message, state = purchasePotion(player, request, data)
		else
			success, message, state = purchaseExtraEquipSlot(player, data)
		end
	end)
	ShopService._purchaseLocks[userId] = nil

	if not callOk then
		if type(warn) == "function" then
			warn("[ShopService] Purchase failed: " .. tostring(callError))
		end
		return false, "Purchase failed"
	end
	if not success then
		return false, message
	end

	if purchaseKind == "potion" and ShopService._potionService then
		local notifyOk, potionState = pcall(
			ShopService._potionService.notifyInventoryChanged,
			player
		)
		if notifyOk and type(potionState) == "table" then
			state.potionState = potionState
		end
	end
	fireShopUpdate(player, state)
	return true, nil, state
end

-- Legacy multipliers remain neutral unless preexisting transient state exists.
function ShopService.getShopMultiplier(player, buffType)
	if ShopService._potionService then
		return ShopService._potionService.getMultiplier(player, buffType)
	end
	if not player or not buffType then
		return 1
	end

	local buffs = removeExpiredBuffs(player, os.clock())
	if not buffs or not buffs[buffType] then
		return 1
	end

	for _, itemId in ipairs(ShopData.Order) do
		local itemDef = ShopData.Items[itemId]
		if itemDef.buffType == buffType then
			return itemDef.multiplier
		end
	end
	return 1
end

function ShopService.onPlayerRemoving(player)
	if not player then
		return
	end
	ShopService._purchaseLocks[player.UserId] = nil
	ShopService._activeBuffs[player.UserId] = nil
end

-- Rolling compatibility symbol only. QOF-18 never reads legacy buffs, chooses a
-- highest zone, or schedules from ShopService.
function ShopService._processAutoHatch()
	return false
end

return ShopService
