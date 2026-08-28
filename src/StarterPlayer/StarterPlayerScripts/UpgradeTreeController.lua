--[[
	UpgradeTreeController.lua - Server-state adapter for the imported Vide tree.
	QOF-07 adds dual-currency state, purchase feedback/in-flight protection, and
	a touch-accessible open button without changing upgradeTree.lua or Vide.
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

local function initialAvailability()
	local available = {}
	for _, tree in pairs(UpgradeTreeData.upgrades) do
		for _, upgrade in ipairs(tree) do
			if upgrade.runtimeAvailable == true then
				available[upgrade.id] = true
			end
		end
	end
	return available
end

local function createAccessGui(playerGui)
	local gui = Instance.new("ScreenGui")
	gui.Name = "UpgradeTreeAccessGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 25
	gui.Parent = playerGui

	local openButton = Instance.new("TextButton")
	openButton.Name = "OpenUpgradeTree"
	openButton.AnchorPoint = Vector2.new(0, 1)
	openButton.Position = UDim2.new(0, 16, 1, -92)
	openButton.Size = UDim2.fromOffset(72, 72)
	openButton.BackgroundColor3 = Color3.fromRGB(44, 82, 160)
	openButton.Text = "TREE\n[Q]"
	openButton.TextColor3 = Color3.fromRGB(245, 249, 255)
	openButton.TextScaled = true
	openButton.TextWrapped = true
	openButton.Font = Enum.Font.GothamBold
	openButton.AutoButtonColor = true
	openButton.Parent = gui

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 14)
	buttonCorner.Parent = openButton

	local buttonStroke = Instance.new("UIStroke")
	buttonStroke.Color = Color3.fromRGB(116, 184, 255)
	buttonStroke.Thickness = 3
	buttonStroke.Parent = openButton

	local feedback = Instance.new("TextLabel")
	feedback.Name = "PurchaseFeedback"
	feedback.AnchorPoint = Vector2.new(0.5, 0)
	feedback.Position = UDim2.new(0.5, 0, 0, 18)
	feedback.Size = UDim2.new(0.7, 0, 0, 48)
	feedback.BackgroundColor3 = Color3.fromRGB(22, 29, 48)
	feedback.BackgroundTransparency = 0.08
	feedback.TextColor3 = Color3.fromRGB(255, 255, 255)
	feedback.TextScaled = true
	feedback.TextWrapped = true
	feedback.Font = Enum.Font.GothamBold
	feedback.Visible = false
	feedback.ZIndex = 50
	feedback.Parent = gui

	local feedbackConstraint = Instance.new("UISizeConstraint")
	feedbackConstraint.MinSize = Vector2.new(260, 48)
	feedbackConstraint.MaxSize = Vector2.new(680, 48)
	feedbackConstraint.Parent = feedback

	local feedbackCorner = Instance.new("UICorner")
	feedbackCorner.CornerRadius = UDim.new(0, 10)
	feedbackCorner.Parent = feedback

	local feedbackStroke = Instance.new("UIStroke")
	feedbackStroke.Color = Color3.fromRGB(100, 150, 255)
	feedbackStroke.Thickness = 2
	feedbackStroke.Parent = feedback

	return gui, openButton, feedback, feedbackStroke
end

function UpgradeTreeController.new()
	return setmetatable({
		_initialized = false,
		_connections = {},
		_treeCleanup = nil,
		_feedbackToken = 0,
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
	local _, openButton, feedbackLabel, feedbackStroke = createAccessGui(playerGui)

	local currency = Vide.source({
		coins = tonumber(playerData and playerData.coins) or 0,
		diamonds = tonumber(playerData and playerData.diamonds) or 0,
	})
	local purchased = Vide.source(copyMap(playerData and playerData.upgradeTreePurchases))
	local available = Vide.source(initialAvailability())
	local entitlements = Vide.source({})
	local purchasePending = Vide.source(false)

	local function showFeedback(message, success)
		self._feedbackToken += 1
		local token = self._feedbackToken
		feedbackLabel.Text = tostring(message or (success and "Purchase complete" or "Purchase failed"))
		feedbackLabel.TextColor3 = success and Color3.fromRGB(145, 255, 170)
			or Color3.fromRGB(255, 160, 160)
		feedbackStroke.Color = success and Color3.fromRGB(70, 210, 110)
			or Color3.fromRGB(230, 80, 80)
		feedbackLabel.Visible = true
		task.delay(3, function()
			if self._feedbackToken == token then
				feedbackLabel.Visible = false
			end
		end)
	end

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
		if type(serverState.available) == "table" then
			available(copyMap(serverState.available))
		end
		if type(serverState.entitlements) == "table" then
			entitlements(copyMap(serverState.entitlements))
		end
	end

	local state = {}

	function state.isPurchased(upgradeId)
		return purchased()[upgradeId] == true
	end

	function state.isUnlocked(upgrade)
		if state.isPurchased(upgrade.id) then
			return true
		end
		for _, requiredId in ipairs(upgrade.requireId or {}) do
			if not state.isPurchased(requiredId) then
				return false
			end
		end
		return true
	end

	function state.canBuy(upgrade)
		if purchasePending()
			or available()[upgrade.id] ~= true
			or state.isPurchased(upgrade.id)
			or not state.isUnlocked(upgrade) then
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
		if purchasePending() then
			showFeedback("A purchase is already in progress", false)
			return false
		end
		if available()[upgrade.id] ~= true then
			showFeedback("This upgrade is coming in a later QOF", false)
			return false
		end
		if not state.canBuy(upgrade) then
			showFeedback("Missing prerequisite or currency", false)
			return false
		end

		purchasePending(true)
		showFeedback("Purchasing " .. tostring(upgrade.name) .. "…", true)
		local callSucceeded, purchaseSucceeded, message, serverState = pcall(function()
			return purchaseRemote:InvokeServer(upgrade.id)
		end)
		purchasePending(false)

		if callSucceeded then
			applyServerState(serverState)
		end
		if not callSucceeded then
			showFeedback("Purchase request failed — please retry", false)
			return false
		end
		showFeedback(message, purchaseSucceeded == true)
		return purchaseSucceeded == true
	end

	state.currency = currency
	state.purchased = purchased
	state.available = available
	state.entitlements = entitlements

	table.insert(self._connections, currencyUpdated.OnClientEvent:Connect(function(coins, diamonds)
		local nextCurrency = copyMap(currency())
		nextCurrency.coins = tonumber(coins) or 0
		nextCurrency.diamonds = tonumber(diamonds) or 0
		currency(nextCurrency)
	end))

	table.insert(self._connections, updatedRemote.OnClientEvent:Connect(applyServerState))

	local stateCallSucceeded, serverState = pcall(function()
		return getStateRemote:InvokeServer()
	end)
	if stateCallSucceeded then
		applyServerState(serverState)
	end

	local function mountTree(startOpen)
		if self._treeCleanup then
			self._treeCleanup()
			self._treeCleanup = nil
		end
		self._treeCleanup = Vide.mount(function()
			return UpgradeTree(Vide, {
				data = UpgradeTreeData,
				state = state,
				title = "Battle Pets Upgrade Tree",
				toggleKey = Enum.KeyCode.Q,
				startOpen = startOpen,
				enableKeybind = true,
				enableFovZoom = true,
			})
		end, playerGui)
	end

	mountTree(false)
	table.insert(self._connections, openButton.Activated:Connect(function()
		mountTree(true)
	end))
end

return UpgradeTreeController
