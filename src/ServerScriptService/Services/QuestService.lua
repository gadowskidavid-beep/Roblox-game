--[[
	QuestService.lua - Quest-based upgrade system
	Tracks quest progress (destroys, hatches, coins earned) and awards upgrades
	when milestones are reached. Replaces the old coin-buying upgrade model.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuestData = require(game.ReplicatedStorage.Shared.QuestData)

local QuestService = {}

-- References to other services
QuestService._dataService = nil
QuestService._currencyService = nil

function QuestService.init(dataService, currencyService)
	QuestService._dataService = dataService
	QuestService._currencyService = currencyService
end

-- Increment a quest stat for a player and check for quest completions
-- statType: "destroyDestructibles", "hatchEggs", "earnCoins", "destroyType"
-- amount: how much to increment (default 1)
function QuestService.incrementStat(player, statType, amount)
	if not player or not statType then return end
	amount = amount or 1

	local data = QuestService._dataService.getPlayerData(player)
	if not data then return end

	-- Ensure questStats table exists
	if not data.questStats then
		data.questStats = {}
	end

	-- Increment the stat
	data.questStats[statType] = (data.questStats[statType] or 0) + amount

	-- Check all quests to see if any new levels have been unlocked
	local upgradesChanged = false
	for questId, questDef in pairs(QuestData.Quests) do
		if questDef.requirement.type == statType then
			local currentLevel = data.upgrades[questId] or 0
			local maxLevel = #questDef.levels

			-- Check if current stat meets any unachieved level requirement
			if currentLevel < maxLevel then
				local currentStat = data.questStats[statType] or 0
				local requiredForNext = questDef.levelRequirements[currentLevel + 1]

				if currentStat >= requiredForNext then
					-- Award the upgrade level
					data.upgrades[questId] = currentLevel + 1
					upgradesChanged = true
				end
			end
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
	local questStats = data.questStats or {}

	for _, questId in ipairs(QuestData.QuestOrder) do
		local questDef = QuestData.Quests[questId]
		if questDef then
			local currentLevel = data.upgrades[questId] or 0
			local maxLevel = #questDef.levels
			local statType = questDef.requirement.type
			local currentStat = questStats[statType] or 0

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

	return data.upgrades[upgradeId] or 0
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

	local currentLevel = data.upgrades[upgradeId] or 0
	if currentLevel == 0 then
		return 0
	end

	return questDef.levels[currentLevel].bonus
end

-- Fire upgrade update to client
function QuestService._fireUpgradeUpdate(player, data)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local event = remotes:FindFirstChild("UpgradeUpdated")
		if event then
			event:FireClient(player, data.upgrades)
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
