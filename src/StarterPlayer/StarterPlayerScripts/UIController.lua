--[[
	UIController.lua - Complete Pet Simulator 1 style UI for Battle Pets
	Creates all UI elements procedurally via code (no external assets).
	Responsive layout using UDim2 scale values for PC, tablet, and phone.
	
	Screens:
	- MainHUD: currency display, XP bar, navigation buttons, equipped pets bar
	- PetInventory: scrollable pet grid with equip/delete/multi-select
	- UpgradeWindow: large centered modal with tile upgrade cards
	- ShopWindow: egg purchase UI
	- CampaignSelect: delegated to CampaignController but toggled from here
	
	Style: Large rounded buttons, thick UIStroke borders, bright saturated colors,
	dark navy backgrounds, bold text, cartoon style.
]]

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local UIController = {}
UIController.__index = UIController

-- Color palette (Pet Simulator 1 style: bright, saturated, cartoon)
local COLORS = {
	Background = Color3.fromRGB(30, 40, 80),
	DarkBg = Color3.fromRGB(20, 28, 60),
	NavPets = Color3.fromRGB(0, 200, 80),
	NavUpgrades = Color3.fromRGB(255, 150, 0),
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
}

local RARITY_COLORS = {
	Common = Color3.fromRGB(255, 255, 255),
	Uncommon = Color3.fromRGB(0, 200, 0),
	Rare = Color3.fromRGB(0, 120, 255),
	Epic = Color3.fromRGB(180, 0, 255),
	Legendary = Color3.fromRGB(255, 200, 0),
}

-- Upgrade icon characters
local UPGRADE_ICONS = {
	Friendship = "♥",
	Diamonds = "◆",
	ExtraSlots = "+",
	FasterPets = "»",
	StrongPets = "⚡",
	LuckyEggs = "★",
	GoldenPetsChance = "✦",
	Sprinting = "↑",
	DropCloner = "×2",
	LuckyDrops = "$",
}

function UIController.new()
	local self = setmetatable({}, UIController)
	self._remotes = nil
	self._player = nil
	self._playerGui = nil
	self._screens = {}
	self._coinLabel = nil
	self._diamondLabel = nil
	self._xpFill = nil
	self._xpLevelLabel = nil
	self._petInventoryData = {}
	self._upgradeData = {}
	self._equippedPets = {}
	self._equippedBar = nil
	self._multiSelectMode = false
	self._selectedPets = {}
	self._currentZone = 1
	self._initialized = false
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
		self._petInventoryData = playerData.pets or {}
		self._equippedPets = playerData.equippedPets or {}
		self._upgradeData = playerData.upgrades or {}
		self._currentZone = playerData.currentZone or 1
	end

	-- Create all UI
	self:_createMainHUD(playerData)
	self:_createPetInventory()
	self:_createUpgradeWindow()
	self:_createShopWindow()

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

	-- ===== EQUIPPED PET BAR (above nav buttons) =====
	self:_createEquippedPetBar(screenGui)
end

function UIController:_createCurrencyDisplay(parent, playerData)
	local frame = Instance.new("Frame")
	frame.Name = "CurrencyDisplay"
	frame.Size = UDim2.fromScale(0.18, 0.12)
	frame.Position = UDim2.fromScale(0.8, 0.02)
	frame.BackgroundColor3 = COLORS.Background
	frame.BackgroundTransparency = 0.3
	frame.BorderSizePixel = 0
	frame.Parent = parent

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

	-- Coin icon (yellow circle)
	local coinIcon = Instance.new("Frame")
	coinIcon.Name = "CoinIcon"
	coinIcon.Size = UDim2.fromOffset(22, 22)
	coinIcon.Position = UDim2.fromOffset(0, 1)
	coinIcon.BackgroundColor3 = COLORS.CoinYellow
	coinIcon.Parent = coinRow

	local coinIconCorner = Instance.new("UICorner")
	coinIconCorner.CornerRadius = UDim.new(1, 0)
	coinIconCorner.Parent = coinIcon

	-- Coin icon text
	local coinIconText = Instance.new("TextLabel")
	coinIconText.Size = UDim2.fromScale(1, 1)
	coinIconText.BackgroundTransparency = 1
	coinIconText.Text = "$"
	coinIconText.TextColor3 = Color3.fromRGB(180, 130, 0)
	coinIconText.Font = Enum.Font.GothamBold
	coinIconText.TextScaled = true
	coinIconText.Parent = coinIcon

	-- Coin amount
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

	-- Diamond icon (blue diamond shape - rotated frame)
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

	-- Diamond amount
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

	-- Inner fill
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

	-- Level number
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
	navFrame.Size = UDim2.fromScale(0.35, 0.09)
	navFrame.Position = UDim2.fromScale(0.63, 0.88)
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
		{ name = "Upgrades", icon = "^", color = COLORS.NavUpgrades, screen = "UpgradeWindow" },
		{ name = "Shop", icon = "S", color = COLORS.NavShop, screen = "ShopWindow" },
		{ name = "Settings", icon = "G", color = COLORS.NavSettings, screen = nil },
		{ name = "Favorit", icon = "★", color = COLORS.NavFavorit, screen = nil },
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
		-- Slightly darker stroke
		btnStroke.Color = Color3.fromRGB(
			math.max(0, btnData.color.R * 255 - 40),
			math.max(0, btnData.color.G * 255 - 40),
			math.max(0, btnData.color.B * 255 - 40)
		)
		btnStroke.Parent = btn

		-- Icon text (top)
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

		-- Label text (bottom)
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

		-- Hover scale effect
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

		-- Click handler
		if btnData.screen then
			btn.MouseButton1Click:Connect(function()
				self:toggleScreen(btnData.screen)
			end)
		end
	end
end

function UIController:_createEquippedPetBar(parent)
	local barFrame = Instance.new("Frame")
	barFrame.Name = "EquippedPetBar"
	barFrame.Size = UDim2.fromScale(0.35, 0.06)
	barFrame.Position = UDim2.fromScale(0.63, 0.81)
	barFrame.BackgroundColor3 = COLORS.Background
	barFrame.BackgroundTransparency = 0.4
	barFrame.Parent = parent
	self._equippedBar = barFrame

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 10)
	barCorner.Parent = barFrame

	local barStroke = Instance.new("UIStroke")
	barStroke.Thickness = 2
	barStroke.Color = Color3.fromRGB(60, 80, 130)
	barStroke.Parent = barFrame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 4)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = barFrame

	-- Populate with equipped pets
	self:_refreshEquippedBar()
end

function UIController:_refreshEquippedBar()
	if not self._equippedBar then return end

	-- Clear existing icons (only destroy Frame children, keep UIListLayout etc.)
	for _, child in ipairs(self._equippedBar:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	-- If no equipped pets, show a hint label
	if #self._equippedPets == 0 then
		local hintLabel = Instance.new("TextLabel")
		hintLabel.Name = "HintLabel"
		hintLabel.Size = UDim2.fromScale(0.9, 0.8)
		hintLabel.BackgroundTransparency = 1
		hintLabel.Text = "No pets equipped"
		hintLabel.TextColor3 = Color3.fromRGB(150, 150, 170)
		hintLabel.Font = Enum.Font.GothamBold
		hintLabel.TextScaled = true
		hintLabel.Parent = self._equippedBar
		return
	end

	for _, petData in ipairs(self._equippedPets) do
		-- Handle both pet data tables and string IDs gracefully
		local petName = "?"
		local petRarity = "Common"
		if type(petData) == "table" then
			petName = petData.name or "?"
			petRarity = petData.rarity or "Common"
		end

		local rarityColor = RARITY_COLORS[petRarity] or RARITY_COLORS.Common

		local slot = Instance.new("Frame")
		slot.Name = "Slot_" .. petName
		slot.Size = UDim2.fromOffset(44, 44)
		slot.BackgroundColor3 = rarityColor
		slot.Parent = self._equippedBar

		local slotCorner = Instance.new("UICorner")
		slotCorner.CornerRadius = UDim.new(0, 8)
		slotCorner.Parent = slot

		local slotStroke = Instance.new("UIStroke")
		slotStroke.Thickness = 2
		slotStroke.Color = Color3.fromRGB(255, 255, 255)
		slotStroke.Parent = slot

		local petLabel = Instance.new("TextLabel")
		petLabel.Size = UDim2.fromScale(1, 1)
		petLabel.BackgroundTransparency = 1
		petLabel.Text = string.sub(petName, 1, 2)
		petLabel.TextColor3 = COLORS.White
		petLabel.Font = Enum.Font.GothamBold
		petLabel.TextScaled = true
		petLabel.Parent = slot
	end
end

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

	-- Large centered frame
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

	-- Title
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

	-- Close button (top-right, red circle with X)
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

	-- Multi-select toggle button
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

	-- Delete Selected button (red, appears in multi-select mode)
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

	-- Scrolling frame grid (scrollbar hidden but still scrollable via touch/mousewheel)
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "PetGrid"
	scrollFrame.Size = UDim2.fromScale(0.94, 0.78)
	scrollFrame.Position = UDim2.fromScale(0.03, 0.1)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.ScrollBarThickness = 0
	scrollFrame.CanvasSize = UDim2.fromScale(0, 0) -- will be auto-sized
	scrollFrame.Parent = mainFrame

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.Name = "GridLayout"
	gridLayout.CellSize = UDim2.fromOffset(120, 150)
	gridLayout.CellPadding = UDim2.fromOffset(8, 8)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = scrollFrame

	-- Auto-size canvas
	gridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		scrollFrame.CanvasSize = UDim2.fromOffset(0, gridLayout.AbsoluteContentSize.Y + 20)
	end)

	-- Initial population
	self:_refreshPetGrid()
end

function UIController:_refreshPetGrid()
	local screenGui = self._screens.PetInventory
	if not screenGui then return end
	local mainFrame = screenGui:FindFirstChild("MainFrame")
	if not mainFrame then return end
	local scrollFrame = mainFrame:FindFirstChild("PetGrid")
	if not scrollFrame then return end

	-- Show/hide delete button based on multi-select mode
	local deleteBtn = mainFrame:FindFirstChild("DeleteSelectedBtn")
	if deleteBtn then
		deleteBtn.Visible = self._multiSelectMode
	end

	-- Clear existing cards (keep layout)
	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	for i, petData in ipairs(self._petInventoryData) do
		local card = Instance.new("Frame")
		card.Name = "PetCard_" .. i
		card.BackgroundColor3 = COLORS.DarkBg
		card.LayoutOrder = i
		card.Parent = scrollFrame

		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 12)
		cardCorner.Parent = card

		-- Rarity color border
		local rarityColor = RARITY_COLORS[petData.rarity or "Common"] or RARITY_COLORS.Common
		local cardStroke = Instance.new("UIStroke")
		cardStroke.Thickness = 3
		cardStroke.Color = rarityColor
		cardStroke.Parent = card

		-- Pet color circle (icon)
		local petIcon = Instance.new("Frame")
		petIcon.Name = "PetIcon"
		petIcon.Size = UDim2.fromScale(0.45, 0.35)
		petIcon.Position = UDim2.fromScale(0.275, 0.05)
		petIcon.BackgroundColor3 = rarityColor
		petIcon.Parent = card

		local iconCorner = Instance.new("UICorner")
		iconCorner.CornerRadius = UDim.new(1, 0)
		iconCorner.Parent = petIcon

		-- Pet name
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "PetName"
		nameLabel.Size = UDim2.fromScale(0.9, 0.15)
		nameLabel.Position = UDim2.fromScale(0.05, 0.42)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = petData.name or "Pet"
		nameLabel.TextColor3 = COLORS.White
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextScaled = true
		nameLabel.Parent = card

		-- Damage stat
		local dmgLabel = Instance.new("TextLabel")
		dmgLabel.Name = "DmgStat"
		dmgLabel.Size = UDim2.fromScale(0.9, 0.12)
		dmgLabel.Position = UDim2.fromScale(0.05, 0.58)
		dmgLabel.BackgroundTransparency = 1
		dmgLabel.Text = "DMG: " .. tostring(petData.damage or petData.baseDamage or 5)
		dmgLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
		dmgLabel.Font = Enum.Font.GothamBold
		dmgLabel.TextScaled = true
		dmgLabel.Parent = card

		-- Equip/Unequip button (or selection checkbox in multi-select)
		local petUniqueId = petData.uniqueId or petData.id
		if self._multiSelectMode then
			local isSelected = self._selectedPets[petUniqueId] ~= nil
			local selectBox = Instance.new("TextButton")
			selectBox.Name = "SelectBox"
			selectBox.Size = UDim2.fromScale(0.8, 0.16)
			selectBox.Position = UDim2.fromScale(0.1, 0.75)
			selectBox.BackgroundColor3 = isSelected and Color3.fromRGB(200, 100, 0) or Color3.fromRGB(60, 70, 110)
			selectBox.Text = isSelected and "Selected" or "Select"
			selectBox.TextColor3 = COLORS.White
			selectBox.Font = Enum.Font.GothamBold
			selectBox.TextScaled = true
			selectBox.Parent = card

			local selectCorner = Instance.new("UICorner")
			selectCorner.CornerRadius = UDim.new(0, 6)
			selectCorner.Parent = selectBox

			local petId = petUniqueId
			selectBox.MouseButton1Click:Connect(function()
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
			equipBtn.Position = UDim2.fromScale(0.1, 0.75)
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

			-- Hover effect
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

function UIController:_isPetEquipped(uniqueId)
	for _, pet in ipairs(self._equippedPets) do
		local petId = pet.uniqueId or pet.id
		if petId == uniqueId then
			return true
		end
	end
	return false
end

function UIController:_equipPet(uniqueId)
	if self._remotes then
		local remote = self._remotes:FindFirstChild("EquipPet")
		if remote then
			remote:InvokeServer(uniqueId)
		end
	end
end

function UIController:_unequipPet(uniqueId)
	if self._remotes then
		local remote = self._remotes:FindFirstChild("UnequipPet")
		if remote then
			remote:InvokeServer(uniqueId)
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
			remote:InvokeServer(ids)
		end
	end
	self._selectedPets = {}
end

--------------------------------------------------------------------------------
-- UPGRADE WINDOW
--------------------------------------------------------------------------------
function UIController:_createUpgradeWindow()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "UpgradeWindow"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = false
	screenGui.Parent = self._playerGui
	self._screens.UpgradeWindow = screenGui

	-- Large centered frame with THICK border
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
	mainStroke.Color = COLORS.NavUpgrades
	mainStroke.Parent = mainFrame

	-- Title "Upgrades" at top-center
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(0.4, 0.08)
	title.Position = UDim2.fromScale(0.3, 0.01)
	title.BackgroundTransparency = 1
	title.Text = "UPGRADES"
	title.TextColor3 = COLORS.NavUpgrades
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.Parent = mainFrame

	-- BIG X close button (top-right corner, 44x44)
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
		self:toggleScreen("UpgradeWindow")
	end)

	-- Scrolling frame for upgrade grid
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "UpgradeGrid"
	scrollFrame.Size = UDim2.fromScale(0.94, 0.82)
	scrollFrame.Position = UDim2.fromScale(0.03, 0.12)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.ScrollBarThickness = 8
	scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 130, 200)
	scrollFrame.CanvasSize = UDim2.fromScale(0, 0)
	scrollFrame.Parent = mainFrame

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.Name = "GridLayout"
	gridLayout.CellSize = UDim2.fromOffset(180, 200)
	gridLayout.CellPadding = UDim2.fromOffset(12, 12)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = scrollFrame

	-- Auto-size canvas
	gridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		scrollFrame.CanvasSize = UDim2.fromOffset(0, gridLayout.AbsoluteContentSize.Y + 20)
	end)

	-- Populate upgrade cards
	self:_refreshUpgradeGrid()
end

function UIController:_refreshUpgradeGrid()
	local screenGui = self._screens.UpgradeWindow
	if not screenGui then return end
	local mainFrame = screenGui:FindFirstChild("MainFrame")
	if not mainFrame then return end
	local scrollFrame = mainFrame:FindFirstChild("UpgradeGrid")
	if not scrollFrame then return end

	-- Clear existing cards (keep layout)
	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	-- Define upgrade order and colors
	local upgradeOrder = {
		"Friendship", "Diamonds", "ExtraSlots", "FasterPets", "StrongPets",
		"LuckyEggs", "GoldenPetsChance", "Sprinting", "DropCloner", "LuckyDrops",
	}

	local upgradeColors = {
		Friendship = Color3.fromRGB(255, 100, 150),
		Diamonds = Color3.fromRGB(0, 180, 255),
		ExtraSlots = Color3.fromRGB(100, 200, 0),
		FasterPets = Color3.fromRGB(255, 200, 0),
		StrongPets = Color3.fromRGB(255, 80, 0),
		LuckyEggs = Color3.fromRGB(200, 100, 255),
		GoldenPetsChance = Color3.fromRGB(255, 200, 0),
		Sprinting = Color3.fromRGB(0, 220, 150),
		DropCloner = Color3.fromRGB(0, 150, 255),
		LuckyDrops = Color3.fromRGB(255, 220, 0),
	}

	for order, upgradeName in ipairs(upgradeOrder) do
		local currentLevel = self._upgradeData[upgradeName] or 0
		local maxLevel = 3  -- from Config
		local cardColor = upgradeColors[upgradeName] or Color3.fromRGB(100, 100, 200)
		local iconChar = UPGRADE_ICONS[upgradeName] or "?"
		local displayName = upgradeName

		-- Calculate cost for next level
		local costText = "MAX"
		if currentLevel < maxLevel then
			-- Estimated costs (actual would come from Config)
			local baseCosts = { 500, 2000, 10000 }
			local nextCost = baseCosts[currentLevel + 1] or 10000
			costText = tostring(nextCost) .. " Coins"
		end

		local card = Instance.new("Frame")
		card.Name = "Upgrade_" .. upgradeName
		card.BackgroundColor3 = Color3.fromRGB(
			math.floor(cardColor.R * 255 * 0.3 + 30),
			math.floor(cardColor.G * 255 * 0.3 + 30),
			math.floor(cardColor.B * 255 * 0.3 + 50)
		)
		card.LayoutOrder = order
		card.Parent = scrollFrame

		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 12)
		cardCorner.Parent = card

		local cardStroke = Instance.new("UIStroke")
		cardStroke.Thickness = 3
		cardStroke.Color = cardColor
		cardStroke.Parent = card

		-- Icon
		local iconLabel = Instance.new("TextLabel")
		iconLabel.Name = "Icon"
		iconLabel.Size = UDim2.fromScale(0.4, 0.25)
		iconLabel.Position = UDim2.fromScale(0.3, 0.03)
		iconLabel.BackgroundTransparency = 1
		iconLabel.Text = iconChar
		iconLabel.TextColor3 = cardColor
		iconLabel.Font = Enum.Font.GothamBold
		iconLabel.TextScaled = true
		iconLabel.Parent = card

		-- Upgrade name (bold)
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "UpgradeName"
		nameLabel.Size = UDim2.fromScale(0.9, 0.14)
		nameLabel.Position = UDim2.fromScale(0.05, 0.3)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = displayName
		nameLabel.TextColor3 = COLORS.White
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextScaled = true
		nameLabel.Parent = card

		-- Level indicator
		local levelText = ""
		for lv = 1, maxLevel do
			levelText = levelText .. (lv <= currentLevel and "★" or "☆")
		end
		local levelLabel = Instance.new("TextLabel")
		levelLabel.Name = "LevelIndicator"
		levelLabel.Size = UDim2.fromScale(0.9, 0.12)
		levelLabel.Position = UDim2.fromScale(0.05, 0.45)
		levelLabel.BackgroundTransparency = 1
		levelLabel.Text = "Lv." .. tostring(currentLevel) .. " " .. levelText
		levelLabel.TextColor3 = cardColor
		levelLabel.Font = Enum.Font.GothamBold
		levelLabel.TextScaled = true
		levelLabel.Parent = card

		-- Cost
		local costLabel = Instance.new("TextLabel")
		costLabel.Name = "CostLabel"
		costLabel.Size = UDim2.fromScale(0.9, 0.1)
		costLabel.Position = UDim2.fromScale(0.05, 0.59)
		costLabel.BackgroundTransparency = 1
		costLabel.Text = costText
		costLabel.TextColor3 = COLORS.CoinYellow
		costLabel.Font = Enum.Font.GothamBold
		costLabel.TextScaled = true
		costLabel.Parent = card

		-- BUY button (green, rounded)
		if currentLevel < maxLevel then
			local buyBtn = Instance.new("TextButton")
			buyBtn.Name = "BuyBtn"
			buyBtn.Size = UDim2.fromScale(0.7, 0.17)
			buyBtn.Position = UDim2.fromScale(0.15, 0.75)
			buyBtn.BackgroundColor3 = COLORS.ButtonGreen
			buyBtn.Text = "BUY"
			buyBtn.TextColor3 = COLORS.White
			buyBtn.Font = Enum.Font.GothamBold
			buyBtn.TextScaled = true
			buyBtn.Parent = card

			local buyCorner = Instance.new("UICorner")
			buyCorner.CornerRadius = UDim.new(0, 8)
			buyCorner.Parent = buyBtn

			local buyStroke = Instance.new("UIStroke")
			buyStroke.Thickness = 2
			buyStroke.Color = Color3.fromRGB(0, 150, 50)
			buyStroke.Parent = buyBtn

			buyBtn.MouseButton1Click:Connect(function()
				self:_purchaseUpgrade(upgradeName)
			end)

			-- Hover effect
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
		else
			local maxLabel = Instance.new("TextLabel")
			maxLabel.Size = UDim2.fromScale(0.7, 0.17)
			maxLabel.Position = UDim2.fromScale(0.15, 0.75)
			maxLabel.BackgroundTransparency = 1
			maxLabel.Text = "MAXED"
			maxLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
			maxLabel.Font = Enum.Font.GothamBold
			maxLabel.TextScaled = true
			maxLabel.Parent = card
		end
	end
end

function UIController:_purchaseUpgrade(upgradeName)
	if self._remotes then
		local remote = self._remotes:FindFirstChild("PurchaseUpgrade")
		if remote then
			remote:InvokeServer(upgradeName)
		end
	end
end

--------------------------------------------------------------------------------
-- SHOP WINDOW
--------------------------------------------------------------------------------
function UIController:_createShopWindow()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ShopWindow"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = false
	screenGui.Parent = self._playerGui
	self._screens.ShopWindow = screenGui

	-- Main frame
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.fromScale(0.7, 0.65)
	mainFrame.Position = UDim2.fromScale(0.15, 0.175)
	mainFrame.BackgroundColor3 = COLORS.Background
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = screenGui

	local mainCorner = Instance.new("UICorner")
	mainCorner.CornerRadius = UDim.new(0, 16)
	mainCorner.Parent = mainFrame

	local mainStroke = Instance.new("UIStroke")
	mainStroke.Thickness = 4
	mainStroke.Color = COLORS.NavShop
	mainStroke.Parent = mainFrame

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(0.4, 0.1)
	title.Position = UDim2.fromScale(0.3, 0.01)
	title.BackgroundTransparency = 1
	title.Text = "EGG SHOP"
	title.TextColor3 = COLORS.NavShop
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.Parent = mainFrame

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.fromOffset(42, 42)
	closeBtn.Position = UDim2.new(1, -52, 0, 10)
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
		self:toggleScreen("ShopWindow")
	end)

	-- Egg cards container
	local eggFrame = Instance.new("ScrollingFrame")
	eggFrame.Name = "EggCards"
	eggFrame.Size = UDim2.fromScale(0.94, 0.78)
	eggFrame.Position = UDim2.fromScale(0.03, 0.14)
	eggFrame.BackgroundTransparency = 1
	eggFrame.ScrollBarThickness = 6
	eggFrame.CanvasSize = UDim2.fromScale(0, 0)
	eggFrame.Parent = mainFrame

	local eggLayout = Instance.new("UIListLayout")
	eggLayout.FillDirection = Enum.FillDirection.Horizontal
	eggLayout.Padding = UDim.new(0, 12)
	eggLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	eggLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	eggLayout.Parent = eggFrame

	-- Populate with sample egg cards
	self:_refreshShop()
end

function UIController:_refreshShop()
	local screenGui = self._screens.ShopWindow
	if not screenGui then return end
	local mainFrame = screenGui:FindFirstChild("MainFrame")
	if not mainFrame then return end
	local eggFrame = mainFrame:FindFirstChild("EggCards")
	if not eggFrame then return end

	-- Clear existing
	for _, child in ipairs(eggFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	-- Egg types based on current zone
	local eggTypes = {
		{ name = "Basic Egg", cost = 100, zone = 1, rarities = "60% Common, 25% Uncommon, 10% Rare, 4% Epic, 1% Legendary" },
		{ name = "Premium Egg", cost = 500, zone = 2, rarities = "40% Common, 30% Uncommon, 20% Rare, 10% Legendary" },
	}

	local eggColors = {
		Color3.fromRGB(200, 230, 180),
		Color3.fromRGB(180, 200, 255),
		Color3.fromRGB(255, 200, 180),
	}

	for i, eggData in ipairs(eggTypes) do
		local card = Instance.new("Frame")
		card.Name = "EggCard_" .. i
		card.Size = UDim2.fromOffset(200, 280)
		card.BackgroundColor3 = COLORS.DarkBg
		card.Parent = eggFrame

		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 14)
		cardCorner.Parent = card

		local cardStroke = Instance.new("UIStroke")
		cardStroke.Thickness = 3
		cardStroke.Color = eggColors[i] or eggColors[1]
		cardStroke.Parent = card

		-- Egg icon (ellipsoid representation: oval frame)
		local eggIcon = Instance.new("Frame")
		eggIcon.Name = "EggIcon"
		eggIcon.Size = UDim2.fromScale(0.4, 0.3)
		eggIcon.Position = UDim2.fromScale(0.3, 0.05)
		eggIcon.BackgroundColor3 = eggColors[i] or eggColors[1]
		eggIcon.Parent = card

		local eggIconCorner = Instance.new("UICorner")
		eggIconCorner.CornerRadius = UDim.new(0.5, 0)
		eggIconCorner.Parent = eggIcon

		-- Egg text inside
		local eggText = Instance.new("TextLabel")
		eggText.Size = UDim2.fromScale(1, 1)
		eggText.BackgroundTransparency = 1
		eggText.Text = "?"
		eggText.TextColor3 = Color3.fromRGB(80, 80, 80)
		eggText.Font = Enum.Font.GothamBold
		eggText.TextScaled = true
		eggText.Parent = eggIcon

		-- Egg name
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "EggName"
		nameLabel.Size = UDim2.fromScale(0.9, 0.1)
		nameLabel.Position = UDim2.fromScale(0.05, 0.38)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = eggData.name
		nameLabel.TextColor3 = COLORS.White
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextScaled = true
		nameLabel.Parent = card

		-- Cost
		local costLabel = Instance.new("TextLabel")
		costLabel.Name = "Cost"
		costLabel.Size = UDim2.fromScale(0.9, 0.08)
		costLabel.Position = UDim2.fromScale(0.05, 0.5)
		costLabel.BackgroundTransparency = 1
		costLabel.Text = tostring(eggData.cost) .. " Coins"
		costLabel.TextColor3 = COLORS.CoinYellow
		costLabel.Font = Enum.Font.GothamBold
		costLabel.TextScaled = true
		costLabel.Parent = card

		-- Rarity chances
		local rarityLabel = Instance.new("TextLabel")
		rarityLabel.Name = "Rarities"
		rarityLabel.Size = UDim2.fromScale(0.9, 0.18)
		rarityLabel.Position = UDim2.fromScale(0.05, 0.6)
		rarityLabel.BackgroundTransparency = 1
		rarityLabel.Text = eggData.rarities
		rarityLabel.TextColor3 = Color3.fromRGB(180, 180, 200)
		rarityLabel.Font = Enum.Font.Gotham
		rarityLabel.TextScaled = true
		rarityLabel.TextWrapped = true
		rarityLabel.Parent = card

		-- Hatch button
		local hatchBtn = Instance.new("TextButton")
		hatchBtn.Name = "HatchBtn"
		hatchBtn.Size = UDim2.fromScale(0.7, 0.12)
		hatchBtn.Position = UDim2.fromScale(0.15, 0.82)
		hatchBtn.BackgroundColor3 = COLORS.ButtonGreen
		hatchBtn.Text = "Hatch!"
		hatchBtn.TextColor3 = COLORS.White
		hatchBtn.Font = Enum.Font.GothamBold
		hatchBtn.TextScaled = true
		hatchBtn.Parent = card

		local hatchCorner = Instance.new("UICorner")
		hatchCorner.CornerRadius = UDim.new(0, 10)
		hatchCorner.Parent = hatchBtn

		local hatchStroke = Instance.new("UIStroke")
		hatchStroke.Thickness = 2
		hatchStroke.Color = Color3.fromRGB(0, 150, 50)
		hatchStroke.Parent = hatchBtn

		-- Hatch on click
		local eggType = (i == 1) and "BasicEgg" or "PremiumEgg"
		hatchBtn.MouseButton1Click:Connect(function()
			self:_hatchEgg(eggType)
		end)

		-- Hover effect
		hatchBtn.MouseEnter:Connect(function()
			TweenService:Create(hatchBtn, TweenInfo.new(0.1), {
				Size = UDim2.fromScale(0.74, 0.13),
			}):Play()
		end)
		hatchBtn.MouseLeave:Connect(function()
			TweenService:Create(hatchBtn, TweenInfo.new(0.1), {
				Size = UDim2.fromScale(0.7, 0.12),
			}):Play()
		end)
	end
end

function UIController:_hatchEgg(eggType)
	if self._remotes then
		local remote = self._remotes:FindFirstChild("HatchEgg")
		if remote then
			remote:InvokeServer(eggType)
		end
	end
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

-- Update currency display
function UIController:updateCurrency(coins, diamonds)
	if self._coinLabel then
		self._coinLabel.Text = tostring(coins or 0)
	end
	if self._diamondLabel then
		self._diamondLabel.Text = tostring(diamonds or 0)
	end
end

-- Update pet inventory data and refresh grid
function UIController:updatePetInventory(pets)
	self._petInventoryData = pets or {}
	self:_refreshPetGrid()
end

-- Update equipped pets and refresh bar
function UIController:updateEquippedPets(equippedPets)
	self._equippedPets = equippedPets or {}
	self:_refreshEquippedBar()
	self:_refreshPetGrid()
end

-- Update upgrades data and refresh grid
function UIController:updateUpgrades(upgrades)
	self._upgradeData = upgrades or {}
	self:_refreshUpgradeGrid()
end

-- Show egg hatch result overlay
function UIController:showEggHatch(petData)
	if not self._playerGui then return end

	-- Create a simple overlay showing the hatched pet
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

	local rarityColor = RARITY_COLORS[petData and petData.rarity or "Common"] or RARITY_COLORS.Common
	local panelStroke = Instance.new("UIStroke")
	panelStroke.Thickness = 4
	panelStroke.Color = rarityColor
	panelStroke.Parent = panel

	-- "NEW PET!" text
	local newPetText = Instance.new("TextLabel")
	newPetText.Size = UDim2.fromScale(0.8, 0.15)
	newPetText.Position = UDim2.fromScale(0.1, 0.05)
	newPetText.BackgroundTransparency = 1
	newPetText.Text = "NEW PET!"
	newPetText.TextColor3 = COLORS.CoinYellow
	newPetText.Font = Enum.Font.GothamBold
	newPetText.TextScaled = true
	newPetText.Parent = panel

	-- Pet icon
	local petIcon = Instance.new("Frame")
	petIcon.Size = UDim2.fromScale(0.35, 0.35)
	petIcon.Position = UDim2.fromScale(0.325, 0.22)
	petIcon.BackgroundColor3 = rarityColor
	petIcon.Parent = panel

	local petIconCorner = Instance.new("UICorner")
	petIconCorner.CornerRadius = UDim.new(1, 0)
	petIconCorner.Parent = petIcon

	-- Pet name
	local petName = Instance.new("TextLabel")
	petName.Size = UDim2.fromScale(0.8, 0.12)
	petName.Position = UDim2.fromScale(0.1, 0.6)
	petName.BackgroundTransparency = 1
	petName.Text = petData and petData.name or "Pet"
	petName.TextColor3 = rarityColor
	petName.Font = Enum.Font.GothamBold
	petName.TextScaled = true
	petName.Parent = panel

	-- Rarity
	local rarityText = Instance.new("TextLabel")
	rarityText.Size = UDim2.fromScale(0.8, 0.08)
	rarityText.Position = UDim2.fromScale(0.1, 0.73)
	rarityText.BackgroundTransparency = 1
	rarityText.Text = petData and petData.rarity or "Common"
	rarityText.TextColor3 = rarityColor
	rarityText.Font = Enum.Font.GothamBold
	rarityText.TextScaled = true
	rarityText.Parent = panel

	-- OK button
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

	-- Auto-close after 5 seconds
	task.delay(5, function()
		if overlay and overlay.Parent then
			overlay:Destroy()
		end
	end)
end

-- Toggle a screen on/off
function UIController:toggleScreen(screenName)
	local screen = self._screens[screenName]
	if screen then
		screen.Enabled = not screen.Enabled
		-- Close other screens when opening one
		if screen.Enabled then
			for name, otherScreen in pairs(self._screens) do
				if name ~= screenName and name ~= "MainHUD" then
					otherScreen.Enabled = false
				end
			end
		end
	end
end

-- Update XP bar
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

-- Cleanup
function UIController:cleanup()
	for _, screen in pairs(self._screens) do
		screen:Destroy()
	end
	self._screens = {}
end

return UIController
