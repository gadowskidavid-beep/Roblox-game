--[[
	ShopService.lua - Shop system for timed buffs and permanent purchases
	Players spend diamonds on potions (timed buffs) or permanent upgrades.
	Timed buffs are tracked in-memory (lost on server restart, which is OK).
	Permanent effects are stored in player data (shopPurchases).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PetData = require(game.ReplicatedStorage.Shared.PetData)
local Config = require(game.ReplicatedStorage.Shared.Config)
local BalanceConfig = require(game.ReplicatedStorage.Shared.BalanceConfig)
local ShopData = require(game.ReplicatedStorage.Shared.ShopData)

local ShopService = {}

-- References to other services
ShopService._dataService = nil
ShopService._currencyService = nil
ShopService._eggService = nil
ShopService._walkSpeedRefresh = nil

-- In-memory timed buff storage: _activeBuffs[userId] = { buffType = expiryTimestamp, ... }
ShopService._activeBuffs = {}

-- Compatibility alias. ShopData is the single catalog definition.
ShopService.Items = ShopData.Items

function ShopService.init(dataService, currencyService)
	ShopService._dataService = dataService
	ShopService._currencyService = currencyService

	-- The legacy timed Auto-Hatch loop is feature-gated off until its complete
	-- shop behavior ships. Persisted hatch preferences remain untouched.
	if BalanceConfig.Shop.AutoHatchRuntimeEnabled then
		task.spawn(function()
			while true do
				task.wait(Config.AutoHatchInterval or 3)
				ShopService._processAutoHatch()
			end
		end)
	end
end

-- Set EggService reference (called after init to avoid circular deps)
function ShopService.setEggService(eggService)
	ShopService._eggService = eggService
end

-- MovementService owns the complete WalkSpeed formula. ShopService only notifies
-- it when a speed potion expires so every non-shop movement source is preserved.
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

-- Get active buffs for a player (returns table of { buffType = remainingSeconds }).
-- Expired entries are removed as the state is built.
function ShopService.getActiveBuffs(player)
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

-- Return the complete client-facing shop state. Display metadata is shared through
-- ShopData, while this mutable state is always produced authoritatively by the server.
function ShopService.getShopState(player)
	local extraEquipSlots = 0
	if player and ShopService._dataService then
		local data = ShopService._dataService.getPlayerData(player)
		if data and data.shopPurchases then
			extraEquipSlots = math.clamp(
				math.floor(data.shopPurchases.extraEquipSlots or 0),
				0,
				getMaxExtraEquipSlots()
			)
		end
	end

	return {
		buffs = ShopService.getActiveBuffs(player),
		purchases = { extraEquipSlots = extraEquipSlots },
		maxExtraEquipSlots = getMaxExtraEquipSlots(),
	}
end

-- Purchase a shop item. All validation, charging, and effect application stays server-side.
function ShopService.purchaseItem(player, itemId)
	if not player or type(itemId) ~= "string" then
		return false, "Invalid parameters"
	end
	if itemId == "AutoHatch" and not BalanceConfig.Shop.AutoHatchRuntimeEnabled then
		return false, "Auto-Hatch is not available yet"
	end

	local itemDef = ShopData.Items[itemId]
	if not itemDef then
		return false, "Unknown item: " .. tostring(itemId)
	end

	local data = ShopService._dataService.getPlayerData(player)
	if not data then
		return false, "No player data"
	end

	-- Validate permanent purchase limits before charging the player.
	if itemId == "ExtraEquipSlot" then
		local purchases = data.shopPurchases and data.shopPurchases.extraEquipSlots or 0
		local maxPurchases = getMaxExtraEquipSlots()
		if purchases >= maxPurchases then
			return false, "Maximum extra equip slots reached (" .. tostring(maxPurchases) .. ")"
		end
	end

	if itemDef.currency ~= "diamonds" then
		return false, "Unsupported shop currency"
	end
	local success = ShopService._currencyService.removeDiamonds(player, itemDef.cost)
	if not success then
		return false, "Not enough diamonds (need " .. tostring(itemDef.cost) .. ")"
	end

	if itemDef.permanent then
		if not data.shopPurchases then
			data.shopPurchases = { extraEquipSlots = 0 }
		end
		data.shopPurchases.extraEquipSlots = math.clamp(
			(data.shopPurchases.extraEquipSlots or 0) + 1,
			0,
			getMaxExtraEquipSlots()
		)
	else
		local userId = player.UserId
		if not ShopService._activeBuffs[userId] then
			ShopService._activeBuffs[userId] = {}
		end
		local now = os.clock()
		local currentExpiry = ShopService._activeBuffs[userId][itemDef.buffType] or now
		ShopService._activeBuffs[userId][itemDef.buffType] = math.max(now, currentExpiry) + itemDef.duration
	end

	local state = ShopService.getShopState(player)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local event = remotes:FindFirstChild("ShopBuffsUpdated")
		if event then
			event:FireClient(player, state)
		end
	end

	return true, nil, state
end

-- Get the multiplier for a given buff type (returns 1 if not active).
function ShopService.getShopMultiplier(player, buffType)
	if not player or not buffType then
		return 1
	end

	local buffs = removeExpiredBuffs(player, os.clock())
	if not buffs then
		return 1
	end

	if not buffs[buffType] then
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

-- Process auto-hatch for players with active AutoHatch buff
function ShopService._processAutoHatch()
	if not BalanceConfig.Shop.AutoHatchRuntimeEnabled then
		return false
	end
	local now = os.clock()
	for _, player in ipairs(Players:GetPlayers()) do
		local buffs = removeExpiredBuffs(player, now)
		if buffs and buffs.autoHatch then
			-- Buff active: determine the egg for the player's highest unlocked zone and hatch it
			if ShopService._eggService and ShopService._dataService then
				local data = ShopService._dataService.getPlayerData(player)
				if data and data.unlockedZones then
					-- Find the highest unlocked zone
					local highestZone = 1
					for _, zoneId in ipairs(data.unlockedZones) do
						if zoneId > highestZone then
							highestZone = zoneId
						end
					end
					-- Find the egg type for this zone
					local targetEgg = nil
					for eggType, eggDef in pairs(PetData.Eggs) do
						if eggDef.zone == highestZone then
							targetEgg = eggType
							break
						end
					end
					-- Auto-hatch uses the same atomic paid batch path and the player's
					-- server-validated session selection. It never falls back silently.
					if targetEgg then
						task.spawn(function()
							local batchCount = ShopService._eggService.getSelectedBatchCount(player)
							ShopService._eggService.purchaseAndHatch(player, targetEgg, batchCount, {
								bypassStation = true,
							})
						end)
					end
				end
			end
		end
	end
end

return ShopService
