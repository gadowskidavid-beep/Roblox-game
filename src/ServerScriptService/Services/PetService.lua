--[[
	PetService.lua - Pet inventory management
	Handles hatching, equipping, unequipping, and deleting pets.
	Server-authoritative with unique IDs and validation.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(game.ReplicatedStorage.Shared.Config)
local BalanceConfig = require(game.ReplicatedStorage.Shared.BalanceConfig)
local PetData = require(game.ReplicatedStorage.Shared.PetData)
local PetHatchMath = require(game.ReplicatedStorage.Shared.PetHatchMath)
local PetVariantMath = require(game.ReplicatedStorage.Shared.PetVariantMath)
local PetVariantPresentation = require(game.ReplicatedStorage.Shared.PetVariantPresentation)
local PetEnchantMath = require(game.ReplicatedStorage.Shared.PetEnchantMath)
local PetDex = require(game.ReplicatedStorage.Shared.PetDex)

local PetService = {}

-- References to other services
PetService._dataService = nil
PetService._currencyService = nil
PetService._upgradeService = nil
PetService._masteryService = nil
PetService._shopService = nil
PetService._upgradeTreeService = nil

-- Shared per-player lease used by every economic pet mutation. Opaque table
-- identity prevents stale cleanup/finally paths from releasing a newer owner.
PetService._inventoryMutationLeases = {}
PetService._inventoryMutationIncarnations = {}

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

local function projectPets(pets)
	local projected = {}
	if type(pets) ~= "table" then
		return projected
	end
	for index, pet in ipairs(pets) do
		projected[index] = deepCopy(pet)
	end
	return projected
end

local function isFiniteNumber(value)
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
end

-- Capacity sources are external service/profile values. Slot bonuses are always
-- non-negative whole numbers; malformed, negative, or non-finite values are inert.
local function safeSlotBonus(value, maximum)
	if not isFiniteNumber(value) or value <= 0 then
		return 0
	end
	local bonus = math.floor(value)
	if maximum then
		bonus = math.min(bonus, maximum)
	end
	return bonus
end

function PetService.init(dataService, currencyService, upgradeService)
	PetService._dataService = dataService
	PetService._currencyService = currencyService
	PetService._upgradeService = upgradeService
	PetService._inventoryMutationLeases = {}
	PetService._inventoryMutationIncarnations = {}
end

function PetService.beginInventoryMutation(player, owner)
	local userId = player and player.UserId
	if not isFiniteNumber(userId) or userId % 1 ~= 0 then
		return nil
	end
	if type(PetService._dataService) == "table"
		and type(PetService._dataService.isMutationAdmissionOpen) == "function"
		and PetService._dataService.isMutationAdmissionOpen(player) ~= true then
		return nil
	end
	if PetService._inventoryMutationLeases[userId] ~= nil then
		return nil
	end
	local lease = {
		player = player,
		owner = owner,
		incarnation = PetService._inventoryMutationIncarnations[userId] or 0,
	}
	PetService._inventoryMutationLeases[userId] = lease
	return lease
end

function PetService.isInventoryMutationIdle(player)
	local userId = player and player.UserId
	return isFiniteNumber(userId)
		and userId % 1 == 0
		and PetService._inventoryMutationLeases[userId] == nil
end

function PetService.isInventoryMutationCurrent(player, lease)
	local userId = player and player.UserId
	return type(lease) == "table"
		and lease.player == player
		and PetService._inventoryMutationLeases[userId] == lease
		and (PetService._inventoryMutationIncarnations[userId] or 0) == lease.incarnation
end

function PetService.endInventoryMutation(player, lease, mutated)
	if not PetService.isInventoryMutationCurrent(player, lease) then
		return false
	end
	local userId = player.UserId
	if mutated == true then
		PetService._inventoryMutationIncarnations[userId] = lease.incarnation + 1
	end
	PetService._inventoryMutationLeases[userId] = nil
	return true
end

local function acquireInventoryMutation(player, owner, suppliedLease)
	if suppliedLease ~= nil then
		if PetService.isInventoryMutationCurrent(player, suppliedLease) then
			return suppliedLease, false
		end
		return nil, false
	end
	local lease = PetService.beginInventoryMutation(player, owner)
	return lease, lease ~= nil
end

local function withInventoryMutation(player, owner, callback)
	local lease = PetService.beginInventoryMutation(player, owner)
	if not lease then
		return false, "Pet inventory mutation already in progress"
	end
	local ok, result, resultError = xpcall(callback, debug.traceback)
	local mutated = ok and result == true
	local released = PetService.endInventoryMutation(player, lease, mutated)
	if not ok then
		return false, "Pet inventory mutation failed safely"
	end
	if not released then
		-- Exact identity prevents an old finally from releasing a newer owner. The
		-- current lease remains held fail-closed if release cannot be proven.
		return false, "Pet inventory mutation settlement failed"
	end
	return result, resultError
end

-- Set mastery service reference (called after init to avoid circular deps)
function PetService.setMasteryService(masteryService)
	PetService._masteryService = masteryService
end

-- Set shop service reference (called after init to avoid circular deps)
function PetService.setShopService(shopService)
	PetService._shopService = shopService
end

function PetService.setUpgradeTreeService(upgradeTreeService)
	PetService._upgradeTreeService = upgradeTreeService
end

function PetService.getHatchEntitlements(player)
	local neutral = {
		eggQualityMultiplier = 1,
		generalLuckMultiplier = 1,
		directVariantMultipliers = { Golden = 1, Rainbow = 1, Shiny = 1 },
	}
	if not PetService._upgradeTreeService then
		return neutral
	end
	local entitlements = PetService._upgradeTreeService.getEntitlements(player)
	if type(entitlements) ~= "table" then
		return neutral
	end
	return {
		eggQualityMultiplier = entitlements.eggQualityMultiplier,
		generalLuckMultiplier = entitlements.generalLuckMultiplier,
		directVariantMultipliers = type(entitlements.directVariantMultipliers) == "table"
			and entitlements.directVariantMultipliers
			or neutral.directVariantMultipliers,
	}
end

-- Resolve every currently active server-side hatch luck source once per egg.
function PetService.getHatchLuckMultiplier(player, hatchEntitlements)
	local questLuck = 1
	if PetService._upgradeService then
		questLuck = PetService._upgradeService.getUpgradeBonus(player, "LuckyEggs")
	end

	local masteryLuck = 1
	if PetService._masteryService then
		masteryLuck = PetService._masteryService.getBuffBonus(player, "BetterLuck")
	end

	local shopLuck = 1
	if PetService._shopService then
		shopLuck = PetService._shopService.getShopMultiplier(player, "luck")
	end

	local treeLuck = 1
	if type(hatchEntitlements) == "table" then
		treeLuck = hatchEntitlements.generalLuckMultiplier
	elseif PetService._upgradeTreeService then
		local entitlements = PetService.getHatchEntitlements(player)
		treeLuck = entitlements.generalLuckMultiplier
	end

	return PetHatchMath.combineLuckMultipliers(
		questLuck,
		masteryLuck,
		shopLuck,
		treeLuck
	)
end

-- Weighted species selection respects the same composed luck while bounding its
-- influence independently from direct Gold/Rainbow/Shiny chance caps.
local function weightedRandomPet(petPool, luckMultiplier, eggQualityMultiplier)
	local totalWeight = 0
	local adjustedPool = {}
	local speciesMultiplier = PetHatchMath.getSpeciesMultiplier(
		luckMultiplier,
		eggQualityMultiplier
	)

	for _, entry in ipairs(petPool) do
		local weight = entry.weight
		local petDef = PetData.Pets[entry.petId]
		if petDef and petDef.rarity ~= "Common" then
			weight = weight * speciesMultiplier
		end
		totalWeight = totalWeight + weight
		table.insert(adjustedPool, { petId = entry.petId, weight = weight })
	end

	if #adjustedPool == 0 or totalWeight <= 0 then
		return nil
	end

	local roll = math.random() * totalWeight
	local cumulative = 0
	for _, entry in ipairs(adjustedPool) do
		cumulative = cumulative + entry.weight
		if roll <= cumulative then
			return entry.petId
		end
	end
	return adjustedPool[#adjustedPool].petId
end

-- Get the server-authoritative inventory capacity for a player.
-- Formula: clamp(100 + ExtraSlots quest + tree Storage, 100, 250).
function PetService.getMaxInventory(player)
	local questBonus = 0
	if PetService._upgradeService then
		questBonus = safeSlotBonus(PetService._upgradeService.getUpgradeBonus(player, "ExtraSlots"))
	end

	local treeBonus = 0
	if PetService._upgradeTreeService then
		local entitlements = PetService._upgradeTreeService.getEntitlements(player)
		if type(entitlements) == "table" then
			treeBonus = safeSlotBonus(entitlements.storageBonusSlots)
		end
	end

	return math.clamp(
		BalanceConfig.Limits.PetInventoryBase + questBonus + treeBonus,
		BalanceConfig.Limits.PetInventoryBase,
		BalanceConfig.Limits.PetInventoryAbsolute
	)
end

function PetService.canAddPets(player, count)
	if type(count) ~= "number" or count ~= count or count == math.huge or count == -math.huge
		or count % 1 ~= 0 or count < 1 then
		return false, "Invalid pet count"
	end
	local data = PetService._dataService.getPlayerData(player)
	if not data or type(data.pets) ~= "table" then
		return false, "No player data"
	end
	local capacity = PetService.getMaxInventory(player)
	if #data.pets + count > capacity then
		return false, "Pet inventory needs " .. tostring(count) .. " free slots (" .. tostring(capacity) .. " max)"
	end
	return true
end

function PetService.canAddPet(player)
	return PetService.canAddPets(player, 1)
end

-- Legacy mirrors remain additive while canonical six-state keys own discovery.
function PetService.getLegacyDiscoveryKey(petId, baseVariant, isShiny)
	return PetDex.getLegacyKey(petId, baseVariant, isShiny == true)
end

function PetService.getDiscoveryKey(petId, baseVariant, isShiny)
	return PetDex.getCanonicalKey(petId, baseVariant, isShiny == true)
end

local function copyBooleanMap(input)
	local output = {}
	if type(input) ~= "table" then
		return output
	end
	for key, value in pairs(input) do
		if type(key) == "string" and value == true then
			output[key] = true
		end
	end
	return output
end

local function buildPreparedPet(eggDef, luckMultiplier, hatchEntitlements, discovered, shinyBoosted)
	local petId = weightedRandomPet(
		eggDef.petPool,
		luckMultiplier,
		hatchEntitlements.eggQualityMultiplier
	)
	local petDef = petId and PetData.Pets[petId] or nil
	if not petDef then
		return nil, "Invalid pet in pool"
	end

	local directVariantMultipliers = hatchEntitlements.directVariantMultipliers
	if shinyBoosted == true then
		directVariantMultipliers = {
			Golden = directVariantMultipliers.Golden,
			Rainbow = directVariantMultipliers.Rainbow,
			Shiny = (isFiniteNumber(directVariantMultipliers.Shiny)
				and math.max(1, directVariantMultipliers.Shiny) or 1)
				* BalanceConfig.Potions.Catalog.ShinyPotion.multiplier,
		}
	end
	local baseVariant, isShiny = PetHatchMath.rollOutcome(
		math.random(),
		math.random(),
		luckMultiplier,
		directVariantMultipliers
	)
	local presentation = PetVariantPresentation.resolve({
		petId = petId,
		variant = baseVariant,
		shiny = isShiny,
	})
	local newPet = {
		id = HttpService:GenerateGUID(false),
		petId = petId,
		name = presentation.displayPetName,
		rarity = petDef.rarity,
		damage = PetVariantMath.getBaseDamage(petId, baseVariant, isShiny),
		variant = baseVariant,
		shiny = isShiny,
		golden = baseVariant == "Golden",
		favorite = false,
		equipped = false,
	}

	local discoveryKeys = PetDex.getWriteKeys(petId, baseVariant, isShiny)
	if not discoveryKeys then
		return nil, "Invalid pet discovery state"
	end
	newPet.isNewDiscovery = discovered[discoveryKeys[1]] ~= true
	for _, discoveryKey in ipairs(discoveryKeys) do
		discovered[discoveryKey] = true
	end
	return newPet, discoveryKeys
end

-- Prepare every random outcome without mutating inventory, discovery, currency,
-- quests, or replication. EggService can therefore reject or roll back a whole
-- batch instead of exposing partially completed hatches.
function PetService.prepareHatchBatch(player, eggType, count, options)
	if not player or type(eggType) ~= "string" then
		return nil, "Invalid parameters"
	end
	local maximumCount = BalanceConfig.Hatch.MultiOpen[#BalanceConfig.Hatch.MultiOpen].eggCount
	if type(count) ~= "number" or count % 1 ~= 0 or count < 1 or count > maximumCount then
		return nil, "Invalid hatch count"
	end
	local eggDef = PetData.Eggs[eggType]
	if not eggDef then
		return nil, "Unknown egg type: " .. tostring(eggType)
	end
	local data = PetService._dataService.getPlayerData(player)
	if not data or type(data.pets) ~= "table" then
		return nil, "No player data"
	end
	local hasSpace, capacityError = PetService.canAddPets(player, count)
	if not hasSpace then
		return nil, capacityError
	end
	if not Config.EggCosts[eggDef.zone] then
		return nil, "No cost defined for egg zone"
	end

	local hatchEntitlements = PetService.getHatchEntitlements(player)
	local luckMultiplier = PetService.getHatchLuckMultiplier(player, hatchEntitlements)
	local shinyBoostCount = type(options) == "table" and options.shinyBoostCount or 0
	if not isFiniteNumber(shinyBoostCount) or shinyBoostCount < 0 then shinyBoostCount = 0 end
	shinyBoostCount = math.min(count, math.floor(shinyBoostCount))
	local discovered = copyBooleanMap(data.discoveredPets)
	local petsTable = data.pets
	local originalPets = {}
	for index, pet in ipairs(petsTable) do
		originalPets[index] = pet
	end
	local discoveryTable = type(data.discoveredPets) == "table" and data.discoveredPets or nil
	local discoverySnapshot = copyBooleanMap(discoveryTable)
	local pets = {}
	local newDiscoveryKeys = {}
	for index = 1, count do
		local pet, discoveryKeysOrError = buildPreparedPet(
			eggDef,
			luckMultiplier,
			hatchEntitlements,
			discovered,
			index <= shinyBoostCount
		)
		if not pet then
			return nil, discoveryKeysOrError
		end
		table.insert(pets, pet)
		for _, discoveryKey in ipairs(discoveryKeysOrError) do
			if discoverySnapshot[discoveryKey] ~= true then
				newDiscoveryKeys[discoveryKey] = true
			end
		end
	end

	return {
		player = player,
		data = data,
		eggType = eggType,
		pets = pets,
		newDiscoveryKeys = newDiscoveryKeys,
		petsTable = petsTable,
		originalPets = originalPets,
		discoveryTable = discoveryTable,
		discoverySnapshot = discoverySnapshot,
		originalPetCount = #data.pets,
		discoveryTableWasNil = type(data.discoveredPets) ~= "table",
		discoveryWrites = {},
		mutationStarted = false,
		committed = false,
	}, nil
end

local function hatchSnapshotMatches(prepared)
	local data = prepared.data
	if PetService._dataService.getPlayerData(prepared.player) ~= data
		or type(data) ~= "table" or data.pets ~= prepared.petsTable
		or #data.pets ~= #prepared.originalPets then
		return false
	end
	for index, pet in ipairs(prepared.originalPets) do
		if data.pets[index] ~= pet then
			return false
		end
	end
	if data.discoveredPets ~= prepared.discoveryTable then
		return false
	end
	if prepared.discoveryTable then
		for key, value in pairs(prepared.discoveryTable) do
			if prepared.discoverySnapshot[key] ~= value then return false end
		end
		for key, value in pairs(prepared.discoverySnapshot) do
			if prepared.discoveryTable[key] ~= value then return false end
		end
	end
	return true
end

local function commitHatchBatchUnlocked(player, prepared)
	if type(prepared) ~= "table" or prepared.player ~= player or prepared.committed then
		return false, "Invalid prepared hatch"
	end
	if not hatchSnapshotMatches(prepared) then
		return false, "Inventory changed during hatch"
	end
	local data = prepared.data
	local hasSpace, capacityError = PetService.canAddPets(player, #prepared.pets)
	if not hasSpace then
		return false, capacityError
	end

	prepared.mutationStarted = true
	if type(data.discoveredPets) ~= "table" then
		data.discoveredPets = {}
	end
	prepared.discoveryWriteTable = data.discoveredPets
	for discoveryKey in pairs(prepared.newDiscoveryKeys) do
		prepared.discoveryWrites[discoveryKey] = {
			present = rawget(data.discoveredPets, discoveryKey) ~= nil,
			value = rawget(data.discoveredPets, discoveryKey),
		}
		data.discoveredPets[discoveryKey] = true
	end
	for _, pet in ipairs(prepared.pets) do
		table.insert(data.pets, pet)
	end
	prepared.committed = true
	return true
end

function PetService.commitHatchBatch(player, prepared, suppliedLease)
	local lease, ownsLease = acquireInventoryMutation(player, "PetService.commitHatchBatch", suppliedLease)
	if not lease then return false, "Pet inventory mutation already in progress" end
	local ok, committed, commitError = xpcall(function()
		return commitHatchBatchUnlocked(player, prepared)
	end, debug.traceback)
	if ownsLease then
		PetService.endInventoryMutation(player, lease, ok and committed == true)
	end
	if not ok then return false, "Hatch commit failed safely" end
	return committed, commitError
end

local function rollbackHatchBatchUnlocked(prepared)
	if type(prepared) ~= "table" or not prepared.mutationStarted or type(prepared.data) ~= "table" then
		return true
	end
	local data = prepared.data
	if data.pets ~= prepared.petsTable
		or #data.pets ~= prepared.originalPetCount + #prepared.pets then
		return false
	end
	for index, pet in ipairs(prepared.pets) do
		if data.pets[prepared.originalPetCount + index] ~= pet then
			return false
		end
	end
	for _ = 1, #prepared.pets do
		table.remove(data.pets)
	end
	if data.discoveredPets ~= prepared.discoveryWriteTable then
		return false
	end
	for discoveryKey, previous in pairs(prepared.discoveryWrites) do
		if rawget(data.discoveredPets, discoveryKey) ~= true then
			return false
		end
		if previous.present then
			data.discoveredPets[discoveryKey] = previous.value
		else
			data.discoveredPets[discoveryKey] = nil
		end
	end
	if prepared.discoveryTableWasNil and next(data.discoveredPets) == nil then
		data.discoveredPets = nil
	end
	prepared.mutationStarted = false
	prepared.committed = false
	return true
end

function PetService.rollbackHatchBatch(prepared, suppliedLease)
	local player = type(prepared) == "table" and prepared.player or nil
	if not player then return false end
	local lease, ownsLease = acquireInventoryMutation(player, "PetService.rollbackHatchBatch", suppliedLease)
	if not lease then return false end
	local ok, restored = xpcall(function()
		return rollbackHatchBatchUnlocked(prepared)
	end, debug.traceback)
	if ownsLease then
		PetService.endInventoryMutation(player, lease, ok and restored == true)
	end
	return ok and restored == true
end

function PetService.replicateInventory(player)
	local data = PetService._dataService.getPlayerData(player)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local event = remotes and remotes:FindFirstChild("PetInventoryUpdated")
	if data and event then
		pcall(event.FireClient, event, player, projectPets(data.pets))
	end
end

-- Compatibility single-roll API used by campaign rewards. Paid player hatches
-- are orchestrated by EggService through the atomic batch methods above.
local function hatchEggUnlocked(player, eggType, skipCostDeduction, inventoryLease)
	local prepared, prepareError = PetService.prepareHatchBatch(player, eggType, 1)
	if not prepared then
		return nil, prepareError
	end

	local paidAmount = 0
	if not skipCostDeduction then
		local eggDef = PetData.Eggs[eggType]
		local eggCost = eggDef and Config.EggCosts[eggDef.zone]
		paidAmount = eggCost and eggCost.Coins or 0
		if paidAmount > 0 then
			local spent = PetService._currencyService.spend
				and PetService._currencyService.spend(player, "coins", paidAmount)
				or PetService._currencyService.removeCoins(player, paidAmount)
			if not spent then
				return nil, "Not enough coins"
			end
		end
	end

	local callSucceeded, committed, commitError = pcall(
		PetService.commitHatchBatch,
		player,
		prepared,
		inventoryLease
	)
	if not callSucceeded or not committed then
		PetService.rollbackHatchBatch(prepared, inventoryLease)
		if paidAmount > 0 then
			PetService._currencyService.creditRaw(player, "coins", paidAmount)
		end
		return nil, callSucceeded and commitError or "Hatch failed safely"
	end
	PetService.replicateInventory(player)
	return prepared.pets[1], nil
end

function PetService.hatchEgg(player, eggType, skipCostDeduction)
	local lease = PetService.beginInventoryMutation(player, "PetService.hatchEgg")
	if not lease then
		return nil, "Pet inventory mutation already in progress"
	end
	local ok, pet, hatchError = xpcall(function()
		return hatchEggUnlocked(player, eggType, skipCostDeduction, lease)
	end, debug.traceback)
	local released = PetService.endInventoryMutation(player, lease, ok and pet ~= nil)
	if not ok then return nil, "Hatch failed safely" end
	if not released then return nil, "Hatch settlement failed" end
	return pet, hatchError
end

-- Public authoritative equip capacity.
-- Formula: clamp(3 + Friendship quest + MorePetSlots mastery + legacy shop
-- + tree Pet Equip, 3, 12).
function PetService.getMaxEquipped(player)
	local friendshipBonus = 0
	if PetService._upgradeService then
		friendshipBonus = safeSlotBonus(PetService._upgradeService.getUpgradeBonus(player, "Friendship"))
	end

	local masteryBonus = 0
	if PetService._masteryService then
		masteryBonus = safeSlotBonus(PetService._masteryService.getBuffBonus(player, "MorePetSlots"))
	end

	local legacyShopBonus = 0
	local data = PetService._dataService and PetService._dataService.getPlayerData(player)
	if data and type(data.shopPurchases) == "table" then
		legacyShopBonus = safeSlotBonus(
			data.shopPurchases.extraEquipSlots,
			BalanceConfig.Limits.ExtraEquipSlots
		)
	end

	local treeBonus = 0
	if PetService._upgradeTreeService then
		local entitlements = PetService._upgradeTreeService.getEntitlements(player)
		if type(entitlements) == "table" then
			treeBonus = safeSlotBonus(entitlements.petEquipBonusSlots)
		end
	end

	return math.clamp(
		BalanceConfig.Limits.EquippedPetsBase
			+ friendshipBonus
			+ masteryBonus
			+ legacyShopBonus
			+ treeBonus,
		BalanceConfig.Limits.EquippedPetsBase,
		BalanceConfig.Limits.EquippedPetsAbsolute
	)
end

-- Equip a pet by instance ID
local function equipPetUnlocked(player, petInstanceId)
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
	local maxEquipped = PetService.getMaxEquipped(player)
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
					pcall(event.FireClient, event, player, deepCopy(pet))
				end
			end

			return true, nil
		end
	end

	print("[PetService] equipPet FAILED: Pet not found in inventory")
	return false, "Pet not found in inventory"
end

function PetService.equipPet(player, petInstanceId)
	return withInventoryMutation(player, "PetService.equipPet", function()
		return equipPetUnlocked(player, petInstanceId)
	end)
end

-- Unequip a pet by instance ID
local function unequipPetUnlocked(player, petInstanceId)
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
					pcall(event.FireClient, event, player, petInstanceId)
				end
			end

			return true, nil
		end
	end

	print("[PetService] unequipPet FAILED: Pet not found in inventory (searched " .. tostring(#data.pets) .. " pets)")
	return false, "Pet not found in inventory"
end

function PetService.unequipPet(player, petInstanceId)
	return withInventoryMutation(player, "PetService.unequipPet", function()
		return unequipPetUnlocked(player, petInstanceId)
	end)
end

local function fireInventoryUpdate(player, pets)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then return end
	local event = remotes:FindFirstChild("PetInventoryUpdated")
	if event then
		pcall(event.FireClient, event, player, projectPets(pets))
	end
end

-- Set a pet's favorite state by instance ID.
local function setPetFavoriteUnlocked(player, petInstanceId, isFavorite)
	if not player or type(petInstanceId) ~= "string" or type(isFavorite) ~= "boolean" then
		return false, "Invalid parameters"
	end

	local data = PetService._dataService.getPlayerData(player)
	if not data then
		return false, "No player data"
	end

	for _, pet in ipairs(data.pets) do
		if pet.id == petInstanceId then
			pet.favorite = isFavorite
			fireInventoryUpdate(player, data.pets)
			return true, nil
		end
	end

	return false, "Pet not found in inventory"
end

function PetService.setPetFavorite(player, petInstanceId, isFavorite)
	return withInventoryMutation(player, "PetService.setPetFavorite", function()
		return setPetFavoriteUnlocked(player, petInstanceId, isFavorite)
	end)
end

-- Delete a single pet by instance ID
local function deletePetUnlocked(player, petInstanceId)
	if not player or type(petInstanceId) ~= "string" then
		return false, "Invalid parameters"
	end

	local data = PetService._dataService.getPlayerData(player)
	if not data then
		return false, "No player data"
	end

	for i, pet in ipairs(data.pets) do
		if pet.id == petInstanceId then
			if pet.favorite == true then
				return false, "Favorited pets cannot be deleted"
			end

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

			fireInventoryUpdate(player, data.pets)

			return true, nil
		end
	end

	return false, "Pet not found in inventory"
end

function PetService.deletePet(player, petInstanceId)
	return withInventoryMutation(player, "PetService.deletePet", function()
		return deletePetUnlocked(player, petInstanceId)
	end)
end

-- Delete multiple pets by instance IDs (bulk operation)
local function deletePetsUnlocked(player, petInstanceIds)
	if not player or type(petInstanceIds) ~= "table" then
		return false, "Invalid parameters"
	end

	local count = #petInstanceIds
	if count < 1 or count > (Config.MaxPetInventoryAbsolute or 250) then
		return false, "Invalid number of pets"
	end

	local data = PetService._dataService.getPlayerData(player)
	if not data then
		return false, "No player data"
	end

	-- Preflight the entire request before mutating anything, so a protected or
	-- stale ID cannot cause a partial delete.
	local petById = {}
	for _, pet in ipairs(data.pets) do
		petById[pet.id] = pet
	end

	local idsToDelete = {}
	for _, id in ipairs(petInstanceIds) do
		if type(id) ~= "string" or id == "" then
			return false, "Invalid pet ID in list"
		end
		if idsToDelete[id] then
			return false, "Duplicate pet ID in list"
		end
		local pet = petById[id]
		if not pet then
			return false, "Pet not found in inventory: " .. tostring(id)
		end
		if pet.favorite == true then
			return false, "Favorited pets cannot be deleted"
		end
		idsToDelete[id] = true
	end

	-- Remove pets from inventory (iterate in reverse to safely remove).
	for i = #data.pets, 1, -1 do
		local pet = data.pets[i]
		if idsToDelete[pet.id] then
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

	fireInventoryUpdate(player, data.pets)
	return true, nil
end

function PetService.deletePets(player, petInstanceIds)
	return withInventoryMutation(player, "PetService.deletePets", function()
		return deletePetsUnlocked(player, petInstanceIds)
	end)
end

-- Prepare a canonical variant conversion without mutating inventory, discovery,
-- currency, quests, or replication. MachineService owns payment and chance.
function PetService.prepareVariantConversion(player, petInstanceIds, inputVariant, outputVariant)
	if not player or type(petInstanceIds) ~= "table" then
		return nil, "Invalid parameters"
	end
	-- Reject before any iteration, length, or indexing so caller-controlled
	-- metamethods cannot execute inside this admission path.
	if getmetatable(petInstanceIds) ~= nil then
		return nil, "Pet IDs must be a plain dense list"
	end
	if (inputVariant ~= "Normal" and inputVariant ~= "Golden" and inputVariant ~= "Rainbow")
		or (outputVariant ~= "Normal" and outputVariant ~= "Golden" and outputVariant ~= "Rainbow")
		or inputVariant == outputVariant then
		return nil, "Invalid variant conversion"
	end

	local count = 0
	for key in next, petInstanceIds do
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 then
			return nil, "Pet IDs must be a dense list"
		end
		count = count + 1
	end
	if count < BalanceConfig.Machines.MinInputs or count > BalanceConfig.Machines.MaxInputs
		or rawlen(petInstanceIds) ~= count then
		return nil, "Pet IDs must be a dense list of 1 to 7 pets"
	end

	local validatedPetIds = {}
	for index = 1, count do
		validatedPetIds[index] = rawget(petInstanceIds, index)
	end

	local data = PetService._dataService and PetService._dataService.getPlayerData(player)
	if type(data) ~= "table" or type(data.pets) ~= "table" then
		return nil, "No player data"
	end
	local petsTable = data.pets
	local petById = {}
	for _, pet in ipairs(petsTable) do
		if type(pet) == "table" and type(pet.id) == "string" then
			petById[pet.id] = pet
		end
	end
	local equippedById = {}
	if type(data.equippedPets) == "table" then
		for _, equippedId in ipairs(data.equippedPets) do
			equippedById[equippedId] = true
		end
	end

	local selectedIds = {}
	local selectedPets = {}
	local selectedSnapshots = {}
	local speciesId = nil
	local anyShiny = false
	for index = 1, count do
		local instanceId = validatedPetIds[index]
		if type(instanceId) ~= "string" or instanceId == "" then
			return nil, "Invalid pet ID in list"
		end
		if selectedIds[instanceId] then
			return nil, "Duplicate pet ID in list"
		end
		selectedIds[instanceId] = true
		local pet = petById[instanceId]
		if not pet then
			return nil, "Pet not found in inventory: " .. tostring(instanceId)
		end
		if pet.favorite == true then
			return nil, "Favorited pets cannot be converted"
		end
		if pet.equipped == true or equippedById[instanceId] then
			return nil, "Equipped pets cannot be converted"
		end
		local canonicalVariant = PetVariantPresentation.normalizeBaseVariant(pet)
		if canonicalVariant ~= inputVariant then
			return nil, "Pet has the wrong source variant"
		end
		if type(pet.petId) ~= "string" or not PetData.Pets[pet.petId] then
			return nil, "Invalid pet species"
		end
		if speciesId == nil then
			speciesId = pet.petId
		elseif speciesId ~= pet.petId then
			return nil, "All pets must be the same species"
		end
		anyShiny = anyShiny or pet.shiny == true
		selectedPets[index] = pet
		selectedSnapshots[index] = {
			id = pet.id,
			petId = pet.petId,
			variant = canonicalVariant,
			shiny = pet.shiny == true,
			enchantPresent = rawget(pet, "enchantId") ~= nil,
			enchantId = rawget(pet, "enchantId"),
		}
	end

	local projectedCount = #petsTable - count + 1
	if projectedCount > PetService.getMaxInventory(player) then
		return nil, "Pet inventory has no room for the conversion result"
	end

	local definition = PetData.Pets[speciesId]
	local presentation = PetVariantPresentation.resolve({
		petId = speciesId,
		variant = outputVariant,
		shiny = anyShiny,
	})
	local outputPet = {
		id = HttpService:GenerateGUID(false),
		petId = speciesId,
		name = presentation.displayPetName,
		rarity = definition.rarity,
		damage = PetVariantMath.getBaseDamage(speciesId, outputVariant, anyShiny),
		variant = outputVariant,
		shiny = anyShiny,
		golden = outputVariant == "Golden",
		favorite = false,
		equipped = false,
	}
	-- Machine success always creates a fresh, explicitly unenchanted output.
	outputPet.enchantId = nil
	local discoveryKeys = PetDex.getWriteKeys(speciesId, outputVariant, anyShiny)
	if not discoveryKeys then
		return nil, "Invalid output discovery state"
	end
	local originalPets = {}
	for index, pet in ipairs(petsTable) do
		originalPets[index] = pet
	end
	local discoveryTable = type(data.discoveredPets) == "table" and data.discoveredPets or nil
	local discoverySnapshot = {}
	if discoveryTable then
		for key, value in pairs(discoveryTable) do
			discoverySnapshot[key] = value
		end
	end

	return {
		player = player,
		data = data,
		petsTable = petsTable,
		originalPets = originalPets,
		selectedIds = selectedIds,
		selectedPets = selectedPets,
		selectedSnapshots = selectedSnapshots,
		inputVariant = inputVariant,
		outputVariant = outputVariant,
		outputPet = outputPet,
		discoveryKey = discoveryKeys[1],
		discoveryKeys = discoveryKeys,
		discoveryTable = discoveryTable,
		discoverySnapshot = discoverySnapshot,
		discoveryMutationStarted = false,
		mutationStarted = false,
		committed = false,
		transactionCommitted = false,
		isNewDiscovery = false,
	}, nil
end

local function discoveryMatchesPreparedSnapshot(data, prepared)
	if data.discoveredPets ~= prepared.discoveryTable then
		return false
	end
	if prepared.discoveryTable == nil then
		return true
	end
	for key, value in pairs(prepared.discoveryTable) do
		if prepared.discoverySnapshot[key] ~= value then
			return false
		end
	end
	for key, value in pairs(prepared.discoverySnapshot) do
		if prepared.discoveryTable[key] ~= value then
			return false
		end
	end
	return true
end

local function commitVariantConversionUnlocked(player, prepared, succeeded)
	if type(prepared) ~= "table" or prepared.player ~= player or prepared.committed
		or type(succeeded) ~= "boolean" then
		return false, "Invalid prepared conversion"
	end
	local data = PetService._dataService.getPlayerData(player)
	if data ~= prepared.data or data.pets ~= prepared.petsTable
		or #data.pets ~= #prepared.originalPets then
		return false, "Inventory changed during conversion"
	end
	if not discoveryMatchesPreparedSnapshot(data, prepared) then
		return false, "Discovery changed during conversion"
	end
	for index, pet in ipairs(prepared.originalPets) do
		if data.pets[index] ~= pet then
			return false, "Inventory changed during conversion"
		end
	end
	local equippedById = {}
	if type(data.equippedPets) == "table" then
		for _, equippedId in ipairs(data.equippedPets) do
			equippedById[equippedId] = true
		end
	end
	for index, pet in ipairs(prepared.selectedPets) do
		local snapshot = prepared.selectedSnapshots[index]
		if pet.id ~= snapshot.id or pet.petId ~= snapshot.petId
			or PetVariantPresentation.normalizeBaseVariant(pet) ~= snapshot.variant
			or (pet.shiny == true) ~= snapshot.shiny
			or (rawget(pet, "enchantId") ~= nil) ~= snapshot.enchantPresent
			or rawget(pet, "enchantId") ~= snapshot.enchantId
			or pet.favorite == true or pet.equipped == true or equippedById[pet.id] then
			return false, "Selected pet changed during conversion"
		end
	end
	if succeeded and #data.pets - #prepared.selectedPets + 1 > PetService.getMaxInventory(player) then
		return false, "Pet inventory has no room for the conversion result"
	end

	prepared.mutationStarted = true
	local writeIndex = 1
	for _, pet in ipairs(prepared.originalPets) do
		if not prepared.selectedIds[pet.id] then
			data.pets[writeIndex] = pet
			writeIndex = writeIndex + 1
		end
	end
	for index = #data.pets, writeIndex, -1 do
		data.pets[index] = nil
	end

	if succeeded then
		prepared.isNewDiscovery = not prepared.discoveryTable
			or prepared.discoveryTable[prepared.discoveryKey] ~= true
		local discoveryWriteTable = data.discoveredPets
		local createdDiscoveryTable = false
		if type(discoveryWriteTable) ~= "table" then
			discoveryWriteTable = {}
			data.discoveredPets = discoveryWriteTable
			createdDiscoveryTable = true
		end
		prepared.discoveryWriteTable = discoveryWriteTable
		prepared.discoveryWrites = {}
		prepared.discoveryCreatedTable = createdDiscoveryTable
		prepared.discoveryMutationStarted = true
		for _, discoveryKey in ipairs(prepared.discoveryKeys) do
			local previousValue = rawget(discoveryWriteTable, discoveryKey)
			prepared.discoveryWrites[discoveryKey] = {
				present = previousValue ~= nil,
				value = previousValue,
			}
			discoveryWriteTable[discoveryKey] = true
		end
		table.insert(data.pets, prepared.outputPet)
	end
	prepared.committed = true
	return true
end

function PetService.commitVariantConversion(player, prepared, succeeded, suppliedLease)
	local lease, ownsLease = acquireInventoryMutation(
		player,
		"PetService.commitVariantConversion",
		suppliedLease
	)
	if not lease then return false, "Pet inventory mutation already in progress" end
	local ok, committed, commitError = xpcall(function()
		return commitVariantConversionUnlocked(player, prepared, succeeded)
	end, debug.traceback)
	if ownsLease then
		PetService.endInventoryMutation(player, lease, ok and committed == true)
	end
	if not ok then return false, "Conversion failed safely" end
	return committed, commitError
end

local function rollbackVariantConversionUnlocked(prepared)
	if type(prepared) ~= "table" or not prepared.mutationStarted
		or type(prepared.data) ~= "table" or type(prepared.petsTable) ~= "table" then
		return true
	end
	local petsTable = prepared.petsTable
	prepared.data.pets = petsTable
	for index = #petsTable, 1, -1 do
		petsTable[index] = nil
	end
	for index, pet in ipairs(prepared.originalPets) do
		petsTable[index] = pet
	end

	-- Roll back only the discovery keys this transaction wrote. Concurrent keys
	-- or replacement tables belong to other work and must remain untouched.
	if prepared.discoveryMutationStarted
		and prepared.data.discoveredPets == prepared.discoveryWriteTable then
		for discoveryKey, previous in pairs(prepared.discoveryWrites or {}) do
			-- Restore only an unchanged value owned by this transaction. If another
			-- path replaced it, preserve that newer value instead of clobbering it.
			if rawget(prepared.discoveryWriteTable, discoveryKey) == true then
				if previous.present then
					prepared.discoveryWriteTable[discoveryKey] = previous.value
				else
					prepared.discoveryWriteTable[discoveryKey] = nil
				end
			end
		end
		if prepared.discoveryCreatedTable
			and prepared.data.discoveredPets == prepared.discoveryWriteTable
			and next(prepared.discoveryWriteTable) == nil then
			prepared.data.discoveredPets = nil
		end
	end
	prepared.discoveryMutationStarted = false
	prepared.discoveryWriteTable = nil
	prepared.discoveryWrites = nil
	prepared.discoveryCreatedTable = nil
	prepared.mutationStarted = false
	prepared.committed = false
	prepared.isNewDiscovery = false
	return true
end

function PetService.rollbackVariantConversion(prepared, suppliedLease)
	local player = type(prepared) == "table" and prepared.player or nil
	if not player then return false end
	local lease, ownsLease = acquireInventoryMutation(
		player,
		"PetService.rollbackVariantConversion",
		suppliedLease
	)
	if not lease then return false end
	local ok, restored = xpcall(function()
		return rollbackVariantConversionUnlocked(prepared)
	end, debug.traceback)
	if ownsLease then
		PetService.endInventoryMutation(player, lease, ok and restored == true)
	end
	return ok and restored == true
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

-- Calculate effective damage from canonical identity and apply active buffs once.
-- pet.damage is a replicated compatibility mirror and is never combat authority.
function PetService.getPetDamage(pet, player)
	if type(pet) ~= "table" or not player then
		return 0
	end

	local baseOk, baseDamage = pcall(PetVariantMath.getPetBaseDamage, pet)
	if not baseOk or not isFiniteNumber(baseDamage) or baseDamage < 0 then
		return 0
	end
	local enchantOk, enchantMultiplier = pcall(PetEnchantMath.getDamageMultiplier, pet)
	if not enchantOk or not isFiniteNumber(enchantMultiplier) or enchantMultiplier < 0 then
		enchantMultiplier = 1
	end
	local enchantedDamage = baseDamage * enchantMultiplier
	if isFiniteNumber(enchantedDamage) and enchantedDamage >= 0 then
		baseDamage = enchantedDamage
	end

	local strongBonus = 0
	if type(PetService._upgradeService) == "table"
		and type(PetService._upgradeService.getUpgradeBonus) == "function" then
		local bonusOk, bonus = pcall(
			PetService._upgradeService.getUpgradeBonus,
			player,
			"StrongPets"
		)
		if bonusOk and isFiniteNumber(bonus) and bonus > 0 then
			strongBonus = bonus
		end
	end
	if strongBonus > 0 then
		local candidate = baseDamage * strongBonus
		if isFiniteNumber(candidate) and candidate >= 0 then
			baseDamage = math.floor(candidate)
		end
	end

	if type(PetService._shopService) == "table"
		and type(PetService._shopService.getShopMultiplier) == "function" then
		local multiplierOk, shopDamageMultiplier = pcall(
			PetService._shopService.getShopMultiplier,
			player,
			"damage"
		)
		if multiplierOk and isFiniteNumber(shopDamageMultiplier) and shopDamageMultiplier > 1 then
			local candidate = baseDamage * shopDamageMultiplier
			if isFiniteNumber(candidate) and candidate >= 0 then
				baseDamage = math.floor(candidate)
			end
		end
	end

	return isFiniteNumber(baseDamage) and baseDamage >= 0 and baseDamage or 0
end

-- Campaign lane movement is snapshotted by CampaignService at deploy. It uses
-- only canonical PetData base speed and an Agile enchant from the whitelist.
function PetService.getCampaignLaneSpeed(pet)
	if type(pet) ~= "table" then
		return 0
	end
	local petId = rawget(pet, "petId")
	if type(petId) ~= "string" then
		return 0
	end
	local definition = PetData.Pets[petId]
	local baseSpeed = definition and definition.baseSpeed or nil
	if not isFiniteNumber(baseSpeed) or baseSpeed < 0 then
		return 0
	end
	local multiplierOk, multiplier = pcall(PetEnchantMath.getCampaignSpeedMultiplier, pet)
	if not multiplierOk or not isFiniteNumber(multiplier) or multiplier < 0 then
		return 0
	end
	local speed = baseSpeed * multiplier
	return isFiniteNumber(speed) and speed >= 0 and speed or 0
end

-- Shared machine chance table. QOF-02 centralizes this without changing the
-- existing Golden conversion behavior; machine costs/zones activate later.
local GOLDEN_CONVERSION = BalanceConfig.Legacy.GoldenConversion
local GOLDEN_CHANCES = GOLDEN_CONVERSION.SuccessChanceByInput

-- Convert pets into a golden pet (multi-pet sacrifice with chance)
-- petInstanceIds: table of 1-7 pet instance IDs (all must be same petId/type)
-- Returns: { success = bool, goldenPet = pet|nil, chance = number, isNewDiscovery = bool }
local function convertToGoldenPetUnlocked(player, petInstanceIds)
	if not player or type(petInstanceIds) ~= "table" then
		return nil, "Invalid parameters"
	end

	local count = #petInstanceIds
	if count < GOLDEN_CONVERSION.MinInputs or count > GOLDEN_CONVERSION.MaxInputs then
		return nil, "Must sacrifice between "
			.. tostring(GOLDEN_CONVERSION.MinInputs)
			.. " and "
			.. tostring(GOLDEN_CONVERSION.MaxInputs)
			.. " pets"
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

		if foundPet.favorite == true then
			return nil, "Favorited pets cannot be sacrificed"
		end

		if foundPet.golden then
			return nil, "Cannot sacrifice a golden pet"
		end

		if foundPet.shiny == true then
			return nil, "Shiny pets cannot be sacrificed"
		end

		local variant = foundPet.variant or "Normal"
		if variant ~= "Normal" then
			return nil, "Only normal pets can be converted; keep Shiny and Rainbow pets safe"
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

	local petDef = PetData.Pets[requiredPetId]
	if not petDef then
		return nil, "Invalid pet type"
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
	local isNewDiscovery = false

	if success then
		-- Create a new golden pet based on the sacrificed type
		goldenPet = {
			id = HttpService:GenerateGUID(false),
			petId = requiredPetId,
			name = "Golden " .. petDef.name,
			rarity = petDef.rarity,
			damage = PetVariantMath.getBaseDamage(requiredPetId, "Golden", false),
			variant = "Golden",
			shiny = false,
			golden = true,
			favorite = false,
			equipped = false,
		}
		table.insert(data.pets, goldenPet)

		-- Track canonical discovery and retain the QOF-19 compatibility mirror.
		if not data.discoveredPets then
			data.discoveredPets = {}
		end
		local discoveryKeys = PetDex.getWriteKeys(requiredPetId, "Golden", false)
		if discoveryKeys then
			isNewDiscovery = data.discoveredPets[discoveryKeys[1]] ~= true
			for _, discoveryKey in ipairs(discoveryKeys) do
				data.discoveredPets[discoveryKey] = true
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

	return {
		success = success,
		goldenPet = goldenPet,
		chance = chance,
		isNewDiscovery = isNewDiscovery,
	}, nil
end

function PetService.convertToGoldenPet(player, petInstanceIds)
	local lease = PetService.beginInventoryMutation(player, "PetService.convertToGoldenPet")
	if not lease then return nil, "Pet inventory mutation already in progress" end
	local ok, result, conversionError = xpcall(function()
		return convertToGoldenPetUnlocked(player, petInstanceIds)
	end, debug.traceback)
	local released = PetService.endInventoryMutation(player, lease, ok and result ~= nil)
	if not ok then return nil, "Conversion failed safely" end
	if not released then return nil, "Conversion settlement failed" end
	return result, conversionError
end

return PetService
