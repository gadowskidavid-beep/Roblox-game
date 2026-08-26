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

local ShopService = {}

-- References to other services
ShopService._dataService = nil
ShopService._currencyService = nil
ShopService._eggService = nil

-- In-memory timed buff storage: _activeBuffs[userId] = { buffType = expiryTimestamp, ... }
ShopService._activeBuffs = {}

-- Shop item definitions
ShopService.Items = {
	LuckyPotion = {
		displayName = "Lucky Potion",
		description = "2x egg luck for 5 minutes",
		cost = 100,
		currency = "diamonds",
		buffType = "luck",
		multiplier = 2,
		duration = 300, -- 5 minutes in seconds
		permanent = false,
	},
	SpeedPotion = {
		displayName = "Speed Potion",
		description = "2x walkspeed for 5 minutes",
		cost = 50,
		currency = "diamonds",
		buffType = "speed",
		multiplier = 2,
		duration = 300, -- 5 minutes in seconds
		permanent = false,
	},
	AutoHatch = {
		displayName = "Auto-Hatch",
		description = "Automatically buys your highest unlocked egg for 10 minutes",
		cost = 500,
		currency = "diamonds",
		buffType = "autoHatch",
		multiplier = 1,
		duration = 600, -- 10 minutes in seconds
		permanent = false,
	},
	ExtraEquipSlot = {
		displayName = "Extra Equip Slot",
		description = "Permanently equip +1 pet (maximum 5 purchases)",
		cost = 1000,
		currency = "diamonds",
		buffType = "equipSlot",
		multiplier = 1,
		duration = 0,
		permanent = true,
	},
}

function ShopService.init(dataService, currencyService)
	ShopService._dataService = dataService
	ShopService._currencyService = currencyService

	-- Start auto-hatch loop
	task.spawn(function()
		while true do
			task.wait(Config.AutoHatchInterval or 3)
			ShopService._processAutoHatch()
		end
	end)
end

-- Set EggService reference (called after init to avoid circular deps)
function ShopService.setEggService(eggService)
	ShopService._eggService = eggService
end

-- Purchase a shop item
function ShopService.purchaseItem(player, itemId)
	if not player or type(itemId) ~= "string" then
		return false, "Invalid parameters"
	end

	local itemDef = ShopService.Items[itemId]
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
		local maxPurchases = Config.MaxExtraEquipSlots or 5
		if purchases >= maxPurchases then
			return false, "Maximum extra equip slots reached (" .. tostring(maxPurchases) .. ")"
		end
	end

	-- Deduct currency
	local success = ShopService._currencyService.removeDiamonds(player, itemDef.cost)
	if not success then
		return false, "Not enough diamonds (need " .. tostring(itemDef.cost) .. ")"
	end

	-- Apply effect
	if itemDef.permanent then
		-- Permanent effect: Extra Equip Slot
		if not data.shopPurchases then
			data.shopPurchases = { extraEquipSlots = 0 }
		end
		data.shopPurchases.extraEquipSlots = math.clamp(
			(data.shopPurchases.extraEquipSlots or 0) + 1,
			0,
			Config.MaxExtraEquipSlots or 5
		)
	else
		-- Timed buff
		local userId = player.UserId
		if not ShopService._activeBuffs[userId] then
			ShopService._activeBuffs[userId] = {}
		end
		local expiry = os.clock() + itemDef.duration
		ShopService._activeBuffs[userId][itemDef.buffType] = expiry
	end

	-- Fire client event to update UI
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local event = remotes:FindFirstChild("ShopBuffsUpdated")
		if event then
			event:FireClient(player, ShopService.getActiveBuffs(player))
		end
	end

	return true, nil
end

-- Get active buffs for a player (returns table of { buffType = remainingSeconds })
function ShopService.getActiveBuffs(player)
	if not player then
		return {}
	end

	local userId = player.UserId
	local buffs = ShopService._activeBuffs[userId]
	if not buffs then
		return {}
	end

	local now = os.clock()
	local result = {}
	for buffType, expiry in pairs(buffs) do
		local remaining = expiry - now
		if remaining > 0 then
			result[buffType] = math.ceil(remaining)
		end
	end
	return result
end

-- Get the multiplier for a given buff type (returns 1 if not active)
function ShopService.getShopMultiplier(player, buffType)
	if not player or not buffType then
		return 1
	end

	local userId = player.UserId
	local buffs = ShopService._activeBuffs[userId]
	if not buffs then
		return 1
	end

	local expiry = buffs[buffType]
	if not expiry then
		return 1
	end

	if os.clock() < expiry then
		-- Find the matching item to get its multiplier
		for _, itemDef in pairs(ShopService.Items) do
			if itemDef.buffType == buffType then
				return itemDef.multiplier
			end
		end
		return 2 -- fallback multiplier
	end

	-- Expired, clean up
	buffs[buffType] = nil
	return 1
end

-- Process auto-hatch for players with active AutoHatch buff
function ShopService._processAutoHatch()
	local now = os.clock()
	for _, player in ipairs(Players:GetPlayers()) do
		local userId = player.UserId
		local buffs = ShopService._activeBuffs[userId]
		if buffs and buffs.autoHatch then
			if now < buffs.autoHatch then
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
						-- Auto-hatch is automation, not a free-egg faucet: every hatch
						-- uses the normal server-authoritative coin price and inventory limit.
						if targetEgg then
							task.spawn(function()
								ShopService._eggService.purchaseAndHatch(player, targetEgg)
							end)
						end
					end
				end
			else
				-- Expired, clean up
				buffs.autoHatch = nil
			end
		end
	end
end

return ShopService
