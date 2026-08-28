--[[
	DataSchema.lua - Versioned player data schema and migration helpers
	Keeps array fields atomic, repairs cross-field invariants, normalizes future
	potion state, and removes transient values before persistence.
]]

local Config = require(game.ReplicatedStorage.Shared.Config)
local BalanceConfig = require(game.ReplicatedStorage.Shared.BalanceConfig)
local PetVariantMath = require(game.ReplicatedStorage.Shared.PetVariantMath)

local DataSchema = {}

DataSchema.VERSION = 9

local ARRAY_FIELDS = {
	pets = true,
	unlockedZones = true,
	campaignProgress = true,
	equippedPets = true,
}

local POTION_CATALOG = BalanceConfig.Potions.Catalog
local POTION_UPGRADES = BalanceConfig.Potions.Upgrades
local POTION_PERSISTENCE = BalanceConfig.Potions.Persistence
local TIMED_BUFF_TYPES = {}
local CHARGE_BUFF_TYPES = {}
local LEGACY_TIMED_SOURCE_BY_BUFF = {
	luck = "LuckPotion",
	speed = "SpeedPotion",
	coins = "CoinPotion",
}
for potionId, potion in pairs(POTION_CATALOG) do
	if potion.durationSeconds ~= nil then
		TIMED_BUFF_TYPES[potion.buffType] = TIMED_BUFF_TYPES[potion.buffType] or {}
		TIMED_BUFF_TYPES[potion.buffType][potionId] = true
	elseif potion.hatchCharges ~= nil then
		CHARGE_BUFF_TYPES[potion.buffType] = true
	end
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
		damage = PetVariantMath.getBaseDamage("Buddy", "Normal", false),
		variant = "Normal",
		shiny = false,
		golden = false,
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
		hatchPreferences = {
			preferredBatchCount = 1,
		},
		autoHatchExpiresAt = 0,
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
		potionInventory = {},
		activeBuffs = {},
		-- Persistence-only rolling-version mirror. QOF-13 preserves this unknown
		-- root field even though it rewrites structured activeBuffs as schema V7.
		potionBuffSources = {},
		potionUpgrades = {
			slots = POTION_UPGRADES.BaseSlots,
			durationLevel = 0,
			autoDrink = false,
		},
		autoDrinkSelection = {},
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
			local legacyVariant = type(pet.variant) == "string" and pet.variant or "Normal"
			local variant = "Normal"
			if pet.golden == true or legacyVariant == "Golden" then
				variant = "Golden"
			elseif legacyVariant == "Rainbow" then
				variant = "Rainbow"
			end

			-- Preserve the V5 exclusive marker and a V6 Boolean mirror. Reading
			-- both makes V6 -> rolling V5 save -> V6 lossless because V5 servers
			-- retain unknown fields even when they stamp schemaVersion back to 5.
			local shiny = legacyVariant == "Shiny" or pet.shiny == true

			pet.variant = variant
			pet.shiny = shiny
			-- Keep the current visual/rolling-version compatibility mirror. The
			-- base variant remains authoritative in V6.
			pet.golden = variant == "Golden"
			PetVariantMath.refreshDamageMirror(pet)
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

local function normalizeBooleanMap(values, maximumKeyLength)
	local normalized = {}
	if type(values) == "table" then
		for key, value in pairs(values) do
			if type(key) == "string" and #key > 0 and #key <= maximumKeyLength and value == true then
				normalized[key] = true
			end
		end
	end
	return normalized
end

local function normalizePotionInventory(values)
	local normalized = {}
	if type(values) == "table" then
		for potionId, count in pairs(values) do
			if POTION_CATALOG[potionId] and type(count) == "number" then
				count = math.clamp(
					math.floor(finiteNumber(count, 0, 0)),
					0,
					POTION_PERSISTENCE.MaxInventoryPerPotion
				)
				if count > 0 then
					normalized[potionId] = count
				end
			end
		end
	end
	return normalized
end

local function normalizeTimedSource(sourceState, currentTime)
	local expiresAt = sourceState
	if type(sourceState) == "table" then
		expiresAt = sourceState.expiresAt
	end
	if type(expiresAt) ~= "number" then
		return nil
	end
	expiresAt = math.floor(finiteNumber(expiresAt, 0, 0))
	if expiresAt <= currentTime then
		return nil
	end
	return {
		expiresAt = math.min(
			expiresAt,
			currentTime + POTION_PERSISTENCE.MaxTimedBuffSeconds
		),
	}
end

local function normalizeActiveBuffs(values, currentTime)
	local normalized = {}
	if type(values) ~= "table" then
		return normalized
	end

	for buffType, state in pairs(values) do
		local validSources = TIMED_BUFF_TYPES[buffType]
		if validSources then
			local sources = {}
			-- V7 stored one ambiguous numeric timer per type. Map it to the
			-- conservative canonical source (Luck becomes x2, never an invented x5).
			if type(state) == "number" then
				local legacySource = LEGACY_TIMED_SOURCE_BY_BUFF[buffType]
				local source = legacySource and normalizeTimedSource(state, currentTime)
				if source then
					sources[legacySource] = source
				end
			elseif type(state) == "table" then
				local inputSources = type(state.sources) == "table" and state.sources or nil
				-- Accept the short-lived pre-V8 structured prototype safely.
				if not inputSources and state.expiresAt ~= nil then
					local sourceId = validSources[state.sourceId] and state.sourceId
						or LEGACY_TIMED_SOURCE_BY_BUFF[buffType]
					inputSources = sourceId and { [sourceId] = state } or nil
				end
				for sourceId, sourceState in pairs(inputSources or {}) do
					if validSources[sourceId] then
						local source = normalizeTimedSource(sourceState, currentTime)
						if source then
							sources[sourceId] = source
						end
					end
				end
			end
			if next(sources) ~= nil then
				normalized[buffType] = { sources = sources }
			end
		elseif CHARGE_BUFF_TYPES[buffType] and type(state) == "table" then
			local charges = math.clamp(
				math.floor(finiteNumber(state.charges, 0, 0)),
				0,
				POTION_UPGRADES.MaxShinyCharges
			)
			if charges > 0 then
				normalized[buffType] = { charges = charges }
			end
		end
	end
	return normalized
end

local function normalizePotionBuffSources(values, currentTime)
	local normalized = {}
	if type(values) ~= "table" then
		return normalized
	end
	for potionId, sourceState in pairs(values) do
		local potion = POTION_CATALOG[potionId]
		if potion and potion.durationSeconds ~= nil then
			local source = normalizeTimedSource(sourceState, currentTime)
			if source then
				normalized[potionId] = source
			end
		end
	end
	return normalized
end

local function mergePotionBuffSources(activeBuffs, backupSources)
	for potionId, source in pairs(backupSources) do
		local potion = POTION_CATALOG[potionId]
		local state = activeBuffs[potion.buffType]
		if type(state) ~= "table" or type(state.sources) ~= "table" then
			state = { sources = {} }
			activeBuffs[potion.buffType] = state
		end
		local existing = state.sources[potionId]
		if type(existing) ~= "table" or existing.expiresAt < source.expiresAt then
			state.sources[potionId] = source
		end
	end
end

local function buildPotionBuffSources(activeBuffs)
	local synchronized = {}
	for buffType, state in pairs(activeBuffs) do
		local validSources = TIMED_BUFF_TYPES[buffType]
		if validSources and type(state) == "table" and type(state.sources) == "table" then
			for potionId, source in pairs(state.sources) do
				if validSources[potionId] then
					synchronized[potionId] = { expiresAt = source.expiresAt }
				end
			end
		end
	end
	return synchronized
end

local VALID_HATCH_BATCH_COUNTS = {
	[1] = true,
	[2] = true,
	[5] = true,
	[10] = true,
}

local function normalizeHatchPreferences(values)
	local preferredBatchCount = type(values) == "table" and values.preferredBatchCount or nil
	if type(preferredBatchCount) ~= "number"
		or preferredBatchCount ~= preferredBatchCount
		or preferredBatchCount == math.huge
		or preferredBatchCount == -math.huge
		or not VALID_HATCH_BATCH_COUNTS[preferredBatchCount] then
		preferredBatchCount = 1
	end
	return {
		preferredBatchCount = preferredBatchCount,
	}
end

local function normalizeAutoHatchExpiry(value, currentTime)
	if type(value) ~= "number"
		or value ~= value
		or value == math.huge
		or value == -math.huge
		or value % 1 ~= 0 then
		return 0
	end
	local expiresAt = value
	local maximumExpiry = currentTime + BalanceConfig.Shop.AutoHatch.durationSeconds
	-- Paid access is always exactly one non-stackable ten-minute grant. Values
	-- outside the only possible live window fail closed instead of being capped.
	if expiresAt <= currentTime or expiresAt > maximumExpiry then
		return 0
	end
	return expiresAt
end

local function normalizePotionUpgrades(values)
	if type(values) ~= "table" then
		values = {}
	end
	return {
		slots = math.clamp(
			math.floor(finiteNumber(values.slots, POTION_UPGRADES.BaseSlots, POTION_UPGRADES.BaseSlots)),
			POTION_UPGRADES.BaseSlots,
			POTION_UPGRADES.MaxSlots
		),
		durationLevel = math.clamp(
			math.floor(finiteNumber(values.durationLevel, 0, 0)),
			0,
			#POTION_UPGRADES.Duration
		),
		autoDrink = values.autoDrink == true,
	}
end

function DataSchema.normalize(data, currentTime)
	currentTime = math.floor(finiteNumber(currentTime, os.time(), 0))

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
	data.upgradeTreePurchases = normalizeBooleanMap(data.upgradeTreePurchases, 64)
	if type(data.masteryBuffs) ~= "table" then data.masteryBuffs = {} end
	data.discoveredPets = normalizeBooleanMap(data.discoveredPets, 128)
	if type(data.campaignBossRewards) ~= "table" then data.campaignBossRewards = {} end
	if type(data.shopPurchases) ~= "table" then data.shopPurchases = {} end
	data.shopPurchases.extraEquipSlots = math.clamp(
		math.floor(finiteNumber(data.shopPurchases.extraEquipSlots, 0, 0)),
		0,
		Config.MaxExtraEquipSlots or 5
	)

	data.potionInventory = normalizePotionInventory(data.potionInventory)
	local activeBuffs = normalizeActiveBuffs(data.activeBuffs, currentTime)
	local backupSources = normalizePotionBuffSources(data.potionBuffSources, currentTime)
	-- The runtime consumes only activeBuffs. The flat mirror exists solely so a
	-- rolling QOF-13 server can preserve V8 source identity while dropping the
	-- structured field. Prefer the later valid expiry; timed effects have no
	-- cancellation operation, so a stale rolling save must never shorten one.
	mergePotionBuffSources(activeBuffs, backupSources)
	data.activeBuffs = activeBuffs
	data.potionBuffSources = buildPotionBuffSources(activeBuffs)
	data.potionUpgrades = normalizePotionUpgrades(data.potionUpgrades)
	data.autoDrinkSelection = normalizeBooleanMap(data.autoDrinkSelection, 64)
	for potionId in pairs(data.autoDrinkSelection) do
		if not POTION_CATALOG[potionId] then
			data.autoDrinkSelection[potionId] = nil
		end
	end
	data.hatchPreferences = normalizeHatchPreferences(data.hatchPreferences)
	data.autoHatchExpiresAt = normalizeAutoHatchExpiry(data.autoHatchExpiresAt, currentTime)

	data.schemaVersion = DataSchema.VERSION
	data.xpNeeded = nil
	return data
end

function DataSchema.migrate(rawData, currentTime)
	if type(rawData) ~= "table" then
		return DataSchema.getDefaultData()
	end

	local data = deepCopy(rawData)
	mergeDefaults(data, DataSchema.getDefaultData())
	return DataSchema.normalize(data, currentTime)
end

function DataSchema.cloneForPersistence(data, currentTime)
	local snapshot = deepCopy(data)
	return DataSchema.normalize(snapshot, currentTime)
end

function DataSchema.deepCopy(value)
	return deepCopy(value)
end

return DataSchema
