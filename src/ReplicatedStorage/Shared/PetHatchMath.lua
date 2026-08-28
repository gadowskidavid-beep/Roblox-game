--[[
	PetHatchMath.lua - Pure canonical direct-hatch probability model.
	Gold and Rainbow share one mutually exclusive base-variant roll. Shiny uses
	an independent roll, so all six base-variant/Shiny combinations are possible.
]]

local BalanceConfig = require(script.Parent.BalanceConfig)

local PetHatchMath = {}

local function finiteNumber(value)
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
end

local function normalizedMultiplier(value)
	if not finiteNumber(value) or value <= 1 then
		return 1
	end
	return value
end

local function maxUsefulLuckMultiplier()
	local chances = BalanceConfig.Hatch.BaseChances
	local caps = BalanceConfig.Hatch.LuckCaps
	return math.max(
		caps.SpeciesMultiplier,
		caps.GoldenChance / chances.Golden,
		caps.RainbowChance / chances.Rainbow,
		caps.ShinyChance / chances.Shiny
	)
end

-- Existing active luck sources compose multiplicatively. The aggregate is
-- bounded once it cannot improve any approved species or direct-variant cap.
function PetHatchMath.combineLuckMultipliers(...)
	local result = 1
	local maximum = maxUsefulLuckMultiplier()
	for index = 1, select("#", ...) do
		local source = normalizedMultiplier(select(index, ...))
		result = math.min(result * source, maximum)
	end
	return result
end

function PetHatchMath.getSpeciesMultiplier(luckMultiplier, eggQualityMultiplier)
	return math.min(
		normalizedMultiplier(luckMultiplier) * normalizedMultiplier(eggQualityMultiplier),
		BalanceConfig.Hatch.LuckCaps.SpeciesMultiplier
	)
end

function PetHatchMath.getEffectiveChances(luckMultiplier, directVariantMultipliers)
	local generalMultiplier = normalizedMultiplier(luckMultiplier)
	local direct = type(directVariantMultipliers) == "table" and directVariantMultipliers or {}
	local base = BalanceConfig.Hatch.BaseChances
	local caps = BalanceConfig.Hatch.LuckCaps
	return {
		Golden = math.min(
			base.Golden * generalMultiplier * normalizedMultiplier(direct.Golden),
			caps.GoldenChance
		),
		Rainbow = math.min(
			base.Rainbow * generalMultiplier * normalizedMultiplier(direct.Rainbow),
			caps.RainbowChance
		),
		Shiny = math.min(
			base.Shiny * generalMultiplier * normalizedMultiplier(direct.Shiny),
			caps.ShinyChance
		),
	}
end

local function normalizedRoll(value)
	if not finiteNumber(value) or value < 0 or value >= 1 then
		return 1
	end
	return value
end

function PetHatchMath.rollOutcome(baseVariantRoll, shinyRoll, luckMultiplier, directVariantMultipliers)
	local chances = PetHatchMath.getEffectiveChances(luckMultiplier, directVariantMultipliers)
	local baseRoll = normalizedRoll(baseVariantRoll)
	local baseVariant = "Normal"

	-- Rainbow owns the first exact probability slice, followed by the complete
	-- Golden slice. Threshold equality advances to the next category.
	if baseRoll < chances.Rainbow then
		baseVariant = "Rainbow"
	elseif baseRoll < chances.Rainbow + chances.Golden then
		baseVariant = "Golden"
	end

	local isShiny = normalizedRoll(shinyRoll) < chances.Shiny
	return baseVariant, isShiny, chances
end

return PetHatchMath
