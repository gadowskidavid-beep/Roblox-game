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

function PetService.init(dataService, currencyService, upgradeService)
	PetService._dataService = dataService
	PetService._currencyService = currencyService
	PetService._upgradeService = upgradeService
end

-- Weighted random selection from a pet pool, respecting LuckyEggs upgrade
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

	-- Create unique pet instance
	local newPet = {
		id = HttpService:GenerateGUID(false),
		petId = petId,
		name = petDef.name,
		rarity = petDef.rarity,
		damage = petDef.baseDamage,
		equipped = false,
	}

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

-- Get maximum equipped pets for a player (base + Friendship bonus)
local function getMaxEquipped(player)
	local base = Config.MaxEquippedPetsBase
	local bonus = PetService._upgradeService.getUpgradeBonus(player, "Friendship")
	return base + (bonus or 0)
end

-- Equip a pet by instance ID
function PetService.equipPet(player, petInstanceId)
	if not player or type(petInstanceId) ~= "string" then
		return false, "Invalid parameters"
	end

	local data = PetService._dataService.getPlayerData(player)
	if not data then
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
		return false, "Maximum pets equipped (" .. tostring(maxEquipped) .. ")"
	end

	-- Find pet and equip it
	for _, pet in ipairs(data.pets) do
		if pet.id == petInstanceId then
			if pet.equipped then
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
					event:FireClient(player, pet)
				end
			end

			return true, nil
		end
	end

	return false, "Pet not found in inventory"
end

-- Unequip a pet by instance ID
function PetService.unequipPet(player, petInstanceId)
	if not player or type(petInstanceId) ~= "string" then
		return false, "Invalid parameters"
	end

	local data = PetService._dataService.getPlayerData(player)
	if not data then
		return false, "No player data"
	end

	-- Find pet and unequip it
	for _, pet in ipairs(data.pets) do
		if pet.id == petInstanceId then
			if not pet.equipped then
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
					event:FireClient(player, petInstanceId)
				end
			end

			return true, nil
		end
	end

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
function PetService.getPetDamage(pet, player)
	if not pet or not player then
		return 0
	end

	local baseDamage = pet.damage or 0
	local strongBonus = PetService._upgradeService.getUpgradeBonus(player, "StrongPets")

	if strongBonus > 0 then
		return math.floor(baseDamage * strongBonus)
	end

	return baseDamage
end

return PetService
