--[[
	DataSchema.lua - Versioned player data schema and migration helpers
	Keeps array fields atomic, repairs cross-field invariants, and removes
	transient values before persistence.
]]

local Config = require(game.ReplicatedStorage.Shared.Config)

local DataSchema = {}

DataSchema.VERSION = 5

local ARRAY_FIELDS = {
	pets = true,
	unlockedZones = true,
	campaignProgress = true,
	equippedPets = true,
}

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

local function finiteNumber(value, fallback, minimum)
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	if minimum ~= nil and value < minimum then
		return minimum
	end
	return value
end

local function mergeObjectDefaults(data, defaults)
	for key, defaultValue in pairs(defaults) do
		local currentValue = data[key]
		if currentValue == nil then
			data[key] = deepCopy(defaultValue)
		elseif type(defaultValue) == "table" then
			if type(currentValue) ~= "table" then
				data[key] = deepCopy(defaultValue)
			else
				mergeObjectDefaults(currentValue, defaultValue)
			end
		end
	end
end

function DataSchema.getDefaultData()
	local starterPet = {
		id = "starter_pet_1",
		petId = "Buddy",
		name = "Buddy",
		rarity = "Common",
		damage = 1,
		variant = "Normal",
		favorite = false,
		equipped = true,
	}

	return {
		schemaVersion = DataSchema.VERSION,
		coins = 0,
		diamonds = 0,
		xp = 0,
		level = 1,
		pets = { starterPet },
		unlockedZones = { 1 },
		campaignProgress = {},
		campaignBossRewards = {},
		upgrades = {},
		upgradeTreePurchases = {},
		equippedPets = { "starter_pet_1" },
		questStats = {
			destroyDestructibles = 0,
			hatchEggs = 0,
			earnCoins = 0,
			playtime = 0,
			reachLevel = 0,
			goldenPetsConverted = 0,
		},
		masteryPoints = 0,
		masteryBuffs = {},
		discoveredPets = {},
		shopPurchases = {
			extraEquipSlots = 0,
		},
	}
end

local function mergeDefaults(data, defaults)
	for key, defaultValue in pairs(defaults) do
		local currentValue = data[key]
		if currentValue == nil then
			data[key] = deepCopy(defaultValue)
		elseif type(defaultValue) == "table" then
			if type(currentValue) ~= "table" then
				data[key] = deepCopy(defaultValue)
			elseif not ARRAY_FIELDS[key] then
				mergeObjectDefaults(currentValue, defaultValue)
			end
		end
	end
end

local function normalizePets(data)
	if type(data.pets) ~= "table" then
		data.pets = {}
	end
	if type(data.equippedPets) ~= "table" then
		data.equippedPets = {}
	end

	local normalizedPets = {}
	local petById = {}
	for _, pet in ipairs(data.pets) do
		if type(pet) == "table" and type(pet.id) == "string" and pet.id ~= "" and not petById[pet.id] then
			pet.damage = math.floor(finiteNumber(pet.damage, 0, 0))
			if pet.golden == true then
				pet.variant = "Golden"
			else
				pet.variant = type(pet.variant) == "string" and pet.variant or "Normal"
			end
			pet.favorite = pet.favorite == true
			pet.equipped = pet.equipped == true
			petById[pet.id] = pet
			table.insert(normalizedPets, pet)
		end
	end
	data.pets = normalizedPets

	local equipped = {}
	local equippedSet = {}
	for _, petId in ipairs(data.equippedPets) do
		if type(petId) == "string" and petById[petId] and not equippedSet[petId] then
			equippedSet[petId] = true
			table.insert(equipped, petId)
		end
	end

	-- Repair older saves where the per-pet flag and equippedPets list diverged.
	for _, pet in ipairs(normalizedPets) do
		if pet.equipped and not equippedSet[pet.id] then
			equippedSet[pet.id] = true
			table.insert(equipped, pet.id)
		end
	end
	for _, pet in ipairs(normalizedPets) do
		pet.equipped = equippedSet[pet.id] == true
	end
	data.equippedPets = equipped
end

local function normalizeNumberArray(values, minimum, maximum, requiredValue)
	local normalized = {}
	local seen = {}
	if type(values) == "table" then
		for _, value in ipairs(values) do
			if type(value) == "number" then
				value = math.floor(value)
				if value >= minimum and value <= maximum and not seen[value] then
					seen[value] = true
				table.insert(normalized, value)
				end
			end
		end
	end
	if requiredValue and not seen[requiredValue] then
		table.insert(normalized, requiredValue)
	end
	table.sort(normalized)
	return normalized
end

function DataSchema.normalize(data)
	data.coins = math.floor(finiteNumber(data.coins, 0, 0))
	data.diamonds = math.floor(finiteNumber(data.diamonds, 0, 0))
	data.xp = math.floor(finiteNumber(data.xp, 0, 0))
	data.level = math.floor(finiteNumber(data.level, 1, 1))
	data.masteryPoints = math.floor(finiteNumber(data.masteryPoints, 0, 0))

	normalizePets(data)
	data.unlockedZones = normalizeNumberArray(data.unlockedZones, 1, 8, 1)
	data.campaignProgress = normalizeNumberArray(data.campaignProgress, 1, 48)

	if type(data.questStats) ~= "table" then data.questStats = {} end
	for statName, defaultValue in pairs(DataSchema.getDefaultData().questStats) do
		data.questStats[statName] = math.floor(finiteNumber(data.questStats[statName], defaultValue, 0))
	end
	if type(data.upgrades) ~= "table" then data.upgrades = {} end
	local normalizedTreePurchases = {}
	if type(data.upgradeTreePurchases) == "table" then
		for upgradeId, isPurchased in pairs(data.upgradeTreePurchases) do
			if type(upgradeId) == "string" and #upgradeId > 0 and #upgradeId <= 64 and isPurchased == true then
				normalizedTreePurchases[upgradeId] = true
			end
		end
	end
	data.upgradeTreePurchases = normalizedTreePurchases
	if type(data.masteryBuffs) ~= "table" then data.masteryBuffs = {} end
	if type(data.discoveredPets) ~= "table" then data.discoveredPets = {} end
	if type(data.campaignBossRewards) ~= "table" then data.campaignBossRewards = {} end
	if type(data.shopPurchases) ~= "table" then data.shopPurchases = {} end
	data.shopPurchases.extraEquipSlots = math.clamp(
		math.floor(finiteNumber(data.shopPurchases.extraEquipSlots, 0, 0)),
		0,
		Config.MaxExtraEquipSlots or 5
	)

	data.schemaVersion = DataSchema.VERSION
	data.xpNeeded = nil
	return data
end

function DataSchema.migrate(rawData)
	if type(rawData) ~= "table" then
		return DataSchema.getDefaultData()
	end

	local data = deepCopy(rawData)
	mergeDefaults(data, DataSchema.getDefaultData())
	return DataSchema.normalize(data)
end

function DataSchema.cloneForPersistence(data)
	local snapshot = deepCopy(data)
	snapshot.xpNeeded = nil
	snapshot.schemaVersion = DataSchema.VERSION
	return snapshot
end

function DataSchema.deepCopy(value)
	return deepCopy(value)
end

return DataSchema
