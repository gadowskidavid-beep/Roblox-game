--[[
	PetVariantPresentation.lua - Pure presentation resolver for canonical pet variants.
	It derives labels, stable visual keys, and color tokens only. It never mutates
	pet data and must not influence persistence, gameplay, damage, or eligibility.
]]

local PetData = require(script.Parent.PetData)

local PetVariantPresentation = {}

local BASE_STYLES = {
	Normal = {
		displayName = "Normal",
		accentRGB = { 160, 170, 190 },
		bodyRGB = nil,
	},
	Golden = {
		displayName = "Gold",
		accentRGB = { 255, 200, 0 },
		bodyRGB = { 255, 215, 0 },
	},
	Rainbow = {
		displayName = "Rainbow",
		accentRGB = { 255, 100, 210 },
		bodyRGB = { 255, 100, 210 },
	},
}

local SHINY_RGB = { 175, 245, 255 }

local function safeName(value)
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

function PetVariantPresentation.normalizeBaseVariant(petData)
	if type(petData) ~= "table" then
		return "Normal"
	end

	if petData.variant == "Rainbow" then
		return "Rainbow"
	end
	if petData.variant == "Golden" or petData.golden == true then
		return "Golden"
	end
	return "Normal"
end

function PetVariantPresentation.isShiny(petData)
	return type(petData) == "table"
		and (petData.shiny == true or petData.variant == "Shiny")
end

function PetVariantPresentation.resolve(petData)
	petData = type(petData) == "table" and petData or {}

	local baseVariant = PetVariantPresentation.normalizeBaseVariant(petData)
	local shiny = PetVariantPresentation.isShiny(petData)
	local style = BASE_STYLES[baseVariant]
	local variantLabel = style.displayName .. (shiny and " Shiny" or "")

	local definition = type(petData.petId) == "string" and PetData.Pets[petData.petId] or nil
	local petName = definition and safeName(definition.name)
		or safeName(petData.name)
		or safeName(petData.petId)
		or "Pet"

	local namePrefix = ""
	if baseVariant == "Golden" then
		namePrefix = "Gold "
	elseif baseVariant == "Rainbow" then
		namePrefix = "Rainbow "
	end
	if shiny then
		namePrefix = namePrefix .. "Shiny "
	end

	-- Legacy inventory filtering and Pet Index stay four-category compatible
	-- until their dedicated migration. Labels and visuals remain fully combined.
	local legacyCategory = shiny and "Shiny" or baseVariant

	return {
		baseVariant = baseVariant,
		isShiny = shiny,
		baseDisplayName = style.displayName,
		variantLabel = variantLabel,
		petName = petName,
		displayPetName = namePrefix .. petName,
		visualKey = baseVariant .. (shiny and ":Shiny" or ":Standard"),
		legacyCategory = legacyCategory,
		accentRGB = { style.accentRGB[1], style.accentRGB[2], style.accentRGB[3] },
		bodyRGB = style.bodyRGB and { style.bodyRGB[1], style.bodyRGB[2], style.bodyRGB[3] } or nil,
		shinyRGB = { SHINY_RGB[1], SHINY_RGB[2], SHINY_RGB[3] },
	}
end

return PetVariantPresentation
