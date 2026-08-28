--[[
	UIController.lua - Complete Pet Simulator 1 style UI for Battle Pets
	Creates all UI elements procedurally via code (no external assets).
	Responsive layout using UDim2 scale values for PC, tablet, and phone.
	
	Screens:
	- MainHUD: currency display, XP bar, navigation buttons, equipped pets bar
	- PetInventory: scrollable pet grid with equip/delete/multi-select
	- QuestWindow: quest-based upgrades with progress bars
	- MasteryWindow: mastery buff spending tab
	- ShopWindow: egg station hatch prompt (station-based, like Pet Simulator)
	- CampaignSelect: delegated to CampaignController but toggled from here
	
	Style: Large rounded buttons, thick UIStroke borders, bright saturated colors,
	dark navy backgrounds, bold text, cartoon style.
]]

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local BalanceConfig = require(Shared:WaitForChild("BalanceConfig"))
local PetData = require(Shared:WaitForChild("PetData"))
local QuestData = require(Shared:WaitForChild("QuestData"))
local MasteryData = require(Shared:WaitForChild("MasteryData"))
local ZoneData = require(Shared:WaitForChild("ZoneData"))
local ShopData = require(Shared:WaitForChild("ShopData"))
local PetVariantPresentation = require(Shared:WaitForChild("PetVariantPresentation"))

local UIController = {}
UIController.__index = UIController

-- Color palette (Pet Simulator 1 style: bright, saturated, cartoon)
local COLORS = {
	Background = Color3.fromRGB(30, 40, 80),
	DarkBg = Color3.fromRGB(20, 28, 60),
	NavPets = Color3.fromRGB(0, 200, 80),
	NavQuests = Color3.fromRGB(255, 150, 0),
	NavMastery = Color3.fromRGB(180, 80, 255),
	NavShop = Color3.fromRGB(0, 150, 255),
	NavSettings = Color3.fromRGB(120, 120, 140),
	NavFavorit = Color3.fromRGB(255, 100, 180),
	CoinYellow = Color3.fromRGB(255, 220, 0),
	DiamondCyan = Color3.fromRGB(0, 200, 255),
	ButtonGreen = Color3.fromRGB(0, 200, 80),
	ButtonRed = Color3.fromRGB(220, 50, 50),
	White = Color3.fromRGB(255, 255, 255),
	CloseRed = Color3.fromRGB(220, 50, 50),
	XPBarOuter = Color3.fromRGB(30, 30, 50),
	XPBarFill = Color3.fromRGB(0, 200, 100),
	QuestProgressBg = Color3.fromRGB(40, 50, 80),
	QuestProgressFill = Color3.fromRGB(0, 200, 80),
	MasteryPurple = Color3.fromRGB(180, 80, 255),
}

local RARITY_COLORS = {
	Common = Color3.fromRGB(255, 255, 255),
	Uncommon = Color3.fromRGB(0, 200, 0),
	Rare = Color3.fromRGB(0, 120, 255),
	Epic = Color3.fromRGB(180, 0, 255),
	Legendary = Color3.fromRGB(255, 200, 0),
}

local PET_SORT_MODES = { "Default", "Rarity", "Variant", "Damage" }
local PET_VARIANT_FILTERS = { "All", "Normal", "Golden", "Shiny", "Rainbow" }
local RARITY_RANK = {
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
}
local VARIANT_RANK = {
	Normal = 1,
	Golden = 2,
	Shiny = 3,
	Rainbow = 4,
}

local function resolvePetVariant(petData)
	return PetVariantPresentation.resolve(petData).legacyCategory
end

local function rgbToColor(rgb)
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function getPetDamage(petData)
	return tonumber(petData.damage) or tonumber(petData.baseDamage) or 0
end

local function normalizeZoneId(zoneId)
	local numericZoneId = tonumber(zoneId)
	if not numericZoneId
		or numericZoneId ~= numericZoneId
		or numericZoneId == math.huge
		or numericZoneId == -math.huge
		or numericZoneId % 1 ~= 0
		or not ZoneData.Zones[numericZoneId] then
		return nil
	end
	return numericZoneId
end

local function safeSlotBonus(value)
	local numeric = tonumber(value)
	if not numeric
		or numeric ~= numeric
		or numeric == math.huge
		or numeric == -math.huge
		or numeric <= 0 then
		return 0
	end
	return math.floor(numeric)
end

local function resolveLevelBonus(definition, rawLevel, valuesKey)
	if type(definition) ~= "table" then return 0 end
	local level = tonumber(rawLevel)
	if not level
		or level ~= level
		or level == math.huge
		or level == -math.huge
		or level < 1
		or level % 1 ~= 0 then
		return 0
	end
	local values = definition[valuesKey]
	if type(values) ~= "table" then return 0 end
	local levelValue = values[level]
	if valuesKey == "levels" then
		levelValue = type(levelValue) == "table" and levelValue.bonus or nil
	end
	return safeSlotBonus(levelValue)
end

local function sanitizeDefinedLevels(source, definitions, valuesKey)
	source = type(source) == "table" and source or {}
	local normalized = {}
	for id, definition in pairs(type(definitions) == "table" and definitions or {}) do
		local rawLevel = tonumber(source[id])
		local values = type(definition) == "table" and definition[valuesKey] or nil
		if rawLevel
			and rawLevel == rawLevel
			and rawLevel ~= math.huge
			and rawLevel ~= -math.huge
			and rawLevel >= 0
			and rawLevel % 1 == 0
			and (rawLevel == 0 or (type(values) == "table" and values[rawLevel] ~= nil)) then
			normalized[id] = rawLevel
		else
			normalized[id] = 0
		end
	end
	return normalized
end

function UIController.new()
	local self = setmetatable({}, UIController)
	self._remotes = nil
	self._player = nil
	self._playerGui = nil
	self._screens = {}
	self._coinLabel = nil
	self._diamondLabel = nil
	self._eggShortfallLabel = nil
	self._zoneProgressLabel = nil
	self._coins = 0
	self._diamonds = 0
	self._unlockedZones = { [1] = true }
	self._selectedEggType = nil
	self._hatchPurchaseGui = nil
	self._hatchPurchasePanel = nil
	self._hatchPurchaseTitle = nil
	self._hatchPurchaseUnitPrice = nil
	self._hatchPurchaseFeedback = nil
	self._hatchPurchaseRefreshButton = nil
	self._hatchPurchaseOptionButtons = {}
	self._hatchPurchaseCallbacks = {}
	self._hatchPurchaseConnections = {}
	self._activeHatchPurchaseEggType = nil
	self._xpFill = nil
	self._xpLevelLabel = nil
	self._petInventoryData = {}
	self._inventoryTitle = nil
	self._equippedTitle = nil
	self._petSortMode = "Default"
	self._petVariantFilter = "All"
	self._petSortButton = nil
	self._petVariantFilterButton = nil
	self._upgradeData = {}
	self._treeEntitlements = {
		storageBonusSlots = 0,
		petEquipBonusSlots = 0,
	}
	self._equippedPets = {}
	self._equippedBar = nil
	self._multiSelectMode = false
	self._selectedPets = {}
	self._favoriteRequests = {}
	self._currentZone = 1
	self._initialized = false
	-- Quest and mastery state
	self._questProgress = {}
	self._masteryState = { masteryPoints = 0, level = 1, buffs = {} }
	-- Pet index (collection book) state
	self._discoveredPets = {}
	-- Shop state and live countdown UI
	self._shopBuffs = {}
	self._shopState = {
		buffs = {},
		purchases = { extraEquipSlots = 0 },
		maxExtraEquipSlots = ShopData.Items.ExtraEquipSlot.maxPurchases or 5,
	}
	self._shopBuffExpiry = {}
	self._shopCards = {}
	self._shopDiamondLabel = nil
	self._shopFeedbackLabel = nil
	self._shopFeedbackToken = 0
	self._shopPurchaseInFlight = nil
	self._shopTimerConnection = nil
	self._shopConnections = {}
	self._screenAnimationTokens = {}
	self._screenStates = {}
	self._screenRestingPositions = {}
	-- New pet discovery toast queue
	self._discoveryToastQueue = {}
	self._discoveryToastActive = false
	self._activeDiscoveryToast = nil
	-- Lightweight onboarding hint state
	self._onboardingCard = nil
	self._onboardingTitle = nil
	self._onboardingText = nil
	self._onboardingArrow = nil
	return self
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------
function UIController:init(remotes, playerData)
	self._remotes = remotes
	self._player = Players.LocalPlayer
	self._playerGui = self._player:WaitForChild("PlayerGui")

	-- Apply initial player data
	if playerData then
		self._coins = tonumber(playerData.coins) or 0
		self._diamonds = tonumber(playerData.diamonds) or 0
		self._unlockedZones = {}
		for _, zoneId in ipairs(playerData.unlockedZones or { 1 }) do
			local numericZoneId = normalizeZoneId(zoneId)
			if numericZoneId then
				self._unlockedZones[numericZoneId] = true
			end
		end
		self._unlockedZones[1] = true
		self._petInventoryData = type(playerData.pets) == "table" and playerData.pets or {}
		self._equippedPets = type(playerData.equippedPets) == "table" and playerData.equippedPets or {}
		self._upgradeData = sanitizeDefinedLevels(playerData.upgrades, QuestData.Quests, "levels")
		self._currentZone = playerData.currentZone or 1
		self._masteryState = {
			masteryPoints = playerData.masteryPoints or 0,
			level = playerData.level or 1,
			buffs = sanitizeDefinedLevels(playerData.masteryBuffs, MasteryData.Buffs, "bonusPerLevel"),
		}
		self._discoveredPets = playerData.discoveredPets or {}
		local initialPurchases = type(playerData.shopPurchases) == "table" and playerData.shopPurchases or {}
		local maxExtraEquipSlots = safeSlotBonus(self._shopState.maxExtraEquipSlots)
		self._shopState.purchases.extraEquipSlots = math.clamp(
			safeSlotBonus(initialPurchases.extraEquipSlots),
			0,
			maxExtraEquipSlots
		)
	end

	-- Create all UI
	self:_createMainHUD(playerData)
	self:_createPetInventory()
	self:_createQuestWindow()
	self:_createMasteryWindow()
	self:_createShopWindow()
	self:_createShopScreen()
	self:_createPetIndex()

	self._initialized = true
end

--------------------------------------------------------------------------------
-- MAIN HUD
--------------------------------------------------------------------------------
function UIController:_createMainHUD(playerData)
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MainHUD"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = self._playerGui
	self._screens.MainHUD = screenGui

	-- ===== TOP-RIGHT: Currency Display =====
	self:_createCurrencyDisplay(screenGui, playerData)

	-- ===== BOTTOM-CENTER: Level/XP Bar =====
	self:_createXPBar(screenGui, playerData)

	-- ===== BOTTOM-RIGHT: Navigation Buttons =====
	self:_createNavButtons(screenGui)

	-- ===== NON-BLOCKING ONBOARDING HINT =====
	self:_createOnboardingHint(screenGui)

	-- ===== EQUIPPED CAPACITY (display only; server remains authoritative) =====
	self:_createEquippedCapacityDisplay(screenGui)

	-- ===== QOF-10 MANUAL HATCH PURCHASE DIALOG =====
	self:_createHatchPurchaseDialog()
end

function UIController:_createEquippedCapacityDisplay(parent)
	local panel = Instance.new("Frame")
	panel.Name = "EquippedCapacity"
	panel.Size = UDim2.new(0.3, 0, 0, 52)
	panel.Position = UDim2.fromScale(0.02, 0.04)
	panel.BackgroundColor3 = COLORS.DarkBg
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.Parent = parent

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(180, 52)
	sizeConstraint.MaxSize = Vector2.new(360, 52)
	sizeConstraint.Parent = panel

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = COLORS.NavPets
	stroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -16, 1, -10)
	title.Position = UDim2.fromOffset(8, 5)
	title.BackgroundTransparency = 1
	title.TextColor3 = COLORS.White
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextWrapped = true
	title.Parent = panel
	self._equippedTitle = title
	self:_refreshCapacityUI()
end

local function normalizeQuoteInteger(value)
	local numeric = tonumber(value)
	if not numeric or numeric ~= numeric or numeric == math.huge or numeric == -math.huge then
		return 0
	end
	return math.max(0, math.floor(numeric))
end

local function formatHatchCost(value)
	local formatted = tostring(normalizeQuoteInteger(value))
	while true do
		local replacements
		formatted, replacements = string.gsub(formatted, "^(%d+)(%d%d%d)", "%1,%2")
		if replacements == 0 then
			return formatted
		end
	end
end

local function deriveHatchUnavailableReason(quote, count, isMax)
	local freeSlots = normalizeQuoteInteger(quote.freeSlots)
	local coins = normalizeQuoteInteger(quote.coins)
	local unitCost = normalizeQuoteInteger(quote.unitCost)
	local entitlementCap = normalizeQuoteInteger(quote.entitlementCap)

	if freeSlots < (isMax and 1 or count) then
		return freeSlots == 0 and "No pet inventory slots" or "Need more pet inventory slots"
	end
	if not isMax and entitlementCap < count then
		return "Multi-Open entitlement required"
	end
	if coins < unitCost * (isMax and 1 or count) then
		return "Not enough Coins"
	end
	return "Unavailable right now"
end

-- QOF-10 API: Main owns quote/purchase requests; UIController owns exactly one
-- reusable dialog and forwards only the three fixed server intent shapes.
function UIController:_createHatchPurchaseDialog()
	if self._hatchPurchaseGui then return end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "HatchPurchaseDialog"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	pcall(function()
		screenGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	end)
	screenGui.DisplayOrder = 40 -- MainHUD < purchase dialog < hatch cinematic (50)
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = false
	screenGui.Parent = self._playerGui
	self._hatchPurchaseGui = screenGui

	local dimmer = Instance.new("TextButton")
	dimmer.Name = "Dimmer"
	dimmer.Size = UDim2.fromScale(1, 1)
	dimmer.BackgroundColor3 = Color3.fromRGB(5, 8, 18)
	dimmer.BackgroundTransparency = 0.28
	dimmer.BorderSizePixel = 0
	dimmer.Text = ""
	dimmer.AutoButtonColor = false
	dimmer.Active = true
	dimmer.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.Name = "PurchasePanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.94, 0.88)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = COLORS.Background
	panel.BorderSizePixel = 0
	panel.Parent = screenGui
	self._hatchPurchasePanel = panel

	local panelConstraint = Instance.new("UISizeConstraint")
	panelConstraint.MaxSize = Vector2.new(680, 610)
	panelConstraint.Parent = panel

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 20)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Thickness = 4
	panelStroke.Color = COLORS.DiamondCyan
	panelStroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "EggName"
	title.Size = UDim2.new(1, -28, 0.1, 0)
	title.Position = UDim2.new(0, 14, 0.025, 0)
	title.BackgroundTransparency = 1
	title.Text = "EGG"
	title.TextColor3 = COLORS.CoinYellow
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextWrapped = true
	title.Parent = panel
	self._hatchPurchaseTitle = title

	local instruction = Instance.new("TextLabel")
	instruction.Name = "Instruction"
	instruction.Size = UDim2.new(1, -28, 0.055, 0)
	instruction.Position = UDim2.new(0, 14, 0.13, 0)
	instruction.BackgroundTransparency = 1
	instruction.Text = "Choose how many eggs to buy"
	instruction.TextColor3 = COLORS.White
	instruction.Font = Enum.Font.GothamBold
	instruction.TextScaled = true
	instruction.TextWrapped = true
	instruction.Parent = panel

	local unitPrice = Instance.new("TextLabel")
	unitPrice.Name = "UnitPrice"
	unitPrice.Size = UDim2.new(1, -28, 0.045, 0)
	unitPrice.Position = UDim2.new(0, 14, 0.19, 0)
	unitPrice.BackgroundTransparency = 1
	unitPrice.Text = "Loading current price…"
	unitPrice.TextColor3 = COLORS.CoinYellow
	unitPrice.Font = Enum.Font.GothamBold
	unitPrice.TextScaled = true
	unitPrice.TextWrapped = true
	unitPrice.Parent = panel
	self._hatchPurchaseUnitPrice = unitPrice

	local optionContainer = Instance.new("ScrollingFrame")
	optionContainer.Name = "Options"
	optionContainer.Size = UDim2.new(1, -28, 0.47, 0)
	optionContainer.Position = UDim2.new(0, 14, 0.25, 0)
	optionContainer.BackgroundTransparency = 1
	optionContainer.BorderSizePixel = 0
	optionContainer.ScrollBarThickness = 5
	optionContainer.ScrollBarImageColor3 = COLORS.DiamondCyan
	optionContainer.ScrollingDirection = Enum.ScrollingDirection.Y
	optionContainer.CanvasSize = UDim2.fromOffset(0, 208)
	optionContainer.Parent = panel

	local optionLayout = Instance.new("UIListLayout")
	optionLayout.FillDirection = Enum.FillDirection.Vertical
	optionLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	optionLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	optionLayout.Padding = UDim.new(0, 8)
	optionLayout.Parent = optionContainer

	local optionDefinitions = {
		{ key = "x1", defaultText = "x1" },
		{ key = "x3", defaultText = "x3" },
		{ key = "max", defaultText = "MAX" },
	}
	for _, definition in ipairs(optionDefinitions) do
		local button = Instance.new("TextButton")
		button.Name = "Option_" .. definition.key
		button.Size = UDim2.new(1, -8, 0, 64)
		button.BackgroundColor3 = COLORS.NavSettings
		button.Text = definition.defaultText .. "\nLoading…"
		button.TextColor3 = COLORS.White
		button.Font = Enum.Font.GothamBold
		button.TextScaled = true
		button.TextWrapped = true
		button.AutoButtonColor = false
		button.Active = false
		button.Selectable = false
		button.Parent = optionContainer

		local buttonConstraint = Instance.new("UISizeConstraint")
		buttonConstraint.MinSize = Vector2.new(132, 52)
		buttonConstraint.MaxSize = Vector2.new(640, 82)
		buttonConstraint.Parent = button

		local buttonCorner = Instance.new("UICorner")
		buttonCorner.CornerRadius = UDim.new(0, 12)
		buttonCorner.Parent = button

		local buttonStroke = Instance.new("UIStroke")
		buttonStroke.Thickness = 3
		buttonStroke.Color = Color3.fromRGB(75, 82, 105)
		buttonStroke.Parent = button

		button.Activated:Connect(function()
			if not button.Active then return end
			local callback = self._hatchPurchaseCallbacks.confirm
			if callback then
				if definition.key == "x1" then
					callback({ mode = "Fixed", count = 1 })
				elseif definition.key == "x3" then
					callback({ mode = "Fixed", count = 3 })
				else
					callback({ mode = "Max" })
				end
			end
		end)

		self._hatchPurchaseOptionButtons[definition.key] = {
			button = button,
			stroke = buttonStroke,
		}
	end

	local feedback = Instance.new("TextLabel")
	feedback.Name = "Feedback"
	feedback.Size = UDim2.new(1, -28, 0.075, 0)
	feedback.Position = UDim2.new(0, 14, 0.735, 0)
	feedback.BackgroundTransparency = 1
	feedback.Text = ""
	feedback.TextColor3 = COLORS.White
	feedback.Font = Enum.Font.GothamBold
	feedback.TextScaled = true
	feedback.TextWrapped = true
	feedback.Parent = panel
	self._hatchPurchaseFeedback = feedback

	local refreshButton = Instance.new("TextButton")
	refreshButton.Name = "RefreshQuote"
	refreshButton.AnchorPoint = Vector2.new(0, 1)
	refreshButton.Size = UDim2.new(0.42, 0, 0, 52)
	refreshButton.Position = UDim2.new(0.04, 0, 0.97, 0)
	refreshButton.BackgroundColor3 = COLORS.DiamondCyan
	refreshButton.Text = "Refresh Quote"
	refreshButton.TextColor3 = COLORS.White
	refreshButton.Font = Enum.Font.GothamBold
	refreshButton.TextScaled = true
	refreshButton.AutoButtonColor = false
	refreshButton.Visible = false
	refreshButton.Parent = panel
	local refreshConstraint = Instance.new("UISizeConstraint")
	refreshConstraint.MinSize = Vector2.new(132, 52)
	refreshConstraint.Parent = refreshButton
	local refreshCorner = Instance.new("UICorner")
	refreshCorner.CornerRadius = UDim.new(0, 12)
	refreshCorner.Parent = refreshButton
	refreshButton.Activated:Connect(function()
		if not refreshButton.Active then return end
		local callback = self._hatchPurchaseCallbacks.refresh
		if callback then callback() end
	end)
	self._hatchPurchaseRefreshButton = refreshButton

	local cancelButton = Instance.new("TextButton")
	cancelButton.Name = "Cancel"
	cancelButton.AnchorPoint = Vector2.new(1, 1)
	cancelButton.Size = UDim2.new(0.42, 0, 0, 52)
	cancelButton.Position = UDim2.new(0.96, 0, 0.97, 0)
	cancelButton.BackgroundColor3 = COLORS.ButtonRed
	cancelButton.Text = "Cancel"
	cancelButton.TextColor3 = COLORS.White
	cancelButton.Font = Enum.Font.GothamBold
	cancelButton.TextScaled = true
	cancelButton.AutoButtonColor = false
	cancelButton.Parent = panel
	local cancelConstraint = Instance.new("UISizeConstraint")
	cancelConstraint.MinSize = Vector2.new(132, 52)
	cancelConstraint.Parent = cancelButton
	local cancelCorner = Instance.new("UICorner")
	cancelCorner.CornerRadius = UDim.new(0, 12)
	cancelCorner.Parent = cancelButton
	cancelButton.Activated:Connect(function()
		self:_requestHatchPurchaseCancel()
	end)

	local function updateResponsiveLayout()
		local size = panel.AbsoluteSize
		local compactFooter = size.X < 320 or size.Y < 500
		if compactFooter then
			optionContainer.Position = UDim2.new(0, 14, 0.23, 0)
			optionContainer.Size = UDim2.new(1, -28, 0.36, 0)
			feedback.Position = UDim2.new(0, 14, 0.60, 0)
			feedback.Size = UDim2.new(1, -28, 0.08, 0)

			refreshButton.AnchorPoint = Vector2.new(0.5, 1)
			refreshButton.Size = UDim2.new(0.84, 0, 0, 52)
			refreshButton.Position = UDim2.new(0.5, 0, 0.84, 0)
			cancelButton.AnchorPoint = Vector2.new(0.5, 1)
			cancelButton.Size = UDim2.new(0.84, 0, 0, 52)
			cancelButton.Position = UDim2.new(0.5, 0, 0.98, 0)
		else
			optionContainer.Position = UDim2.new(0, 14, 0.25, 0)
			optionContainer.Size = UDim2.new(1, -28, 0.47, 0)
			feedback.Position = UDim2.new(0, 14, 0.735, 0)
			feedback.Size = UDim2.new(1, -28, 0.075, 0)

			refreshButton.AnchorPoint = Vector2.new(0, 1)
			refreshButton.Size = UDim2.new(0.42, 0, 0, 52)
			refreshButton.Position = UDim2.new(0.04, 0, 0.97, 0)
			cancelButton.AnchorPoint = Vector2.new(1, 1)
			cancelButton.Size = UDim2.new(0.42, 0, 0, 52)
			cancelButton.Position = UDim2.new(0.96, 0, 0.97, 0)
		end
	end
	table.insert(self._hatchPurchaseConnections, panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(
		updateResponsiveLayout
	))
	task.defer(updateResponsiveLayout)

	table.insert(self._hatchPurchaseConnections, UserInputService.InputBegan:Connect(function(input)
		if not self:isHatchPurchaseDialogOpen() then return end
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			self:_requestHatchPurchaseCancel()
		end
	end))
end

function UIController:setHatchPurchaseCallbacks(confirmCallback, cancelCallback, refreshCallback)
	self._hatchPurchaseCallbacks = {
		confirm = type(confirmCallback) == "function" and confirmCallback or nil,
		cancel = type(cancelCallback) == "function" and cancelCallback or nil,
		refresh = type(refreshCallback) == "function" and refreshCallback or nil,
	}
end

function UIController:isHatchPurchaseDialogOpen()
	return self._hatchPurchaseGui ~= nil and self._hatchPurchaseGui.Enabled == true
end

function UIController:_requestHatchPurchaseCancel()
	if not self:isHatchPurchaseDialogOpen() then return end
	local callback = self._hatchPurchaseCallbacks.cancel
	if callback then
		callback()
	else
		self:closeHatchPurchaseDialog()
	end
end

function UIController:_setHatchPurchaseOption(key, heading, totalCost, available, unavailableReason)
	local entry = self._hatchPurchaseOptionButtons[key]
	if not entry then return end
	local button = entry.button
	button.Active = available == true
	button.Selectable = available == true
	button.BackgroundColor3 = available and COLORS.ButtonGreen or COLORS.NavSettings
	button.TextColor3 = available and COLORS.White or Color3.fromRGB(220, 225, 235)
	entry.stroke.Color = available and Color3.fromRGB(0, 125, 55) or Color3.fromRGB(75, 82, 105)
	local priceText = formatHatchCost(totalCost) .. " Coins"
	button.Text = heading .. "  •  " .. priceText
	if not available then
		button.Text ..= "\n" .. tostring(unavailableReason or "Unavailable")
	end
end

function UIController:showHatchPurchaseLoading(eggType)
	if not self._hatchPurchaseGui then return end
	self._activeHatchPurchaseEggType = eggType
	local eggDef = PetData.Eggs[eggType]
	self._hatchPurchaseTitle.Text = string.upper(tostring(eggDef and eggDef.name or eggType or "Egg"))
	self._hatchPurchaseUnitPrice.Text = "Loading current price…"
	self._hatchPurchaseFeedback.Text = "Getting a fresh purchase quote…"
	self._hatchPurchaseFeedback.TextColor3 = COLORS.White
	self._hatchPurchaseRefreshButton.Visible = false
	self._hatchPurchaseRefreshButton.Active = false
	self._hatchPurchaseOptionButtons.x3.button.Visible = false
	self:_setHatchPurchaseOption("x1", "x1", 0, false, "Loading…")
	self:_setHatchPurchaseOption("x3", "x3", 0, false, "Loading…")
	self:_setHatchPurchaseOption("max", "MAX", 0, false, "Loading…")
	self._hatchPurchaseGui.Enabled = true
end

function UIController:showHatchPurchaseQuote(eggType, quote)
	if not self:isHatchPurchaseDialogOpen() or self._activeHatchPurchaseEggType ~= eggType then return end
	quote = type(quote) == "table" and quote or {}
	local eggDef = PetData.Eggs[eggType]
	self._hatchPurchaseTitle.Text = string.upper(tostring(eggDef and eggDef.name or eggType or "Egg"))
	self._hatchPurchaseUnitPrice.Text = "Unit price: " .. formatHatchCost(quote.unitCost) .. " Coins"
	self._hatchPurchaseFeedback.Text = "Quote is current. Confirm one option below."
	self._hatchPurchaseFeedback.TextColor3 = Color3.fromRGB(145, 255, 170)
	self._hatchPurchaseRefreshButton.Visible = true
	self._hatchPurchaseRefreshButton.Active = true

	local x1 = type(quote.x1) == "table" and quote.x1 or {}
	local x3 = type(quote.x3) == "table" and quote.x3 or {}
	local maxOption = type(quote.max) == "table" and quote.max or {}
	local feasibleMax = normalizeQuoteInteger(quote.feasibleMax)
	local entitlementCap = normalizeQuoteInteger(quote.entitlementCap)
	self._hatchPurchaseOptionButtons.x3.button.Visible = entitlementCap >= 3
	self:_setHatchPurchaseOption(
		"x1", "x1", x1.totalCost, x1.available == true,
		deriveHatchUnavailableReason(quote, 1, false)
	)
	self:_setHatchPurchaseOption(
		"x3", "x3", x3.totalCost, x3.available == true,
		deriveHatchUnavailableReason(quote, 3, false)
	)
	self:_setHatchPurchaseOption(
		"max", "MAX x" .. tostring(feasibleMax), maxOption.totalCost,
		maxOption.available == true and feasibleMax > 0,
		deriveHatchUnavailableReason(quote, feasibleMax, true)
	)
end

function UIController:showHatchPurchaseBusy(message)
	if not self:isHatchPurchaseDialogOpen() then return end
	for _, entry in pairs(self._hatchPurchaseOptionButtons) do
		entry.button.Active = false
		entry.button.Selectable = false
		entry.button.BackgroundColor3 = COLORS.NavSettings
	end
	self._hatchPurchaseRefreshButton.Visible = false
	self._hatchPurchaseRefreshButton.Active = false
	self._hatchPurchaseFeedback.Text = tostring(message or "Processing purchase…")
	self._hatchPurchaseFeedback.TextColor3 = COLORS.White
end

function UIController:showHatchPurchaseError(message)
	if not self:isHatchPurchaseDialogOpen() then return end
	for _, entry in pairs(self._hatchPurchaseOptionButtons) do
		entry.button.Active = false
		entry.button.Selectable = false
		entry.button.BackgroundColor3 = COLORS.NavSettings
	end
	self._hatchPurchaseFeedback.Text = tostring(message or "Could not complete the purchase.")
	self._hatchPurchaseFeedback.TextColor3 = Color3.fromRGB(255, 160, 160)
	self._hatchPurchaseRefreshButton.Visible = true
	self._hatchPurchaseRefreshButton.Active = true
end

function UIController:closeHatchPurchaseDialog(eggType)
	if not self._hatchPurchaseGui then return end
	if eggType ~= nil and self._activeHatchPurchaseEggType ~= eggType then return end
	self._hatchPurchaseGui.Enabled = false
	self._activeHatchPurchaseEggType = nil
end

function UIController:_createOnboardingHint(parent)
	local card = Instance.new("Frame")
	card.Name = "OnboardingHint"
	card.Size = UDim2.new(0.3, 0, 0, 82)
	card.Position = UDim2.fromScale(0.02, 0.16)
	card.BackgroundColor3 = COLORS.DarkBg
	card.BackgroundTransparency = 0.08
	card.BorderSizePixel = 0
	card.Visible = false
	card.Active = false
	card.Parent = parent
	self._onboardingCard = card

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(190, 82)
	sizeConstraint.MaxSize = Vector2.new(360, 82)
	sizeConstraint.Parent = card

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = COLORS.CoinYellow
	stroke.Parent = card

	local title = Instance.new("TextLabel")
	title.Name = "StepTitle"
	title.Size = UDim2.new(1, -16, 0, 24)
	title.Position = UDim2.fromOffset(8, 6)
	title.BackgroundTransparency = 1
	title.TextColor3 = COLORS.CoinYellow
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.Active = false
	title.Parent = card
	self._onboardingTitle = title

	local instruction = Instance.new("TextLabel")
	instruction.Name = "Instruction"
	instruction.Size = UDim2.new(1, -16, 0, 42)
	instruction.Position = UDim2.fromOffset(8, 32)
	instruction.BackgroundTransparency = 1
	instruction.TextColor3 = COLORS.White
	instruction.TextXAlignment = Enum.TextXAlignment.Left
	instruction.TextYAlignment = Enum.TextYAlignment.Top
	instruction.Font = Enum.Font.GothamBold
	instruction.TextScaled = true
	instruction.TextWrapped = true
	instruction.Active = false
	instruction.Parent = card
	self._onboardingText = instruction

	local arrow = Instance.new("BillboardGui")
	arrow.Name = "OnboardingWorldArrow"
	arrow.Size = UDim2.fromOffset(120, 70)
	arrow.StudsOffset = Vector3.new(0, 5, 0)
	arrow.AlwaysOnTop = true
	arrow.Enabled = false
	arrow.Parent = self._playerGui
	self._onboardingArrow = arrow

	local arrowText = Instance.new("TextLabel")
	arrowText.Size = UDim2.fromScale(1, 1)
	arrowText.BackgroundTransparency = 1
	arrowText.Text = "GO HERE\n▼"
	arrowText.TextColor3 = COLORS.CoinYellow
	arrowText.TextStrokeColor3 = COLORS.DarkBg
	arrowText.TextStrokeTransparency = 0
	arrowText.Font = Enum.Font.GothamBold
	arrowText.TextScaled = true
	arrowText.TextWrapped = true
	arrowText.Active = false
	arrowText.Parent = arrow
end

function UIController:setOnboardingHint(stepNumber, totalSteps, instruction, targetPart)
	if not self._onboardingCard then return end

	self._onboardingTitle.Text = "GETTING STARTED  " .. tostring(stepNumber) .. "/" .. tostring(totalSteps)
	self._onboardingText.Text = instruction
	self._onboardingCard.Visible = true

	local hasTarget = targetPart and targetPart:IsA("BasePart") and targetPart.Parent ~= nil
	if self._onboardingArrow then
		self._onboardingArrow.Adornee = hasTarget and targetPart or nil
		self._onboardingArrow.Enabled = hasTarget == true
	end
end

function UIController:clearOnboardingHint()
	if self._onboardingCard then
		self._onboardingCard.Visible = false
	end
	if self._onboardingArrow then
		self._onboardingArrow.Enabled = false
		self._onboardingArrow.Adornee = nil
	end
end

function UIController:_createCurrencyDisplay(parent, playerData)
	local frame = Instance.new("Frame")
	frame.Name = "CurrencyDisplay"
	frame.AnchorPoint = Vector2.new(1, 0)
	frame.Size = UDim2.new(0.3, 0, 0, 140)
	frame.Position = UDim2.fromScale(0.98, 0.02)
	frame.BackgroundColor3 = COLORS.Background
	frame.BackgroundTransparency = 0.3
	frame.BorderSizePixel = 0
	frame.Parent = parent

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(210, 140)
	sizeConstraint.MaxSize = Vector2.new(340, 140)
	sizeConstraint.Parent = frame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(60, 80, 140)
	stroke.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 4)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.Parent = frame

	-- Coins row
	local coinRow = Instance.new("Frame")
	coinRow.Name = "CoinRow"
	coinRow.Size = UDim2.new(1, 0, 0, 24)
	coinRow.BackgroundTransparency = 1
	coinRow.Parent = frame

	local coinIcon = Instance.new("Frame")
	coinIcon.Name = "CoinIcon"
	coinIcon.Size = UDim2.fromOffset(22, 22)
	coinIcon.Position = UDim2.fromOffset(0, 1)
	coinIcon.BackgroundColor3 = COLORS.CoinYellow
	coinIcon.Parent = coinRow

	local coinIconCorner = Instance.new("UICorner")
	coinIconCorner.CornerRadius = UDim.new(1, 0)
	coinIconCorner.Parent = coinIcon

	local coinIconText = Instance.new("TextLabel")
	coinIconText.Size = UDim2.fromScale(1, 1)
	coinIconText.BackgroundTransparency = 1
	coinIconText.Text = "$"
	coinIconText.TextColor3 = Color3.fromRGB(180, 130, 0)
	coinIconText.Font = Enum.Font.GothamBold
	coinIconText.TextScaled = true
	coinIconText.Parent = coinIcon

	local coinLabel = Instance.new("TextLabel")
	coinLabel.Name = "CoinAmount"
	coinLabel.Size = UDim2.new(1, -30, 1, 0)
	coinLabel.Position = UDim2.fromOffset(28, 0)
	coinLabel.BackgroundTransparency = 1
	coinLabel.Text = tostring(playerData and playerData.coins or 0)
	coinLabel.TextColor3 = COLORS.CoinYellow
	coinLabel.TextXAlignment = Enum.TextXAlignment.Left
	coinLabel.Font = Enum.Font.GothamBold
	coinLabel.TextScaled = true
	coinLabel.Parent = coinRow
	self._coinLabel = coinLabel

	-- Diamonds row
	local diamondRow = Instance.new("Frame")
	diamondRow.Name = "DiamondRow"
	diamondRow.Size = UDim2.new(1, 0, 0, 24)
	diamondRow.BackgroundTransparency = 1
	diamondRow.Parent = frame

	local diamondIcon = Instance.new("Frame")
	diamondIcon.Name = "DiamondIcon"
	diamondIcon.Size = UDim2.fromOffset(18, 18)
	diamondIcon.Position = UDim2.fromOffset(2, 3)
	diamondIcon.BackgroundColor3 = COLORS.DiamondCyan
	diamondIcon.Rotation = 45
	diamondIcon.Parent = diamondRow

	local diamondIconCorner = Instance.new("UICorner")
	diamondIconCorner.CornerRadius = UDim.new(0, 3)
	diamondIconCorner.Parent = diamondIcon

	local diamondLabel = Instance.new("TextLabel")
	diamondLabel.Name = "DiamondAmount"
	diamondLabel.Size = UDim2.new(1, -30, 1, 0)
	diamondLabel.Position = UDim2.fromOffset(28, 0)
	diamondLabel.BackgroundTransparency = 1
	diamondLabel.Text = tostring(playerData and playerData.diamonds or 0)
	diamondLabel.TextColor3 = COLORS.DiamondCyan
	diamondLabel.TextXAlignment = Enum.TextXAlignment.Left
	diamondLabel.Font = Enum.Font.GothamBold
	diamondLabel.TextScaled = true
	diamondLabel.Parent = diamondRow
	self._diamondLabel = diamondLabel

	-- Distance to the next hatch for the selected or latest unlocked egg
	local eggShortfallLabel = Instance.new("TextLabel")
	eggShortfallLabel.Name = "EggShortfall"
	eggShortfallLabel.Size = UDim2.new(1, 0, 0, 34)
	eggShortfallLabel.BackgroundColor3 = COLORS.DarkBg
	eggShortfallLabel.BackgroundTransparency = 0.25
	eggShortfallLabel.BorderSizePixel = 0
	eggShortfallLabel.TextColor3 = COLORS.White
	eggShortfallLabel.Font = Enum.Font.GothamBold
	eggShortfallLabel.TextScaled = true
	eggShortfallLabel.TextWrapped = true
	eggShortfallLabel.Parent = frame

	local eggShortfallCorner = Instance.new("UICorner")
	eggShortfallCorner.CornerRadius = UDim.new(0, 8)
	eggShortfallCorner.Parent = eggShortfallLabel

	local eggShortfallPadding = Instance.new("UIPadding")
	eggShortfallPadding.PaddingLeft = UDim.new(0, 5)
	eggShortfallPadding.PaddingRight = UDim.new(0, 5)
	eggShortfallPadding.Parent = eggShortfallLabel

	self._eggShortfallLabel = eggShortfallLabel
	self:_updateEggShortfall()

	-- Live progress toward the first zone that has not been unlocked yet
	local zoneProgressLabel = Instance.new("TextLabel")
	zoneProgressLabel.Name = "ZoneProgress"
	zoneProgressLabel.Size = UDim2.new(1, 0, 0, 34)
	zoneProgressLabel.BackgroundColor3 = COLORS.DarkBg
	zoneProgressLabel.BackgroundTransparency = 0.25
	zoneProgressLabel.BorderSizePixel = 0
	zoneProgressLabel.TextColor3 = COLORS.White
	zoneProgressLabel.Font = Enum.Font.GothamBold
	zoneProgressLabel.TextScaled = true
	zoneProgressLabel.TextWrapped = true
	zoneProgressLabel.Parent = frame

	local zoneProgressCorner = Instance.new("UICorner")
	zoneProgressCorner.CornerRadius = UDim.new(0, 8)
	zoneProgressCorner.Parent = zoneProgressLabel

	local zoneProgressPadding = Instance.new("UIPadding")
	zoneProgressPadding.PaddingLeft = UDim.new(0, 5)
	zoneProgressPadding.PaddingRight = UDim.new(0, 5)
	zoneProgressPadding.Parent = zoneProgressLabel

	self._zoneProgressLabel = zoneProgressLabel
	self:_updateZoneProgress()
end

function UIController:_createXPBar(parent, playerData)
	local barFrame = Instance.new("Frame")
	barFrame.Name = "XPBar"
	barFrame.Size = UDim2.fromScale(0.3, 0.035)
	barFrame.Position = UDim2.fromScale(0.35, 0.94)
	barFrame.BackgroundColor3 = COLORS.XPBarOuter
	barFrame.BorderSizePixel = 0
	barFrame.Parent = parent

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0.5, 0)
	barCorner.Parent = barFrame

	local barStroke = Instance.new("UIStroke")
	barStroke.Thickness = 3
	barStroke.Color = Color3.fromRGB(50, 70, 110)
	barStroke.Parent = barFrame

	local level = playerData and playerData.level or 1
	local xp = playerData and playerData.xp or 0
	local xpNeeded = playerData and playerData.xpNeeded or 100
	local fillFraction = math.clamp(xp / math.max(xpNeeded, 1), 0, 1)

	local fillFrame = Instance.new("Frame")
	fillFrame.Name = "XPFill"
	fillFrame.Size = UDim2.fromScale(fillFraction, 0.7)
	fillFrame.Position = UDim2.fromScale(0.02, 0.15)
	fillFrame.BackgroundColor3 = COLORS.XPBarFill
	fillFrame.BorderSizePixel = 0
	fillFrame.Parent = barFrame
	self._xpFill = fillFrame

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = fillFrame

	local levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "LevelLabel"
	levelLabel.Size = UDim2.fromScale(1, 1)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Text = "Lv. " .. tostring(level)
	levelLabel.TextColor3 = COLORS.White
	levelLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	levelLabel.TextStrokeTransparency = 0.4
	levelLabel.Font = Enum.Font.GothamBold
	levelLabel.TextScaled = true
	levelLabel.ZIndex = 3
	levelLabel.Parent = barFrame
	self._xpLevelLabel = levelLabel
end

function UIController:_createNavButtons(parent)
	local navFrame = Instance.new("Frame")
	navFrame.Name = "NavButtons"
	navFrame.Size = UDim2.fromScale(0.4, 0.09)
	navFrame.Position = UDim2.fromScale(0.58, 0.88)
	navFrame.BackgroundTransparency = 1
	navFrame.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = navFrame

	local buttons = {
		{ name = "Pets", icon = "P", color = COLORS.NavPets, screen = "PetInventory" },
		{ name = "Index", icon = "I", color = Color3.fromRGB(255, 100, 180), screen = "PetIndex" },
		{ name = "Shop", icon = "S", color = COLORS.NavShop, screen = "ShopScreen" },
		{ name = "Quests", icon = "!", color = COLORS.NavQuests, screen = "QuestWindow" },
		{ name = "Mastery", icon = "M", color = COLORS.NavMastery, screen = "MasteryWindow" },
		{ name = "Settings", icon = "G", color = COLORS.NavSettings, screen = nil },
	}

	for _, btnData in ipairs(buttons) do
		local btn = Instance.new("TextButton")
		btn.Name = "Nav_" .. btnData.name
		btn.Size = UDim2.fromOffset(60, 60)
		btn.BackgroundColor3 = btnData.color
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.Parent = navFrame

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 12)
		btnCorner.Parent = btn

		local btnStroke = Instance.new("UIStroke")
		btnStroke.Thickness = 3
		btnStroke.Color = Color3.fromRGB(
			math.max(0, btnData.color.R * 255 - 40),
			math.max(0, btnData.color.G * 255 - 40),
			math.max(0, btnData.color.B * 255 - 40)
		)
		btnStroke.Parent = btn

		local iconLabel = Instance.new("TextLabel")
		iconLabel.Name = "Icon"
		iconLabel.Size = UDim2.fromScale(1, 0.55)
		iconLabel.Position = UDim2.fromScale(0, 0.05)
		iconLabel.BackgroundTransparency = 1
		iconLabel.Text = btnData.icon
		iconLabel.TextColor3 = COLORS.White
		iconLabel.Font = Enum.Font.GothamBold
		iconLabel.TextScaled = true
		iconLabel.Parent = btn

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "Label"
		nameLabel.Size = UDim2.fromScale(1, 0.35)
		nameLabel.Position = UDim2.fromScale(0, 0.6)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = btnData.name
		nameLabel.TextColor3 = COLORS.White
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextScaled = true
		nameLabel.Parent = btn

		btn.MouseEnter:Connect(function()
			TweenService:Create(btn, TweenInfo.new(0.15), {
				Size = UDim2.fromOffset(66, 66),
			}):Play()
		end)

		btn.MouseLeave:Connect(function()
			TweenService:Create(btn, TweenInfo.new(0.15), {
				Size = UDim2.fromOffset(60, 60),
			}):Play()
		end)

		if btnData.screen then
			btn.MouseButton1Click:Connect(function()
				self:toggleScreen(btnData.screen)
			end)
		end
	end
end

-- Equipped pet bar removed (no longer shown in UI)

--------------------------------------------------------------------------------
-- PET INVENTORY SCREEN
--------------------------------------------------------------------------------
function UIController:_createPetInventory()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PetInventory"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = false
	screenGui.Parent = self._playerGui
	self._screens.PetInventory = screenGui

	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.fromScale(0.8, 0.7)
	mainFrame.Position = UDim2.fromScale(0.1, 0.15)
	mainFrame.BackgroundColor3 = COLORS.Background
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = screenGui

	local mainCorner = Instance.new("UICorner")
	mainCorner.CornerRadius = UDim.new(0, 16)
	mainCorner.Parent = mainFrame

	local mainStroke = Instance.new("UIStroke")
	mainStroke.Thickness = 4
	mainStroke.Color = Color3.fromRGB(80, 120, 200)
	mainStroke.Parent = mainFrame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(0.4, 0.08)
	title.Position = UDim2.fromScale(0.3, 0.01)
	title.BackgroundTransparency = 1
	title.Text = "My Pets"
	title.TextColor3 = COLORS.White
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.Parent = mainFrame
	self._inventoryTitle = title

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.fromOffset(40, 40)
	closeBtn.Position = UDim2.new(1, -50, 0, 10)
	closeBtn.BackgroundColor3 = COLORS.CloseRed
	closeBtn.Text = "X"
	closeBtn.TextColor3 = COLORS.White
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 22
	closeBtn.Parent = mainFrame

	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(1, 0)
	closeBtnCorner.Parent = closeBtn

	closeBtn.MouseButton1Click:Connect(function()
		self:toggleScreen("PetInventory")
	end)

	local multiSelectBtn = Instance.new("TextButton")
	multiSelectBtn.Name = "MultiSelectBtn"
	multiSelectBtn.Size = UDim2.fromScale(0.15, 0.06)
	multiSelectBtn.Position = UDim2.fromScale(0.02, 0.01)
	multiSelectBtn.BackgroundColor3 = Color3.fromRGB(80, 100, 160)
	multiSelectBtn.Text = "Multi-Select"
	multiSelectBtn.TextColor3 = COLORS.White
	multiSelectBtn.Font = Enum.Font.GothamBold
	multiSelectBtn.TextScaled = true
	multiSelectBtn.Parent = mainFrame

	local multiCorner = Instance.new("UICorner")
	multiCorner.CornerRadius = UDim.new(0, 8)
	multiCorner.Parent = multiSelectBtn

	multiSelectBtn.MouseButton1Click:Connect(function()
		self._multiSelectMode = not self._multiSelectMode
		multiSelectBtn.BackgroundColor3 = self._multiSelectMode
			and Color3.fromRGB(200, 100, 0)
			or Color3.fromRGB(80, 100, 160)
		self:_refreshPetGrid()
	end)

	local toolbar = Instance.new("Frame")
	toolbar.Name = "InventoryToolbar"
	toolbar.Size = UDim2.fromScale(0.58, 0.06)
	toolbar.Position = UDim2.fromScale(0.21, 0.095)
	toolbar.BackgroundTransparency = 1
	toolbar.Parent = mainFrame

	local toolbarLayout = Instance.new("UIListLayout")
	toolbarLayout.FillDirection = Enum.FillDirection.Horizontal
	toolbarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	toolbarLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	toolbarLayout.Padding = UDim.new(0.03, 0)
	toolbarLayout.Parent = toolbar

	local sortBtn = Instance.new("TextButton")
	sortBtn.Name = "SortButton"
	sortBtn.Size = UDim2.fromScale(0.46, 1)
	sortBtn.BackgroundColor3 = Color3.fromRGB(65, 90, 150)
	sortBtn.Text = "Sort: " .. self._petSortMode
	sortBtn.TextColor3 = COLORS.White
	sortBtn.Font = Enum.Font.GothamBold
	sortBtn.TextScaled = true
	sortBtn.Parent = toolbar
	self._petSortButton = sortBtn

	local sortCorner = Instance.new("UICorner")
	sortCorner.CornerRadius = UDim.new(0, 8)
	sortCorner.Parent = sortBtn

	sortBtn.MouseButton1Click:Connect(function()
		local currentIndex = table.find(PET_SORT_MODES, self._petSortMode) or 1
		self._petSortMode = PET_SORT_MODES[(currentIndex % #PET_SORT_MODES) + 1]
		sortBtn.Text = "Sort: " .. self._petSortMode
		self:_refreshPetGrid()
	end)

	local filterBtn = Instance.new("TextButton")
	filterBtn.Name = "VariantFilterButton"
	filterBtn.Size = UDim2.fromScale(0.46, 1)
	filterBtn.BackgroundColor3 = Color3.fromRGB(90, 70, 145)
	filterBtn.Text = "Variant: " .. self._petVariantFilter
	filterBtn.TextColor3 = COLORS.White
	filterBtn.Font = Enum.Font.GothamBold
	filterBtn.TextScaled = true
	filterBtn.Parent = toolbar
	self._petVariantFilterButton = filterBtn

	local filterCorner = Instance.new("UICorner")
	filterCorner.CornerRadius = UDim.new(0, 8)
	filterCorner.Parent = filterBtn

	filterBtn.MouseButton1Click:Connect(function()
		local currentIndex = table.find(PET_VARIANT_FILTERS, self._petVariantFilter) or 1
		self._petVariantFilter = PET_VARIANT_FILTERS[(currentIndex % #PET_VARIANT_FILTERS) + 1]
		filterBtn.Text = "Variant: " .. self._petVariantFilter
		self:_refreshPetGrid()
	end)

	local deleteBtn = Instance.new("TextButton")
	deleteBtn.Name = "DeleteSelectedBtn"
	deleteBtn.Size = UDim2.fromScale(0.15, 0.06)
	deleteBtn.Position = UDim2.fromScale(0.02, 0.92)
	deleteBtn.BackgroundColor3 = COLORS.ButtonRed
	deleteBtn.Text = "Delete Selected"
	deleteBtn.TextColor3 = COLORS.White
	deleteBtn.Font = Enum.Font.GothamBold
	deleteBtn.TextScaled = true
	deleteBtn.Visible = false
	deleteBtn.Parent = mainFrame

	local deleteCorner = Instance.new("UICorner")
	deleteCorner.CornerRadius = UDim.new(0, 8)
	deleteCorner.Parent = deleteBtn

	deleteBtn.MouseButton1Click:Connect(function()
		self:_deleteSelectedPets()
	end)

	-- "Make Golden" button (visible in multi-select mode)
	local goldenBtn = Instance.new("TextButton")
	goldenBtn.Name = "MakeGoldenBtn"
	goldenBtn.Size = UDim2.fromScale(0.15, 0.06)
	goldenBtn.Position = UDim2.fromScale(0.18, 0.92)
	goldenBtn.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
	goldenBtn.Text = "Make Golden"
	goldenBtn.TextColor3 = Color3.fromRGB(40, 30, 0)
	goldenBtn.Font = Enum.Font.GothamBold
	goldenBtn.TextScaled = true
	goldenBtn.Visible = false
	goldenBtn.Parent = mainFrame

	local goldenCorner = Instance.new("UICorner")
	goldenCorner.CornerRadius = UDim.new(0, 8)
	goldenCorner.Parent = goldenBtn

	local goldenStroke = Instance.new("UIStroke")
	goldenStroke.Thickness = 2
	goldenStroke.Color = Color3.fromRGB(180, 140, 0)
	goldenStroke.Parent = goldenBtn

	goldenBtn.MouseButton1Click:Connect(function()
		self:_showGoldenConversionConfirm()
	end)

	goldenBtn.MouseEnter:Connect(function()
		TweenService:Create(goldenBtn, TweenInfo.new(0.1), {
			Size = UDim2.fromScale(0.16, 0.065),
		}):Play()
	end)
	goldenBtn.MouseLeave:Connect(function()
		TweenService:Create(goldenBtn, TweenInfo.new(0.1), {
			Size = UDim2.fromScale(0.15, 0.06),
		}):Play()
	end)

	local duplicatesBtn = Instance.new("TextButton")
	duplicatesBtn.Name = "SelectDuplicatesBtn"
	duplicatesBtn.Size = UDim2.fromScale(0.2, 0.06)
	duplicatesBtn.Position = UDim2.fromScale(0.35, 0.92)
	duplicatesBtn.BackgroundColor3 = Color3.fromRGB(70, 130, 200)
	duplicatesBtn.Text = "Select All Duplicates"
	duplicatesBtn.TextColor3 = COLORS.White
	duplicatesBtn.Font = Enum.Font.GothamBold
	duplicatesBtn.TextScaled = true
	duplicatesBtn.Visible = false
	duplicatesBtn.Parent = mainFrame

	local duplicatesCorner = Instance.new("UICorner")
	duplicatesCorner.CornerRadius = UDim.new(0, 8)
	duplicatesCorner.Parent = duplicatesBtn

	duplicatesBtn.MouseButton1Click:Connect(function()
		self:_selectDuplicatePets()
	end)

	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "PetGrid"
	scrollFrame.Size = UDim2.fromScale(0.94, 0.69)
	scrollFrame.Position = UDim2.fromScale(0.03, 0.17)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.ScrollBarThickness = 0
	scrollFrame.CanvasSize = UDim2.fromScale(0, 0)
	scrollFrame.Parent = mainFrame

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.Name = "GridLayout"
	gridLayout.CellSize = UDim2.fromOffset(120, 150)
	gridLayout.CellPadding = UDim2.fromOffset(8, 8)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = scrollFrame

	gridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		scrollFrame.CanvasSize = UDim2.fromOffset(0, gridLayout.AbsoluteContentSize.Y + 20)
	end)

	self:_updateInventoryTitle()
	self:_refreshPetGrid()
end

function UIController:_getInventoryCapacity()
	local extraSlots = resolveLevelBonus(
		QuestData.Quests.ExtraSlots,
		type(self._upgradeData) == "table" and self._upgradeData.ExtraSlots or nil,
		"levels"
	)
	local treeStorage = safeSlotBonus(
		type(self._treeEntitlements) == "table" and self._treeEntitlements.storageBonusSlots or nil
	)
	local limits = BalanceConfig.Limits
	return math.clamp(
		limits.PetInventoryBase + extraSlots + treeStorage,
		limits.PetInventoryBase,
		limits.PetInventoryAbsolute
	)
end

function UIController:_getEquipCapacity()
	local friendship = resolveLevelBonus(
		QuestData.Quests.Friendship,
		type(self._upgradeData) == "table" and self._upgradeData.Friendship or nil,
		"levels"
	)
	local masteryBuffs = type(self._masteryState) == "table" and self._masteryState.buffs or nil
	local morePetSlots = resolveLevelBonus(
		MasteryData.Buffs.MorePetSlots,
		type(masteryBuffs) == "table" and masteryBuffs.MorePetSlots or nil,
		"bonusPerLevel"
	)
	local purchases = type(self._shopState) == "table" and self._shopState.purchases or nil
	local legacyShop = safeSlotBonus(
		type(purchases) == "table" and purchases.extraEquipSlots or nil
	)
	legacyShop = math.min(legacyShop, ShopData.Items.ExtraEquipSlot.maxPurchases or 5)
	local treeEquip = safeSlotBonus(
		type(self._treeEntitlements) == "table" and self._treeEntitlements.petEquipBonusSlots or nil
	)
	local limits = BalanceConfig.Limits
	return math.clamp(
		limits.EquippedPetsBase + friendship + morePetSlots + legacyShop + treeEquip,
		limits.EquippedPetsBase,
		limits.EquippedPetsAbsolute
	)
end

function UIController:_countEquippedPets()
	local count = 0
	local seen = {}
	for _, pet in ipairs(type(self._equippedPets) == "table" and self._equippedPets or {}) do
		local id = type(pet) == "string" and pet
			or type(pet) == "table" and (pet.uniqueId or pet.id)
		if type(id) == "string" and id ~= "" and not seen[id] then
			seen[id] = true
			count += 1
		end
	end
	return count
end

function UIController:_refreshCapacityUI()
	local inventoryCapacity = self:_getInventoryCapacity()
	if self._inventoryTitle then
		local absoluteCap = BalanceConfig.Limits.PetInventoryAbsolute
		local capText = inventoryCapacity >= absoluteCap
			and "  •  CAP " .. tostring(absoluteCap) or ""
		self._inventoryTitle.Text = "My Pets  " .. tostring(#self._petInventoryData)
			.. "/" .. tostring(inventoryCapacity) .. capText
	end

	local equipCapacity = self:_getEquipCapacity()
	if self._equippedTitle then
		local absoluteCap = BalanceConfig.Limits.EquippedPetsAbsolute
		local capText = equipCapacity >= absoluteCap
			and "  •  CAP " .. tostring(absoluteCap) or ""
		self._equippedTitle.Text = "Equipped  " .. tostring(self:_countEquippedPets())
			.. "/" .. tostring(equipCapacity) .. capText
	end
end

function UIController:_updateInventoryTitle()
	self:_refreshCapacityUI()
end

function UIController:_buildPetDisplayList()
	local displayPets = {}
	for sourceIndex, petData in ipairs(self._petInventoryData) do
		local presentation = PetVariantPresentation.resolve(petData)
		local variant = presentation.legacyCategory
		if self._petVariantFilter == "All" or variant == self._petVariantFilter then
			table.insert(displayPets, {
				pet = petData,
				sourceIndex = sourceIndex,
				variant = variant,
				presentation = presentation,
			})
		end
	end

	if self._petSortMode == "Default" then
		return displayPets
	end

	table.sort(displayPets, function(a, b)
		local petA = a.pet
		local petB = b.pet
		local rarityA = RARITY_RANK[petA.rarity] or 0
		local rarityB = RARITY_RANK[petB.rarity] or 0
		local variantA = VARIANT_RANK[a.variant] or 0
		local variantB = VARIANT_RANK[b.variant] or 0
		local damageA = getPetDamage(petA)
		local damageB = getPetDamage(petB)

		if self._petSortMode == "Rarity" and rarityA ~= rarityB then
			return rarityA > rarityB
		elseif self._petSortMode == "Variant" and variantA ~= variantB then
			return variantA > variantB
		elseif self._petSortMode == "Damage" and damageA ~= damageB then
			return damageA > damageB
		end

		if self._petSortMode ~= "Rarity" and rarityA ~= rarityB then
			return rarityA > rarityB
		end
		if self._petSortMode ~= "Variant" and variantA ~= variantB then
			return variantA > variantB
		end
		if self._petSortMode ~= "Damage" and damageA ~= damageB then
			return damageA > damageB
		end

		local nameA = string.lower(tostring(petA.petId or petA.name or ""))
		local nameB = string.lower(tostring(petB.petId or petB.name or ""))
		if nameA ~= nameB then return nameA < nameB end

		local idA = tostring(petA.uniqueId or petA.id or "")
		local idB = tostring(petB.uniqueId or petB.id or "")
		if idA ~= idB then return idA < idB end
		return a.sourceIndex < b.sourceIndex
	end)

	return displayPets
end

function UIController:_selectDuplicatePets()
	if not self._multiSelectMode then return end

	local groupCounts = {}
	local keepers = {}
	for sourceIndex, petData in ipairs(self._petInventoryData) do
		local petType = petData.petId
		local petId = petData.uniqueId or petData.id
		if type(petType) == "string" and petType ~= "" and type(petId) == "string" and petId ~= "" then
			groupCounts[petType] = (groupCounts[petType] or 0) + 1
			local candidate = {
				pet = petData,
				id = petId,
				damage = getPetDamage(petData),
				variantRank = VARIANT_RANK[resolvePetVariant(petData)] or 0,
				sourceIndex = sourceIndex,
			}
			local keeper = keepers[petType]
			if not keeper
				or candidate.damage > keeper.damage
				or (candidate.damage == keeper.damage and candidate.variantRank > keeper.variantRank)
				or (candidate.damage == keeper.damage and candidate.variantRank == keeper.variantRank
					and candidate.id < keeper.id)
				or (candidate.damage == keeper.damage and candidate.variantRank == keeper.variantRank
					and candidate.id == keeper.id and candidate.sourceIndex < keeper.sourceIndex) then
				keepers[petType] = candidate
			end
		end
	end

	local selectedPets = {}
	for _, petData in ipairs(self._petInventoryData) do
		local petType = petData.petId
		local petId = petData.uniqueId or petData.id
		local keeper = petType and keepers[petType]
		if type(petType) == "string" and groupCounts[petType] and groupCounts[petType] > 1
			and petId and keeper and petId ~= keeper.id
			and petData.favorite ~= true then
			selectedPets[petId] = true
		end
	end

	self._selectedPets = selectedPets
	self:_refreshPetGrid()
end

function UIController:_refreshPetGrid()
	local screenGui = self._screens.PetInventory
	if not screenGui then return end
	local mainFrame = screenGui:FindFirstChild("MainFrame")
	if not mainFrame then return end
	local scrollFrame = mainFrame:FindFirstChild("PetGrid")
	if not scrollFrame then return end

	local deleteBtn = mainFrame:FindFirstChild("DeleteSelectedBtn")
	if deleteBtn then
		deleteBtn.Visible = self._multiSelectMode
	end

	local goldenBtn = mainFrame:FindFirstChild("MakeGoldenBtn")
	if goldenBtn then
		goldenBtn.Visible = self._multiSelectMode
	end

	local duplicatesBtn = mainFrame:FindFirstChild("SelectDuplicatesBtn")
	if duplicatesBtn then
		duplicatesBtn.Visible = self._multiSelectMode
	end

	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local displayPets = self:_buildPetDisplayList()
	for displayIndex, entry in ipairs(displayPets) do
		local petData = entry.pet
		local presentation = entry.presentation
		local baseAccent = presentation.baseVariant == "Normal"
			and (RARITY_COLORS[petData.rarity or "Common"] or RARITY_COLORS.Common)
			or rgbToColor(presentation.accentRGB)
		local shinyAccent = rgbToColor(presentation.shinyRGB)
		local card = Instance.new("Frame")
		card.Name = "PetCard_" .. tostring(petData.uniqueId or petData.id or displayIndex)
		card.BackgroundColor3 = COLORS.DarkBg
		card.LayoutOrder = displayIndex
		card.Parent = scrollFrame

		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 12)
		cardCorner.Parent = card

		local rarityColor = RARITY_COLORS[petData.rarity or "Common"] or RARITY_COLORS.Common
		local cardStroke = Instance.new("UIStroke")
		cardStroke.Thickness = 3
		cardStroke.Color = presentation.isShiny and shinyAccent or baseAccent
		cardStroke.Parent = card

		local petIcon = Instance.new("Frame")
		petIcon.Name = "PetIcon"
		petIcon.Size = UDim2.fromScale(0.45, 0.35)
		petIcon.Position = UDim2.fromScale(0.275, 0.05)
		petIcon.BackgroundColor3 = baseAccent
		petIcon.Parent = card

		if presentation.baseVariant == "Rainbow" then
			local rainbowGradient = Instance.new("UIGradient")
			rainbowGradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 120)),
				ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 225, 80)),
				ColorSequenceKeypoint.new(0.66, Color3.fromRGB(70, 220, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(210, 90, 255)),
			})
			rainbowGradient.Rotation = 25
			rainbowGradient.Parent = petIcon
		end

		local iconCorner = Instance.new("UICorner")
		iconCorner.CornerRadius = UDim.new(1, 0)
		iconCorner.Parent = petIcon

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "PetName"
		nameLabel.Size = UDim2.fromScale(0.9, 0.13)
		nameLabel.Position = UDim2.fromScale(0.05, 0.4)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = presentation.displayPetName
		nameLabel.TextColor3 = COLORS.White
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextScaled = true
		nameLabel.Parent = card

		local variantBadge = Instance.new("TextLabel")
		variantBadge.Name = "VariantBadge"
		variantBadge.Size = UDim2.fromScale(0.8, 0.1)
		variantBadge.Position = UDim2.fromScale(0.1, 0.54)
		variantBadge.BackgroundColor3 = baseAccent
		variantBadge.BackgroundTransparency = 0.08
		variantBadge.BorderSizePixel = 0
		variantBadge.Text = presentation.variantLabel
		variantBadge.TextColor3 = COLORS.DarkBg
		variantBadge.Font = Enum.Font.GothamBold
		variantBadge.TextScaled = true
		variantBadge.Parent = card

		local variantCorner = Instance.new("UICorner")
		variantCorner.CornerRadius = UDim.new(0, 6)
		variantCorner.Parent = variantBadge

		if presentation.isShiny then
			local shinyStroke = Instance.new("UIStroke")
			shinyStroke.Thickness = 2
			shinyStroke.Color = shinyAccent
			shinyStroke.Parent = variantBadge
		end

		local dmgLabel = Instance.new("TextLabel")
		dmgLabel.Name = "DmgStat"
		dmgLabel.Size = UDim2.fromScale(0.9, 0.1)
		dmgLabel.Position = UDim2.fromScale(0.05, 0.65)
		dmgLabel.BackgroundTransparency = 1
		dmgLabel.Text = tostring(petData.damage or petData.baseDamage or 5)
		dmgLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
		dmgLabel.Font = Enum.Font.GothamBold
		dmgLabel.TextScaled = true
		dmgLabel.Parent = card

		local petUniqueId = petData.uniqueId or petData.id
		local isFavorite = petData.favorite == true
		local favoriteBtn = Instance.new("TextButton")
		favoriteBtn.Name = "FavoriteBtn"
		favoriteBtn.Size = UDim2.fromScale(0.24, 0.2)
		favoriteBtn.Position = UDim2.fromScale(0.73, 0.02)
		favoriteBtn.BackgroundTransparency = 1
		favoriteBtn.Text = isFavorite and "★" or "☆"
		favoriteBtn.TextColor3 = isFavorite and COLORS.CoinYellow or COLORS.White
		favoriteBtn.TextStrokeColor3 = COLORS.DarkBg
		favoriteBtn.TextStrokeTransparency = 0.25
		favoriteBtn.Font = Enum.Font.GothamBold
		favoriteBtn.TextScaled = true
		favoriteBtn.ZIndex = 2
		favoriteBtn.Active = petUniqueId ~= nil and not self._favoriteRequests[petUniqueId]
		favoriteBtn.AutoButtonColor = favoriteBtn.Active
		favoriteBtn.Parent = card

		favoriteBtn.MouseButton1Click:Connect(function()
			if not petUniqueId or self._favoriteRequests[petUniqueId] then return end
			self:_setPetFavorite(petUniqueId, not isFavorite)
		end)

		if self._multiSelectMode then
			local isSelected = not isFavorite and self._selectedPets[petUniqueId] ~= nil
			local selectBox = Instance.new("TextButton")
			selectBox.Name = "SelectBox"
			selectBox.Size = UDim2.fromScale(0.8, 0.16)
			selectBox.Position = UDim2.fromScale(0.1, 0.8)
			selectBox.BackgroundColor3 = isFavorite and Color3.fromRGB(150, 120, 35)
				or (isSelected and Color3.fromRGB(200, 100, 0) or Color3.fromRGB(60, 70, 110))
			selectBox.Text = isFavorite and "Favorite" or (isSelected and "Selected" or "Select")
			selectBox.TextColor3 = COLORS.White
			selectBox.Font = Enum.Font.GothamBold
			selectBox.TextScaled = true
			selectBox.Active = not isFavorite
			selectBox.AutoButtonColor = not isFavorite
			selectBox.Parent = card

			local selectCorner = Instance.new("UICorner")
			selectCorner.CornerRadius = UDim.new(0, 6)
			selectCorner.Parent = selectBox

			local petId = petUniqueId
			selectBox.MouseButton1Click:Connect(function()
				if isFavorite or not petId then return end
				if self._selectedPets[petId] then
					self._selectedPets[petId] = nil
				else
					self._selectedPets[petId] = true
				end
				self:_refreshPetGrid()
			end)
		else
			local isEquipped = self:_isPetEquipped(petUniqueId)
			local equipBtn = Instance.new("TextButton")
			equipBtn.Name = "EquipBtn"
			equipBtn.Size = UDim2.fromScale(0.8, 0.16)
			equipBtn.Position = UDim2.fromScale(0.1, 0.8)
			equipBtn.BackgroundColor3 = isEquipped and COLORS.ButtonRed or COLORS.ButtonGreen
			equipBtn.Text = isEquipped and "Unequip" or "Equip"
			equipBtn.TextColor3 = COLORS.White
			equipBtn.Font = Enum.Font.GothamBold
			equipBtn.TextScaled = true
			equipBtn.Parent = card

			local equipCorner = Instance.new("UICorner")
			equipCorner.CornerRadius = UDim.new(0, 6)
			equipCorner.Parent = equipBtn

			local petId = petUniqueId
			equipBtn.MouseButton1Click:Connect(function()
				if isEquipped then
					self:_unequipPet(petId)
				else
					self:_equipPet(petId)
				end
			end)

			equipBtn.MouseEnter:Connect(function()
				TweenService:Create(equipBtn, TweenInfo.new(0.1), {
					Size = UDim2.fromScale(0.84, 0.17),
				}):Play()
			end)
			equipBtn.MouseLeave:Connect(function()
				TweenService:Create(equipBtn, TweenInfo.new(0.1), {
					Size = UDim2.fromScale(0.8, 0.16),
				}):Play()
			end)
		end
	end
end

function UIController:_setPetFavorite(uniqueId, isFavorite)
	if not self._remotes or self._favoriteRequests[uniqueId] then return end
	local remote = self._remotes:FindFirstChild("SetPetFavorite")
	if not remote then return end

	local wasSelected = self._selectedPets[uniqueId] ~= nil
	self._favoriteRequests[uniqueId] = true
	if isFavorite then
		self._selectedPets[uniqueId] = nil
	end
	self:_refreshPetGrid()

	local invoked, success, err = pcall(function()
		return remote:InvokeServer(uniqueId, isFavorite)
	end)
	self._favoriteRequests[uniqueId] = nil
	if invoked and success then
		for _, petData in ipairs(self._petInventoryData) do
			local petId = petData.uniqueId or petData.id
			if petId == uniqueId then
				petData.favorite = isFavorite
				break
			end
		end
	else
		if wasSelected then
			self._selectedPets[uniqueId] = true
		end
		local message = invoked and err or success
		self:_showGoldenError(message or "Could not update favorite")
	end
	self:_refreshPetGrid()
end

function UIController:_isPetEquipped(uniqueId)
	-- Check the local equipped pets list (contains full pet data objects or string IDs)
	for _, pet in ipairs(self._equippedPets) do
		if type(pet) == "string" then
			-- Legacy: equippedPets might contain raw string IDs
			if pet == uniqueId then
				return true
			end
		elseif type(pet) == "table" then
			local petId = pet.uniqueId or pet.id
			if petId == uniqueId then
				return true
			end
		end
	end
	-- Fallback: check the pet's own equipped boolean from inventory data
	for _, petData in ipairs(self._petInventoryData) do
		local petId = petData.uniqueId or petData.id
		if petId == uniqueId then
			return petData.equipped == true
		end
	end
	return false
end

function UIController:_equipPet(uniqueId)
	if self._remotes then
		local remote = self._remotes:FindFirstChild("EquipPet")
		if remote then
			print("[UIController] Calling EquipPet remote with id=" .. tostring(uniqueId))
			local success, err = remote:InvokeServer(uniqueId)
			print("[UIController] EquipPet result: success=" .. tostring(success) .. " err=" .. tostring(err))
		end
	end
end

function UIController:_unequipPet(uniqueId)
	if self._remotes then
		local remote = self._remotes:FindFirstChild("UnequipPet")
		if remote then
			print("[UIController] Calling UnequipPet remote with id=" .. tostring(uniqueId))
			local success, err = remote:InvokeServer(uniqueId)
			print("[UIController] UnequipPet result: success=" .. tostring(success) .. " err=" .. tostring(err))
		end
	end
end

function UIController:_deleteSelectedPets()
	if not self._multiSelectMode then return end
	local ids = {}
	for id, _ in pairs(self._selectedPets) do
		table.insert(ids, id)
	end
	if #ids == 0 then return end

	if self._remotes then
		local remote = self._remotes:FindFirstChild("DeletePets")
		if remote then
			local success, err = remote:InvokeServer(ids)
			if success then
				self._selectedPets = {}
			else
				self:_showGoldenError(err or "Could not delete selected pets")
			end
		end
	end
end

--------------------------------------------------------------------------------
-- GOLDEN CONVERSION CONFIRM PANEL
--------------------------------------------------------------------------------
function UIController:_showGoldenConversionConfirm()
	-- Validate selection: must be 1-7 same-type pets, not golden, not equipped
	local selectedIds = {}
	for id, _ in pairs(self._selectedPets) do
		table.insert(selectedIds, id)
	end

	if #selectedIds < 1 or #selectedIds > 7 then
		-- Show brief error
		self:_showGoldenError("Select 1-7 same-type pets!")
		return
	end

	-- Check all selected pets are same type and valid
	local requiredPetId = nil
	for _, selId in ipairs(selectedIds) do
		for _, pet in ipairs(self._petInventoryData) do
			local petUniqueId = pet.uniqueId or pet.id
			if petUniqueId == selId then
				if pet.favorite == true then
					self:_showGoldenError("Favorite pets are protected!")
					return
				end
				if pet.golden == true or pet.variant == "Golden" then
					self:_showGoldenError("Cannot use golden pets!")
					return
				end
				if pet.shiny == true or pet.variant == "Shiny" then
					self:_showGoldenError("Shiny pets are protected!")
					return
				end
				local variant = pet.variant or "Normal"
				if variant ~= "Normal" then
					self:_showGoldenError("Only normal pets can become Golden!")
					return
				end
				if pet.equipped then
					self:_showGoldenError("Unequip pets first!")
					return
				end
				if requiredPetId == nil then
					requiredPetId = pet.petId
				elseif pet.petId ~= requiredPetId then
					self:_showGoldenError("All pets must be the same type!")
					return
				end
				break
			end
		end
	end

	if not requiredPetId then
		self:_showGoldenError("No valid pets selected!")
		return
	end

	-- Calculate chance based on count
	local chanceTable = { 13, 26, 39, 50, 63, 88, 100 }
	local count = #selectedIds
	local chance = chanceTable[count] or 13

	-- Show confirmation overlay
	self:_createGoldenConfirmOverlay(count, chance, requiredPetId, selectedIds)
end

function UIController:_showGoldenError(message)
	if not self._playerGui then return end

	local overlay = Instance.new("ScreenGui")
	overlay.Name = "GoldenError"
	overlay.ResetOnSpawn = false
	overlay.Parent = self._playerGui

	local errorLabel = Instance.new("TextLabel")
	errorLabel.Size = UDim2.fromScale(0.4, 0.06)
	errorLabel.Position = UDim2.fromScale(0.3, 0.45)
	errorLabel.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	errorLabel.BackgroundTransparency = 0.1
	errorLabel.Text = message
	errorLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	errorLabel.Font = Enum.Font.GothamBold
	errorLabel.TextScaled = true
	errorLabel.Parent = overlay

	local errorCorner = Instance.new("UICorner")
	errorCorner.CornerRadius = UDim.new(0, 10)
	errorCorner.Parent = errorLabel

	task.delay(2, function()
		if overlay and overlay.Parent then
			overlay:Destroy()
		end
	end)
end

function UIController:_createGoldenConfirmOverlay(count, chance, petId, selectedIds)
	if not self._playerGui then return end

	-- Remove old overlay if exists
	local existing = self._playerGui:FindFirstChild("GoldenConfirmOverlay")
	if existing then existing:Destroy() end

	local overlay = Instance.new("ScreenGui")
	overlay.Name = "GoldenConfirmOverlay"
	overlay.ResetOnSpawn = false
	overlay.Parent = self._playerGui

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	bg.BackgroundTransparency = 0.5
	bg.BorderSizePixel = 0
	bg.Parent = overlay

	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromScale(0.4, 0.45)
	panel.Position = UDim2.fromScale(0.3, 0.275)
	panel.BackgroundColor3 = Color3.fromRGB(30, 40, 80)
	panel.Parent = bg

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 16)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Thickness = 4
	panelStroke.Color = Color3.fromRGB(255, 200, 0)
	panelStroke.Parent = panel

	-- Title
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.fromScale(0.8, 0.12)
	titleLabel.Position = UDim2.fromScale(0.1, 0.03)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "MAKE GOLDEN"
	titleLabel.TextColor3 = Color3.fromRGB(255, 200, 0)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextScaled = true
	titleLabel.Parent = panel

	-- Info text
	local infoLabel = Instance.new("TextLabel")
	infoLabel.Size = UDim2.fromScale(0.8, 0.1)
	infoLabel.Position = UDim2.fromScale(0.1, 0.17)
	infoLabel.BackgroundTransparency = 1
	infoLabel.Text = "Sacrificing " .. tostring(count) .. "x " .. tostring(petId)
	infoLabel.TextColor3 = Color3.fromRGB(220, 220, 240)
	infoLabel.Font = Enum.Font.GothamBold
	infoLabel.TextScaled = true
	infoLabel.Parent = panel

	-- Chance display (big and prominent)
	local chanceLabel = Instance.new("TextLabel")
	chanceLabel.Size = UDim2.fromScale(0.8, 0.18)
	chanceLabel.Position = UDim2.fromScale(0.1, 0.3)
	chanceLabel.BackgroundTransparency = 1
	chanceLabel.Text = tostring(chance) .. "% CHANCE"
	chanceLabel.Font = Enum.Font.GothamBold
	chanceLabel.TextScaled = true
	chanceLabel.Parent = panel

	-- Color based on chance
	if chance >= 80 then
		chanceLabel.TextColor3 = Color3.fromRGB(0, 220, 80)
	elseif chance >= 50 then
		chanceLabel.TextColor3 = Color3.fromRGB(255, 200, 0)
	else
		chanceLabel.TextColor3 = Color3.fromRGB(255, 100, 50)
	end

	-- Warning text
	local warnLabel = Instance.new("TextLabel")
	warnLabel.Size = UDim2.fromScale(0.8, 0.1)
	warnLabel.Position = UDim2.fromScale(0.1, 0.5)
	warnLabel.BackgroundTransparency = 1
	warnLabel.Text = "WARNING: All pets are consumed even on failure!"
	warnLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
	warnLabel.Font = Enum.Font.GothamBold
	warnLabel.TextScaled = true
	warnLabel.Parent = panel

	-- Confirm button
	local confirmBtn = Instance.new("TextButton")
	confirmBtn.Name = "ConfirmBtn"
	confirmBtn.Size = UDim2.fromScale(0.35, 0.14)
	confirmBtn.Position = UDim2.fromScale(0.08, 0.68)
	confirmBtn.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
	confirmBtn.Text = "CONVERT!"
	confirmBtn.TextColor3 = Color3.fromRGB(40, 30, 0)
	confirmBtn.Font = Enum.Font.GothamBold
	confirmBtn.TextScaled = true
	confirmBtn.Parent = panel

	local confirmCorner = Instance.new("UICorner")
	confirmCorner.CornerRadius = UDim.new(0, 10)
	confirmCorner.Parent = confirmBtn

	-- Cancel button
	local cancelBtn = Instance.new("TextButton")
	cancelBtn.Name = "CancelBtn"
	cancelBtn.Size = UDim2.fromScale(0.35, 0.14)
	cancelBtn.Position = UDim2.fromScale(0.57, 0.68)
	cancelBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 120)
	cancelBtn.Text = "Cancel"
	cancelBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	cancelBtn.Font = Enum.Font.GothamBold
	cancelBtn.TextScaled = true
	cancelBtn.Parent = panel

	local cancelCorner = Instance.new("UICorner")
	cancelCorner.CornerRadius = UDim.new(0, 10)
	cancelCorner.Parent = cancelBtn

	-- Result label (shown after conversion)
	local resultLabel = Instance.new("TextLabel")
	resultLabel.Name = "ResultLabel"
	resultLabel.Size = UDim2.fromScale(0.8, 0.12)
	resultLabel.Position = UDim2.fromScale(0.1, 0.85)
	resultLabel.BackgroundTransparency = 1
	resultLabel.Text = ""
	resultLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	resultLabel.Font = Enum.Font.GothamBold
	resultLabel.TextScaled = true
	resultLabel.Parent = panel

	cancelBtn.MouseButton1Click:Connect(function()
		overlay:Destroy()
	end)

	confirmBtn.MouseButton1Click:Connect(function()
		-- Disable buttons during request
		confirmBtn.Text = "..."
		confirmBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
		cancelBtn.Visible = false

		-- Fire remote
		self:_convertToGolden(selectedIds, resultLabel, overlay)
	end)
end

function UIController:_convertToGolden(petInstanceIds, resultLabel, overlay)
	if not self._remotes then return end

	local remote = self._remotes:FindFirstChild("ConvertToGoldenPet")
	if not remote then return end

	local result, err = remote:InvokeServer(petInstanceIds)

	if err then
		if resultLabel then
			resultLabel.Text = "Error: " .. tostring(err)
			resultLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
		end
		task.delay(3, function()
			if overlay and overlay.Parent then
				overlay:Destroy()
			end
		end)
		return
	end

	if result and result.success then
		if resultLabel then
			local goldenName = result.goldenPet and result.goldenPet.name or "Golden Pet"
			resultLabel.Text = "SUCCESS! Got " .. goldenName .. "!"
			resultLabel.TextColor3 = Color3.fromRGB(255, 220, 0)
		end
		if result.goldenPet and result.isNewDiscovery == true then
			self:enqueueDiscoveryToast(result.goldenPet)
		end
	else
		if resultLabel then
			resultLabel.Text = "FAILED! All pets lost..."
			resultLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
		end
	end

	-- Clear selection
	self._selectedPets = {}

	task.delay(3, function()
		if overlay and overlay.Parent then
			overlay:Destroy()
		end
		self:_refreshPetGrid()
	end)
end

--------------------------------------------------------------------------------
-- QUEST WINDOW (replaces old Upgrade Window)
--------------------------------------------------------------------------------
function UIController:_createQuestWindow()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "QuestWindow"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = false
	screenGui.Parent = self._playerGui
	self._screens.QuestWindow = screenGui

	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.fromScale(0.75, 0.75)
	mainFrame.Position = UDim2.fromScale(0.125, 0.125)
	mainFrame.BackgroundColor3 = COLORS.Background
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = screenGui

	local mainCorner = Instance.new("UICorner")
	mainCorner.CornerRadius = UDim.new(0, 16)
	mainCorner.Parent = mainFrame

	local mainStroke = Instance.new("UIStroke")
	mainStroke.Thickness = 5
	mainStroke.Color = COLORS.NavQuests
	mainStroke.Parent = mainFrame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(0.4, 0.08)
	title.Position = UDim2.fromScale(0.3, 0.01)
	title.BackgroundTransparency = 1
	title.Text = "QUESTS"
	title.TextColor3 = COLORS.NavQuests
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.Parent = mainFrame

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.fromScale(0.6, 0.04)
	subtitle.Position = UDim2.fromScale(0.2, 0.085)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "Complete quests to unlock powerful upgrades!"
	subtitle.TextColor3 = Color3.fromRGB(180, 180, 200)
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextScaled = true
	subtitle.Parent = mainFrame

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.fromOffset(44, 44)
	closeBtn.Position = UDim2.new(1, -54, 0, 10)
	closeBtn.BackgroundColor3 = COLORS.CloseRed
	closeBtn.Text = "X"
	closeBtn.TextColor3 = COLORS.White
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 24
	closeBtn.Parent = mainFrame

	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(1, 0)
	closeBtnCorner.Parent = closeBtn

	closeBtn.MouseButton1Click:Connect(function()
		self:toggleScreen("QuestWindow")
	end)

	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "QuestGrid"
	scrollFrame.Size = UDim2.fromScale(0.94, 0.78)
	scrollFrame.Position = UDim2.fromScale(0.03, 0.14)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.ScrollBarThickness = 8
	scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 130, 200)
	scrollFrame.CanvasSize = UDim2.fromScale(0, 0)
	scrollFrame.Parent = mainFrame

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.Name = "GridLayout"
	gridLayout.CellSize = UDim2.fromOffset(220, 180)
	gridLayout.CellPadding = UDim2.fromOffset(12, 12)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = scrollFrame

	gridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		scrollFrame.CanvasSize = UDim2.fromOffset(0, gridLayout.AbsoluteContentSize.Y + 20)
	end)

	self:_refreshQuestGrid()
end

function UIController:_refreshQuestGrid()
	local screenGui = self._screens.QuestWindow
	if not screenGui then return end
	local mainFrame = screenGui:FindFirstChild("MainFrame")
	if not mainFrame then return end
	local scrollFrame = mainFrame:FindFirstChild("QuestGrid")
	if not scrollFrame then return end

	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	for order, questId in ipairs(QuestData.QuestOrder) do
		local questDef = QuestData.Quests[questId]
		if not questDef then continue end

		local currentLevel = self._upgradeData[questId] or 0
		local maxLevel = #questDef.levels
		local questColor = Color3.fromRGB(questDef.color[1], questDef.color[2], questDef.color[3])

		-- Get progress from questProgress state
		local progress = self._questProgress[questId]
		local currentProgress = progress and progress.currentProgress or 0
		local nextRequired = progress and progress.nextRequired or questDef.levelRequirements[1]
		local isCompleted = currentLevel >= maxLevel

		local card = Instance.new("Frame")
		card.Name = "Quest_" .. questId
		card.BackgroundColor3 = Color3.fromRGB(
			math.floor(questColor.R * 255 * 0.2 + 25),
			math.floor(questColor.G * 255 * 0.2 + 25),
			math.floor(questColor.B * 255 * 0.2 + 40)
		)
		card.LayoutOrder = order
		card.Parent = scrollFrame

		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 12)
		cardCorner.Parent = card

		local cardStroke = Instance.new("UIStroke")
		cardStroke.Thickness = 3
		cardStroke.Color = isCompleted and Color3.fromRGB(100, 100, 100) or questColor
		cardStroke.Parent = card

		-- Icon
		local iconLabel = Instance.new("TextLabel")
		iconLabel.Name = "Icon"
		iconLabel.Size = UDim2.fromScale(0.25, 0.22)
		iconLabel.Position = UDim2.fromScale(0.02, 0.03)
		iconLabel.BackgroundTransparency = 1
		iconLabel.Text = questDef.icon
		iconLabel.TextColor3 = questColor
		iconLabel.Font = Enum.Font.GothamBold
		iconLabel.TextScaled = true
		iconLabel.Parent = card

		-- Quest name
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "QuestName"
		nameLabel.Size = UDim2.fromScale(0.7, 0.16)
		nameLabel.Position = UDim2.fromScale(0.28, 0.03)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = questDef.displayName
		nameLabel.TextColor3 = COLORS.White
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextScaled = true
		nameLabel.Parent = card

		-- Description
		local descLabel = Instance.new("TextLabel")
		descLabel.Name = "Description"
		descLabel.Size = UDim2.fromScale(0.9, 0.12)
		descLabel.Position = UDim2.fromScale(0.05, 0.22)
		descLabel.BackgroundTransparency = 1
		descLabel.Text = questDef.description
		descLabel.TextColor3 = Color3.fromRGB(180, 180, 200)
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		descLabel.Font = Enum.Font.Gotham
		descLabel.TextScaled = true
		descLabel.Parent = card

		-- Level indicator
		local levelText = ""
		for lv = 1, maxLevel do
			levelText = levelText .. (lv <= currentLevel and "★" or "☆")
		end
		local levelLabel = Instance.new("TextLabel")
		levelLabel.Name = "LevelIndicator"
		levelLabel.Size = UDim2.fromScale(0.9, 0.12)
		levelLabel.Position = UDim2.fromScale(0.05, 0.36)
		levelLabel.BackgroundTransparency = 1
		levelLabel.Text = "Lv." .. tostring(currentLevel) .. "/" .. tostring(maxLevel) .. " " .. levelText
		levelLabel.TextColor3 = questColor
		levelLabel.TextXAlignment = Enum.TextXAlignment.Left
		levelLabel.Font = Enum.Font.GothamBold
		levelLabel.TextScaled = true
		levelLabel.Parent = card

		-- Requirement text
		local reqText = questDef.requirement.displayText
		if not isCompleted then
			local nextReq = questDef.levelRequirements[currentLevel + 1] or 0
			reqText = questDef.requirement.displayText:gsub("%d[%d,]*", tostring(nextReq))
		end
		local reqLabel = Instance.new("TextLabel")
		reqLabel.Name = "Requirement"
		reqLabel.Size = UDim2.fromScale(0.9, 0.1)
		reqLabel.Position = UDim2.fromScale(0.05, 0.5)
		reqLabel.BackgroundTransparency = 1
		reqLabel.Text = isCompleted and "COMPLETED!" or reqText
		reqLabel.TextColor3 = isCompleted and Color3.fromRGB(0, 200, 80) or Color3.fromRGB(200, 200, 220)
		reqLabel.TextXAlignment = Enum.TextXAlignment.Left
		reqLabel.Font = Enum.Font.Gotham
		reqLabel.TextScaled = true
		reqLabel.Parent = card

		-- Progress bar (only if not fully completed)
		if not isCompleted then
			local progressBg = Instance.new("Frame")
			progressBg.Name = "ProgressBg"
			progressBg.Size = UDim2.fromScale(0.9, 0.1)
			progressBg.Position = UDim2.fromScale(0.05, 0.65)
			progressBg.BackgroundColor3 = COLORS.QuestProgressBg
			progressBg.BorderSizePixel = 0
			progressBg.Parent = card

			local progressCorner = Instance.new("UICorner")
			progressCorner.CornerRadius = UDim.new(0.5, 0)
			progressCorner.Parent = progressBg

			local fillFraction = 0
			if nextRequired > 0 then
				fillFraction = math.clamp(currentProgress / nextRequired, 0, 1)
			end

			local progressFill = Instance.new("Frame")
			progressFill.Name = "ProgressFill"
			progressFill.Size = UDim2.fromScale(fillFraction, 1)
			progressFill.BackgroundColor3 = questColor
			progressFill.BorderSizePixel = 0
			progressFill.Parent = progressBg

			local fillCorner = Instance.new("UICorner")
			fillCorner.CornerRadius = UDim.new(0.5, 0)
			fillCorner.Parent = progressFill

			-- Progress text overlay
			local progressText = Instance.new("TextLabel")
			progressText.Name = "ProgressText"
			progressText.Size = UDim2.fromScale(1, 1)
			progressText.BackgroundTransparency = 1
			progressText.Text = tostring(currentProgress) .. " / " .. tostring(nextRequired)
			progressText.TextColor3 = COLORS.White
			progressText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
			progressText.TextStrokeTransparency = 0.5
			progressText.Font = Enum.Font.GothamBold
			progressText.TextScaled = true
			progressText.ZIndex = 2
			progressText.Parent = progressBg
		end

		-- Bonus info at bottom
		if currentLevel > 0 then
			local bonusValue = questDef.levels[currentLevel].bonus
			local bonusText = ""
			if bonusValue >= 1 then
				bonusText = "Active: x" .. tostring(bonusValue)
			else
				bonusText = "Active: " .. tostring(math.floor(bonusValue * 100)) .. "%"
			end
			local bonusLabel = Instance.new("TextLabel")
			bonusLabel.Name = "BonusLabel"
			bonusLabel.Size = UDim2.fromScale(0.9, 0.12)
			bonusLabel.Position = UDim2.fromScale(0.05, 0.82)
			bonusLabel.BackgroundTransparency = 1
			bonusLabel.Text = bonusText
			bonusLabel.TextColor3 = Color3.fromRGB(0, 220, 100)
			bonusLabel.TextXAlignment = Enum.TextXAlignment.Left
			bonusLabel.Font = Enum.Font.GothamBold
			bonusLabel.TextScaled = true
			bonusLabel.Parent = card
		end
	end
end

--------------------------------------------------------------------------------
-- MASTERY WINDOW
--------------------------------------------------------------------------------
function UIController:_createMasteryWindow()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MasteryWindow"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = false
	screenGui.Parent = self._playerGui
	self._screens.MasteryWindow = screenGui

	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.fromScale(0.7, 0.7)
	mainFrame.Position = UDim2.fromScale(0.15, 0.15)
	mainFrame.BackgroundColor3 = COLORS.Background
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = screenGui

	local mainCorner = Instance.new("UICorner")
	mainCorner.CornerRadius = UDim.new(0, 16)
	mainCorner.Parent = mainFrame

	local mainStroke = Instance.new("UIStroke")
	mainStroke.Thickness = 5
	mainStroke.Color = COLORS.MasteryPurple
	mainStroke.Parent = mainFrame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(0.4, 0.08)
	title.Position = UDim2.fromScale(0.3, 0.01)
	title.BackgroundTransparency = 1
	title.Text = "MASTERY"
	title.TextColor3 = COLORS.MasteryPurple
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.Parent = mainFrame

	-- Points available display
	local pointsLabel = Instance.new("TextLabel")
	pointsLabel.Name = "PointsLabel"
	pointsLabel.Size = UDim2.fromScale(0.4, 0.05)
	pointsLabel.Position = UDim2.fromScale(0.3, 0.09)
	pointsLabel.BackgroundTransparency = 1
	pointsLabel.Text = "Points: " .. tostring(self._masteryState.masteryPoints)
	pointsLabel.TextColor3 = COLORS.CoinYellow
	pointsLabel.Font = Enum.Font.GothamBold
	pointsLabel.TextScaled = true
	pointsLabel.Parent = mainFrame

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.fromScale(0.6, 0.035)
	subtitle.Position = UDim2.fromScale(0.2, 0.14)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "Earn points from leveling up. Spend them on permanent buffs!"
	subtitle.TextColor3 = Color3.fromRGB(180, 180, 200)
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextScaled = true
	subtitle.Parent = mainFrame

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.fromOffset(44, 44)
	closeBtn.Position = UDim2.new(1, -54, 0, 10)
	closeBtn.BackgroundColor3 = COLORS.CloseRed
	closeBtn.Text = "X"
	closeBtn.TextColor3 = COLORS.White
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 24
	closeBtn.Parent = mainFrame

	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(1, 0)
	closeBtnCorner.Parent = closeBtn

	closeBtn.MouseButton1Click:Connect(function()
		self:toggleScreen("MasteryWindow")
	end)

	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "MasteryGrid"
	scrollFrame.Size = UDim2.fromScale(0.94, 0.72)
	scrollFrame.Position = UDim2.fromScale(0.03, 0.19)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.ScrollBarThickness = 8
	scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(150, 100, 220)
	scrollFrame.CanvasSize = UDim2.fromScale(0, 0)
	scrollFrame.Parent = mainFrame

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.Name = "GridLayout"
	gridLayout.CellSize = UDim2.fromOffset(200, 180)
	gridLayout.CellPadding = UDim2.fromOffset(12, 12)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = scrollFrame

	gridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		scrollFrame.CanvasSize = UDim2.fromOffset(0, gridLayout.AbsoluteContentSize.Y + 20)
	end)

	self:_refreshMasteryGrid()
end

function UIController:_refreshMasteryGrid()
	local screenGui = self._screens.MasteryWindow
	if not screenGui then return end
	local mainFrame = screenGui:FindFirstChild("MainFrame")
	if not mainFrame then return end
	local scrollFrame = mainFrame:FindFirstChild("MasteryGrid")
	if not scrollFrame then return end

	-- Update points display
	local pointsLabel = mainFrame:FindFirstChild("PointsLabel")
	if pointsLabel then
		pointsLabel.Text = "Points: " .. tostring(self._masteryState.masteryPoints)
	end

	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local buffs = self._masteryState.buffs or {}

	for order, buffId in ipairs(MasteryData.BuffOrder) do
		local buffDef = MasteryData.Buffs[buffId]
		if not buffDef then continue end

		local currentLevel = buffs[buffId] or 0
		local maxLevel = buffDef.maxLevel
		local buffColor = Color3.fromRGB(buffDef.color[1], buffDef.color[2], buffDef.color[3])
		local isMaxed = currentLevel >= maxLevel

		local card = Instance.new("Frame")
		card.Name = "Buff_" .. buffId
		card.BackgroundColor3 = Color3.fromRGB(
			math.floor(buffColor.R * 255 * 0.2 + 25),
			math.floor(buffColor.G * 255 * 0.2 + 25),
			math.floor(buffColor.B * 255 * 0.2 + 40)
		)
		card.LayoutOrder = order
		card.Parent = scrollFrame

		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 12)
		cardCorner.Parent = card

		local cardStroke = Instance.new("UIStroke")
		cardStroke.Thickness = 3
		cardStroke.Color = buffColor
		cardStroke.Parent = card

		-- Icon
		local iconLabel = Instance.new("TextLabel")
		iconLabel.Name = "Icon"
		iconLabel.Size = UDim2.fromScale(0.35, 0.25)
		iconLabel.Position = UDim2.fromScale(0.325, 0.02)
		iconLabel.BackgroundTransparency = 1
		iconLabel.Text = buffDef.icon
		iconLabel.TextColor3 = buffColor
		iconLabel.Font = Enum.Font.GothamBold
		iconLabel.TextScaled = true
		iconLabel.Parent = card

		-- Buff name
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "BuffName"
		nameLabel.Size = UDim2.fromScale(0.9, 0.14)
		nameLabel.Position = UDim2.fromScale(0.05, 0.28)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = buffDef.displayName
		nameLabel.TextColor3 = COLORS.White
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextScaled = true
		nameLabel.Parent = card

		-- Description
		local descLabel = Instance.new("TextLabel")
		descLabel.Name = "Description"
		descLabel.Size = UDim2.fromScale(0.9, 0.1)
		descLabel.Position = UDim2.fromScale(0.05, 0.42)
		descLabel.BackgroundTransparency = 1
		descLabel.Text = buffDef.description
		descLabel.TextColor3 = Color3.fromRGB(180, 180, 200)
		descLabel.Font = Enum.Font.Gotham
		descLabel.TextScaled = true
		descLabel.Parent = card

		-- Level indicator
		local levelText = "Lv." .. tostring(currentLevel) .. "/" .. tostring(maxLevel)
		local levelLabel = Instance.new("TextLabel")
		levelLabel.Name = "LevelIndicator"
		levelLabel.Size = UDim2.fromScale(0.9, 0.1)
		levelLabel.Position = UDim2.fromScale(0.05, 0.54)
		levelLabel.BackgroundTransparency = 1
		levelLabel.Text = levelText
		levelLabel.TextColor3 = buffColor
		levelLabel.Font = Enum.Font.GothamBold
		levelLabel.TextScaled = true
		levelLabel.Parent = card

		-- Current bonus display
		if currentLevel > 0 then
			local bonusValue = buffDef.bonusPerLevel[currentLevel]
			local bonusText = "x" .. tostring(bonusValue)
			local activeLabel = Instance.new("TextLabel")
			activeLabel.Name = "ActiveBonus"
			activeLabel.Size = UDim2.fromScale(0.9, 0.09)
			activeLabel.Position = UDim2.fromScale(0.05, 0.64)
			activeLabel.BackgroundTransparency = 1
			activeLabel.Text = "Bonus: " .. bonusText
			activeLabel.TextColor3 = Color3.fromRGB(0, 220, 100)
			activeLabel.Font = Enum.Font.GothamBold
			activeLabel.TextScaled = true
			activeLabel.Parent = card
		end

		-- Buy button or MAXED label
		if isMaxed then
			local maxLabel = Instance.new("TextLabel")
			maxLabel.Size = UDim2.fromScale(0.7, 0.15)
			maxLabel.Position = UDim2.fromScale(0.15, 0.78)
			maxLabel.BackgroundTransparency = 1
			maxLabel.Text = "MAXED"
			maxLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
			maxLabel.Font = Enum.Font.GothamBold
			maxLabel.TextScaled = true
			maxLabel.Parent = card
		else
			local cost = buffDef.pointsPerLevel[currentLevel + 1]
			local canAfford = (self._masteryState.masteryPoints or 0) >= cost

			local buyBtn = Instance.new("TextButton")
			buyBtn.Name = "BuyBtn"
			buyBtn.Size = UDim2.fromScale(0.7, 0.17)
			buyBtn.Position = UDim2.fromScale(0.15, 0.78)
			buyBtn.BackgroundColor3 = canAfford and COLORS.MasteryPurple or Color3.fromRGB(80, 80, 100)
			buyBtn.Text = tostring(cost) .. " pts"
			buyBtn.TextColor3 = COLORS.White
			buyBtn.Font = Enum.Font.GothamBold
			buyBtn.TextScaled = true
			buyBtn.Parent = card

			local buyCorner = Instance.new("UICorner")
			buyCorner.CornerRadius = UDim.new(0, 8)
			buyCorner.Parent = buyBtn

			local buyStroke = Instance.new("UIStroke")
			buyStroke.Thickness = 2
			buyStroke.Color = canAfford and Color3.fromRGB(120, 50, 180) or Color3.fromRGB(60, 60, 80)
			buyStroke.Parent = buyBtn

			buyBtn.MouseButton1Click:Connect(function()
				self:_purchaseMasteryBuff(buffId)
			end)

			buyBtn.MouseEnter:Connect(function()
				TweenService:Create(buyBtn, TweenInfo.new(0.1), {
					Size = UDim2.fromScale(0.74, 0.18),
				}):Play()
			end)
			buyBtn.MouseLeave:Connect(function()
				TweenService:Create(buyBtn, TweenInfo.new(0.1), {
					Size = UDim2.fromScale(0.7, 0.17),
				}):Play()
			end)
		end
	end
end

function UIController:_purchaseMasteryBuff(buffId)
	if self._remotes then
		local remote = self._remotes:FindFirstChild("PurchaseMasteryBuff")
		if remote then
			remote:InvokeServer(buffId)
		end
	end
end

--------------------------------------------------------------------------------
-- EGG STATION CONTEXT - the native E ProximityPrompt remains in the world.
-- Triggering it opens the reusable QOF-10 purchase dialog created above; the
-- legacy ShopWindow/EggPrompt overlay remains intentionally empty.
-- BillboardGuis showing pet probabilities are created server-side on the stations.
--------------------------------------------------------------------------------
function UIController:_createShopWindow()
	-- No shop window overlay needed - E-key hatches directly
	-- Create an empty disabled ScreenGui so toggleScreen references still work
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ShopWindow"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = false
	screenGui.Parent = self._playerGui
	self._screens.ShopWindow = screenGui
end

local function formatWholeNumber(value)
	local formatted = tostring(math.max(0, math.floor(tonumber(value) or 0)))
	while true do
		local replacements
		formatted, replacements = string.gsub(formatted, "^(%d+)(%d%d%d)", "%1.%2")
		if replacements == 0 then
			return formatted
		end
	end
end

function UIController:_resolveNextZone()
	for zoneId, zoneDef in ipairs(ZoneData.Zones) do
		if not self._unlockedZones[zoneId] then
			return zoneId, zoneDef
		end
	end
	return nil, nil
end

function UIController:_updateZoneProgress()
	if not self._zoneProgressLabel then return end

	local zoneId, zoneDef = self:_resolveNextZone()
	if not zoneDef then
		self._zoneProgressLabel.Text = "All zones unlocked!"
		self._zoneProgressLabel.TextColor3 = COLORS.ButtonGreen
		return
	end

	local cost = math.max(0, tonumber(zoneDef.unlockCost) or 0)
	local progress = math.min(math.max(0, self._coins), cost)
	local missing = math.max(0, cost - self._coins)
	local progressText = "Zone " .. tostring(zoneId) .. ": "
		.. formatWholeNumber(progress) .. " / " .. formatWholeNumber(cost) .. " Coins"

	local remainingText = formatWholeNumber(missing) .. " Coins remaining"
	if missing > 0 then
		self._zoneProgressLabel.Text = progressText .. "\n" .. remainingText
		self._zoneProgressLabel.TextColor3 = COLORS.White
	else
		self._zoneProgressLabel.Text = progressText .. "\n" .. remainingText .. " - READY!"
		self._zoneProgressLabel.TextColor3 = COLORS.ButtonGreen
	end
end

function UIController:_resolveTargetEgg()
	local selectedEgg = self._selectedEggType and PetData.Eggs[self._selectedEggType]
	if selectedEgg and self._unlockedZones[selectedEgg.zone] then
		return self._selectedEggType, selectedEgg
	end

	local targetEggType = nil
	local targetEgg = nil
	for eggType, eggDef in pairs(PetData.Eggs) do
		if self._unlockedZones[eggDef.zone]
			and (not targetEgg
				or eggDef.zone > targetEgg.zone
				or (eggDef.zone == targetEgg.zone and eggType < targetEggType)) then
			targetEggType = eggType
			targetEgg = eggDef
		end
	end
	return targetEggType, targetEgg
end

function UIController:_updateEggShortfall()
	if not self._eggShortfallLabel then return end

	local _, eggDef = self:_resolveTargetEgg()
	local cost = eggDef and Config.EggCosts[eggDef.zone]
	if not eggDef or not cost then
		self._eggShortfallLabel.Text = "Egg progress unavailable"
		self._eggShortfallLabel.TextColor3 = COLORS.White
		return
	end

	-- Near a station the native ProximityPrompt is the only call to action. The
	-- amount is chosen only after E opens a fresh server-quoted purchase dialog.
	if self._selectedEggType ~= nil then
		self._eggShortfallLabel.Text = eggDef.name .. ": Press E to choose amount"
		self._eggShortfallLabel.TextColor3 = COLORS.White
		return
	end

	local missing = {}
	if cost.Coins then
		local missingCoins = math.max(0, cost.Coins - self._coins)
		if missingCoins > 0 then
			table.insert(missing, tostring(missingCoins) .. " Coins")
		end
	end
	if cost.Diamonds then
		local missingDiamonds = math.max(0, cost.Diamonds - self._diamonds)
		if missingDiamonds > 0 then
			table.insert(missing, tostring(missingDiamonds) .. " Diamonds")
		end
	end

	if #missing == 0 then
		self._eggShortfallLabel.Text = eggDef.name .. ": READY TO HATCH!"
		self._eggShortfallLabel.TextColor3 = COLORS.ButtonGreen
	else
		self._eggShortfallLabel.Text = eggDef.name .. ": Need " .. table.concat(missing, " + ")
		self._eggShortfallLabel.TextColor3 = COLORS.White
	end
end

function UIController:showEggStationPrompt(eggType)
	local eggDef = PetData.Eggs[eggType]
	if not eggDef or not self._unlockedZones[eggDef.zone] then return end

	self._selectedEggType = eggType
	self:_updateEggShortfall()
end

function UIController:hideEggStationPrompt(eggType)
	if self._selectedEggType ~= eggType then return end

	if self._activeHatchPurchaseEggType == eggType then
		self:_requestHatchPurchaseCancel()
	end
	self._selectedEggType = nil
	self:_updateEggShortfall()
end

function UIController:unlockZone(zoneId)
	zoneId = normalizeZoneId(zoneId)
	if not zoneId then return end

	self._unlockedZones[zoneId] = true
	self:_updateEggShortfall()
	self:_updateZoneProgress()
end

--------------------------------------------------------------------------------
-- SHOP SCREEN (Pet Simulator-style potion shop)
--------------------------------------------------------------------------------
local function shopColor(rgb)
	return Color3.fromRGB(rgb[1] or 255, rgb[2] or 255, rgb[3] or 255)
end

local function addShopCorner(instance, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
	return corner
end

local function addShopStroke(instance, color, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Parent = instance
	return stroke
end

local function formatShopTime(seconds)
	seconds = math.max(0, math.ceil(tonumber(seconds) or 0))
	return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

function UIController:_createShopItemArt(parent, item)
	local color = shopColor(item.color)
	local accent = shopColor(item.accentColor)
	local art = Instance.new("Frame")
	art.Name = "ItemArt"
	art.Size = UDim2.fromScale(0.29, 0.62)
	art.Position = UDim2.fromScale(0.035, 0.18)
	art.BackgroundTransparency = 1
	art.Parent = parent

	if item.artType == "potion" then
		local glow = Instance.new("Frame")
		glow.Name = "Glow"
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Size = UDim2.fromScale(0.9, 0.72)
		glow.Position = UDim2.fromScale(0.5, 0.58)
		glow.BackgroundColor3 = accent
		glow.BackgroundTransparency = 0.68
		glow.Parent = art
		addShopCorner(glow, 999)

		local bottle = Instance.new("Frame")
		bottle.Name = "Bottle"
		bottle.AnchorPoint = Vector2.new(0.5, 1)
		bottle.Size = UDim2.fromScale(0.62, 0.62)
		bottle.Position = UDim2.fromScale(0.5, 0.92)
		bottle.BackgroundColor3 = color
		bottle.Parent = art
		addShopCorner(bottle, 18)
		addShopStroke(bottle, Color3.fromRGB(255, 255, 255), 3)

		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, accent),
			ColorSequenceKeypoint.new(1, color),
		})
		gradient.Rotation = 25
		gradient.Parent = bottle

		local shine = Instance.new("Frame")
		shine.Size = UDim2.fromScale(0.14, 0.56)
		shine.Position = UDim2.fromScale(0.16, 0.18)
		shine.BackgroundColor3 = COLORS.White
		shine.BackgroundTransparency = 0.38
		shine.Parent = bottle
		addShopCorner(shine, 999)

		local neck = Instance.new("Frame")
		neck.Name = "Neck"
		neck.AnchorPoint = Vector2.new(0.5, 1)
		neck.Size = UDim2.fromScale(0.3, 0.24)
		neck.Position = UDim2.fromScale(0.5, 0.36)
		neck.BackgroundColor3 = accent
		neck.Parent = art
		addShopCorner(neck, 6)
		addShopStroke(neck, COLORS.White, 2)

		local cork = Instance.new("Frame")
		cork.Name = "Cork"
		cork.AnchorPoint = Vector2.new(0.5, 1)
		cork.Size = UDim2.fromScale(0.4, 0.13)
		cork.Position = UDim2.fromScale(0.5, 0.17)
		cork.BackgroundColor3 = Color3.fromRGB(132, 82, 48)
		cork.Parent = art
		addShopCorner(cork, 5)
		addShopStroke(cork, Color3.fromRGB(88, 50, 30), 2)
	elseif item.artType == "egg" then
		local egg = Instance.new("Frame")
		egg.Name = "Egg"
		egg.AnchorPoint = Vector2.new(0.5, 0.5)
		egg.Size = UDim2.fromScale(0.66, 0.78)
		egg.Position = UDim2.fromScale(0.5, 0.54)
		egg.BackgroundColor3 = accent
		egg.Parent = art
		addShopCorner(egg, 999)
		addShopStroke(egg, COLORS.White, 3)

		local spotPositions = {
			{ 0.20, 0.28, 0.24 },
			{ 0.58, 0.18, 0.19 },
			{ 0.50, 0.56, 0.28 },
			{ 0.16, 0.68, 0.17 },
		}
		for index, spotData in ipairs(spotPositions) do
			local spot = Instance.new("Frame")
			spot.Name = "Spot" .. tostring(index)
			spot.Size = UDim2.fromScale(spotData[3], spotData[3])
			spot.Position = UDim2.fromScale(spotData[1], spotData[2])
			spot.BackgroundColor3 = color
			spot.Rotation = index * 13
			spot.Parent = egg
			addShopCorner(spot, 999)
		end
	else
		local pawColor = color
		local pad = Instance.new("Frame")
		pad.Name = "PawPad"
		pad.AnchorPoint = Vector2.new(0.5, 0.5)
		pad.Size = UDim2.fromScale(0.55, 0.42)
		pad.Position = UDim2.fromScale(0.42, 0.64)
		pad.BackgroundColor3 = pawColor
		pad.Rotation = -8
		pad.Parent = art
		addShopCorner(pad, 999)
		addShopStroke(pad, COLORS.White, 2)

		local toes = {
			{ 0.12, 0.22 }, { 0.36, 0.08 }, { 0.62, 0.12 }, { 0.78, 0.32 },
		}
		for index, position in ipairs(toes) do
			local toe = Instance.new("Frame")
			toe.Name = "Toe" .. tostring(index)
			toe.Size = UDim2.fromScale(0.23, 0.23)
			toe.Position = UDim2.fromScale(position[1], position[2])
			toe.BackgroundColor3 = pawColor
			toe.Parent = art
			addShopCorner(toe, 999)
			addShopStroke(toe, COLORS.White, 2)
		end

		local plus = Instance.new("TextLabel")
		plus.Name = "Plus"
		plus.AnchorPoint = Vector2.new(0.5, 0.5)
		plus.Size = UDim2.fromScale(0.45, 0.45)
		plus.Position = UDim2.fromScale(0.76, 0.72)
		plus.BackgroundColor3 = accent
		plus.Text = "+"
		plus.TextColor3 = Color3.fromRGB(120, 35, 90)
		plus.Font = Enum.Font.GothamBlack
		plus.TextScaled = true
		plus.Parent = art
		addShopCorner(plus, 999)
		addShopStroke(plus, COLORS.White, 3)
	end
end

function UIController:_createShopScreen()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ShopScreen"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 60
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = false
	screenGui.Parent = self._playerGui
	self._screens.ShopScreen = screenGui

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(12, 20, 36)
	backdrop.BackgroundTransparency = 0.28
	backdrop.BorderSizePixel = 0
	backdrop.Active = true
	backdrop.Parent = screenGui

	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	mainFrame.Size = UDim2.fromScale(0.92, 0.88)
	mainFrame.Position = UDim2.fromScale(0.5, 0.5)
	mainFrame.BackgroundColor3 = Color3.fromRGB(64, 218, 77)
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = screenGui
	addShopCorner(mainFrame, 26)
	addShopStroke(mainFrame, Color3.fromRGB(26, 145, 45), 6)

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(980, 760)
	sizeConstraint.Parent = mainFrame

	local innerPanel = Instance.new("Frame")
	innerPanel.Name = "InnerPanel"
	innerPanel.Size = UDim2.new(1, -22, 1, -22)
	innerPanel.Position = UDim2.fromOffset(11, 11)
	innerPanel.BackgroundColor3 = Color3.fromRGB(250, 255, 247)
	innerPanel.BorderSizePixel = 0
	innerPanel.ClipsDescendants = true
	innerPanel.Parent = mainFrame
	addShopCorner(innerPanel, 20)

	local headerGlow = Instance.new("Frame")
	headerGlow.Name = "HeaderGlow"
	headerGlow.Size = UDim2.new(1, 0, 0, 108)
	headerGlow.BackgroundColor3 = Color3.fromRGB(221, 255, 209)
	headerGlow.BorderSizePixel = 0
	headerGlow.Parent = innerPanel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(0.58, 0, 0, 58)
	title.Position = UDim2.new(0.21, 0, 0, 12)
	title.BackgroundTransparency = 1
	title.Text = "POTION SHOP"
	title.TextColor3 = Color3.fromRGB(49, 201, 65)
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.Parent = innerPanel
	addShopStroke(title, Color3.fromRGB(19, 104, 38), 2)

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.new(0.56, 0, 0, 25)
	subtitle.Position = UDim2.new(0.22, 0, 0, 67)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "POWER UP YOUR TEAM!"
	subtitle.TextColor3 = Color3.fromRGB(76, 124, 83)
	subtitle.Font = Enum.Font.GothamBold
	subtitle.TextScaled = true
	subtitle.Parent = innerPanel

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.Size = UDim2.fromOffset(52, 52)
	closeBtn.Position = UDim2.new(1, -14, 0, 14)
	closeBtn.BackgroundColor3 = Color3.fromRGB(239, 63, 73)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = COLORS.White
	closeBtn.Font = Enum.Font.GothamBlack
	closeBtn.TextSize = 27
	closeBtn.AutoButtonColor = false
	closeBtn.Parent = innerPanel
	addShopCorner(closeBtn, 999)
	addShopStroke(closeBtn, Color3.fromRGB(150, 25, 40), 4)
	closeBtn.Activated:Connect(function()
		self:closeScreen("ShopScreen")
	end)

	local diamondPill = Instance.new("Frame")
	diamondPill.Name = "DiamondPill"
	diamondPill.Size = UDim2.fromOffset(176, 42)
	diamondPill.Position = UDim2.fromOffset(20, 74)
	diamondPill.BackgroundColor3 = Color3.fromRGB(22, 67, 105)
	diamondPill.Parent = innerPanel
	addShopCorner(diamondPill, 999)
	addShopStroke(diamondPill, Color3.fromRGB(35, 188, 231), 3)

	local diamondIcon = Instance.new("TextLabel")
	diamondIcon.Name = "DiamondIcon"
	diamondIcon.Size = UDim2.fromOffset(36, 36)
	diamondIcon.Position = UDim2.fromOffset(4, 3)
	diamondIcon.BackgroundTransparency = 1
	diamondIcon.Text = "◆"
	diamondIcon.TextColor3 = Color3.fromRGB(80, 230, 255)
	diamondIcon.Font = Enum.Font.GothamBlack
	diamondIcon.TextSize = 28
	diamondIcon.Parent = diamondPill

	local diamondLabel = Instance.new("TextLabel")
	diamondLabel.Name = "DiamondBalance"
	diamondLabel.Size = UDim2.new(1, -43, 1, 0)
	diamondLabel.Position = UDim2.fromOffset(40, 0)
	diamondLabel.BackgroundTransparency = 1
	diamondLabel.Text = tostring(self._diamonds)
	diamondLabel.TextColor3 = COLORS.White
	diamondLabel.Font = Enum.Font.GothamBlack
	diamondLabel.TextSize = 20
	diamondLabel.TextXAlignment = Enum.TextXAlignment.Left
	diamondLabel.Parent = diamondPill
	self._shopDiamondLabel = diamondLabel

	local feedback = Instance.new("TextLabel")
	feedback.Name = "Feedback"
	feedback.AnchorPoint = Vector2.new(0.5, 0)
	feedback.Size = UDim2.new(0.52, 0, 0, 30)
	feedback.Position = UDim2.new(0.5, 0, 0, 82)
	feedback.BackgroundTransparency = 1
	feedback.Text = ""
	feedback.TextColor3 = Color3.fromRGB(40, 145, 60)
	feedback.Font = Enum.Font.GothamBold
	feedback.TextScaled = true
	feedback.Parent = innerPanel
	self._shopFeedbackLabel = feedback

	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ShopGrid"
	scrollFrame.Size = UDim2.new(1, -32, 1, -132)
	scrollFrame.Position = UDim2.fromOffset(16, 122)
	scrollFrame.BackgroundColor3 = Color3.fromRGB(235, 247, 232)
	scrollFrame.BackgroundTransparency = 0.2
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 9
	scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(57, 200, 72)
	scrollFrame.CanvasSize = UDim2.fromOffset(0, 0)
	scrollFrame.ScrollingDirection = Enum.ScrollingDirection.Y
	scrollFrame.Parent = innerPanel
	addShopCorner(scrollFrame, 14)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 7)
	padding.PaddingRight = UDim.new(0, 7)
	padding.Parent = scrollFrame

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.Name = "GridLayout"
	gridLayout.CellSize = UDim2.fromOffset(360, 220)
	gridLayout.CellPadding = UDim2.fromOffset(14, 14)
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = scrollFrame

	local function updateGridLayout()
		-- AbsoluteSize already reflects the current safe viewport. Subtract the
		-- grid padding and scrollbar instead of imposing a width floor that can
		-- create unreachable horizontal overflow on narrow phones.
		local availableWidth = math.max(1, scrollFrame.AbsoluteSize.X - 25)
		local columns = availableWidth < 590 and 1 or 2
		local gap = 14
		local cellWidth = math.max(1, math.floor((availableWidth - gap * (columns - 1)) / columns))
		local cellHeight
		if columns == 1 then
			cellHeight = math.clamp(math.floor(cellWidth * 0.62), 180, 265)
		else
			cellHeight = math.clamp(math.floor(cellWidth * 0.61), 185, 245)
		end
		gridLayout.FillDirectionMaxCells = columns
		gridLayout.CellSize = UDim2.fromOffset(cellWidth, cellHeight)
	end

	table.insert(self._shopConnections, scrollFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateGridLayout))
	table.insert(self._shopConnections, gridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		scrollFrame.CanvasSize = UDim2.fromOffset(0, gridLayout.AbsoluteContentSize.Y + 16)
	end))
	task.defer(updateGridLayout)

	self:_refreshShopGrid()

	local elapsed = 0
	self._shopTimerConnection = RunService.Heartbeat:Connect(function(deltaTime)
		elapsed += deltaTime
		if elapsed >= 0.25 then
			elapsed = 0
			self:_updateShopCardStates()
		end
	end)
end

function UIController:_refreshShopGrid()
	local screenGui = self._screens.ShopScreen
	if not screenGui then return end
	local mainFrame = screenGui:FindFirstChild("MainFrame")
	local innerPanel = mainFrame and mainFrame:FindFirstChild("InnerPanel")
	local scrollFrame = innerPanel and innerPanel:FindFirstChild("ShopGrid")
	if not scrollFrame then return end

	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	self._shopCards = {}

	for order, itemId in ipairs(ShopData.Order) do
		local item = ShopData.Items[itemId]
		if item then
			local color = shopColor(item.color)
			local accent = shopColor(item.accentColor)
			local card = Instance.new("Frame")
			card.Name = "ShopItem_" .. itemId
			card.BackgroundColor3 = Color3.fromRGB(
				math.floor(244 + color.R * 11),
				math.floor(244 + color.G * 11),
				math.floor(244 + color.B * 11)
			)
			card.BorderSizePixel = 0
			card.LayoutOrder = order
			card.Parent = scrollFrame
			addShopCorner(card, 18)
			local cardStroke = addShopStroke(card, color, 4)

			local topBand = Instance.new("Frame")
			topBand.Name = "TopBand"
			topBand.Size = UDim2.new(1, 0, 0, 12)
			topBand.BackgroundColor3 = color
			topBand.BorderSizePixel = 0
			topBand.Parent = card
			addShopCorner(topBand, 18)

			self:_createShopItemArt(card, item)

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Name = "ItemName"
			nameLabel.Size = UDim2.fromScale(0.62, 0.19)
			nameLabel.Position = UDim2.fromScale(0.34, 0.08)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = string.upper(item.displayName)
			nameLabel.TextColor3 = Color3.fromRGB(41, 54, 74)
			nameLabel.Font = Enum.Font.GothamBlack
			nameLabel.TextScaled = true
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.Parent = card

			local nameSize = Instance.new("UITextSizeConstraint")
			nameSize.MinTextSize = 12
			nameSize.MaxTextSize = 22
			nameSize.Parent = nameLabel

			local description = Instance.new("TextLabel")
			description.Name = "Description"
			description.Size = UDim2.fromScale(0.61, 0.25)
			description.Position = UDim2.fromScale(0.34, 0.27)
			description.BackgroundTransparency = 1
			description.Text = item.description
			description.TextColor3 = Color3.fromRGB(80, 91, 108)
			description.Font = Enum.Font.GothamMedium
			description.TextSize = 14
			description.TextWrapped = true
			description.TextXAlignment = Enum.TextXAlignment.Left
			description.TextYAlignment = Enum.TextYAlignment.Top
			description.Parent = card

			local statusLabel = Instance.new("TextLabel")
			statusLabel.Name = "Status"
			statusLabel.Size = UDim2.fromScale(0.61, 0.13)
			statusLabel.Position = UDim2.fromScale(0.34, 0.52)
			statusLabel.BackgroundColor3 = accent
			statusLabel.BackgroundTransparency = 0.12
			statusLabel.TextColor3 = Color3.fromRGB(55, 65, 75)
			statusLabel.Font = Enum.Font.GothamBold
			statusLabel.TextScaled = true
			statusLabel.Parent = card
			addShopCorner(statusLabel, 999)
			local statusSize = Instance.new("UITextSizeConstraint")
			statusSize.MinTextSize = 10
			statusSize.MaxTextSize = 15
			statusSize.Parent = statusLabel

			local buyBtn = Instance.new("TextButton")
			buyBtn.Name = "BuyBtn"
			buyBtn.Size = UDim2.fromScale(0.61, 0.22)
			buyBtn.Position = UDim2.fromScale(0.34, 0.71)
			buyBtn.BackgroundColor3 = color
			buyBtn.Text = "◆ " .. tostring(item.cost)
			buyBtn.TextColor3 = COLORS.White
			buyBtn.Font = Enum.Font.GothamBlack
			buyBtn.TextScaled = true
			buyBtn.AutoButtonColor = false
			buyBtn.Parent = card
			addShopCorner(buyBtn, 12)
			local buyStroke = addShopStroke(buyBtn, color:Lerp(Color3.new(0, 0, 0), 0.35), 3)
			local buySize = Instance.new("UITextSizeConstraint")
			buySize.MinTextSize = 13
			buySize.MaxTextSize = 21
			buySize.Parent = buyBtn

			buyBtn.Activated:Connect(function()
				self:_purchaseShopItem(itemId)
			end)

			self._shopCards[itemId] = {
				button = buyBtn,
				buttonStroke = buyStroke,
				cardStroke = cardStroke,
				status = statusLabel,
				color = color,
				accent = accent,
			}
		end
	end

	self:_updateShopCardStates()
end

function UIController:_updateShopCardStates()
	if self._shopDiamondLabel then
		self._shopDiamondLabel.Text = tostring(self._diamonds)
	end

	local now = os.clock()
	local purchases = self._shopState.purchases or {}
	local ownedSlots = tonumber(purchases.extraEquipSlots) or 0
	local maxSlots = tonumber(self._shopState.maxExtraEquipSlots)
		or ShopData.Items.ExtraEquipSlot.maxPurchases
		or 5

	for itemId, card in pairs(self._shopCards) do
		local item = ShopData.Items[itemId]
		if item and card.button and card.button.Parent then
			local isMaxed = item.permanent and ownedSlots >= maxSlots
			local isPurchasing = self._shopPurchaseInFlight ~= nil
			local isAffordable = self._diamonds >= item.cost
			local enabled = not isMaxed and not isPurchasing and isAffordable

			if item.permanent then
				if isMaxed then
					card.status.Text = "OWNED " .. tostring(ownedSlots) .. "/" .. tostring(maxSlots) .. " • MAXED"
					card.status.TextColor3 = Color3.fromRGB(115, 44, 81)
				else
					card.status.Text = "OWNED " .. tostring(ownedSlots) .. "/" .. tostring(maxSlots) .. " • PERMANENT"
					card.status.TextColor3 = Color3.fromRGB(88, 52, 78)
				end
			else
				local expiry = self._shopBuffExpiry[item.buffType]
				local remaining = expiry and math.max(0, expiry - now) or 0
				if remaining > 0 then
					card.status.Text = "ACTIVE • " .. formatShopTime(remaining)
					card.status.TextColor3 = Color3.fromRGB(20, 115, 48)
				else
					self._shopBuffExpiry[item.buffType] = nil
					self._shopState.buffs[item.buffType] = nil
					card.status.Text = item.durationLabel
					card.status.TextColor3 = Color3.fromRGB(55, 65, 75)
				end
			end

			if self._shopPurchaseInFlight == itemId then
				card.button.Text = "PURCHASING..."
			elseif isMaxed then
				card.button.Text = "MAXED"
			elseif not isAffordable then
				card.button.Text = "NEED ◆ " .. tostring(item.cost)
			else
				card.button.Text = "BUY • ◆ " .. tostring(item.cost)
			end

			card.button.Active = enabled
			card.button.Selectable = enabled
			if enabled then
				card.button.BackgroundColor3 = card.color
				card.button.TextColor3 = COLORS.White
				card.buttonStroke.Color = card.color:Lerp(Color3.new(0, 0, 0), 0.35)
				card.cardStroke.Transparency = 0
			else
				card.button.BackgroundColor3 = Color3.fromRGB(160, 166, 174)
				card.button.TextColor3 = Color3.fromRGB(235, 238, 240)
				card.buttonStroke.Color = Color3.fromRGB(112, 117, 124)
				card.cardStroke.Transparency = isMaxed and 0.45 or 0.2
			end
		end
	end
end

function UIController:_setShopFeedback(message, color)
	self._shopFeedbackToken += 1
	local token = self._shopFeedbackToken
	if self._shopFeedbackLabel then
		self._shopFeedbackLabel.Text = message or ""
		self._shopFeedbackLabel.TextColor3 = color or Color3.fromRGB(40, 145, 60)
	end
	if message and message ~= "" then
		task.delay(3, function()
			if token == self._shopFeedbackToken and self._shopFeedbackLabel then
				self._shopFeedbackLabel.Text = ""
			end
		end)
	end
end

function UIController:_applyShopState(payload)
	payload = type(payload) == "table" and payload or {}
	local isFullState = type(payload.buffs) == "table" or type(payload.purchases) == "table"
	local buffs = isFullState and (payload.buffs or {}) or payload
	-- Buff-only legacy payloads must not erase the persisted permanent purchase.
	local purchases = type(payload.purchases) == "table"
		and payload.purchases
		or (type(self._shopState.purchases) == "table" and self._shopState.purchases or {})
	local maxSlots = safeSlotBonus(payload.maxExtraEquipSlots)
	if maxSlots == 0 then
		maxSlots = ShopData.Items.ExtraEquipSlot.maxPurchases or 5
	end
	local ownedSlots = math.clamp(safeSlotBonus(purchases.extraEquipSlots), 0, maxSlots)

	local normalizedBuffs = {}
	local now = os.clock()
	for _, itemId in ipairs(ShopData.Order) do
		local item = ShopData.Items[itemId]
		if item and not item.permanent and item.buffType then
			local remaining = math.max(0, tonumber(buffs[item.buffType]) or 0)
			if remaining > 0 then
				normalizedBuffs[item.buffType] = remaining
				self._shopBuffExpiry[item.buffType] = now + remaining
			else
				self._shopBuffExpiry[item.buffType] = nil
			end
		end
	end

	self._shopBuffs = normalizedBuffs
	self._shopState = {
		buffs = normalizedBuffs,
		purchases = { extraEquipSlots = ownedSlots },
		maxExtraEquipSlots = maxSlots,
	}
	self:_updateShopCardStates()
	self:_refreshCapacityUI()
end

function UIController:_refreshShopStateFromServer()
	if not self._remotes then return end
	local remote = self._remotes:FindFirstChild("GetShopBuffs")
	if not remote then return end
	task.spawn(function()
		local ok, state = pcall(function()
			return remote:InvokeServer()
		end)
		if ok and state then
			self:_applyShopState(state)
		elseif not ok then
			self:_setShopFeedback("Could not load shop: " .. tostring(state), COLORS.ButtonRed)
		end
	end)
end

function UIController:_purchaseShopItem(itemId)
	local item = ShopData.Items[itemId]
	if not item or self._shopPurchaseInFlight then return end
	if self._diamonds < item.cost then
		self:_setShopFeedback("You need more diamonds!", COLORS.ButtonRed)
		return
	end
	if item.permanent then
		local owned = tonumber(self._shopState.purchases.extraEquipSlots) or 0
		if owned >= (tonumber(self._shopState.maxExtraEquipSlots) or item.maxPurchases or 5) then
			self:_setShopFeedback("Extra Equip Slot is already maxed!", COLORS.ButtonRed)
			return
		end
	end
	if not self._remotes then return end
	local remote = self._remotes:FindFirstChild("PurchaseShopItem")
	if not remote then
		self:_setShopFeedback("Shop is unavailable right now.", COLORS.ButtonRed)
		return
	end

	self._shopPurchaseInFlight = itemId
	self:_updateShopCardStates()
	task.spawn(function()
		local ok, success, err, state = pcall(function()
			return remote:InvokeServer(itemId)
		end)
		self._shopPurchaseInFlight = nil
		if not ok then
			self:_setShopFeedback("Purchase failed: " .. tostring(success), COLORS.ButtonRed)
		elseif success then
			if state then
				self:_applyShopState(state)
			else
				-- Stay display-only: fetch the committed value instead of inventing
				-- an optimistic permanent slot on the client.
				self:_refreshShopStateFromServer()
			end
			self:_refreshCapacityUI()
			self:_setShopFeedback(item.displayName .. " purchased!", Color3.fromRGB(35, 160, 62))
		else
			self:_setShopFeedback(tostring(err or "Purchase failed."), COLORS.ButtonRed)
		end
		self:_updateShopCardStates()
	end)
end

function UIController:updateShopBuffs(state)
	self:_applyShopState(state)
end

--------------------------------------------------------------------------------
-- PET INDEX (Collection Book) - Shows all pets in all variants
--------------------------------------------------------------------------------
function UIController:_createPetIndex()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PetIndex"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = false
	screenGui.Parent = self._playerGui
	self._screens.PetIndex = screenGui

	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.fromScale(0.8, 0.75)
	mainFrame.Position = UDim2.fromScale(0.1, 0.125)
	mainFrame.BackgroundColor3 = COLORS.Background
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = screenGui

	local mainCorner = Instance.new("UICorner")
	mainCorner.CornerRadius = UDim.new(0, 16)
	mainCorner.Parent = mainFrame

	local mainStroke = Instance.new("UIStroke")
	mainStroke.Thickness = 4
	mainStroke.Color = Color3.fromRGB(255, 100, 180)
	mainStroke.Parent = mainFrame

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(0.4, 0.08)
	title.Position = UDim2.fromScale(0.3, 0.01)
	title.BackgroundTransparency = 1
	title.Text = "PET INDEX"
	title.TextColor3 = Color3.fromRGB(255, 100, 180)
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.Parent = mainFrame

	-- Progress counter
	local progressLabel = Instance.new("TextLabel")
	progressLabel.Name = "ProgressLabel"
	progressLabel.Size = UDim2.fromScale(0.4, 0.05)
	progressLabel.Position = UDim2.fromScale(0.3, 0.09)
	progressLabel.BackgroundTransparency = 1
	progressLabel.Text = "0/16 Discovered"
	progressLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
	progressLabel.Font = Enum.Font.GothamBold
	progressLabel.TextScaled = true
	progressLabel.Parent = mainFrame

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.fromOffset(40, 40)
	closeBtn.Position = UDim2.new(1, -50, 0, 10)
	closeBtn.BackgroundColor3 = COLORS.CloseRed
	closeBtn.Text = "X"
	closeBtn.TextColor3 = COLORS.White
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 22
	closeBtn.Parent = mainFrame

	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(1, 0)
	closeBtnCorner.Parent = closeBtn

	closeBtn.MouseButton1Click:Connect(function()
		self:toggleScreen("PetIndex")
	end)

	-- Scrolling grid for pet entries
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "IndexGrid"
	scrollFrame.Size = UDim2.fromScale(0.94, 0.78)
	scrollFrame.Position = UDim2.fromScale(0.03, 0.16)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.ScrollBarThickness = 6
	scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(255, 100, 180)
	scrollFrame.CanvasSize = UDim2.fromScale(0, 0)
	scrollFrame.Parent = mainFrame

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.Name = "GridLayout"
	gridLayout.CellSize = UDim2.fromOffset(140, 160)
	gridLayout.CellPadding = UDim2.fromOffset(10, 10)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = scrollFrame

	gridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		scrollFrame.CanvasSize = UDim2.fromOffset(0, gridLayout.AbsoluteContentSize.Y + 20)
	end)

	self:_refreshPetIndex()
end

function UIController:_refreshPetIndex()
	local screenGui = self._screens.PetIndex
	if not screenGui then return end
	local mainFrame = screenGui:FindFirstChild("MainFrame")
	if not mainFrame then return end
	local scrollFrame = mainFrame:FindFirstChild("IndexGrid")
	if not scrollFrame then return end

	-- Clear existing cards
	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local discoveredPets = self._discoveredPets or {}
	local variants = PetData.Variants or {"Normal", "Golden", "Shiny", "Rainbow"}

	-- Derive pet list from PetData.Pets keys (sorted alphabetically)
	local petIds = {}
	for petId, _ in pairs(PetData.Pets) do
		table.insert(petIds, petId)
	end
	table.sort(petIds)

	-- Variant colors for display
	local variantColors = {
		Normal = Color3.fromRGB(200, 200, 200),
		Golden = Color3.fromRGB(255, 200, 0),
		Shiny = Color3.fromRGB(0, 220, 255),
		Rainbow = Color3.fromRGB(255, 100, 200),
	}

	local discoveredCount = 0
	local totalCount = #petIds * #variants
	local order = 0

	for _, petId in ipairs(petIds) do
		local petDef = PetData.Pets[petId]
		if not petDef then continue end

		for _, variant in ipairs(variants) do
			order = order + 1

			-- Build discovery key
			local discoveryKey
			if variant == "Normal" then
				discoveryKey = petId
			else
				discoveryKey = variant .. "_" .. petId
			end

			local isDiscovered = discoveredPets[discoveryKey] == true
			if isDiscovered then
				discoveredCount = discoveredCount + 1
			end

			local variantColor = variantColors[variant] or Color3.fromRGB(200, 200, 200)
			local rarityColor = RARITY_COLORS[petDef.rarity or "Common"] or RARITY_COLORS.Common

			local card = Instance.new("Frame")
			card.Name = "IndexCard_" .. petId .. "_" .. variant
			card.BackgroundColor3 = isDiscovered and COLORS.DarkBg or Color3.fromRGB(15, 18, 35)
			card.LayoutOrder = order
			card.Parent = scrollFrame

			local cardCorner = Instance.new("UICorner")
			cardCorner.CornerRadius = UDim.new(0, 12)
			cardCorner.Parent = card

			local cardStroke = Instance.new("UIStroke")
			cardStroke.Thickness = 3
			cardStroke.Color = isDiscovered and variantColor or Color3.fromRGB(40, 40, 60)
			cardStroke.Parent = card

			-- Pet icon (circle)
			local petIcon = Instance.new("Frame")
			petIcon.Name = "PetIcon"
			petIcon.Size = UDim2.fromScale(0.45, 0.35)
			petIcon.Position = UDim2.fromScale(0.275, 0.05)
			petIcon.BackgroundColor3 = isDiscovered and variantColor or Color3.fromRGB(30, 30, 45)
			petIcon.Parent = card

			local iconCorner = Instance.new("UICorner")
			iconCorner.CornerRadius = UDim.new(1, 0)
			iconCorner.Parent = petIcon

			-- Question mark or pet initial inside the circle
			local iconText = Instance.new("TextLabel")
			iconText.Size = UDim2.fromScale(1, 1)
			iconText.BackgroundTransparency = 1
			iconText.Text = isDiscovered and string.sub(petDef.name, 1, 1) or "?"
			iconText.TextColor3 = isDiscovered and COLORS.White or Color3.fromRGB(60, 60, 80)
			iconText.Font = Enum.Font.GothamBold
			iconText.TextScaled = true
			iconText.Parent = petIcon

			-- Pet name
			local nameLabel = Instance.new("TextLabel")
			nameLabel.Name = "PetName"
			nameLabel.Size = UDim2.fromScale(0.9, 0.14)
			nameLabel.Position = UDim2.fromScale(0.05, 0.44)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = isDiscovered and petDef.name or "???"
			nameLabel.TextColor3 = isDiscovered and COLORS.White or Color3.fromRGB(60, 60, 80)
			nameLabel.Font = Enum.Font.GothamBold
			nameLabel.TextScaled = true
			nameLabel.Parent = card

			-- Variant label
			local variantLabel = Instance.new("TextLabel")
			variantLabel.Name = "VariantLabel"
			variantLabel.Size = UDim2.fromScale(0.9, 0.12)
			variantLabel.Position = UDim2.fromScale(0.05, 0.6)
			variantLabel.BackgroundTransparency = 1
			variantLabel.Text = variant
			variantLabel.TextColor3 = isDiscovered and variantColor or Color3.fromRGB(50, 50, 70)
			variantLabel.Font = Enum.Font.GothamBold
			variantLabel.TextScaled = true
			variantLabel.Parent = card

			-- Rarity label
			local rarityLabel = Instance.new("TextLabel")
			rarityLabel.Name = "RarityLabel"
			rarityLabel.Size = UDim2.fromScale(0.9, 0.1)
			rarityLabel.Position = UDim2.fromScale(0.05, 0.74)
			rarityLabel.BackgroundTransparency = 1
			rarityLabel.Text = isDiscovered and (petDef.rarity or "Common") or "---"
			rarityLabel.TextColor3 = isDiscovered and rarityColor or Color3.fromRGB(50, 50, 70)
			rarityLabel.Font = Enum.Font.Gotham
			rarityLabel.TextScaled = true
			rarityLabel.Parent = card

			-- Discovered check mark, "Coming Soon", or lock
			local statusLabel = Instance.new("TextLabel")
			statusLabel.Name = "Status"
			statusLabel.Size = UDim2.fromScale(0.3, 0.12)
			statusLabel.Position = UDim2.fromScale(0.65, 0.85)
			statusLabel.BackgroundTransparency = 1
			if isDiscovered then
				statusLabel.Text = "OK"
				statusLabel.TextColor3 = Color3.fromRGB(0, 200, 80)
			else
				statusLabel.Text = "X"
				statusLabel.TextColor3 = Color3.fromRGB(100, 40, 40)
			end
			statusLabel.Font = Enum.Font.GothamBold
			statusLabel.TextScaled = true
			statusLabel.Parent = card
		end
	end

	-- Update progress counter
	local progressLabel = mainFrame:FindFirstChild("ProgressLabel")
	if progressLabel then
		progressLabel.Text = tostring(discoveredCount) .. "/" .. tostring(totalCount) .. " Discovered"
	end
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function UIController:updateCurrency(coins, diamonds)
	self._coins = tonumber(coins) or 0
	self._diamonds = tonumber(diamonds) or 0
	if self._coinLabel then
		self._coinLabel.Text = tostring(self._coins)
	end
	if self._diamondLabel then
		self._diamondLabel.Text = tostring(self._diamonds)
	end
	if self._shopDiamondLabel then
		self._shopDiamondLabel.Text = tostring(self._diamonds)
	end
	self:_updateShopCardStates()
	self:_updateEggShortfall()
	self:_updateZoneProgress()
end

function UIController:updatePetInventory(pets)
	self._petInventoryData = type(pets) == "table" and pets or {}

	-- Drop stale or newly protected selections while preserving valid selections
	-- across sorting and filtering refreshes.
	local selectableIds = {}
	for _, petData in ipairs(self._petInventoryData) do
		local id = petData.uniqueId or petData.id
		if id and petData.favorite ~= true then
			selectableIds[id] = true
		end
	end
	for id in pairs(self._selectedPets) do
		if not selectableIds[id] then
			self._selectedPets[id] = nil
		end
	end

	self:_updateInventoryTitle()
	self:_refreshPetGrid()
end

function UIController:updateEquippedPets(equippedPets)
	self._equippedPets = type(equippedPets) == "table" and equippedPets or {}
	-- Also update the equipped boolean on inventory data to keep in sync
	local equippedIdSet = {}
	for _, pet in ipairs(self._equippedPets) do
		if type(pet) == "string" then
			equippedIdSet[pet] = true
		elseif type(pet) == "table" then
			local id = pet.uniqueId or pet.id
			if id then
				equippedIdSet[id] = true
			end
		end
	end
	for _, petData in ipairs(self._petInventoryData) do
		local id = petData.uniqueId or petData.id
		if id then
			petData.equipped = equippedIdSet[id] or false
		end
	end
	self:_refreshCapacityUI()
	self:_refreshPetGrid()
end

function UIController:updateUpgrades(upgrades)
	self._upgradeData = sanitizeDefinedLevels(upgrades, QuestData.Quests, "levels")
	self:_refreshCapacityUI()
	self:_refreshQuestGrid()
end

function UIController:updateQuestProgress(questProgress)
	self._questProgress = type(questProgress) == "table" and questProgress or {}
	self:_refreshQuestGrid()
end

function UIController:updateMastery(masteryState)
	masteryState = type(masteryState) == "table" and masteryState or {}
	self._masteryState = {
		masteryPoints = tonumber(masteryState.masteryPoints) or 0,
		level = tonumber(masteryState.level) or 1,
		buffs = sanitizeDefinedLevels(masteryState.buffs, MasteryData.Buffs, "bonusPerLevel"),
	}
	self:_refreshCapacityUI()
	self:_refreshMasteryGrid()
end

-- QOF-10 display-only entitlement snapshot. Server services remain authoritative.
function UIController:updateUpgradeTree(state)
	local entitlements = type(state) == "table" and state.entitlements or nil
	self._treeEntitlements = {
		storageBonusSlots = safeSlotBonus(
			type(entitlements) == "table" and entitlements.storageBonusSlots or nil
		),
		petEquipBonusSlots = safeSlotBonus(
			type(entitlements) == "table" and entitlements.petEquipBonusSlots or nil
		),
	}
	self:_refreshCapacityUI()
end

--------------------------------------------------------------------------------
-- NEW PET DISCOVERY TOASTS
--------------------------------------------------------------------------------
function UIController:enqueueDiscoveryToast(petData)
	if not self._playerGui or type(petData) ~= "table" then return end

	local presentation = PetVariantPresentation.resolve(petData)
	table.insert(self._discoveryToastQueue, {
		name = presentation.displayPetName,
		rarity = petData.rarity or "Common",
		variantLabel = presentation.variantLabel,
		baseVariant = presentation.baseVariant,
		isShiny = presentation.isShiny,
		accentRGB = presentation.accentRGB,
		shinyRGB = presentation.shinyRGB,
	})
	self:_showNextDiscoveryToast()
end

function UIController:_showNextDiscoveryToast()
	if self._discoveryToastActive or not self._playerGui then return end

	local petData = table.remove(self._discoveryToastQueue, 1)
	if not petData then return end
	self._discoveryToastActive = true

	local rarityColor = RARITY_COLORS[petData.rarity] or RARITY_COLORS.Common
	local baseAccent = petData.baseVariant == "Normal" and rarityColor or rgbToColor(petData.accentRGB)
	local shinyAccent = rgbToColor(petData.shinyRGB)

	local toast = Instance.new("ScreenGui")
	toast.Name = "DiscoveryToast"
	toast.ResetOnSpawn = false
	toast.DisplayOrder = 100
	toast.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	toast.Parent = self._playerGui
	self._activeDiscoveryToast = toast

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.fromScale(0.38, 0.11)
	card.Position = UDim2.fromScale(0.31, -0.13)
	card.BackgroundColor3 = COLORS.DarkBg
	card.BackgroundTransparency = 0.08
	card.BorderSizePixel = 0
	card.Parent = toast

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 14)
	cardCorner.Parent = card

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Thickness = 3
	cardStroke.Color = petData.isShiny and shinyAccent or baseAccent
	cardStroke.Parent = card

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(0.68, 0.35)
	title.Position = UDim2.fromScale(0.05, 0.08)
	title.BackgroundTransparency = 1
	title.Text = "NEW PET DISCOVERED!"
	title.TextColor3 = COLORS.CoinYellow
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = card

	local petName = Instance.new("TextLabel")
	petName.Name = "PetName"
	petName.Size = UDim2.fromScale(0.68, 0.38)
	petName.Position = UDim2.fromScale(0.05, 0.5)
	petName.BackgroundTransparency = 1
	petName.Text = petData.name
	petName.TextColor3 = baseAccent
	petName.Font = Enum.Font.GothamBold
	petName.TextScaled = true
	petName.TextXAlignment = Enum.TextXAlignment.Left
	petName.Parent = card

	local variantBadge = Instance.new("TextLabel")
	variantBadge.Name = "VariantBadge"
	variantBadge.Size = UDim2.fromScale(0.22, 0.42)
	variantBadge.Position = UDim2.fromScale(0.74, 0.29)
	variantBadge.BackgroundColor3 = baseAccent
	variantBadge.BorderSizePixel = 0
	variantBadge.Text = string.upper(petData.variantLabel)
	variantBadge.TextColor3 = COLORS.DarkBg
	variantBadge.Font = Enum.Font.GothamBold
	variantBadge.TextScaled = true
	variantBadge.Parent = card

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 9)
	badgeCorner.Parent = variantBadge

	if petData.isShiny then
		local badgeStroke = Instance.new("UIStroke")
		badgeStroke.Thickness = 2
		badgeStroke.Color = shinyAccent
		badgeStroke.Parent = variantBadge
	end

	local badgePadding = Instance.new("UIPadding")
	badgePadding.PaddingLeft = UDim.new(0, 5)
	badgePadding.PaddingRight = UDim.new(0, 5)
	badgePadding.Parent = variantBadge

	TweenService:Create(card, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0.31, 0.05),
	}):Play()

	-- Keep exactly one discovery toast visible at a time, then advance the queue.
	task.delay(2.75, function()
		if self._activeDiscoveryToast ~= toast then return end
		if not toast.Parent or not card.Parent then
			self._activeDiscoveryToast = nil
			self._discoveryToastActive = false
			self:_showNextDiscoveryToast()
			return
		end

		local hideTween = TweenService:Create(card, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.fromScale(0.31, -0.13),
		})
		hideTween.Completed:Connect(function()
			if self._activeDiscoveryToast ~= toast then return end
			toast:Destroy()
			self._activeDiscoveryToast = nil
			self._discoveryToastActive = false
			self:_showNextDiscoveryToast()
		end)
		hideTween:Play()
	end)
end

function UIController:_showHatchToast(petData)
	if not self._playerGui then return end

	local toast = Instance.new("ScreenGui")
	toast.Name = "HatchToast"
	toast.ResetOnSpawn = false
	toast.Parent = self._playerGui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.3, 0.06)
	label.Position = UDim2.fromScale(0.35, 0.82)
	label.BackgroundColor3 = COLORS.DarkBg
	label.BackgroundTransparency = 0.15
	label.BorderSizePixel = 0
	label.Parent = toast

	local labelCorner = Instance.new("UICorner")
	labelCorner.CornerRadius = UDim.new(0, 10)
	labelCorner.Parent = label

	local labelStroke = Instance.new("UIStroke")
	labelStroke.Thickness = 2
	labelStroke.Color = RARITY_COLORS[petData and petData.rarity or "Common"] or RARITY_COLORS.Common
	labelStroke.Parent = label

	local presentation = PetVariantPresentation.resolve(petData)
	label.Text = "Hatched: " .. presentation.displayPetName .. " • " .. presentation.variantLabel
	label.TextColor3 = COLORS.White
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true

	-- Fade out and destroy after 2.5 seconds
	task.delay(2.5, function()
		if toast and toast.Parent then
			toast:Destroy()
		end
	end)
end

function UIController:showEggHatch(petData, isNewDiscovery)
	if not self._playerGui then return end
	local presentation = PetVariantPresentation.resolve(petData)
	local rarityColor = RARITY_COLORS[petData and petData.rarity or "Common"] or RARITY_COLORS.Common
	local baseAccent = presentation.baseVariant == "Normal" and rarityColor or rgbToColor(presentation.accentRGB)
	local shinyAccent = rgbToColor(presentation.shinyRGB)

	-- If not a new discovery, show a brief toast confirming the hatch
	if not isNewDiscovery then
		self:_showHatchToast(petData)
		return
	end

	local overlay = Instance.new("ScreenGui")
	overlay.Name = "EggHatchOverlay"
	overlay.ResetOnSpawn = false
	overlay.Parent = self._playerGui

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	bg.BackgroundTransparency = 0.6
	bg.BorderSizePixel = 0
	bg.Parent = overlay

	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromScale(0.4, 0.5)
	panel.Position = UDim2.fromScale(0.3, 0.25)
	panel.BackgroundColor3 = COLORS.Background
	panel.Parent = bg

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 16)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Thickness = 4
	panelStroke.Color = presentation.isShiny and shinyAccent or baseAccent
	panelStroke.Parent = panel

	local newPetText = Instance.new("TextLabel")
	newPetText.Size = UDim2.fromScale(0.8, 0.15)
	newPetText.Position = UDim2.fromScale(0.1, 0.05)
	newPetText.BackgroundTransparency = 1
	newPetText.Text = "NEW PET!"
	newPetText.TextColor3 = COLORS.CoinYellow
	newPetText.Font = Enum.Font.GothamBold
	newPetText.TextScaled = true
	newPetText.Parent = panel

	local petIcon = Instance.new("Frame")
	petIcon.Size = UDim2.fromScale(0.35, 0.35)
	petIcon.Position = UDim2.fromScale(0.325, 0.22)
	petIcon.BackgroundColor3 = baseAccent
	petIcon.Parent = panel

	if presentation.baseVariant == "Rainbow" then
		local rainbowGradient = Instance.new("UIGradient")
		rainbowGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 120)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 225, 80)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(70, 220, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(210, 90, 255)),
		})
		rainbowGradient.Parent = petIcon
	end

	local petIconCorner = Instance.new("UICorner")
	petIconCorner.CornerRadius = UDim.new(1, 0)
	petIconCorner.Parent = petIcon

	local petName = Instance.new("TextLabel")
	petName.Size = UDim2.fromScale(0.8, 0.12)
	petName.Position = UDim2.fromScale(0.1, 0.6)
	petName.BackgroundTransparency = 1
	petName.Text = presentation.displayPetName
	petName.TextColor3 = baseAccent
	petName.Font = Enum.Font.GothamBold
	petName.TextScaled = true
	petName.Parent = panel

	local rarityText = Instance.new("TextLabel")
	rarityText.Size = UDim2.fromScale(0.8, 0.08)
	rarityText.Position = UDim2.fromScale(0.1, 0.73)
	rarityText.BackgroundTransparency = 1
	rarityText.Text = presentation.variantLabel .. " • " .. (petData and petData.rarity or "Common")
	rarityText.TextColor3 = presentation.isShiny and shinyAccent or baseAccent
	rarityText.Font = Enum.Font.GothamBold
	rarityText.TextScaled = true
	rarityText.Parent = panel

	local okBtn = Instance.new("TextButton")
	okBtn.Size = UDim2.fromScale(0.4, 0.12)
	okBtn.Position = UDim2.fromScale(0.3, 0.84)
	okBtn.BackgroundColor3 = COLORS.ButtonGreen
	okBtn.Text = "OK!"
	okBtn.TextColor3 = COLORS.White
	okBtn.Font = Enum.Font.GothamBold
	okBtn.TextScaled = true
	okBtn.Parent = panel

	local okCorner = Instance.new("UICorner")
	okCorner.CornerRadius = UDim.new(0, 10)
	okCorner.Parent = okBtn

	okBtn.MouseButton1Click:Connect(function()
		overlay:Destroy()
	end)

	task.delay(5, function()
		if overlay and overlay.Parent then
			overlay:Destroy()
		end
	end)
end

function UIController:showEggBatch(pets)
	if not self._playerGui or type(pets) ~= "table" or #pets == 0 then return end
	if self._hatchBatchLayoutConnection then
		self._hatchBatchLayoutConnection:Disconnect()
		self._hatchBatchLayoutConnection = nil
	end
	if self._activeHatchBatchOverlay and self._activeHatchBatchOverlay.Parent then
		self._activeHatchBatchOverlay:Destroy()
	end

	local overlay = Instance.new("ScreenGui")
	overlay.Name = "EggBatchResults"
	overlay.ResetOnSpawn = false
	overlay.IgnoreGuiInset = false
	overlay.DisplayOrder = 45
	overlay.Parent = self._playerGui
	self._activeHatchBatchOverlay = overlay

	local shade = Instance.new("Frame")
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	shade.BackgroundTransparency = 0.42
	shade.BorderSizePixel = 0
	shade.Parent = overlay

	local panel = Instance.new("Frame")
	panel.Name = "ResultsPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.82, 0.76)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = COLORS.Background
	panel.BorderSizePixel = 0
	panel.Parent = shade
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(280, 320)
	constraint.MaxSize = Vector2.new(920, 660)
	constraint.Parent = panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = COLORS.DiamondCyan
	stroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -100, 0, 52)
	title.Position = UDim2.fromOffset(18, 8)
	title.BackgroundTransparency = 1
	title.Text = tostring(#pets) .. " PET" .. (#pets == 1 and "" or "S") .. " HATCHED!"
	title.TextColor3 = COLORS.CoinYellow
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.Parent = panel

	local close = Instance.new("TextButton")
	close.Size = UDim2.fromOffset(58, 46)
	close.Position = UDim2.new(1, -70, 0, 10)
	close.BackgroundColor3 = COLORS.CloseRed
	close.Text = "X"
	close.TextColor3 = COLORS.White
	close.Font = Enum.Font.GothamBold
	close.TextScaled = true
	close.Parent = panel
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 12)
	closeCorner.Parent = close

	local grid = Instance.new("ScrollingFrame")
	grid.Name = "PetGrid"
	grid.Size = UDim2.new(1, -28, 1, -82)
	grid.Position = UDim2.fromOffset(14, 68)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 8
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.fromOffset(0, 0)
	grid.Parent = panel

	local layout = Instance.new("UIGridLayout")
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	local function refreshGridLayout()
		local panelWidth = panel.AbsoluteSize.X
		if panelWidth <= 0 then return end
		local columns = panelWidth < 620 and 2 or 5
		layout.CellSize = UDim2.new(1 / columns, -10, 0, 136)
	end
	local layoutConnection = panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(refreshGridLayout)
	self._hatchBatchLayoutConnection = layoutConnection
	task.defer(refreshGridLayout)

	for index, petData in ipairs(pets) do
		local presentation = PetVariantPresentation.resolve(petData)
		local rarityColor = RARITY_COLORS[petData.rarity or "Common"] or RARITY_COLORS.Common
		local accent = presentation.baseVariant == "Normal" and rarityColor or rgbToColor(presentation.accentRGB)
		local card = Instance.new("Frame")
		card.Name = "Result" .. tostring(index)
		card.LayoutOrder = index
		card.BackgroundColor3 = COLORS.DarkBg
		card.BorderSizePixel = 0
		card.Parent = grid
		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 12)
		cardCorner.Parent = card
		local cardStroke = Instance.new("UIStroke")
		cardStroke.Thickness = petData.isNewDiscovery and 4 or 2
		cardStroke.Color = petData.isNewDiscovery and COLORS.CoinYellow or accent
		cardStroke.Parent = card

		local orb = Instance.new("Frame")
		orb.AnchorPoint = Vector2.new(0.5, 0)
		orb.Size = UDim2.fromOffset(52, 52)
		orb.Position = UDim2.new(0.5, 0, 0, 8)
		orb.BackgroundColor3 = accent
		orb.Parent = card
		local orbCorner = Instance.new("UICorner")
		orbCorner.CornerRadius = UDim.new(1, 0)
		orbCorner.Parent = orb

		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(1, -10, 0, 34)
		name.Position = UDim2.fromOffset(5, 64)
		name.BackgroundTransparency = 1
		name.Text = presentation.displayPetName
		name.TextColor3 = accent
		name.Font = Enum.Font.GothamBold
		name.TextScaled = true
		name.TextWrapped = true
		name.Parent = card

		local detail = Instance.new("TextLabel")
		detail.Size = UDim2.new(1, -8, 0, 26)
		detail.Position = UDim2.fromOffset(4, 101)
		detail.BackgroundTransparency = 1
		detail.Text = presentation.variantLabel .. " • " .. tostring(petData.rarity or "Common")
		detail.TextColor3 = COLORS.White
		detail.Font = Enum.Font.GothamBold
		detail.TextScaled = true
		detail.TextWrapped = true
		detail.Parent = card
	end

	local function dismiss()
		if layoutConnection.Connected then
			layoutConnection:Disconnect()
		end
		if self._hatchBatchLayoutConnection == layoutConnection then
			self._hatchBatchLayoutConnection = nil
		end
		if overlay and overlay.Parent then
			overlay:Destroy()
		end
		if self._activeHatchBatchOverlay == overlay then
			self._activeHatchBatchOverlay = nil
		end
	end
	close.MouseButton1Click:Connect(dismiss)
	task.delay(15, dismiss)
end

function UIController:_refreshScreenData(screenName)
	if not self._remotes then return end
	if screenName == "QuestWindow" then
		local remote = self._remotes:FindFirstChild("GetQuestProgress")
		if remote then
			task.spawn(function()
				local progress = remote:InvokeServer()
				if progress then
					self._questProgress = progress
					self:_refreshQuestGrid()
				end
			end)
		end
	elseif screenName == "MasteryWindow" then
		local remote = self._remotes:FindFirstChild("GetMasteryState")
		if remote then
			task.spawn(function()
				local state = remote:InvokeServer()
				if state then
					self:updateMastery(state)
				end
			end)
		end
	elseif screenName == "PetIndex" then
		local remote = self._remotes:FindFirstChild("GetDiscoveredPets")
		if remote then
			task.spawn(function()
				local discovered = remote:InvokeServer()
				if discovered then
					self._discoveredPets = discovered
					self:_refreshPetIndex()
				end
			end)
		end
	elseif screenName == "ShopScreen" then
		self:_refreshShopStateFromServer()
	end
end

function UIController:openScreen(screenName)
	-- Navigation always dismisses a pending manual hatch flow and invalidates its
	-- async request through Main's registered cancel callback.
	self:_requestHatchPurchaseCancel()
	local screen = self._screens[screenName]
	if not screen then return end

	local currentState = self._screenStates[screenName]
	-- Opening an already-visible, non-closing screen is idempotent. The shop may
	-- still refresh its state, but repeated prompt triggers never close it.
	if screen.Enabled and currentState ~= "closing" then
		if screenName == "ShopScreen" then
			self:_refreshScreenData(screenName)
		end
		return
	end

	for name, otherScreen in pairs(self._screens) do
		if name ~= screenName and name ~= "MainHUD" then
			self._screenAnimationTokens[name] = (self._screenAnimationTokens[name] or 0) + 1
			self._screenStates[name] = "closed"
			otherScreen.Enabled = false
			local otherFrame = otherScreen:FindFirstChild("MainFrame") or otherScreen:FindFirstChild("EggPrompt")
			local otherRestingPosition = self._screenRestingPositions[name]
			if otherFrame and otherRestingPosition then
				otherFrame.Position = otherRestingPosition
			end
		end
	end

	local mainFrame = screen:FindFirstChild("MainFrame") or screen:FindFirstChild("EggPrompt")
	if mainFrame and not self._screenRestingPositions[screenName] then
		self._screenRestingPositions[screenName] = mainFrame.Position
	end
	local targetPos = self._screenRestingPositions[screenName]
	local token = (self._screenAnimationTokens[screenName] or 0) + 1
	self._screenAnimationTokens[screenName] = token
	self._screenStates[screenName] = "opening"
	screen.Enabled = true

	if mainFrame and targetPos then
		-- A fresh open starts below the viewport; reopening during a close starts
		-- from the tween's current position and cancels the pending disable token.
		if currentState ~= "closing" then
			mainFrame.Position = UDim2.new(targetPos.X.Scale, targetPos.X.Offset, 1.2, 0)
		end
		TweenService:Create(mainFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = targetPos,
		}):Play()
	end
	task.delay(0.3, function()
		if self._screenAnimationTokens[screenName] == token and screen.Parent then
			self._screenStates[screenName] = "open"
			if mainFrame and targetPos then
				mainFrame.Position = targetPos
			end
		end
	end)
	self:_refreshScreenData(screenName)
end

function UIController:closeScreen(screenName)
	self:_requestHatchPurchaseCancel()
	local screen = self._screens[screenName]
	if not screen or not screen.Enabled or self._screenStates[screenName] == "closing" then return end

	local mainFrame = screen:FindFirstChild("MainFrame") or screen:FindFirstChild("EggPrompt")
	if mainFrame and not self._screenRestingPositions[screenName] then
		self._screenRestingPositions[screenName] = mainFrame.Position
	end
	local targetPos = self._screenRestingPositions[screenName]
	local token = (self._screenAnimationTokens[screenName] or 0) + 1
	self._screenAnimationTokens[screenName] = token
	self._screenStates[screenName] = "closing"

	if not mainFrame or not targetPos then
		screen.Enabled = false
		self._screenStates[screenName] = "closed"
		return
	end

	TweenService:Create(mainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.new(targetPos.X.Scale, targetPos.X.Offset, 1.2, 0),
	}):Play()
	task.delay(0.25, function()
		if self._screenAnimationTokens[screenName] == token and screen.Parent then
			screen.Enabled = false
			mainFrame.Position = targetPos
			self._screenStates[screenName] = "closed"
		end
	end)
end

function UIController:toggleScreen(screenName)
	self:_requestHatchPurchaseCancel()
	local screen = self._screens[screenName]
	if not screen then return end
	if screen.Enabled then
		self:closeScreen(screenName)
	else
		self:openScreen(screenName)
	end
end

function UIController:updateXP(level, xp, xpNeeded)
	if self._xpFill then
		local fillFraction = math.clamp(xp / math.max(xpNeeded, 1), 0, 1)
		TweenService:Create(self._xpFill, TweenInfo.new(0.3), {
			Size = UDim2.fromScale(fillFraction * 0.96, 0.7),
		}):Play()
	end
	if self._xpLevelLabel then
		self._xpLevelLabel.Text = "Lv. " .. tostring(level)
	end
end

function UIController:cleanup()
	self:_requestHatchPurchaseCancel()
	self:closeHatchPurchaseDialog()
	for _, connection in ipairs(self._hatchPurchaseConnections) do
		connection:Disconnect()
	end
	self._hatchPurchaseConnections = {}
	self._hatchPurchaseCallbacks = {}
	if self._hatchPurchaseGui then
		self._hatchPurchaseGui:Destroy()
		self._hatchPurchaseGui = nil
	end
	self._hatchPurchasePanel = nil
	self._hatchPurchaseTitle = nil
	self._hatchPurchaseUnitPrice = nil
	self._hatchPurchaseFeedback = nil
	self._hatchPurchaseRefreshButton = nil
	self._hatchPurchaseOptionButtons = {}
	self._activeHatchPurchaseEggType = nil
	if self._shopTimerConnection then
		self._shopTimerConnection:Disconnect()
		self._shopTimerConnection = nil
	end
	for _, connection in ipairs(self._shopConnections) do
		connection:Disconnect()
	end
	self._shopConnections = {}
	self._shopCards = {}
	self._shopDiamondLabel = nil
	self._shopFeedbackLabel = nil
	self._screenAnimationTokens = {}
	self._screenStates = {}
	self._screenRestingPositions = {}
	for _, screen in pairs(self._screens) do
		screen:Destroy()
	end
	self._screens = {}
	self._discoveryToastQueue = {}
	if self._activeDiscoveryToast then
		self._activeDiscoveryToast:Destroy()
	end
	self._activeDiscoveryToast = nil
	self._discoveryToastActive = false
	if self._onboardingArrow then
		self._onboardingArrow:Destroy()
	end
	self._onboardingCard = nil
	self._onboardingTitle = nil
	self._onboardingText = nil
	self._onboardingArrow = nil
end

return UIController
