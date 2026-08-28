--[[
	PetVariantMath.lua - Canonical pet variant and damage derivation.
	Pet identity, base variant, and the independent Shiny flag are authoritative;
	persisted/client damage values are compatibility mirrors only.
]]

local BalanceConfig = require(script.Parent.BalanceConfig)
local PetData = require(script.Parent.PetData)

local PetVariantMath = {}

local function finiteNumber(value)
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
end

function PetVariantMath.normalizeBaseVariant(variant)
	if type(variant) == "string" and BalanceConfig.Variants.Base[variant] then
		return variant
	end
	return "Normal"
end

function PetVariantMath.getDamageFromBase(baseDamage, variant, shiny)
	if not finiteNumber(baseDamage) or baseDamage < 0 then
		return 0
	end

	local baseVariant = PetVariantMath.normalizeBaseVariant(variant)
	local variantMultiplier = BalanceConfig.Variants.Base[baseVariant].damageMultiplier
	local shinyMultiplier = shiny == true and BalanceConfig.Variants.Shiny.damageMultiplier or 1
	return baseDamage * variantMultiplier * shinyMultiplier
end

function PetVariantMath.getBaseDamage(petId, variant, shiny)
	if type(petId) ~= "string" then
		return 0
	end
	local petDefinition = PetData.Pets[petId]
	if type(petDefinition) ~= "table" then
		return 0
	end
	return PetVariantMath.getDamageFromBase(petDefinition.baseDamage, variant, shiny)
end

function PetVariantMath.getPetBaseDamage(pet)
	if type(pet) ~= "table" then
		return 0
	end
	return PetVariantMath.getBaseDamage(pet.petId, pet.variant, pet.shiny)
end

function PetVariantMath.refreshDamageMirror(pet)
	if type(pet) ~= "table" then
		return 0
	end
	local damage = PetVariantMath.getPetBaseDamage(pet)
	pet.damage = damage
	return damage
end

return PetVariantMath
