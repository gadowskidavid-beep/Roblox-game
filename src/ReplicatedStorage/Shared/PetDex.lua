--[[
	PetDex.lua - Pure QOF-20 six-state collection contract.
	Discovery is keyed by species + canonical base variant + independent Shiny.
	Legacy four-category keys remain as additive rolling-deployment mirrors.
]]

local PetData = require(script.Parent.PetData)

local PetDex = {}

PetDex.CONTRACT_VERSION = 1

local STATES = {
	{ id = "Normal", baseVariant = "Normal", shiny = false },
	{ id = "NormalShiny", baseVariant = "Normal", shiny = true },
	{ id = "Golden", baseVariant = "Golden", shiny = false },
	{ id = "GoldenShiny", baseVariant = "Golden", shiny = true },
	{ id = "Rainbow", baseVariant = "Rainbow", shiny = false },
	{ id = "RainbowShiny", baseVariant = "Rainbow", shiny = true },
}

local VALID_BASE_VARIANTS = {
	Normal = true,
	Golden = true,
	Rainbow = true,
}

local canonicalKeys = {}
local legacyToCanonical = {}
local validLegacyKeys = {}
local shinyLegacyCanonicalStates = {}

local function isKnownPetId(petId)
	return type(petId) == "string" and PetData.Pets[petId] ~= nil
end

local function canonicalKeyUnchecked(petId, baseVariant, shiny)
	local key = petId .. "|" .. baseVariant
	if shiny == true then
		key = key .. "|Shiny"
	end
	return key
end

local function legacyKeyUnchecked(petId, baseVariant, shiny)
	if shiny == true then
		return "Shiny_" .. petId
	elseif baseVariant == "Golden" then
		return "Golden_" .. petId
	elseif baseVariant == "Rainbow" then
		return "Rainbow_" .. petId
	end
	return petId
end

for petId in pairs(PetData.Pets) do
	for _, state in ipairs(STATES) do
		canonicalKeys[canonicalKeyUnchecked(petId, state.baseVariant, state.shiny)] = true
	end
	local normalKey = petId
	local goldenKey = "Golden_" .. petId
	local rainbowKey = "Rainbow_" .. petId
	local shinyKey = "Shiny_" .. petId
	validLegacyKeys[normalKey] = true
	validLegacyKeys[goldenKey] = true
	validLegacyKeys[rainbowKey] = true
	validLegacyKeys[shinyKey] = true
	legacyToCanonical[normalKey] = canonicalKeyUnchecked(petId, "Normal", false)
	legacyToCanonical[goldenKey] = canonicalKeyUnchecked(petId, "Golden", false)
	legacyToCanonical[rainbowKey] = canonicalKeyUnchecked(petId, "Rainbow", false)
	-- The historic Shiny key did not preserve its base variant. It maps to
	-- Normal Shiny only when no exact canonical Shiny state accompanies it.
	legacyToCanonical[shinyKey] = canonicalKeyUnchecked(petId, "Normal", true)
	shinyLegacyCanonicalStates[shinyKey] = {
		canonicalKeyUnchecked(petId, "Normal", true),
		canonicalKeyUnchecked(petId, "Golden", true),
		canonicalKeyUnchecked(petId, "Rainbow", true),
	}
end

function PetDex.getStates()
	local copy = {}
	for index, state in ipairs(STATES) do
		copy[index] = {
			id = state.id,
			baseVariant = state.baseVariant,
			shiny = state.shiny,
		}
	end
	return copy
end

function PetDex.getTotalStateCount()
	local speciesCount = 0
	for _ in pairs(PetData.Pets) do
		speciesCount = speciesCount + 1
	end
	return speciesCount * #STATES
end

function PetDex.getCanonicalKey(petId, baseVariant, shiny)
	if not isKnownPetId(petId) or VALID_BASE_VARIANTS[baseVariant] ~= true
		or type(shiny) ~= "boolean" then
		return nil
	end
	return canonicalKeyUnchecked(petId, baseVariant, shiny)
end

function PetDex.getLegacyKey(petId, baseVariant, shiny)
	if not isKnownPetId(petId) or VALID_BASE_VARIANTS[baseVariant] ~= true
		or type(shiny) ~= "boolean" then
		return nil
	end
	return legacyKeyUnchecked(petId, baseVariant, shiny)
end

function PetDex.getWriteKeys(petId, baseVariant, shiny)
	local canonical = PetDex.getCanonicalKey(petId, baseVariant, shiny)
	local legacy = PetDex.getLegacyKey(petId, baseVariant, shiny)
	if not canonical or not legacy then
		return nil
	end
	return { canonical, legacy }
end

function PetDex.isCanonicalKey(key)
	return type(key) == "string" and canonicalKeys[key] == true
end

function PetDex.isLegacyKey(key)
	return type(key) == "string" and validLegacyKeys[key] == true
end

function PetDex.projectDiscovery(values)
	if type(values) ~= "table" or getmetatable(values) ~= nil then
		return nil
	end
	local projected = {}
	-- Canonical states are copied first so an additive legacy mirror cannot
	-- fabricate a second Shiny state during a later V11 normalization.
	for key, value in next, values do
		if value == true and canonicalKeys[key] then
			projected[key] = true
		end
	end
	for key, value in next, values do
		if value == true and validLegacyKeys[key] then
			projected[key] = true
			local shinyStates = shinyLegacyCanonicalStates[key]
			if shinyStates then
				local hasExactShiny = false
				for _, canonical in ipairs(shinyStates) do
					if projected[canonical] == true then
						hasExactShiny = true
						break
					end
				end
				if not hasExactShiny then
					projected[legacyToCanonical[key]] = true
				end
			else
				projected[legacyToCanonical[key]] = true
			end
		end
	end
	return projected
end

function PetDex.normalizeDiscovery(values, pets)
	local normalized = PetDex.projectDiscovery(values) or {}
	if type(pets) ~= "table" or getmetatable(pets) ~= nil then
		return normalized
	end
	for _, pet in ipairs(pets) do
		if type(pet) == "table" and getmetatable(pet) == nil then
			local petId = rawget(pet, "petId")
			local variant = rawget(pet, "variant")
			if variant ~= "Golden" and variant ~= "Rainbow" then
				variant = rawget(pet, "golden") == true and "Golden" or "Normal"
			end
			local shiny = rawget(pet, "shiny") == true or rawget(pet, "variant") == "Shiny"
			local keys = PetDex.getWriteKeys(petId, variant, shiny)
			if keys then
				for _, key in ipairs(keys) do
					normalized[key] = true
				end
			end
		end
	end
	return normalized
end

function PetDex.recordPet(discovery, pet)
	if type(discovery) ~= "table" or getmetatable(discovery) ~= nil
		or type(pet) ~= "table" or getmetatable(pet) ~= nil then
		return false
	end
	local variant = rawget(pet, "variant")
	if variant ~= "Golden" and variant ~= "Rainbow" then
		variant = rawget(pet, "golden") == true and "Golden" or "Normal"
	end
	local keys = PetDex.getWriteKeys(
		rawget(pet, "petId"),
		variant,
		rawget(pet, "shiny") == true or rawget(pet, "variant") == "Shiny"
	)
	if not keys then
		return false
	end
	local changed = false
	for _, key in ipairs(keys) do
		if discovery[key] ~= true then
			changed = true
		end
		discovery[key] = true
	end
	return changed
end

return PetDex
