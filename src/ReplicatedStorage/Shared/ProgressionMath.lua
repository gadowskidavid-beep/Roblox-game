--[[
	ProgressionMath.lua - Canonical QOF-23 progression boundaries.
	Persistent and live values share the same fail-closed integer validation so
	no caller can index a quest/mastery definition with hostile profile data.
]]

local QuestData = require(game.ReplicatedStorage.Shared.QuestData)
local MasteryData = require(game.ReplicatedStorage.Shared.MasteryData)

local ProgressionMath = {}

local function finiteInteger(value)
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
		and value % 1 == 0
end

local function contiguousTableLength(values)
	if type(values) ~= "table" then
		return 0
	end
	local length = 0
	while values[length + 1] ~= nil do
		length = length + 1
	end
	return length
end

function ProgressionMath.getQuestMaxLevel(upgradeId)
	if type(upgradeId) ~= "string" then
		return 0
	end
	local definition = QuestData.Quests[upgradeId]
	if type(definition) ~= "table" then
		return 0
	end
	return contiguousTableLength(definition.levels)
end

function ProgressionMath.getMasteryMaxLevel(buffId)
	if type(buffId) ~= "string" then
		return 0
	end
	local definition = MasteryData.Buffs[buffId]
	if type(definition) ~= "table" or not finiteInteger(definition.maxLevel)
		or definition.maxLevel < 0 then
		return 0
	end
	return math.min(
		definition.maxLevel,
		contiguousTableLength(definition.pointsPerLevel),
		contiguousTableLength(definition.bonusPerLevel)
	)
end

local function resolveLevel(values, id, maximum)
	if type(values) ~= "table" or maximum < 1 then
		return 0, false
	end
	local value = values[id]
	if value == nil then
		return 0, true
	end
	if not finiteInteger(value) or value < 0 or value > maximum then
		return 0, false
	end
	return value, true
end

function ProgressionMath.resolveQuestLevel(values, upgradeId)
	return resolveLevel(values, upgradeId, ProgressionMath.getQuestMaxLevel(upgradeId))
end

function ProgressionMath.resolveMasteryLevel(values, buffId)
	return resolveLevel(values, buffId, ProgressionMath.getMasteryMaxLevel(buffId))
end

function ProgressionMath.normalizeQuestLevels(values)
	local normalized = {}
	for upgradeId in pairs(QuestData.Quests) do
		local level = ProgressionMath.resolveQuestLevel(values, upgradeId)
		if level > 0 then
			normalized[upgradeId] = level
		end
	end
	return normalized
end

function ProgressionMath.normalizeMasteryLevels(values)
	local normalized = {}
	for buffId in pairs(MasteryData.Buffs) do
		local level = ProgressionMath.resolveMasteryLevel(values, buffId)
		if level > 0 then
			normalized[buffId] = level
		end
	end
	return normalized
end

function ProgressionMath.getQuestBonus(values, upgradeId)
	local level = ProgressionMath.resolveQuestLevel(values, upgradeId)
	if level == 0 then
		return 0
	end
	local levelDefinition = QuestData.Quests[upgradeId].levels[level]
	local bonus = type(levelDefinition) == "table" and levelDefinition.bonus or nil
	if type(bonus) ~= "number" or bonus ~= bonus or bonus == math.huge or bonus == -math.huge then
		return 0
	end
	return bonus
end

function ProgressionMath.getMasteryBonus(values, buffId)
	local level = ProgressionMath.resolveMasteryLevel(values, buffId)
	if level == 0 then
		return 0
	end
	local bonus = MasteryData.Buffs[buffId].bonusPerLevel[level]
	if type(bonus) ~= "number" or bonus ~= bonus or bonus == math.huge or bonus == -math.huge then
		return 0
	end
	return bonus
end

return ProgressionMath
