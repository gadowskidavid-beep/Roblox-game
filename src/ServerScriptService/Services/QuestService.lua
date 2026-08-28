--[[
	QuestService.lua - Quest-based upgrade system
	Tracks quest progress (destroys, hatches, coins earned, playtime, levels,
	golden pet conversions) and awards upgrades when milestones are reached.
	Replaces the old coin-buying upgrade model.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuestData = require(game.ReplicatedStorage.Shared.QuestData)
local ProgressionMath = require(game.ReplicatedStorage.Shared.ProgressionMath)

local QuestService = {}

local function finiteNonNegativeNumber(value)
	if type(value) ~= "number" or value ~= value or value == math.huge
		or value == -math.huge or value < 0 then
		return 0
	end
	return value
end

-- References to other services
QuestService._dataService = nil
QuestService._currencyService = nil

function QuestService.init(dataService, currencyService)
	QuestService._dataService = dataService
	QuestService._currencyService = currencyService
end

-- Increment a quest stat for a player and check for quest completions
-- statType: "destroyDestructibles", "hatchEggs", "earnCoins", "playtime", "goldenPetsConverted"
-- amount: how much to increment (default 1)
function QuestService.incrementStat(player, statType, amount)
	if not player or type(statType) ~= "string" then return end
	amount = amount == nil and 1 or amount
	if type(amount) ~= "number" or amount ~= amount or amount == math.huge
		or amount == -math.huge or amount <= 0 then
		return
	end

	local data = QuestService._dataService.getPlayerData(player)
	if not data then return end

	if type(data.questStats) ~= "table" then
		data.questStats = {}
	end

	data.questStats[statType] = finiteNonNegativeNumber(data.questStats[statType]) + amount

	-- Check all quests to see if any new levels have been unlocked
	QuestService._checkQuestCompletions(player, data)
end

-- Set a quest stat to a specific value (used for level-based checks)
-- This is for stats like "reachLevel" where the value is the current state, not cumulative
function QuestService.setStat(player, statType, value)
	if not player or type(statType) ~= "string" or type(value) ~= "number"
		or value ~= value or value == math.huge or value == -math.huge or value < 0 then
		return
	end

	local data = QuestService._dataService.getPlayerData(player)
	if not data then return end

	if type(data.questStats) ~= "table" then
		data.questStats = {}
	end

	local current = finiteNonNegativeNumber(data.questStats[statType])
	if value > current then
		data.questStats[statType] = value
		QuestService._checkQuestCompletions(player, data)
	end
end

-- Internal: check all quest completions and award upgrades
function QuestService._checkQuestCompletions(player, data)
	local upgradesChanged = false
	data.upgrades = ProgressionMath.normalizeQuestLevels(data.upgrades)
	local questStats = type(data.questStats) == "table" and data.questStats or {}

	for questId, questDef in pairs(QuestData.Quests) do
		local statType = questDef.requirement.type
		local maxLevel = ProgressionMath.getQuestMaxLevel(questId)
		local currentLevel = ProgressionMath.resolveQuestLevel(data.upgrades, questId)

		-- Award every milestone already covered by the current stat. This matters for
		-- migrated profiles and large one-shot progress gains.
		local currentStat = finiteNonNegativeNumber(questStats[statType])
		while currentLevel < maxLevel do
			local requiredForNext = questDef.levelRequirements[currentLevel + 1]
			if type(requiredForNext) ~= "number" or requiredForNext ~= requiredForNext
				or requiredForNext == math.huge or requiredForNext == -math.huge
				or currentStat < requiredForNext then
				break
			end
			currentLevel = currentLevel + 1
			data.upgrades[questId] = currentLevel
			upgradesChanged = true
		end
	end

	-- If any upgrades changed, notify client
	if upgradesChanged then
		QuestService._fireUpgradeUpdate(player, data)
		QuestService._fireQuestUpdate(player, data)
	end
end

-- Get current quest progress for the client
function QuestService.getQuestProgress(player)
	if not player then return {} end

	local data = QuestService._dataService.getPlayerData(player)
	if not data then return {} end

	local progress = {}
	local questStats = type(data.questStats) == "table" and data.questStats or {}

	for _, questId in ipairs(QuestData.QuestOrder) do
		local questDef = QuestData.Quests[questId]
		if questDef then
			local currentLevel = ProgressionMath.resolveQuestLevel(data.upgrades, questId)
			local maxLevel = ProgressionMath.getQuestMaxLevel(questId)
			local statType = questDef.requirement.type
			local currentStat = finiteNonNegativeNumber(questStats[statType])

			-- Determine next requirement
			local nextRequired = 0
			if currentLevel < maxLevel then
				nextRequired = questDef.levelRequirements[currentLevel + 1]
			end

			progress[questId] = {
				currentLevel = currentLevel,
				maxLevel = maxLevel,
				currentProgress = currentStat,
				nextRequired = nextRequired,
				completed = currentLevel >= maxLevel,
			}
		end
	end

	return progress
end

-- Get upgrade level (backward compat with old UpgradeService interface)
function QuestService.getUpgradeLevel(player, upgradeId)
	if not player or type(upgradeId) ~= "string" then
		return 0
	end

	local data = QuestService._dataService.getPlayerData(player)
	if not data then
		return 0
	end

	return ProgressionMath.resolveQuestLevel(data.upgrades, upgradeId)
end

-- Get the bonus value for current upgrade level (backward compat)
function QuestService.getUpgradeBonus(player, upgradeId)
	if not player or type(upgradeId) ~= "string" then
		return 0
	end

	local questDef = QuestData.Quests[upgradeId]
	if not questDef then
		return 0
	end

	local data = QuestService._dataService.getPlayerData(player)
	if not data then
		return 0
	end

	return ProgressionMath.getQuestBonus(data.upgrades, upgradeId)
end

-- Fire upgrade update to client
function QuestService._fireUpgradeUpdate(player, data)
	data.upgrades = ProgressionMath.normalizeQuestLevels(data.upgrades)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local event = remotes:FindFirstChild("UpgradeUpdated")
		if event then
			event:FireClient(player, ProgressionMath.normalizeQuestLevels(data.upgrades))
		end
	end
end

-- Fire quest progress update to client
function QuestService._fireQuestUpdate(player, data)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local event = remotes:FindFirstChild("QuestProgressUpdated")
		if event then
			event:FireClient(player, QuestService.getQuestProgress(player))
		end
	end
end

return QuestService
