--[[
	UpgradeTreeController.lua - Mounts the imported Vide upgrade tree in Battle Pets.
	Q opens the tree. Purchases are sent to UpgradeTreeService and are never trusted
	from the local Vide state alone.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local packages = ReplicatedStorage:WaitForChild("packages")
local modules = ReplicatedStorage:WaitForChild("modules")
local upgradeTreeFolder = modules:WaitForChild("upgradeTree")

local Vide = require(packages:WaitForChild("vide"))
local UpgradeTree = require(upgradeTreeFolder:WaitForChild("upgradeTree"))
local UpgradeTreeData = require(upgradeTreeFolder:WaitForChild("upgradeTreeData"))

local UpgradeTreeController = {}
UpgradeTreeController.__index = UpgradeTreeController

local function copyMap(input)
	local output = {}
	if type(input) ~= "table" then
		return output
	end
	for key, value in pairs(input) do
		output[key] = value
	end
	return output
end

function UpgradeTreeController.new()
	return setmetatable({
		_initialized = false,
		_connections = {},
	}, UpgradeTreeController)
end

function UpgradeTreeController:init(remotes, playerData)
	if self._initialized then
		return
	end
	self._initialized = true

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local purchaseRemote = remotes:WaitForChild("PurchaseTreeUpgrade")
	local getStateRemote = remotes:WaitForChild("GetUpgradeTreeState")
	local updatedRemote = remotes:WaitForChild("UpgradeTreeUpdated")
	local currencyUpdated = remotes:WaitForChild("CurrencyUpdated")

	local currency = Vide.source({
		coins = tonumber(playerData and playerData.coins) or 0,
	})
	local purchased = Vide.source(copyMap(playerData and playerData.upgradeTreePurchases))

	local function applyServerState(serverState)
		if type(serverState) ~= "table" then
			return
		end
		if type(serverState.currency) == "table" then
			currency(copyMap(serverState.currency))
		end
		if type(serverState.purchased) == "table" then
			purchased(copyMap(serverState.purchased))
		end
	end

	local state = {}

	function state.isPurchased(upgradeId)
		return purchased()[upgradeId] == true
	end

	function state.isUnlocked(upgrade)
		for _, requiredId in ipairs(upgrade.requireId or {}) do
			if not state.isPurchased(requiredId) then
				return false
			end
		end
		return true
	end

	function state.canBuy(upgrade)
		if state.isPurchased(upgrade.id) or not state.isUnlocked(upgrade) then
			return false
		end
		local balances = currency()
		for _, requirement in ipairs(upgrade.requirements or {}) do
			if (balances[requirement.currency] or 0) < requirement.amount then
				return false
			end
		end
		return true
	end

	function state.buy(upgrade)
		if not state.canBuy(upgrade) then
			return false
		end
		local callSucceeded, purchaseSucceeded, _message, serverState = pcall(function()
			return purchaseRemote:InvokeServer(upgrade.id)
		end)
		if not callSucceeded or purchaseSucceeded ~= true then
			if callSucceeded then
				applyServerState(serverState)
			end
			return false
		end
		applyServerState(serverState)
		return true
	end

	state.currency = currency
	state.purchased = purchased

	table.insert(self._connections, currencyUpdated.OnClientEvent:Connect(function(coins)
		local nextCurrency = copyMap(currency())
		nextCurrency.coins = tonumber(coins) or 0
		currency(nextCurrency)
	end))

	table.insert(self._connections, updatedRemote.OnClientEvent:Connect(applyServerState))

	local stateCallSucceeded, serverState = pcall(function()
		return getStateRemote:InvokeServer()
	end)
	if stateCallSucceeded then
		applyServerState(serverState)
	end

	Vide.mount(function()
		return UpgradeTree(Vide, {
			data = UpgradeTreeData,
			state = state,
			title = "Battle Pets Upgrade Tree",
			toggleKey = Enum.KeyCode.Q,
			startOpen = false,
			enableKeybind = true,
			enableFovZoom = true,
		})
	end, playerGui)
end

return UpgradeTreeController
