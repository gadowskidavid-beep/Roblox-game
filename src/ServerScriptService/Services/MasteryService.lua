--[[
	MasteryService.lua - Mastery point spending system
	Players earn mastery points from level-ups and spend them on buffs.
	Each buff has multiple levels with increasing costs and bonuses.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MasteryData = require(game.ReplicatedStorage.Shared.MasteryData)
local ProgressionMath = require(game.ReplicatedStorage.Shared.ProgressionMath)

local MasteryService = {}

local function finiteNonNegativeInteger(value)
	return type(value) == "number" and value == value and value ~= math.huge
		and value ~= -math.huge and value % 1 == 0 and value >= 0
end

-- References to other services
MasteryService._dataService = nil

function MasteryService.init(dataService)
	MasteryService._dataService = dataService
end

-- Purchase a mastery buff level with mastery points
function MasteryService.purchaseBuff(player, buffId)
	if not player or type(buffId) ~= "string" then
		return false, "Invalid parameters"
	end

	-- Validate buff exists
	local buffDef = MasteryData.Buffs[buffId]
	if not buffDef then
		return false, "Unknown buff: " .. tostring(buffId)
	end

	local data = MasteryService._dataService.getPlayerData(player)
	if not data then
		return false, "No player data"
	end

	-- Ensure mastery tables exist
	if type(data.masteryBuffs) ~= "table" then
		data.masteryBuffs = {}
	end

	local currentLevel, levelWasValid = ProgressionMath.resolveMasteryLevel(
		data.masteryBuffs,
		buffId
	)
	data.masteryBuffs = ProgressionMath.normalizeMasteryLevels(data.masteryBuffs)
	local maxLevel = ProgressionMath.getMasteryMaxLevel(buffId)
	if not levelWasValid then
		return false, "Invalid level"
	end

	-- Validate not max level
	if currentLevel >= maxLevel then
		return false, "Already at max level"
	end

	-- Get cost for next level from the same consistent boundary.
	local cost = buffDef.pointsPerLevel[currentLevel + 1]
	if not finiteNonNegativeInteger(cost) or cost < 1 then
		return false, "Invalid level"
	end

	local availablePoints = data.masteryPoints
	if not finiteNonNegativeInteger(availablePoints) then
		return false, "Invalid mastery points"
	end
	if availablePoints < cost then
		return false, "Not enough mastery points (need " .. tostring(cost) .. ", have " .. tostring(availablePoints) .. ")"
	end

	-- Deduct mastery points and increment buff level
	data.masteryPoints = availablePoints - cost
	data.masteryBuffs[buffId] = currentLevel + 1

	-- Fire mastery update to client
	MasteryService._fireMasteryUpdate(player, data)

	return true, "Upgraded to level " .. tostring(data.masteryBuffs[buffId])
end

-- Get mastery buff bonus value for a player
function MasteryService.getBuffBonus(player, buffId)
	if not player or type(buffId) ~= "string" then
		return 0
	end

	local buffDef = MasteryData.Buffs[buffId]
	if not buffDef then
		return 0
	end

	local data = MasteryService._dataService.getPlayerData(player)
	if not data then
		return 0
	end

	return ProgressionMath.getMasteryBonus(data.masteryBuffs, buffId)
end

-- Get full mastery state for client display
function MasteryService.getMasteryState(player)
	if not player then return {} end

	local data = MasteryService._dataService.getPlayerData(player)
	if not data then return {} end

	return {
		masteryPoints = finiteNonNegativeInteger(data.masteryPoints) and data.masteryPoints or 0,
		level = finiteNonNegativeInteger(data.level) and math.max(data.level, 1) or 1,
		buffs = ProgressionMath.normalizeMasteryLevels(data.masteryBuffs),
	}
end

-- Award a mastery point (called on level-up)
function MasteryService.awardMasteryPoint(player)
	if not player then return end

	local data = MasteryService._dataService.getPlayerData(player)
	if not data then return end

	local masteryPoints = data.masteryPoints
	if not finiteNonNegativeInteger(masteryPoints) then
		masteryPoints = 0
	end
	data.masteryPoints = masteryPoints + 1

	-- Notify client
	MasteryService._fireMasteryUpdate(player, data)
end

-- Fire mastery state update to client
function MasteryService._fireMasteryUpdate(player, data)
	data.masteryBuffs = ProgressionMath.normalizeMasteryLevels(data.masteryBuffs)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local event = remotes:FindFirstChild("MasteryUpdated")
		if event then
			event:FireClient(player, {
				masteryPoints = finiteNonNegativeInteger(data.masteryPoints) and data.masteryPoints or 0,
				level = finiteNonNegativeInteger(data.level) and math.max(data.level, 1) or 1,
				buffs = ProgressionMath.normalizeMasteryLevels(data.masteryBuffs),
			})
		end
	end
end

return MasteryService
