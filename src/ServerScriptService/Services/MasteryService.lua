--[[
	MasteryService.lua - Mastery point spending system
	Players earn mastery points from level-ups and spend them on buffs.
	Each buff has multiple levels with increasing costs and bonuses.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MasteryData = require(game.ReplicatedStorage.Shared.MasteryData)

local MasteryService = {}

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
	if not data.masteryBuffs then
		data.masteryBuffs = {}
	end

	-- Get current level of this buff
	local currentLevel = data.masteryBuffs[buffId] or 0
	local maxLevel = buffDef.maxLevel

	-- Validate not max level
	if currentLevel >= maxLevel then
		return false, "Already at max level"
	end

	-- Get cost for next level
	local cost = buffDef.pointsPerLevel[currentLevel + 1]
	if not cost then
		return false, "Invalid level"
	end

	-- Check if player has enough mastery points
	local availablePoints = (data.masteryPoints or 0)
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

	if not data.masteryBuffs then
		return 0
	end

	local currentLevel = data.masteryBuffs[buffId] or 0
	if currentLevel == 0 then
		return 0
	end

	return buffDef.bonusPerLevel[currentLevel]
end

-- Get full mastery state for client display
function MasteryService.getMasteryState(player)
	if not player then return {} end

	local data = MasteryService._dataService.getPlayerData(player)
	if not data then return {} end

	return {
		masteryPoints = data.masteryPoints or 0,
		level = data.level or 1,
		buffs = data.masteryBuffs or {},
	}
end

-- Award a mastery point (called on level-up)
function MasteryService.awardMasteryPoint(player)
	if not player then return end

	local data = MasteryService._dataService.getPlayerData(player)
	if not data then return end

	data.masteryPoints = (data.masteryPoints or 0) + 1

	-- Notify client
	MasteryService._fireMasteryUpdate(player, data)
end

-- Fire mastery state update to client
function MasteryService._fireMasteryUpdate(player, data)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local event = remotes:FindFirstChild("MasteryUpdated")
		if event then
			event:FireClient(player, {
				masteryPoints = data.masteryPoints or 0,
				level = data.level or 1,
				buffs = data.masteryBuffs or {},
			})
		end
	end
end

return MasteryService
