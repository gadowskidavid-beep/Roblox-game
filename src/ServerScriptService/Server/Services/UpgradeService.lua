--[[
	UpgradeService.lua - Manages purchasing and querying upgrades
	Validates costs, deducts currency, and increments upgrade levels.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(game.ReplicatedStorage.Shared.Config)

local UpgradeService = {}

-- References to other services
UpgradeService._dataService = nil
UpgradeService._currencyService = nil

function UpgradeService.init(dataService, currencyService)
	UpgradeService._dataService = dataService
	UpgradeService._currencyService = currencyService
end

-- Purchase an upgrade for a player
function UpgradeService.purchaseUpgrade(player, upgradeId)
	if not player or type(upgradeId) ~= "string" then
		return false, "Invalid parameters"
	end

	-- Validate upgrade exists
	local upgradeDef = Config.Upgrades[upgradeId]
	if not upgradeDef then
		return false, "Unknown upgrade: " .. tostring(upgradeId)
	end

	local data = UpgradeService._dataService.getPlayerData(player)
	if not data then
		return false, "No player data"
	end

	-- Get current level (0 if not purchased yet)
	local currentLevel = data.upgrades[upgradeId] or 0
	local maxLevel = #upgradeDef.levels

	-- Validate not max level
	if currentLevel >= maxLevel then
		return false, "Already at max level"
	end

	-- Get cost for next level
	local nextLevelData = upgradeDef.levels[currentLevel + 1]
	local cost = nextLevelData.cost

	-- Deduct coins
	local success = UpgradeService._currencyService.removeCoins(player, cost)
	if not success then
		return false, "Not enough coins"
	end

	-- Increment upgrade level
	data.upgrades[upgradeId] = currentLevel + 1

	-- Fire client update
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local event = remotes:FindFirstChild("UpgradeUpdated")
		if event then
			event:FireClient(player, data.upgrades)
		end
	end

	return true, "Upgraded to level " .. tostring(data.upgrades[upgradeId])
end

-- Get current upgrade level for a player
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
function UpgradeService.getUpgradeBonus(player, upgradeId)
	if not player or type(upgradeId) ~= "string" then
		return 0
	end

	local upgradeDef = Config.Upgrades[upgradeId]
	if not upgradeDef then
		return 0
	end

	local data = UpgradeService._dataService.getPlayerData(player)
	if not data then
		return 0
	end

	local currentLevel = data.upgrades[upgradeId] or 0
	if currentLevel == 0 then
		return 0
	end

	return upgradeDef.levels[currentLevel].bonus
end

return UpgradeService
