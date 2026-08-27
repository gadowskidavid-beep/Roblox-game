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

local purchaseLocks = setmetatable({}, { __mode = "k" })

local function normalizeLevel(value, maxLevel)
	local numericLevel = tonumber(value)
	if not numericLevel
		or numericLevel ~= numericLevel
		or numericLevel == math.huge
		or numericLevel == -math.huge then
		return 0
	end
	return math.clamp(math.floor(numericLevel), 0, maxLevel)
end

local function normalizePoints(value)
	local numericPoints = tonumber(value)
	if not numericPoints
		or numericPoints ~= numericPoints
		or numericPoints == math.huge
		or numericPoints == -math.huge then
		return 0
	end
	return math.max(0, math.floor(numericPoints))
end

local function buildMasteryState(data)
	return {
		masteryPoints = data.masteryPoints or 0,
		level = data.level or 1,
		buffs = data.masteryBuffs or {},
	}
end

function MasteryService.init(dataService)
	MasteryService._dataService = dataService
end

-- Purchases one ordinary level, or one complete skill-tree node when tierIndex is supplied.
function MasteryService.purchaseBuff(player, buffId, tierIndex)
	if not player or type(buffId) ~= "string" then
		return false, "Invalid parameters"
	end
	if purchaseLocks[player] then
		return false, "A mastery purchase is already in progress"
	end

	purchaseLocks[player] = true
	local ok, success, message, state = pcall(function()
		local buffDef = MasteryData.Buffs[buffId]
		if not buffDef then
			return false, "Unknown buff: " .. tostring(buffId)
		end

		local data = MasteryService._dataService.getPlayerData(player)
		if not data then
			return false, "No player data"
		end

		if not data.masteryBuffs then
			data.masteryBuffs = {}
		end

		local currentLevel = normalizeLevel(data.masteryBuffs[buffId], buffDef.maxLevel)
		local treeBuff = MasteryData.SkillTree.buffs[buffId]
		local targetLevel
		local cost = 0

		if treeBuff then
			if type(tierIndex) ~= "number" or tierIndex % 1 ~= 0 then
				return false, "A valid tier is required for this skill-tree buff"
			end

			local tier = MasteryData.SkillTree.tiers[tierIndex]
			if not tier then
				return false, "Invalid mastery tier"
			end

			local activeTierIndex
			for index, candidateTier in ipairs(MasteryData.SkillTree.tiers) do
				if currentLevel < candidateTier.lastLevel then
					activeTierIndex = index
					break
				end
			end
			if not activeTierIndex then
				return false, "Already at max level"
			end
			if tierIndex < activeTierIndex then
				return false, "That skill-tree node is already purchased"
			elseif tierIndex > activeTierIndex then
				return false, "Purchase the previous skill-tree node first"
			end

			targetLevel = math.min(tier.lastLevel, buffDef.maxLevel)
			for level = currentLevel + 1, targetLevel do
				local levelCost = tonumber(buffDef.pointsPerLevel[level])
				if not levelCost or levelCost < 0 then
					return false, "Invalid mastery cost data"
				end
				cost += levelCost
			end
		else
			if tierIndex ~= nil then
				return false, "This mastery buff does not use skill-tree tiers"
			end
			if currentLevel >= buffDef.maxLevel then
				return false, "Already at max level"
			end
			targetLevel = currentLevel + 1
			cost = tonumber(buffDef.pointsPerLevel[targetLevel])
			if not cost or cost < 0 then
				return false, "Invalid mastery cost data"
			end
		end

		local availablePoints = normalizePoints(data.masteryPoints)
		if availablePoints < cost then
			return false, "Not enough mastery points (need " .. tostring(cost)
				.. ", have " .. tostring(availablePoints) .. ")"
		end

		-- These two assignments form the complete purchase mutation and do not yield.
		data.masteryPoints = availablePoints - cost
		data.masteryBuffs[buffId] = targetLevel

		local updatedState = buildMasteryState(data)
		MasteryService._fireMasteryUpdate(player, data)
		return true, "Upgraded to level " .. tostring(targetLevel), updatedState
	end)
	purchaseLocks[player] = nil

	if not ok then
		warn("Mastery purchase failed: " .. tostring(success))
		return false, "Mastery purchase failed"
	end
	return success, message, state
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

	local currentLevel = normalizeLevel(data.masteryBuffs[buffId], buffDef.maxLevel)
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

	return buildMasteryState(data)
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
			event:FireClient(player, buildMasteryState(data))
		end
	end
end

return MasteryService
