--[[
	PetEnchantMath.lua - Canonical QOF-19 pet enchant lookup and stat math.
	BalanceConfig.Enchanting.Pool is the only whitelist and authority. Callers
	receive defensive copies and must never trust stat/multiplier fields on pets.
]]

local BalanceConfig = require(script.Parent.BalanceConfig)

local PetEnchantMath = {}

local definitionsById = {}
local orderedIds = {}
for index, definition in ipairs(BalanceConfig.Enchanting.Pool) do
	definitionsById[definition.id] = {
		id = definition.id,
		weight = definition.weight,
		stat = definition.stat,
		multiplier = definition.multiplier,
	}
	orderedIds[index] = definition.id
end

local function copyDefinition(definition)
	if not definition then
		return nil
	end
	return {
		id = definition.id,
		weight = definition.weight,
		stat = definition.stat,
		multiplier = definition.multiplier,
	}
end

function PetEnchantMath.normalizeEnchantId(value)
	if type(value) ~= "string" or value == "" then
		return nil
	end
	local definition = definitionsById[value]
	return definition and definition.id or nil
end

function PetEnchantMath.getDefinition(enchantId)
	local normalized = PetEnchantMath.normalizeEnchantId(enchantId)
	return copyDefinition(normalized and definitionsById[normalized] or nil)
end

function PetEnchantMath.getPublicPool()
	local pool = {}
	for index, enchantId in ipairs(orderedIds) do
		pool[index] = copyDefinition(definitionsById[enchantId])
	end
	return pool
end

function PetEnchantMath.getMultiplierForStat(pet, stat)
	if type(pet) ~= "table" or (stat ~= "damage" and stat ~= "speed") then
		return 1
	end
	local enchantId = PetEnchantMath.normalizeEnchantId(rawget(pet, "enchantId"))
	local definition = enchantId and definitionsById[enchantId] or nil
	if not definition or definition.stat ~= stat then
		return 1
	end
	return definition.multiplier
end

function PetEnchantMath.getDamageMultiplier(pet)
	return PetEnchantMath.getMultiplierForStat(pet, "damage")
end

function PetEnchantMath.getCampaignSpeedMultiplier(pet)
	return PetEnchantMath.getMultiplierForStat(pet, "speed")
end

return PetEnchantMath
