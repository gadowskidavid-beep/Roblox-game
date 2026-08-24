--[[
	CampaignController.lua - Campaign battle client for Battle Pets
	Manages the lane-based battle UI: player base (left), enemy base (right),
	energy system, pet deployment cards, entity movement visualization,
	and victory/defeat screens. All visuals are procedural.
]]

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local CampaignController = {}
CampaignController.__index = CampaignController

-- Colors
local COLORS = {
	Background = Color3.fromRGB(20, 25, 50),
	PlayerBase = Color3.fromRGB(0, 180, 80),
	EnemyBase = Color3.fromRGB(200, 40, 40),
	EnergyBar = Color3.fromRGB(0, 180, 255),
	EnergyBg = Color3.fromRGB(30, 40, 70),
	CardBg = Color3.fromRGB(40, 50, 90),
	LaneGround = Color3.fromRGB(50, 60, 90),
	Victory = Color3.fromRGB(255, 200, 0),
	Defeat = Color3.fromRGB(200, 40, 40),
	DeployButton = Color3.fromRGB(0, 200, 100),
}

local RARITY_COLORS = {
	Common = Color3.fromRGB(255, 255, 255),
	Uncommon = Color3.fromRGB(0, 200, 0),
	Rare = Color3.fromRGB(0, 120, 255),
	Epic = Color3.fromRGB(180, 0, 255),
	Legendary = Color3.fromRGB(255, 200, 0),
}

function CampaignController.new()
	local self = setmetatable({}, CampaignController)
	self._remotes = nil
	self._player = nil
	self._playerGui = nil
	self._battleGui = nil
	self._selectGui = nil
	self._inBattle = false
	self._energy = 0
	self._maxEnergy = 100
	self._entities = {} -- tracked entities on the lane
	self._deployCards = {} -- UI card references
	self._initialized = false
	return self
end

function CampaignController:init(remotes)
	self._remotes = remotes
	self._player = Players.LocalPlayer
	self._playerGui = self._player:WaitForChild("PlayerGui")
	self._initialized = true
end

--------------------------------------------------------------------------------
-- Campaign Level Select Screen
--------------------------------------------------------------------------------
function CampaignController:showCampaignSelect(campaignData, playerProgress)
	if not self._initialized then return end

	-- Remove existing
	if self._selectGui then
		self._selectGui:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CampaignSelect"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = self._playerGui
	self._selectGui = screenGui

	-- Main frame
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.fromScale(0.85, 0.8)
	mainFrame.Position = UDim2.fromScale(0.075, 0.1)
	mainFrame.BackgroundColor3 = COLORS.Background
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = screenGui

	local mainCorner = Instance.new("UICorner")
	mainCorner.CornerRadius = UDim.new(0, 16)
	mainCorner.Parent = mainFrame

	local mainStroke = Instance.new("UIStroke")
	mainStroke.Thickness = 4
	mainStroke.Color = Color3.fromRGB(100, 140, 255)
	mainStroke.Parent = mainFrame

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(0.6, 0.08)
	title.Position = UDim2.fromScale(0.2, 0.01)
	title.BackgroundTransparency = 1
	title.Text = "CAMPAIGN"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.Parent = mainFrame

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.fromScale(0.06, 0.08)
	closeBtn.Position = UDim2.fromScale(0.92, 0.01)
	closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextScaled = true
	closeBtn.Parent = mainFrame

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 8)
	closeCorner.Parent = closeBtn

	closeBtn.MouseButton1Click:Connect(function()
		self:hideCampaignSelect()
	end)

	-- Region tabs at top
	local tabFrame = Instance.new("Frame")
	tabFrame.Name = "RegionTabs"
	tabFrame.Size = UDim2.fromScale(0.9, 0.08)
	tabFrame.Position = UDim2.fromScale(0.05, 0.1)
	tabFrame.BackgroundTransparency = 1
	tabFrame.Parent = mainFrame

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 4)
	tabLayout.Parent = tabFrame

	local regions = campaignData and campaignData.Regions or {}
	for i = 1, 8 do
		local regionName = regions[i] or ("Region " .. i)
		local tab = Instance.new("TextButton")
		tab.Name = "Region_" .. i
		tab.Size = UDim2.fromScale(0.12, 1)
		tab.BackgroundColor3 = Color3.fromRGB(50, 60, 100)
		tab.Text = tostring(i)
		tab.TextColor3 = Color3.fromRGB(255, 255, 255)
		tab.Font = Enum.Font.GothamBold
		tab.TextScaled = true
		tab.Parent = tabFrame

		local tabCorner = Instance.new("UICorner")
		tabCorner.CornerRadius = UDim.new(0, 8)
		tabCorner.Parent = tab

		tab.MouseButton1Click:Connect(function()
			self:_showRegionLevels(mainFrame, i, campaignData, playerProgress)
		end)
	end

	-- Show first region by default
	self:_showRegionLevels(mainFrame, 1, campaignData, playerProgress)
end

function CampaignController:_showRegionLevels(parentFrame, regionNum, campaignData, playerProgress)
	-- Remove previous level grid
	local existing = parentFrame:FindFirstChild("LevelGrid")
	if existing then existing:Destroy() end

	local gridFrame = Instance.new("Frame")
	gridFrame.Name = "LevelGrid"
	gridFrame.Size = UDim2.fromScale(0.9, 0.7)
	gridFrame.Position = UDim2.fromScale(0.05, 0.22)
	gridFrame.BackgroundTransparency = 1
	gridFrame.Parent = parentFrame

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromScale(0.3, 0.45)
	gridLayout.CellPadding = UDim2.fromScale(0.02, 0.03)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = gridFrame

	-- 6 levels per region
	for stage = 1, 6 do
		local levelNum = (regionNum - 1) * 6 + stage
		local completed = playerProgress and playerProgress[levelNum]
		local stars = completed and completed.stars or 0

		local card = Instance.new("Frame")
		card.Name = "Level_" .. levelNum
		card.BackgroundColor3 = Color3.fromRGB(40, 50, 90)
		card.LayoutOrder = stage
		card.Parent = gridFrame

		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 12)
		cardCorner.Parent = card

		local cardStroke = Instance.new("UIStroke")
		cardStroke.Thickness = 3
		cardStroke.Color = completed and Color3.fromRGB(0, 200, 100) or Color3.fromRGB(80, 90, 130)
		cardStroke.Parent = card

		-- Level number
		local levelLabel = Instance.new("TextLabel")
		levelLabel.Name = "LevelNum"
		levelLabel.Size = UDim2.fromScale(0.8, 0.3)
		levelLabel.Position = UDim2.fromScale(0.1, 0.05)
		levelLabel.BackgroundTransparency = 1
		levelLabel.Text = "Level " .. levelNum
		levelLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		levelLabel.Font = Enum.Font.GothamBold
		levelLabel.TextScaled = true
		levelLabel.Parent = card

		-- Stars display
		local starsLabel = Instance.new("TextLabel")
		starsLabel.Name = "Stars"
		starsLabel.Size = UDim2.fromScale(0.8, 0.2)
		starsLabel.Position = UDim2.fromScale(0.1, 0.35)
		starsLabel.BackgroundTransparency = 1
		local starText = ""
		for s = 1, 3 do
			starText = starText .. (s <= stars and "★" or "☆")
		end
		starsLabel.Text = starText
		starsLabel.TextColor3 = Color3.fromRGB(255, 200, 0)
		starsLabel.Font = Enum.Font.GothamBold
		starsLabel.TextScaled = true
		starsLabel.Parent = card

		-- Boss indicator
		if stage == 6 then
			local bossLabel = Instance.new("TextLabel")
			bossLabel.Name = "BossTag"
			bossLabel.Size = UDim2.fromScale(0.6, 0.15)
			bossLabel.Position = UDim2.fromScale(0.2, 0.55)
			bossLabel.BackgroundTransparency = 1
			bossLabel.Text = "BOSS"
			bossLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
			bossLabel.Font = Enum.Font.GothamBold
			bossLabel.TextScaled = true
			bossLabel.Parent = card
		end

		-- Play button
		local playBtn = Instance.new("TextButton")
		playBtn.Name = "PlayBtn"
		playBtn.Size = UDim2.fromScale(0.6, 0.2)
		playBtn.Position = UDim2.fromScale(0.2, 0.72)
		playBtn.BackgroundColor3 = COLORS.DeployButton
		playBtn.Text = "PLAY"
		playBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		playBtn.Font = Enum.Font.GothamBold
		playBtn.TextScaled = true
		playBtn.Parent = card

		local playCorner = Instance.new("UICorner")
		playCorner.CornerRadius = UDim.new(0, 8)
		playCorner.Parent = playBtn

		playBtn.MouseButton1Click:Connect(function()
			self:_startLevel(levelNum)
		end)
	end
end

function CampaignController:_startLevel(levelNum)
	if self._remotes then
		local startRemote = self._remotes:FindFirstChild("StartCampaignLevel")
		if startRemote then
			local result = startRemote:InvokeServer(levelNum)
			if result and result.success then
				self:hideCampaignSelect()
				self:showBattleUI(result.initialState)
			end
		end
	end
end

function CampaignController:hideCampaignSelect()
	if self._selectGui then
		self._selectGui:Destroy()
		self._selectGui = nil
	end
end

--------------------------------------------------------------------------------
-- Battle UI: full-screen lane-based battle
--------------------------------------------------------------------------------
function CampaignController:showBattleUI(initialState)
	if not self._initialized then return end
	self._inBattle = true

	-- Remove existing
	if self._battleGui then
		self._battleGui:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CampaignBattle"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = self._playerGui
	self._battleGui = screenGui

	-- Full-screen background
	local bgFrame = Instance.new("Frame")
	bgFrame.Name = "BattleBG"
	bgFrame.Size = UDim2.fromScale(1, 1)
	bgFrame.BackgroundColor3 = COLORS.Background
	bgFrame.BorderSizePixel = 0
	bgFrame.Parent = screenGui

	-- Lane area (main battle area)
	local laneFrame = Instance.new("Frame")
	laneFrame.Name = "LaneArea"
	laneFrame.Size = UDim2.fromScale(0.9, 0.55)
	laneFrame.Position = UDim2.fromScale(0.05, 0.05)
	laneFrame.BackgroundColor3 = COLORS.LaneGround
	laneFrame.BorderSizePixel = 0
	laneFrame.Parent = bgFrame

	local laneCorner = Instance.new("UICorner")
	laneCorner.CornerRadius = UDim.new(0, 12)
	laneCorner.Parent = laneFrame

	-- Player base (left, green rectangle with HP bar)
	local playerBase = Instance.new("Frame")
	playerBase.Name = "PlayerBase"
	playerBase.Size = UDim2.fromScale(0.08, 0.6)
	playerBase.Position = UDim2.fromScale(0.02, 0.2)
	playerBase.BackgroundColor3 = COLORS.PlayerBase
	playerBase.Parent = laneFrame

	local playerBaseCorner = Instance.new("UICorner")
	playerBaseCorner.CornerRadius = UDim.new(0, 8)
	playerBaseCorner.Parent = playerBase

	-- Player HP bar above base
	local playerHPBg = Instance.new("Frame")
	playerHPBg.Name = "PlayerHPBg"
	playerHPBg.Size = UDim2.fromScale(0.12, 0.06)
	playerHPBg.Position = UDim2.fromScale(0.01, 0.1)
	playerHPBg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	playerHPBg.Parent = laneFrame

	local playerHPCorner = Instance.new("UICorner")
	playerHPCorner.CornerRadius = UDim.new(0, 4)
	playerHPCorner.Parent = playerHPBg

	local playerHPFill = Instance.new("Frame")
	playerHPFill.Name = "PlayerHPFill"
	playerHPFill.Size = UDim2.fromScale(1, 0.8)
	playerHPFill.Position = UDim2.fromScale(0, 0.1)
	playerHPFill.BackgroundColor3 = COLORS.PlayerBase
	playerHPFill.BorderSizePixel = 0
	playerHPFill.Parent = playerHPBg

	local playerHPFillCorner = Instance.new("UICorner")
	playerHPFillCorner.CornerRadius = UDim.new(0, 3)
	playerHPFillCorner.Parent = playerHPFill

	-- Enemy base (right, red rectangle with HP bar)
	local enemyBase = Instance.new("Frame")
	enemyBase.Name = "EnemyBase"
	enemyBase.Size = UDim2.fromScale(0.08, 0.6)
	enemyBase.Position = UDim2.fromScale(0.9, 0.2)
	enemyBase.BackgroundColor3 = COLORS.EnemyBase
	enemyBase.Parent = laneFrame

	local enemyBaseCorner = Instance.new("UICorner")
	enemyBaseCorner.CornerRadius = UDim.new(0, 8)
	enemyBaseCorner.Parent = enemyBase

	-- Enemy HP bar above base
	local enemyHPBg = Instance.new("Frame")
	enemyHPBg.Name = "EnemyHPBg"
	enemyHPBg.Size = UDim2.fromScale(0.12, 0.06)
	enemyHPBg.Position = UDim2.fromScale(0.87, 0.1)
	enemyHPBg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	enemyHPBg.Parent = laneFrame

	local enemyHPCorner = Instance.new("UICorner")
	enemyHPCorner.CornerRadius = UDim.new(0, 4)
	enemyHPCorner.Parent = enemyHPBg

	local enemyHPFill = Instance.new("Frame")
	enemyHPFill.Name = "EnemyHPFill"
	enemyHPFill.Size = UDim2.fromScale(1, 0.8)
	enemyHPFill.Position = UDim2.fromScale(0, 0.1)
	enemyHPFill.BackgroundColor3 = COLORS.EnemyBase
	enemyHPFill.BorderSizePixel = 0
	enemyHPFill.Parent = enemyHPBg

	local enemyHPFillCorner = Instance.new("UICorner")
	enemyHPFillCorner.CornerRadius = UDim.new(0, 3)
	enemyHPFillCorner.Parent = enemyHPFill

	-- Entity container (where moving entities are displayed)
	local entityContainer = Instance.new("Frame")
	entityContainer.Name = "EntityContainer"
	entityContainer.Size = UDim2.fromScale(0.76, 0.8)
	entityContainer.Position = UDim2.fromScale(0.12, 0.1)
	entityContainer.BackgroundTransparency = 1
	entityContainer.Parent = laneFrame

	-- Energy bar (bottom-left)
	local energyFrame = Instance.new("Frame")
	energyFrame.Name = "EnergyFrame"
	energyFrame.Size = UDim2.fromScale(0.25, 0.06)
	energyFrame.Position = UDim2.fromScale(0.05, 0.65)
	energyFrame.BackgroundColor3 = COLORS.EnergyBg
	energyFrame.Parent = bgFrame

	local energyCorner = Instance.new("UICorner")
	energyCorner.CornerRadius = UDim.new(0, 8)
	energyCorner.Parent = energyFrame

	local energyStroke = Instance.new("UIStroke")
	energyStroke.Thickness = 2
	energyStroke.Color = COLORS.EnergyBar
	energyStroke.Parent = energyFrame

	local energyFill = Instance.new("Frame")
	energyFill.Name = "EnergyFill"
	energyFill.Size = UDim2.fromScale(0, 0.7)
	energyFill.Position = UDim2.fromScale(0.02, 0.15)
	energyFill.BackgroundColor3 = COLORS.EnergyBar
	energyFill.BorderSizePixel = 0
	energyFill.Parent = energyFrame

	local energyFillCorner = Instance.new("UICorner")
	energyFillCorner.CornerRadius = UDim.new(0, 4)
	energyFillCorner.Parent = energyFill

	local energyText = Instance.new("TextLabel")
	energyText.Name = "EnergyText"
	energyText.Size = UDim2.fromScale(1, 1)
	energyText.BackgroundTransparency = 1
	energyText.Text = "0 / 100"
	energyText.TextColor3 = Color3.fromRGB(255, 255, 255)
	energyText.Font = Enum.Font.GothamBold
	energyText.TextScaled = true
	energyText.ZIndex = 3
	energyText.Parent = energyFrame

	-- Pet deployment cards (bottom row)
	local cardsFrame = Instance.new("Frame")
	cardsFrame.Name = "DeployCards"
	cardsFrame.Size = UDim2.fromScale(0.9, 0.25)
	cardsFrame.Position = UDim2.fromScale(0.05, 0.73)
	cardsFrame.BackgroundTransparency = 1
	cardsFrame.Parent = bgFrame

	local cardsLayout = Instance.new("UIListLayout")
	cardsLayout.FillDirection = Enum.FillDirection.Horizontal
	cardsLayout.Padding = UDim.new(0, 8)
	cardsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	cardsLayout.Parent = cardsFrame

	-- Apply initial state
	if initialState then
		self:updateBattle(initialState)
	end
end

--------------------------------------------------------------------------------
-- Update Battle State from server
--------------------------------------------------------------------------------
function CampaignController:updateBattle(state)
	if not self._battleGui then return end

	local bgFrame = self._battleGui:FindFirstChild("BattleBG")
	if not bgFrame then return end

	local laneFrame = bgFrame:FindFirstChild("LaneArea")
	if not laneFrame then return end

	-- Update player HP
	if state.playerHP and state.playerMaxHP then
		local playerHPBg = laneFrame:FindFirstChild("PlayerHPBg")
		if playerHPBg then
			local fill = playerHPBg:FindFirstChild("PlayerHPFill")
			if fill then
				local fraction = math.clamp(state.playerHP / state.playerMaxHP, 0, 1)
				TweenService:Create(fill, TweenInfo.new(0.3), {
					Size = UDim2.fromScale(fraction, 0.8),
				}):Play()
			end
		end
	end

	-- Update enemy HP
	if state.enemyHP and state.enemyMaxHP then
		local enemyHPBg = laneFrame:FindFirstChild("EnemyHPBg")
		if enemyHPBg then
			local fill = enemyHPBg:FindFirstChild("EnemyHPFill")
			if fill then
				local fraction = math.clamp(state.enemyHP / state.enemyMaxHP, 0, 1)
				TweenService:Create(fill, TweenInfo.new(0.3), {
					Size = UDim2.fromScale(fraction, 0.8),
				}):Play()
			end
		end
	end

	-- Update energy
	if state.energy then
		self._energy = state.energy
		local energyFrame = bgFrame:FindFirstChild("EnergyFrame")
		if energyFrame then
			local fill = energyFrame:FindFirstChild("EnergyFill")
			local text = energyFrame:FindFirstChild("EnergyText")
			if fill then
				local fraction = math.clamp(state.energy / self._maxEnergy, 0, 1)
				TweenService:Create(fill, TweenInfo.new(0.2), {
					Size = UDim2.fromScale(fraction * 0.96, 0.7),
				}):Play()
			end
			if text then
				text.Text = tostring(math.floor(state.energy)) .. " / " .. tostring(self._maxEnergy)
			end
		end
	end

	-- Update entities on the lane
	local entityContainer = laneFrame:FindFirstChild("EntityContainer")
	if entityContainer and state.entities then
		-- Clear old entities
		for _, child in ipairs(entityContainer:GetChildren()) do
			child:Destroy()
		end

		for _, entity in ipairs(state.entities) do
			local dot = Instance.new("Frame")
			dot.Name = "Entity_" .. (entity.id or "unknown")

			-- Size based on entity type
			local size = entity.isBoss and 0.06 or 0.035
			dot.Size = UDim2.fromScale(size, size * 1.5)

			-- Position based on lane position (0 = left/player side, 1 = right/enemy side)
			local xPos = math.clamp(entity.lanePosition or 0.5, 0, 1)
			local yPos = entity.lane and (entity.lane / 4) or 0.5
			dot.Position = UDim2.fromScale(xPos, yPos - size / 2)

			-- Color: player pets are colored by rarity, enemies are red
			if entity.isEnemy then
				dot.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
			else
				local rarityColor = RARITY_COLORS[entity.rarity or "Common"]
				dot.BackgroundColor3 = rarityColor or RARITY_COLORS.Common
			end

			dot.BorderSizePixel = 0
			dot.Parent = entityContainer

			local dotCorner = Instance.new("UICorner")
			dotCorner.CornerRadius = UDim.new(1, 0)
			dotCorner.Parent = dot

			-- HP text above entity
			if entity.hp and entity.maxHP then
				local hpLabel = Instance.new("TextLabel")
				hpLabel.Size = UDim2.fromScale(2, 0.6)
				hpLabel.Position = UDim2.fromScale(-0.5, -0.7)
				hpLabel.BackgroundTransparency = 1
				hpLabel.Text = tostring(math.floor(entity.hp))
				hpLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
				hpLabel.Font = Enum.Font.GothamBold
				hpLabel.TextScaled = true
				hpLabel.Parent = dot
			end
		end
	end

	-- Update deployment cards
	if state.availablePets then
		self:_updateDeployCards(bgFrame, state.availablePets)
	end
end

function CampaignController:_updateDeployCards(bgFrame, availablePets)
	local cardsFrame = bgFrame:FindFirstChild("DeployCards")
	if not cardsFrame then return end

	-- Clear old cards (keep layout)
	for _, child in ipairs(cardsFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	self._deployCards = {}

	for i, petInfo in ipairs(availablePets) do
		local card = Instance.new("Frame")
		card.Name = "Card_" .. (petInfo.name or i)
		card.Size = UDim2.fromOffset(90, 120)
		card.BackgroundColor3 = COLORS.CardBg
		card.LayoutOrder = i
		card.Parent = cardsFrame

		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 10)
		cardCorner.Parent = card

		local cardStroke = Instance.new("UIStroke")
		cardStroke.Thickness = 3
		cardStroke.Color = RARITY_COLORS[petInfo.rarity or "Common"] or RARITY_COLORS.Common
		cardStroke.Parent = card

		-- Pet icon (colored circle)
		local icon = Instance.new("Frame")
		icon.Name = "Icon"
		icon.Size = UDim2.fromScale(0.5, 0.35)
		icon.Position = UDim2.fromScale(0.25, 0.05)
		icon.BackgroundColor3 = RARITY_COLORS[petInfo.rarity or "Common"] or RARITY_COLORS.Common
		icon.Parent = card

		local iconCorner = Instance.new("UICorner")
		iconCorner.CornerRadius = UDim.new(1, 0)
		iconCorner.Parent = icon

		-- Pet name
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "PetName"
		nameLabel.Size = UDim2.fromScale(0.9, 0.18)
		nameLabel.Position = UDim2.fromScale(0.05, 0.42)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = petInfo.name or "Pet"
		nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextScaled = true
		nameLabel.Parent = card

		-- Energy cost
		local costLabel = Instance.new("TextLabel")
		costLabel.Name = "Cost"
		costLabel.Size = UDim2.fromScale(0.9, 0.15)
		costLabel.Position = UDim2.fromScale(0.05, 0.6)
		costLabel.BackgroundTransparency = 1
		costLabel.Text = "Cost: " .. tostring(petInfo.energyCost or 10)
		costLabel.TextColor3 = COLORS.EnergyBar
		costLabel.Font = Enum.Font.GothamBold
		costLabel.TextScaled = true
		costLabel.Parent = card

		-- Deploy button
		local deployBtn = Instance.new("TextButton")
		deployBtn.Name = "DeployBtn"
		deployBtn.Size = UDim2.fromScale(0.8, 0.18)
		deployBtn.Position = UDim2.fromScale(0.1, 0.78)
		deployBtn.BackgroundColor3 = COLORS.DeployButton
		deployBtn.Text = "DEPLOY"
		deployBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		deployBtn.Font = Enum.Font.GothamBold
		deployBtn.TextScaled = true
		deployBtn.Parent = card

		local deployCorner = Instance.new("UICorner")
		deployCorner.CornerRadius = UDim.new(0, 6)
		deployCorner.Parent = deployBtn

		-- Deploy on click
		local petId = petInfo.uniqueId or petInfo.id
		deployBtn.MouseButton1Click:Connect(function()
			self:_deployPet(petId)
		end)

		table.insert(self._deployCards, card)
	end
end

function CampaignController:_deployPet(petId)
	if self._remotes then
		local deployRemote = self._remotes:FindFirstChild("DeployPetInCampaign")
		if deployRemote then
			deployRemote:InvokeServer(petId)
		end
	end
end

--------------------------------------------------------------------------------
-- Victory Screen
--------------------------------------------------------------------------------
function CampaignController:onVictory(rewards)
	if not self._battleGui then return end
	self._inBattle = false

	local bgFrame = self._battleGui:FindFirstChild("BattleBG")
	if not bgFrame then return end

	-- Overlay
	local overlay = Instance.new("Frame")
	overlay.Name = "VictoryOverlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 0.5
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 10
	overlay.Parent = bgFrame

	-- Victory panel
	local panel = Instance.new("Frame")
	panel.Name = "VictoryPanel"
	panel.Size = UDim2.fromScale(0.5, 0.6)
	panel.Position = UDim2.fromScale(0.25, 0.2)
	panel.BackgroundColor3 = Color3.fromRGB(30, 40, 80)
	panel.ZIndex = 11
	panel.Parent = overlay

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 16)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Thickness = 4
	panelStroke.Color = COLORS.Victory
	panelStroke.Parent = panel

	-- Victory text
	local victoryText = Instance.new("TextLabel")
	victoryText.Size = UDim2.fromScale(0.8, 0.2)
	victoryText.Position = UDim2.fromScale(0.1, 0.05)
	victoryText.BackgroundTransparency = 1
	victoryText.Text = "VICTORY!"
	victoryText.TextColor3 = COLORS.Victory
	victoryText.Font = Enum.Font.GothamBold
	victoryText.TextScaled = true
	victoryText.ZIndex = 12
	victoryText.Parent = panel

	-- Rewards breakdown
	local rewardsText = ""
	if rewards then
		if rewards.Coins then
			rewardsText = rewardsText .. "Coins: +" .. tostring(rewards.Coins) .. "\n"
		end
		if rewards.Diamonds then
			rewardsText = rewardsText .. "Diamonds: +" .. tostring(rewards.Diamonds) .. "\n"
		end
		if rewards.SpecialEgg then
			rewardsText = rewardsText .. "Special Egg Earned!\n"
		end
	end

	local rewardsLabel = Instance.new("TextLabel")
	rewardsLabel.Size = UDim2.fromScale(0.8, 0.4)
	rewardsLabel.Position = UDim2.fromScale(0.1, 0.3)
	rewardsLabel.BackgroundTransparency = 1
	rewardsLabel.Text = rewardsText
	rewardsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	rewardsLabel.Font = Enum.Font.GothamBold
	rewardsLabel.TextScaled = true
	rewardsLabel.ZIndex = 12
	rewardsLabel.Parent = panel

	-- Continue button
	local continueBtn = Instance.new("TextButton")
	continueBtn.Name = "ContinueBtn"
	continueBtn.Size = UDim2.fromScale(0.5, 0.15)
	continueBtn.Position = UDim2.fromScale(0.25, 0.78)
	continueBtn.BackgroundColor3 = COLORS.DeployButton
	continueBtn.Text = "CONTINUE"
	continueBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	continueBtn.Font = Enum.Font.GothamBold
	continueBtn.TextScaled = true
	continueBtn.ZIndex = 12
	continueBtn.Parent = panel

	local continueCorner = Instance.new("UICorner")
	continueCorner.CornerRadius = UDim.new(0, 10)
	continueCorner.Parent = continueBtn

	continueBtn.MouseButton1Click:Connect(function()
		self:hideBattle()
	end)
end

--------------------------------------------------------------------------------
-- Defeat Screen
--------------------------------------------------------------------------------
function CampaignController:onDefeat()
	if not self._battleGui then return end
	self._inBattle = false

	local bgFrame = self._battleGui:FindFirstChild("BattleBG")
	if not bgFrame then return end

	-- Overlay
	local overlay = Instance.new("Frame")
	overlay.Name = "DefeatOverlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 0.5
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 10
	overlay.Parent = bgFrame

	-- Defeat panel
	local panel = Instance.new("Frame")
	panel.Name = "DefeatPanel"
	panel.Size = UDim2.fromScale(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.25, 0.25)
	panel.BackgroundColor3 = Color3.fromRGB(30, 40, 80)
	panel.ZIndex = 11
	panel.Parent = overlay

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 16)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Thickness = 4
	panelStroke.Color = COLORS.Defeat
	panelStroke.Parent = panel

	-- Defeat text
	local defeatText = Instance.new("TextLabel")
	defeatText.Size = UDim2.fromScale(0.8, 0.25)
	defeatText.Position = UDim2.fromScale(0.1, 0.1)
	defeatText.BackgroundTransparency = 1
	defeatText.Text = "DEFEATED"
	defeatText.TextColor3 = COLORS.Defeat
	defeatText.Font = Enum.Font.GothamBold
	defeatText.TextScaled = true
	defeatText.ZIndex = 12
	defeatText.Parent = panel

	-- Retry button
	local retryBtn = Instance.new("TextButton")
	retryBtn.Name = "RetryBtn"
	retryBtn.Size = UDim2.fromScale(0.4, 0.18)
	retryBtn.Position = UDim2.fromScale(0.05, 0.7)
	retryBtn.BackgroundColor3 = Color3.fromRGB(200, 150, 0)
	retryBtn.Text = "RETRY"
	retryBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	retryBtn.Font = Enum.Font.GothamBold
	retryBtn.TextScaled = true
	retryBtn.ZIndex = 12
	retryBtn.Parent = panel

	local retryCorner = Instance.new("UICorner")
	retryCorner.CornerRadius = UDim.new(0, 10)
	retryCorner.Parent = retryBtn

	-- Exit button
	local exitBtn = Instance.new("TextButton")
	exitBtn.Name = "ExitBtn"
	exitBtn.Size = UDim2.fromScale(0.4, 0.18)
	exitBtn.Position = UDim2.fromScale(0.55, 0.7)
	exitBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
	exitBtn.Text = "EXIT"
	exitBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	exitBtn.Font = Enum.Font.GothamBold
	exitBtn.TextScaled = true
	exitBtn.ZIndex = 12
	exitBtn.Parent = panel

	local exitCorner = Instance.new("UICorner")
	exitCorner.CornerRadius = UDim.new(0, 10)
	exitCorner.Parent = exitBtn

	retryBtn.MouseButton1Click:Connect(function()
		self:hideBattle()
		-- Re-open campaign select for retry
	end)

	exitBtn.MouseButton1Click:Connect(function()
		self:hideBattle()
	end)
end

--------------------------------------------------------------------------------
-- Hide battle UI
--------------------------------------------------------------------------------
function CampaignController:hideBattle()
	self._inBattle = false
	if self._battleGui then
		self._battleGui:Destroy()
		self._battleGui = nil
	end
end

function CampaignController:isInBattle()
	return self._inBattle
end

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------
function CampaignController:cleanup()
	self:hideBattle()
	self:hideCampaignSelect()
end

return CampaignController
