--[[
	HatchCinematicPolicy.lua - Pure QOF-09 rare hatch presentation policy.
	It classifies already-authoritative hatch results and builds deterministic
	client timing metadata only. It never mutates pets or grants gameplay value.
]]

local HatchCinematicPolicy = {}

local TIMINGS = {
	IntroDuration = 0.18,
	PopStagger = 0.12,
	PopDuration = 0.24,
	StandardHoldDuration = 0.36,
	HeroHoldDuration = 0.72,
	OutroDuration = 0.30,
	MaxTotalDuration = 3.00,
}

HatchCinematicPolicy.TIMINGS = TIMINGS
HatchCinematicPolicy.Timings = TIMINGS
HatchCinematicPolicy.MAX_PETS = 10

local CLASSIFICATION_PRIORITY = {
	Normal = 0,
	Rare = 1,
	Epic = 2,
	Legendary = 3,
	Golden = 4,
	Rainbow = 5,
	Shiny = 6,
}

local function normalizeBaseVariant(pet)
	if pet.variant == "Rainbow" then
		return "Rainbow"
	end
	if pet.variant == "Golden" or pet.golden == true then
		return "Golden"
	end
	return "Normal"
end

local function isShiny(pet)
	return pet.shiny == true or pet.variant == "Shiny"
end

function HatchCinematicPolicy.classifyPet(pet)
	if type(pet) ~= "table" then
		return "Normal"
	end

	if isShiny(pet) then
		return "Shiny"
	end

	local baseVariant = normalizeBaseVariant(pet)
	if baseVariant == "Rainbow" then
		return "Rainbow"
	end
	if baseVariant == "Golden" then
		return "Golden"
	end

	if pet.rarity == "Legendary" then
		return "Legendary"
	end
	if pet.rarity == "Epic" then
		return "Epic"
	end
	if pet.rarity == "Rare" then
		return "Rare"
	end
	return "Normal"
end

local function getPriority(pet)
	return CLASSIFICATION_PRIORITY[HatchCinematicPolicy.classifyPet(pet)]
end

function HatchCinematicPolicy.chooseHero(pets)
	if type(pets) ~= "table" or #pets == 0 then
		return nil
	end

	local heroIndex = 1
	local heroPriority = getPriority(pets[1])
	local count = math.min(#pets, HatchCinematicPolicy.MAX_PETS)
	for index = 2, count do
		local priority = getPriority(pets[index])
		if priority > heroPriority then
			heroIndex = index
			heroPriority = priority
		end
	end
	return heroIndex
end

function HatchCinematicPolicy.buildPlan(pets)
	pets = type(pets) == "table" and pets or {}
	local count = math.min(#pets, HatchCinematicPolicy.MAX_PETS)
	local heroIndex = HatchCinematicPolicy.chooseHero(pets)
	local entries = {}

	for index = 1, count do
		entries[index] = {
			delay = (index - 1) * TIMINGS.PopStagger,
			isHero = index == heroIndex,
			classification = HatchCinematicPolicy.classifyPet(pets[index]),
		}
	end

	local heroClassification = heroIndex and entries[heroIndex].classification or "Normal"
	local hasRare = heroClassification ~= "Normal"
	local totalDuration = 0
	if count > 0 then
		local holdDuration = hasRare and TIMINGS.HeroHoldDuration or TIMINGS.StandardHoldDuration
		totalDuration = TIMINGS.IntroDuration
			+ entries[count].delay
			+ TIMINGS.PopDuration
			+ holdDuration
			+ TIMINGS.OutroDuration
	end

	return {
		heroIndex = heroIndex,
		hasRare = hasRare,
		count = count,
		entries = entries,
		totalDuration = math.min(totalDuration, TIMINGS.MaxTotalDuration),
	}
end

return HatchCinematicPolicy
