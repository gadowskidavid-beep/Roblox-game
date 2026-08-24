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
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PetData = require(Shared:WaitForChild("PetData"))
local QuestData = require(Shared:WaitForChild("QuestData"))
local MasteryData = require(Shared:WaitForChild("MasteryData"))

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
	-- Quest and mastery state
	self._questProgress = {}
	self._masteryState = { masteryPoints = 0, level = 1, buffs = {} }
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
		self._masteryState = {
			masteryPoints = playerData.masteryPoints or 0,
			level = playerData.level or 1,
			buffs = playerData.masteryBuffs or {},
		}
	end

	-- Create all UI
	self:_createMainHUD(playerData)
	self:_createPetInventory()
	self:_createQuestWindow()
	self:_createMasteryWindow()
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

	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "PetGrid"
	scrollFrame.Size = UDim2.fromScale(0.94, 0.78)
	scrollFrame.Position = UDim2.fromScale(0.03, 0.1)
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

		local rarityColor = RARITY_COLORS[petData.rarity or "Common"] or RARITY_COLORS.Common
		local cardStroke = Instance.new("UIStroke")
		cardStroke.Thickness = 3
		cardStroke.Color = rarityColor
		cardStroke.Parent = card

		local petIcon = Instance.new("Frame")
		petIcon.Name = "PetIcon"
		petIcon.Size = UDim2.fromScale(0.45, 0.35)
		petIcon.Position = UDim2.fromScale(0.275, 0.05)
		petIcon.BackgroundColor3 = rarityColor
		petIcon.Parent = card

		local iconCorner = Instance.new("UICorner")
		iconCorner.CornerRadius = UDim.new(1, 0)
		iconCorner.Parent = petIcon

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

		local dmgLabel = Instance.new("TextLabel")
		dmgLabel.Name = "DmgStat"
		dmgLabel.Size = UDim2.fromScale(0.9, 0.12)
		dmgLabel.Position = UDim2.fromScale(0.05, 0.58)
		dmgLabel.BackgroundTransparency = 1
		dmgLabel.Text = tostring(petData.damage or petData.baseDamage or 5)
		dmgLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
		dmgLabel.Font = Enum.Font.GothamBold
		dmgLabel.TextScaled = true
		dmgLabel.Parent = card

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
			remote:InvokeServer(ids)
		end
	end
	self._selectedPets = {}
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
				if pet.golden then
					self:_showGoldenError("Cannot use golden pets!")
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
-- EGG STATION - No overlay menu needed (E-key directly hatches via ProximityPrompt)
-- The old ShopWindow/EggPrompt overlay is removed.
-- BillboardGuis showing pet probabilities are created server-side on the egg stations.
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

function UIController:showEggStationPrompt(eggType)
	-- No-op: E-key ProximityPrompt handles hatching directly
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

function UIController:updateCurrency(coins, diamonds)
	if self._coinLabel then
		self._coinLabel.Text = tostring(coins or 0)
	end
	if self._diamondLabel then
		self._diamondLabel.Text = tostring(diamonds or 0)
	end
end

function UIController:updatePetInventory(pets)
	self._petInventoryData = pets or {}
	self:_refreshPetGrid()
end

function UIController:updateEquippedPets(equippedPets)
	self._equippedPets = equippedPets or {}
	self:_refreshPetGrid()
end

function UIController:updateUpgrades(upgrades)
	self._upgradeData = upgrades or {}
	self:_refreshQuestGrid()
end

function UIController:updateQuestProgress(questProgress)
	self._questProgress = questProgress or {}
	self:_refreshQuestGrid()
end

function UIController:updateMastery(masteryState)
	self._masteryState = masteryState or { masteryPoints = 0, level = 1, buffs = {} }
	self:_refreshMasteryGrid()
end

function UIController:showEggHatch(petData)
	if not self._playerGui then return end

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
	petIcon.BackgroundColor3 = rarityColor
	petIcon.Parent = panel

	local petIconCorner = Instance.new("UICorner")
	petIconCorner.CornerRadius = UDim.new(1, 0)
	petIconCorner.Parent = petIcon

	local petName = Instance.new("TextLabel")
	petName.Size = UDim2.fromScale(0.8, 0.12)
	petName.Position = UDim2.fromScale(0.1, 0.6)
	petName.BackgroundTransparency = 1
	petName.Text = petData and petData.name or "Pet"
	petName.TextColor3 = rarityColor
	petName.Font = Enum.Font.GothamBold
	petName.TextScaled = true
	petName.Parent = panel

	local rarityText = Instance.new("TextLabel")
	rarityText.Size = UDim2.fromScale(0.8, 0.08)
	rarityText.Position = UDim2.fromScale(0.1, 0.73)
	rarityText.BackgroundTransparency = 1
	rarityText.Text = petData and petData.rarity or "Common"
	rarityText.TextColor3 = rarityColor
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

function UIController:toggleScreen(screenName)
	local screen = self._screens[screenName]
	if screen then
		if screen.Enabled then
			-- Slide out animation then disable
			local mainFrame = screen:FindFirstChild("MainFrame") or screen:FindFirstChild("EggPrompt")
			if mainFrame then
				local slideOutInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				local originalPos = mainFrame.Position
				TweenService:Create(mainFrame, slideOutInfo, {
					Position = UDim2.new(originalPos.X.Scale, originalPos.X.Offset, 1.2, 0),
				}):Play()
				task.delay(0.25, function()
					if screen and screen.Parent then
						screen.Enabled = false
						mainFrame.Position = originalPos
					end
				end)
			else
				screen.Enabled = false
			end
		else
			-- Close other screens first
			for name, otherScreen in pairs(self._screens) do
				if name ~= screenName and name ~= "MainHUD" then
					otherScreen.Enabled = false
				end
			end

			-- Enable and slide in from below
			screen.Enabled = true
			local mainFrame = screen:FindFirstChild("MainFrame") or screen:FindFirstChild("EggPrompt")
			if mainFrame then
				local targetPos = mainFrame.Position
				mainFrame.Position = UDim2.new(targetPos.X.Scale, targetPos.X.Offset, 1.2, 0)
				local slideInInfo = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				TweenService:Create(mainFrame, slideInInfo, {
					Position = targetPos,
				}):Play()
			end

			-- Refresh quest progress when opening quest window
			if screenName == "QuestWindow" and self._remotes then
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
			end
			-- Refresh mastery state when opening mastery window
			if screenName == "MasteryWindow" and self._remotes then
				local remote = self._remotes:FindFirstChild("GetMasteryState")
				if remote then
					task.spawn(function()
						local state = remote:InvokeServer()
						if state then
							self._masteryState = state
							self:_refreshMasteryGrid()
						end
					end)
				end
			end
		end
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
	for _, screen in pairs(self._screens) do
		screen:Destroy()
	end
	self._screens = {}
end

return UIController
