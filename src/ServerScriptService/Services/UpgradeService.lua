--[[
	UpgradeService.lua - Backward-compatible wrapper for quest-based upgrades
	Now delegates to QuestService for upgrade bonuses.
	The old purchaseUpgrade function is removed; upgrades are earned via quests.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuestData = require(game.ReplicatedStorage.Shared.QuestData)
local MasteryData = require(game.ReplicatedStorage.Shared.MasteryData)

local UpgradeService = {}

-- References to other services
UpgradeService._dataService = nil
UpgradeService._currencyService = nil
UpgradeService._questService = nil
UpgradeService._masteryService = nil

function UpgradeService.init(dataService, currencyService)
	UpgradeService._dataService = dataService
	UpgradeService._currencyService = currencyService
end

-- Set quest and mastery service references (called after init)
function UpgradeService.setQuestService(questService)
	UpgradeService._questService = questService
end

function UpgradeService.setMasteryService(masteryService)
	UpgradeService._masteryService = masteryService
end

-- Get current upgrade level for a player (from quest completions)
function UpgradeService.getUpgradeLevel(player, upgradeId)
	if not player or type(upgradeId) ~= "string" then
		return 0
	end

	local data = UpgradeService._dataService.getPlayerData(player)
	if not data then
		return 0
	end

	return data.upgrades[upgradeId] or 0
end

-- Get the bonus value for the current upgrade level
-- Checks both quest-based upgrades AND mastery buffs
function UpgradeService.getUpgradeBonus(player, upgradeId)
	if not player or type(upgradeId) ~= "string" then
		return 0
	end

	-- First check quest-based upgrades
	local questDef = QuestData.Quests[upgradeId]
	if questDef then
		local data = UpgradeService._dataService.getPlayerData(player)
		if not data then
			return 0
		end
		local currentLevel = data.upgrades[upgradeId] or 0
		if currentLevel == 0 then
			return 0
		end
		return questDef.levels[currentLevel].bonus
	end

	-- Check mastery buffs for matching bonus types
	-- Map old upgrade names to mastery buff equivalents
	local masteryMapping = {
		LuckyDrops = "MoreCoins",
		Diamonds = "MoreDiamonds",
	}

	local masteryId = masteryMapping[upgradeId]
	if masteryId and UpgradeService._masteryService then
		return UpgradeService._masteryService.getBuffBonus(player, masteryId)
	end

	return 0
end

-- Old purchaseUpgrade is no longer available - upgrades are quest-based
function UpgradeService.purchaseUpgrade(player, upgradeId)
	return false, "Upgrades are now quest-based. Complete quests to unlock them!"
end

return UpgradeService
