--[[
	PetService.lua - Pet inventory management
	Handles hatching, equipping, unequipping, and deleting pets.
	Server-authoritative with unique IDs and validation.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(game.ReplicatedStorage.Shared.Config)
local PetData = require(game.ReplicatedStorage.Shared.PetData)

local PetService = {}

-- References to other services
PetService._dataService = nil
PetService._currencyService = nil
PetService._upgradeService = nil
PetService._masteryService = nil
PetService._shopService = nil

function PetService.init(dataService, currencyService, upgradeService)
	PetService._dataService = dataService
	PetService._currencyService = currencyService
	PetService._upgradeService = upgradeService
end

-- Set mastery service reference (called after init to avoid circular deps)
function PetService.setMasteryService(masteryService)
	PetService._masteryService = masteryService
end

-- Set shop service reference (called after init to avoid circular deps)
function PetService.setShopService(shopService)
	PetService._shopService = shopService
end

-- Weighted random selection from a pet pool, respecting LuckyEggs upgrade, BetterLuck mastery, and Lucky Potion
local function weightedRandomPet(petPool, player)
	-- Calculate total weight
	local totalWeight = 0
	local adjustedPool = {}

	for _, entry in ipairs(petPool) do
		local weight = entry.weight
		-- LuckyEggs bonus: increases weight of rarer pets
		local petDef = PetData.Pets[entry.petId]
		if petDef and petDef.rarity ~= "Common" then
			local luckyBonus = PetService._upgradeService.getUpgradeBonus(player, "LuckyEggs")
			if luckyBonus > 0 then
				weight = weight * luckyBonus
			end
			-- BetterLuck mastery bonus: further increases weight of rarer pets
			if PetService._masteryService then
				local betterLuckBonus = PetService._masteryService.getBuffBonus(player, "BetterLuck")
				if betterLuckBonus > 0 then
					weight = weight * betterLuckBonus
				end
			end
			-- Lucky Potion shop buff: further increases weight of rarer pets
			if PetService._shopService then
				local shopLuckMultiplier = PetService._shopService.getShopMultiplier(player, "luck")
				if shopLuckMultiplier > 1 then
					weight = weight * shopLuckMultiplier
				end
			end
		end
		totalWeight = totalWeight + weight
		table.insert(adjustedPool, { petId = entry.petId, weight = weight })
	end

	-- Roll random number
	local roll = math.random() * totalWeight
	local cumulative = 0

	for _, entry in ipairs(adjustedPool) do
		cumulative = cumulative + entry.weight
		if roll <= cumulative then
			return entry.petId
		end
	end

	-- Fallback: return last entry
	return adjustedPool[#adjustedPool].petId
end

-- Hatch an egg and return the new pet
-- If skipCostDeduction is true, assumes cost was already deducted by the caller (EggService)
function PetService.hatchEgg(player, eggType, skipCostDeduction)
	if not player or type(eggType) ~= "string" then
		return nil, "Invalid parameters"
	end

	-- Validate egg type exists
	local eggDef = PetData.Eggs[eggType]
	if not eggDef then
		return nil, "Unknown egg type: " .. tostring(eggType)
	end

	local data = PetService._dataService.getPlayerData(player)
	if not data then
		return nil, "No player data"
	end

	-- Get egg cost from config based on zone
	local eggZone = eggDef.zone
	local eggCost = Config.EggCosts[eggZone]
	if not eggCost then
		return nil, "No cost defined for egg zone"
	end

	-- Deduct cost (only if not already deducted by EggService)
	if not skipCostDeduction then
		if eggCost.Coins then
			local success = PetService._currencyService.removeCoins(player, eggCost.Coins)
			if not success then
				return nil, "Not enough coins"
			end
		end
	end

	-- Select random pet from pool
	local petId = weightedRandomPet(eggDef.petPool, player)
	local petDef = PetData.Pets[petId]
	if not petDef then
		return nil, "Invalid pet in pool"
	end

	-- Roll for Shiny/Rainbow variant
	local luckyBonus = PetService._upgradeService.getUpgradeBonus(player, "LuckyEggs")
	local luckyMultiplier = (luckyBonus > 0) and luckyBonus or 1
	-- BetterLuck mastery bonus also improves variant roll
	if PetService._masteryService then
		local betterLuckBonus = PetService._masteryService.getBuffBonus(player, "BetterLuck")
		if betterLuckBonus > 0 then
			luckyMultiplier = luckyMultiplier * betterLuckBonus
		end
	end
	-- Lucky Potion shop buff also improves variant roll
	if PetService._shopService then
		local shopLuckMultiplier = PetService._shopService.getShopMultiplier(player, "luck")
		if shopLuckMultiplier > 1 then
			luckyMultiplier = luckyMultiplier * shopLuckMultiplier
		end
	end
	local variant = "Normal"
	if math.random() < Config.RAINBOW_CHANCE * luckyMultiplier then
		variant = "Rainbow"
	elseif math.random() < Config.SHINY_CHANCE * luckyMultiplier then
		variant = "Shiny"
	end

	-- Set name and damage based on variant
	local petName = petDef.name
	local petDamage = petDef.baseDamage
	if variant == "Shiny" then
		petName = "Shiny " .. petDef.name
		petDamage = petDef.baseDamage * 3
	elseif variant == "Rainbow" then
		petName = "Rainbow " .. petDef.name
		petDamage = petDef.baseDamage * 5
	end

	-- Create unique pet instance
	local newPet = {
		id = HttpService:GenerateGUID(false),
		petId = petId,
		name = petName,
		rarity = petDef.rarity,
		damage = petDamage,
		variant = variant,
		equipped = false,
	}

	-- Track discovery (collection book)
	local discoveryKey
	if variant == "Normal" then
		discoveryKey = petId
	elseif variant == "Shiny" then
		discoveryKey = "Shiny_" .. petId
	elseif variant == "Rainbow" then
		discoveryKey = "Rainbow_" .. petId
	end
	if not data.discoveredPets then
		data.discoveredPets = {}
	end
	if not data.discoveredPets[discoveryKey] then
		data.discoveredPets[discoveryKey] = true
		newPet.isNewDiscovery = true
	else
		newPet.isNewDiscovery = false
	end

	-- Add to player inventory
	table.insert(data.pets, newPet)

	-- Fire inventory update event
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local event = remotes:FindFirstChild("PetInventoryUpdated")
		if event then
			event:FireClient(player, data.pets)
		end
	end

	return newPet, nil
end

-- Get maximum equipped pets for a player (base + Friendship bonus + Extra Equip Slots)
local function getMaxEquipped(player)
	local base = Config.MaxEquippedPetsBase
	local bonus = PetService._upgradeService.getUpgradeBonus(player, "Friendship")
	local extraSlots = 0
	local data = PetService._dataService.getPlayerData(player)
	if data and data.shopPurchases then
		extraSlots = data.shopPurchases.extraEquipSlots or 0
	end
	return base + (bonus or 0) + extraSlots
end

-- Equip a pet by instance ID
function PetService.equipPet(player, petInstanceId)
	print("[PetService] equipPet called for player=" .. tostring(player.Name) .. " petId=" .. tostring(petInstanceId))

	if not player or type(petInstanceId) ~= "string" then
		print("[PetService] equipPet FAILED: Invalid parameters")
		return false, "Invalid parameters"
	end

	local data = PetService._dataService.getPlayerData(player)
	if not data then
		print("[PetService] equipPet FAILED: No player data")
		return false, "No player data"
	end

	-- Count currently equipped pets
	local equippedCount = 0
	for _, pet in ipairs(data.pets) do
		if pet.equipped then
			equippedCount = equippedCount + 1
		end
	end

	-- Validate max equipped
	local maxEquipped = getMaxEquipped(player)
	if equippedCount >= maxEquipped then
		print("[PetService] equipPet FAILED: Max equipped (" .. tostring(equippedCount) .. "/" .. tostring(maxEquipped) .. ")")
		return false, "Maximum pets equipped (" .. tostring(maxEquipped) .. ")"
	end

	-- Find pet and equip it
	for _, pet in ipairs(data.pets) do
		if pet.id == petInstanceId then
			if pet.equipped then
				print("[PetService] equipPet FAILED: Pet already equipped")
				return false, "Pet already equipped"
			end
			pet.equipped = true

			-- Update equipped list
			table.insert(data.equippedPets, petInstanceId)

			-- Fire event
			local remotes = ReplicatedStorage:FindFirstChild("Remotes")
			if remotes then
				local event = remotes:FindFirstChild("PetEquipped")
				if event then
					print("[PetService] equipPet SUCCESS: Firing PetEquipped event for " .. tostring(pet.name))
					event:FireClient(player, pet)
				end
			end

			return true, nil
		end
	end

	print("[PetService] equipPet FAILED: Pet not found in inventory")
	return false, "Pet not found in inventory"
end

-- Unequip a pet by instance ID
function PetService.unequipPet(player, petInstanceId)
	print("[PetService] unequipPet called for player=" .. tostring(player.Name) .. " petId=" .. tostring(petInstanceId))

	if not player or type(petInstanceId) ~= "string" then
		print("[PetService] unequipPet FAILED: Invalid parameters")
		return false, "Invalid parameters"
	end

	local data = PetService._dataService.getPlayerData(player)
	if not data then
		print("[PetService] unequipPet FAILED: No player data")
		return false, "No player data"
	end

	-- Find pet and unequip it
	for _, pet in ipairs(data.pets) do
		if pet.id == petInstanceId then
			if not pet.equipped then
				print("[PetService] unequipPet FAILED: Pet is not equipped (pet.equipped=" .. tostring(pet.equipped) .. ")")
				return false, "Pet is not equipped"
			end
			pet.equipped = false

			-- Remove from equipped list
			for i, id in ipairs(data.equippedPets) do
				if id == petInstanceId then
					table.remove(data.equippedPets, i)
					break
				end
			end

			-- Fire event
			local remotes = ReplicatedStorage:FindFirstChild("Remotes")
			if remotes then
				local event = remotes:FindFirstChild("PetUnequipped")
				if event then
					print("[PetService] unequipPet SUCCESS: Firing PetUnequipped event for " .. tostring(pet.name))
					event:FireClient(player, petInstanceId)
				end
			end

			return true, nil
		end
	end

	print("[PetService] unequipPet FAILED: Pet not found in inventory (searched " .. tostring(#data.pets) .. " pets)")
	return false, "Pet not found in inventory"
end

-- Delete a single pet by instance ID
function PetService.deletePet(player, petInstanceId)
	if not player or type(petInstanceId) ~= "string" then
		return false, "Invalid parameters"
	end

	local data = PetService._dataService.getPlayerData(player)
	if not data then
		return false, "No player data"
	end

	for i, pet in ipairs(data.pets) do
		if pet.id == petInstanceId then
			-- Unequip if equipped
			if pet.equipped then
				for j, id in ipairs(data.equippedPets) do
					if id == petInstanceId then
						table.remove(data.equippedPets, j)
						break
					end
				end
			end
			table.remove(data.pets, i)

			-- Fire inventory update
			local remotes = ReplicatedStorage:FindFirstChild("Remotes")
			if remotes then
				local event = remotes:FindFirstChild("PetInventoryUpdated")
				if event then
					event:FireClient(player, data.pets)
				end
			end

			return true, nil
		end
	end

	return false, "Pet not found in inventory"
end

-- Delete multiple pets by instance IDs (bulk operation)
function PetService.deletePets(player, petInstanceIds)
	if not player or type(petInstanceIds) ~= "table" then
		return false, "Invalid parameters"
	end

	local data = PetService._dataService.getPlayerData(player)
	if not data then
		return false, "No player data"
	end

	-- Validate all IDs exist and belong to player
	local idsToDelete = {}
	for _, id in ipairs(petInstanceIds) do
		if type(id) == "string" then
			idsToDelete[id] = true
		end
	end

	-- Remove pets from inventory (iterate in reverse to safely remove)
	for i = #data.pets, 1, -1 do
		local pet = data.pets[i]
		if idsToDelete[pet.id] then
			-- Unequip if equipped
			if pet.equipped then
				for j, id in ipairs(data.equippedPets) do
					if id == pet.id then
						table.remove(data.equippedPets, j)
						break
					end
				end
			end
			table.remove(data.pets, i)
		end
	end

	-- Fire inventory update
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local event = remotes:FindFirstChild("PetInventoryUpdated")
		if event then
			event:FireClient(player, data.pets)
		end
	end

	return true, nil
end

-- Get player's pet inventory
function PetService.getInventory(player)
	if not player then
		return {}
	end

	local data = PetService._dataService.getPlayerData(player)
	if not data then
		return {}
	end

	return data.pets
end

-- Calculate effective pet damage with StrongPets upgrade multiplier
-- Note: variant (Shiny 3x, Rainbow 5x) and golden (2x) multipliers are already
-- baked into pet.damage at creation time (hatchEgg / convertToGoldenPet).
-- Only the StrongPets upgrade bonus is applied at runtime to avoid double-multiplying.
function PetService.getPetDamage(pet, player)
	if not pet or not player then
		return 0
	end

	local baseDamage = pet.damage or 0
	local strongBonus = PetService._upgradeService.getUpgradeBonus(player, "StrongPets")

	if strongBonus > 0 then
		baseDamage = math.floor(baseDamage * strongBonus)
	end

	return baseDamage
end

-- Golden conversion chance table: index = number of pets sacrificed, value = success chance (0-1)
local GOLDEN_CHANCES = {
	[1] = 0.13,
	[2] = 0.26,
	[3] = 0.39,
	[4] = 0.50,
	[5] = 0.63,
	[6] = 0.88,
	[7] = 1.00,
}

-- Convert pets into a golden pet (multi-pet sacrifice with chance)
-- petInstanceIds: table of 1-7 pet instance IDs (all must be same petId/type)
-- Returns: { success = bool, goldenPet = pet|nil, chance = number }
function PetService.convertToGoldenPet(player, petInstanceIds)
	if not player or type(petInstanceIds) ~= "table" then
		return nil, "Invalid parameters"
	end

	local count = #petInstanceIds
	if count < 1 or count > 7 then
		return nil, "Must sacrifice between 1 and 7 pets"
	end

	local data = PetService._dataService.getPlayerData(player)
	if not data then
		return nil, "No player data"
	end

	-- Find all pets and validate
	local foundPets = {}
	local requiredPetId = nil

	for _, instanceId in ipairs(petInstanceIds) do
		if type(instanceId) ~= "string" then
			return nil, "Invalid pet ID in list"
		end

		local foundPet = nil
		for _, pet in ipairs(data.pets) do
			if pet.id == instanceId then
				foundPet = pet
				break
			end
		end

		if not foundPet then
			return nil, "Pet not found in inventory: " .. tostring(instanceId)
		end

		if foundPet.golden then
			return nil, "Cannot sacrifice a golden pet"
		end

		if foundPet.equipped then
			return nil, "Unequip pet before converting: " .. tostring(foundPet.name)
		end

		-- Enforce all pets must be the same type (petId)
		if requiredPetId == nil then
			requiredPetId = foundPet.petId
		elseif foundPet.petId ~= requiredPetId then
			return nil, "All pets must be the same type"
		end

		table.insert(foundPets, foundPet)
	end

	-- Check for duplicate instance IDs
	local idSet = {}
	for _, instanceId in ipairs(petInstanceIds) do
		if idSet[instanceId] then
			return nil, "Duplicate pet ID in list"
		end
		idSet[instanceId] = true
	end

	-- Calculate chance
	local chance = GOLDEN_CHANCES[count] or 0.13

	-- Roll for success
	local roll = math.random()
	local success = roll <= chance

	-- Remove ALL sacrificed pets from inventory (regardless of success or failure)
	local idsToRemove = {}
	for _, instanceId in ipairs(petInstanceIds) do
		idsToRemove[instanceId] = true
	end

	for i = #data.pets, 1, -1 do
		if idsToRemove[data.pets[i].id] then
			-- Also remove from equipped list if somehow equipped (extra safety)
			if data.pets[i].equipped then
				for j, eqId in ipairs(data.equippedPets) do
					if eqId == data.pets[i].id then
						table.remove(data.equippedPets, j)
						break
					end
				end
			end
			table.remove(data.pets, i)
		end
	end

	local goldenPet = nil

	if success then
		-- Create a new golden pet based on the sacrificed type
		local petDef = PetData.Pets[requiredPetId]
		if petDef then
			goldenPet = {
				id = HttpService:GenerateGUID(false),
				petId = requiredPetId,
				name = "Golden " .. petDef.name,
				rarity = petDef.rarity,
				damage = petDef.baseDamage * 2,
				golden = true,
				equipped = false,
			}
			table.insert(data.pets, goldenPet)

			-- Track golden discovery (collection book)
			local goldenKey = "Golden_" .. requiredPetId
			if not data.discoveredPets then
				data.discoveredPets = {}
			end
			if not data.discoveredPets[goldenKey] then
				data.discoveredPets[goldenKey] = true
			end
		end
	end

	-- Fire inventory update event
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local event = remotes:FindFirstChild("PetInventoryUpdated")
		if event then
			event:FireClient(player, data.pets)
		end
	end

	return { success = success, goldenPet = goldenPet, chance = chance }, nil
end

return PetService
