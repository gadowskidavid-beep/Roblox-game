--[[
	UpgradeTreeService.lua - Server-authoritative purchases for the Vide upgrade tree.
	The renderer and visual data remain in ReplicatedStorage; the server only accepts
	an upgrade ID and independently validates its canonical cost and prerequisites.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local upgradeTreeFolder = ReplicatedStorage
	:WaitForChild("modules")
	:WaitForChild("upgradeTree")
local UpgradeTreeData = require(upgradeTreeFolder:WaitForChild("upgradeTreeData"))

local UpgradeTreeService = {}

UpgradeTreeService._dataService = nil
UpgradeTreeService._currencyService = nil

local upgradeById = {}
for _, tree in pairs(UpgradeTreeData.upgrades) do
	for _, upgrade in ipairs(tree) do
		if type(upgrade.id) == "string" and not upgrade.isPortal and not upgrade.toggleButton then
			upgradeById[upgrade.id] = upgrade
		end
	end
end

local function copyPurchased(purchased)
	local copy = {}
	if type(purchased) ~= "table" then
		return copy
	end
	for upgradeId, isPurchased in pairs(purchased) do
		if type(upgradeId) == "string" and isPurchased == true then
			copy[upgradeId] = true
		end
	end
	return copy
end

function UpgradeTreeService.init(dataService, currencyService)
	UpgradeTreeService._dataService = dataService
	UpgradeTreeService._currencyService = currencyService
end

function UpgradeTreeService.getState(player)
	local data = UpgradeTreeService._dataService.getPlayerData(player)
	if not data then
		return {
			currency = { coins = 0 },
			purchased = {},
		}
	end

	return {
		currency = { coins = data.coins or 0 },
		purchased = copyPurchased(data.upgradeTreePurchases),
	}
end

local function fireUpdate(player)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local event = remotes and remotes:FindFirstChild("UpgradeTreeUpdated")
	if event then
		event:FireClient(player, UpgradeTreeService.getState(player))
	end
end

function UpgradeTreeService.purchase(player, upgradeId)
	if not player or type(upgradeId) ~= "string" or #upgradeId == 0 or #upgradeId > 64 then
		return false, "Invalid upgrade", UpgradeTreeService.getState(player)
	end

	local upgrade = upgradeById[upgradeId]
	if not upgrade then
		return false, "Unknown upgrade", UpgradeTreeService.getState(player)
	end

	local data = UpgradeTreeService._dataService.getPlayerData(player)
	if not data then
		return false, "No player data", UpgradeTreeService.getState(player)
	end

	if type(data.upgradeTreePurchases) ~= "table" then
		data.upgradeTreePurchases = {}
	end
	if data.upgradeTreePurchases[upgradeId] == true then
		return false, "Already purchased", UpgradeTreeService.getState(player)
	end

	for _, requiredId in ipairs(upgrade.requireId or {}) do
		if data.upgradeTreePurchases[requiredId] ~= true then
			return false, "Missing prerequisite", UpgradeTreeService.getState(player)
		end
	end

	local coinCost = 0
	for _, requirement in ipairs(upgrade.requirements or {}) do
		local amount = requirement.amount
		if requirement.currency ~= "coins"
			or type(amount) ~= "number"
			or amount ~= amount
			or amount == math.huge
			or amount == -math.huge
			or amount < 0 then
			return false, "Unsupported requirement", UpgradeTreeService.getState(player)
		end
		coinCost = coinCost + math.floor(amount)
	end

	if coinCost > 0 and not UpgradeTreeService._currencyService.removeCoins(player, coinCost) then
		return false, "Not enough coins", UpgradeTreeService.getState(player)
	end

	data.upgradeTreePurchases[upgradeId] = true
	fireUpdate(player)
	return true, "Purchased", UpgradeTreeService.getState(player)
end

return UpgradeTreeService
