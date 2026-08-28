--[[
	EffectsController.lua - Visual effects system for Battle Pets
	Handles floating number popups, egg hatching animations, zone unlock effects,
	and progress bars above destructibles. All visuals are procedural (no external assets).
]]

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetVariantPresentation = require(Shared:WaitForChild("PetVariantPresentation"))
local HatchCinematicPolicy = require(Shared:WaitForChild("HatchCinematicPolicy"))

local EffectsController = {}
EffectsController.__index = EffectsController

-- Rarity colors used across the game
local RARITY_COLORS = {
	Common = Color3.fromRGB(255, 255, 255),
	Uncommon = Color3.fromRGB(0, 200, 0),
	Rare = Color3.fromRGB(0, 120, 255),
	Epic = Color3.fromRGB(180, 0, 255),
	Legendary = Color3.fromRGB(255, 200, 0),
}

local function rgbToColor(rgb)
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

function EffectsController.new()
	local self = setmetatable({}, EffectsController)
	self._progressBars = {}
	self._critButtons = {}
	self._activePopups = {}
	self._initialized = false
	self._lastHatchPosition = nil
	self._isHatching = false
	self._hatchPresentationQueue = {}
	self._hatchPresentationActive = false
	self._activeHatchScope = nil
	self._finalizingHatchScope = nil
	self._hatchCleanupCallbacks = {}
	self._seenHatchBatchIds = {}
	self._seenHatchBatchOrder = {}
	return self
end

function EffectsController:init()
	self._player = Players.LocalPlayer
	self._playerGui = self._player:WaitForChild("PlayerGui")
	self._effectsFolder = Instance.new("Folder")
	self._effectsFolder.Name = "ClientEffects"
	self._effectsFolder.Parent = workspace
	self._characterRemovingConnection = self._player.CharacterRemoving:Connect(function()
		self:cancelEggHatch("character_removed")
	end)
	self._initialized = true
end

--------------------------------------------------------------------------------
-- Currency Popup: floating text like "+5" in yellow or "+2" in cyan
-- Enhanced: scales in from small, flies upward, and fades out smoothly
--------------------------------------------------------------------------------
function EffectsController:showCurrencyPopup(position, amount, currencyType)
	if not self._initialized then return end

	-- Limit active popups to 5 max to prevent Part spam
	local MAX_POPUPS = 5
	while #self._activePopups >= MAX_POPUPS do
		local oldest = table.remove(self._activePopups, 1)
		if oldest.billboard and oldest.billboard.Parent then
			oldest.billboard:Destroy()
		end
		if oldest.anchor and oldest.anchor.Parent then
			oldest.anchor:Destroy()
		end
	end

	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "CurrencyPopup"
	billboardGui.Size = UDim2.fromOffset(160, 60)
	billboardGui.StudsOffset = Vector3.new(0, 2, 0)
	billboardGui.AlwaysOnTop = true
	billboardGui.Adornee = nil

	-- Create an anchor part at the position
	local anchor = Instance.new("Part")
	anchor.Name = "PopupAnchor"
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Position = position
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Parent = self._effectsFolder

	billboardGui.Adornee = anchor
	billboardGui.Parent = self._playerGui

	-- Track this popup for limit enforcement
	local popupEntry = { billboard = billboardGui, anchor = anchor }
	table.insert(self._activePopups, popupEntry)

	local color = Color3.fromRGB(255, 220, 0)  -- yellow for coins
	local prefix = "+$"
	if currencyType == "Diamonds" then
		color = Color3.fromRGB(0, 220, 255)  -- cyan for diamonds
		prefix = "+"
	end

	local label = Instance.new("TextLabel")
	label.Name = "PopupText"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = prefix .. tostring(amount)
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0.2
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = billboardGui

	-- Start small and scale up (juice!)
	billboardGui.Size = UDim2.fromOffset(40, 15)
	local scaleInInfo = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(billboardGui, scaleInInfo, {
		Size = UDim2.fromOffset(160, 60),
	}):Play()

	-- Fly upward and fade out after a short delay
	local flyInfo = TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local flyTween = TweenService:Create(anchor, flyInfo, {
		Position = position + Vector3.new(math.random(-1, 1) * 0.5, 5, math.random(-1, 1) * 0.5),
	})

	-- Delayed fade (stay visible for a bit, then fade)
	task.delay(0.6, function()
		if not label or not label.Parent then return end
		local fadeInfo = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local fadeTween = TweenService:Create(label, fadeInfo, {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		fadeTween:Play()
	end)

	flyTween:Play()

	-- Cleanup after animation
	task.delay(2.0, function()
		if billboardGui and billboardGui.Parent then
			billboardGui:Destroy()
		end
		if anchor and anchor.Parent then
			anchor:Destroy()
		end
		-- Remove from active popups tracking
		for i, entry in ipairs(self._activePopups) do
			if entry.billboard == billboardGui then
				table.remove(self._activePopups, i)
				break
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- QOF-09 Egg Hatch Presentation
-- EffectsController owns the lossless FIFO and renders one complete batch in one
-- responsive ScreenGui. UIController remains the only result-grid owner.
--------------------------------------------------------------------------------

-- QOF-09 constants. Sound IDs are intentionally blank until product-owned
-- assets are configured; blank cues never create Sound instances.
local HATCH_START_TIMEOUT = 2.25
local HATCH_SEEN_CACHE_LIMIT = 128
local HATCH_PARTICLE_LIMIT = 24
local HATCH_SOUND_IDS = { Pop = "", RareAccent = "", Hero = "" }
local UPGRADE_TREE_GUI_NAME = "UpgradeTreeGui"

local function shallowCopy(source)
	local copy = {}
	for key, value in pairs(source) do copy[key] = value end
	return copy
end

local function safeDisconnect(connection)
	if connection then pcall(function() connection:Disconnect() end) end
end

local function safeCancel(tween)
	if tween then pcall(function() tween:Cancel() end) end
end

local function findVisibleUpgradeTreeOverlay(playerGui)
	for _, child in ipairs(playerGui:GetChildren()) do
		if child.Name == UPGRADE_TREE_GUI_NAME and child:IsA("ScreenGui") then
			for _, directChild in ipairs(child:GetChildren()) do
				if directChild:IsA("GuiObject") and directChild.Visible then
					return directChild
				end
			end
		end
	end
	return nil
end

local function releaseHeroFovOwnership(scope)
	if scope.heroFovOwnershipReleased then return end
	scope.heroFovOwnershipReleased = true
	scope.heroFovOwned = false
	safeCancel(scope.heroFovTween)
	scope.heroFovTween = nil
end

local function observeUpgradeTreeFovConflict(scope, playerGui)
	local observedGuis = {}
	local observedOverlays = {}

	local function observeOverlay(overlay)
		if not overlay:IsA("GuiObject") or observedOverlays[overlay] then return end
		observedOverlays[overlay] = true
		if overlay.Visible then releaseHeroFovOwnership(scope) end
		table.insert(scope.connections, overlay:GetPropertyChangedSignal("Visible"):Connect(function()
			if overlay.Visible then releaseHeroFovOwnership(scope) end
		end))
	end

	local function observeGui(gui)
		if gui.Name ~= UPGRADE_TREE_GUI_NAME or not gui:IsA("ScreenGui") or observedGuis[gui] then return end
		observedGuis[gui] = true
		for _, child in ipairs(gui:GetChildren()) do observeOverlay(child) end
		table.insert(scope.connections, gui.ChildAdded:Connect(observeOverlay))
	end

	table.insert(scope.connections, playerGui.ChildAdded:Connect(observeGui))
	for _, child in ipairs(playerGui:GetChildren()) do observeGui(child) end
end

local function scopeWait(controller, scope, duration)
	if duration > 0 then task.wait(duration) end
	return controller._activeHatchScope == scope and not scope.finished
end

local function getBatchId(payload)
	local batchId = type(payload) == "table" and payload.batchId or nil
	return type(batchId) == "string" and batchId ~= "" and batchId or nil
end

local function normalizeHatchPayload(payload)
	if type(payload) ~= "table" then return nil end
	local sourcePets = type(payload.pets) == "table" and payload.pets or { payload }
	local pets = {}
	for _, petData in ipairs(sourcePets) do
		if type(petData) == "table" then
			table.insert(pets, petData)
			if #pets == HatchCinematicPolicy.MAX_PETS then break end
		end
	end
	if #pets == 0 then return nil end
	local normalized = shallowCopy(payload)
	normalized.batchId = getBatchId(payload)
	normalized.count = #pets
	normalized.pets = pets
	return normalized
end

local function trackTween(scope, tween)
	table.insert(scope.tweens, tween)
	tween:Play()
	return tween
end

local function addCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

function EffectsController:_playHatchSound(scope, cue)
	local soundId = HATCH_SOUND_IDS[cue]
	if type(soundId) ~= "string" or soundId == "" then return end
	local sound = Instance.new("Sound")
	sound.Name = "QOF09_" .. cue
	sound.SoundId = soundId
	sound.Volume = 0.65
	sound.Parent = scope.screenGui
	table.insert(scope.sounds, sound)
	sound:Play()
end

function EffectsController:_layoutHatchCards(scope)
	local size = scope.overlay.AbsoluteSize
	local count = #scope.cards
	if size.X <= 0 or size.Y <= 0 or count == 0 then return end
	local narrow = size.X < 700 or size.Y > size.X
	local columns = count == 1 and 1 or (narrow and math.min(2, count) or math.min(5, count))
	local rows = math.ceil(count / columns)
	local gap = narrow and (rows >= 4 and 5 or 8) or 12
	local horizontalPadding = narrow and 12 or 24
	local topReserve = narrow and 66 or 74
	local bottomReserve = narrow and 72 or 80
	local availableWidth = math.max(1, math.min(size.X - horizontalPadding * 2, 980))
	local availableHeight = math.max(1, math.min(size.Y - topReserve - bottomReserve, 620))
	local cardWidth = math.floor((availableWidth - gap * (columns - 1)) / columns)
	local cardHeight = math.floor((availableHeight - gap * (rows - 1)) / rows)
	cardWidth = math.max(1, math.min(cardWidth, count == 1 and 260 or 184))
	cardHeight = math.max(1, math.min(cardHeight, count == 1 and 300 or 210))
	local gridWidth = columns * cardWidth + (columns - 1) * gap
	local gridHeight = rows * cardHeight + (rows - 1) * gap
	scope.stage.Size = UDim2.fromOffset(gridWidth, gridHeight)
	scope.stage.Position = UDim2.new(0.5, 0, 0, topReserve + availableHeight * 0.5)

	for index, card in ipairs(scope.cards) do
		local row = math.floor((index - 1) / columns)
		local column = (index - 1) % columns
		local rowCount = math.min(columns, count - row * columns)
		local rowWidth = rowCount * cardWidth + (rowCount - 1) * gap
		card.frame.Size = UDim2.fromOffset(cardWidth, cardHeight)
		card.frame.Position = UDim2.fromOffset(
			(gridWidth - rowWidth) * 0.5 + column * (cardWidth + gap),
			row * (cardHeight + gap)
		)
	end
end

function EffectsController:_createHatchCard(scope, index)
	local frame = Instance.new("Frame")
	frame.Name = "Egg_" .. tostring(index)
	frame.BackgroundColor3 = Color3.fromRGB(26, 29, 44)
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	frame.Parent = scope.stage
	addCorner(frame, 16)

	local stroke = Instance.new("UIStroke")
	stroke.Name = "AccentStroke"
	stroke.Color = Color3.fromRGB(120, 130, 160)
	stroke.Thickness = 2
	stroke.Transparency = 0.25
	stroke.Parent = frame
	local scale = Instance.new("UIScale")
	scale.Parent = frame

	local egg = Instance.new("Frame")
	egg.Name = "EggShell"
	egg.Size = UDim2.fromScale(0.38, 0.58)
	egg.Position = UDim2.fromScale(0.5, 0.48)
	egg.AnchorPoint = Vector2.new(0.5, 0.5)
	egg.BackgroundColor3 = Color3.fromRGB(255, 248, 220)
	egg.BorderSizePixel = 0
	egg.Parent = frame
	addCorner(egg, 999)
	local eggStroke = Instance.new("UIStroke")
	eggStroke.Color = Color3.fromRGB(210, 190, 140)
	eggStroke.Thickness = 2
	eggStroke.Parent = egg

	local result = Instance.new("Frame")
	result.Name = "Result"
	result.Size = UDim2.fromScale(1, 1)
	result.BackgroundTransparency = 1
	result.Visible = false
	result.Parent = frame
	local accent = Instance.new("Frame")
	accent.Name = "VariantAccent"
	accent.Size = UDim2.new(1, 0, 0, 7)
	accent.BackgroundColor3 = Color3.fromRGB(160, 170, 190)
	accent.BorderSizePixel = 0
	accent.Parent = result

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "PetName"
	nameLabel.Size = UDim2.new(1, -12, 0.46, 0)
	nameLabel.Position = UDim2.new(0, 6, 0.14, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	nameLabel.TextStrokeTransparency = 0.35
	nameLabel.TextScaled = true
	nameLabel.TextWrapped = true
	nameLabel.Parent = result
	local rarityLabel = Instance.new("TextLabel")
	rarityLabel.Name = "Rarity"
	rarityLabel.Size = UDim2.new(1, -12, 0.22, 0)
	rarityLabel.Position = UDim2.new(0, 6, 0.61, 0)
	rarityLabel.BackgroundTransparency = 1
	rarityLabel.Font = Enum.Font.GothamBold
	rarityLabel.TextScaled = true
	rarityLabel.Parent = result
	local variantLabel = Instance.new("TextLabel")
	variantLabel.Name = "Variant"
	variantLabel.Size = UDim2.new(1, -12, 0.16, 0)
	variantLabel.Position = UDim2.new(0, 6, 0.82, 0)
	variantLabel.BackgroundTransparency = 1
	variantLabel.Font = Enum.Font.GothamMedium
	variantLabel.TextScaled = true
	variantLabel.Parent = result

	trackTween(scope, TweenService:Create(
		egg,
		TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Rotation = index % 2 == 0 and -10 or 10 }
	))
	return {
		frame = frame, stroke = stroke, scale = scale, egg = egg, result = result,
		accent = accent, nameLabel = nameLabel, rarityLabel = rarityLabel,
		variantLabel = variantLabel,
	}
end

function EffectsController:_createHatchScope(payload, waitingForResult, scope)
	local count = math.clamp(math.floor(tonumber(payload.count) or 1), 1, HatchCinematicPolicy.MAX_PETS)
	scope = scope or {}
	scope.batchId = getBatchId(payload)
	scope.waitingForResult = waitingForResult
	scope.finished = false
	scope.cards = {}
	scope.tweens = {}
	scope.connections = {}
	scope.sounds = {}
	scope.animatedGradients = {}
	scope.lightStrips = {}
	scope.particleCount = 0
	local screenGui = Instance.new("ScreenGui")
	scope.screenGui = screenGui
	screenGui.Name = "EffectsController_QOF09Hatch"
	screenGui.DisplayOrder = 50
	screenGui.IgnoreGuiInset = false
	screenGui.ResetOnSpawn = false
	pcall(function() screenGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)
	screenGui.Parent = self._playerGui
	local overlay = Instance.new("Frame")
	overlay.Name = "HatchOverlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(5, 7, 15)
	overlay.BackgroundTransparency = 0.18
	overlay.BorderSizePixel = 0
	overlay.Parent = screenGui
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(0.8, 0, 0, 42)
	title.Position = UDim2.new(0.1, 0, 0.045, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.Text = waitingForResult and "HATCHING..." or "HATCH RESULTS"
	title.TextColor3 = Color3.fromRGB(255, 245, 210)
	title.TextScaled = true
	title.Parent = overlay
	local stage = Instance.new("Frame")
	stage.Name = "BatchStage"
	stage.Position = UDim2.fromScale(0.5, 0.49)
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.BackgroundTransparency = 1
	stage.Parent = overlay
	local skipButton = Instance.new("TextButton")
	skipButton.Name = "Skip"
	skipButton.Size = UDim2.fromOffset(132, 52)
	skipButton.Position = UDim2.new(1, -20, 1, -20)
	skipButton.AnchorPoint = Vector2.new(1, 1)
	skipButton.BackgroundColor3 = Color3.fromRGB(35, 40, 60)
	skipButton.Font = Enum.Font.GothamBold
	skipButton.Text = waitingForResult and "WAITING" or "SKIP"
	skipButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	skipButton.TextSize = 20
	skipButton.Active = not waitingForResult
	skipButton.AutoButtonColor = not waitingForResult
	skipButton.Parent = overlay
	addCorner(skipButton, 12)
	local skipStroke = Instance.new("UIStroke")
	skipStroke.Color = Color3.fromRGB(190, 200, 230)
	skipStroke.Thickness = 2
	skipStroke.Parent = skipButton

	scope.overlay = overlay
	scope.title = title
	scope.stage = stage
	scope.skipButton = skipButton
	for index = 1, count do table.insert(scope.cards, self:_createHatchCard(scope, index)) end
	self:_layoutHatchCards(scope)
	-- Exactly one AbsoluteSize reflow connection belongs to this scope.
	table.insert(scope.connections, overlay:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if self._activeHatchScope == scope and not scope.finished then self:_layoutHatchCards(scope) end
	end))
	table.insert(scope.connections, skipButton.Activated:Connect(function() self:skipEggHatch() end))
	table.insert(scope.connections, screenGui.Destroying:Connect(function()
		if not scope.destroying then self:_finalizeHatchScope(scope, "gui_destroyed") end
	end))
	return scope
end

function EffectsController:_addHatchParticle(scope, parent, color)
	if scope.particleCount >= HATCH_PARTICLE_LIMIT then return end
	scope.particleCount += 1
	local particle = Instance.new("TextLabel")
	particle.Name = "VariantStar"
	particle.Size = UDim2.fromOffset(18, 18)
	particle.Position = UDim2.fromScale(0.15 + math.random() * 0.7, 0.2 + math.random() * 0.6)
	particle.AnchorPoint = Vector2.new(0.5, 0.5)
	particle.BackgroundTransparency = 1
	particle.Font = Enum.Font.GothamBold
	particle.Text = "*"
	particle.TextColor3 = color
	particle.TextScaled = true
	particle.ZIndex = 8
	particle.Parent = parent
	trackTween(scope, TweenService:Create(particle,
		TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = particle.Position - UDim2.fromOffset(0, 22),
			TextTransparency = 1,
			Rotation = math.random(-45, 45),
		}))
end

function EffectsController:_configureVariantCard(scope, card, petData, entry)
	local presentation = PetVariantPresentation.resolve(petData)
	local rarity = petData.rarity or "Common"
	local rarityColor = RARITY_COLORS[rarity] or RARITY_COLORS.Common
	local accentColor = presentation.baseVariant == "Normal" and rarityColor or rgbToColor(presentation.accentRGB)
	if presentation.isShiny then accentColor = rgbToColor(presentation.shinyRGB) end
	card.nameLabel.Text = presentation.displayPetName
	card.rarityLabel.Text = rarity
	card.rarityLabel.TextColor3 = rarityColor
	card.variantLabel.Text = presentation.variantLabel
	card.variantLabel.TextColor3 = accentColor
	card.accent.BackgroundColor3 = accentColor
	card.stroke.Color = accentColor

	if presentation.baseVariant == "Golden" then
		card.stroke.Thickness = 4
		card.stroke.Transparency = 0
		for _ = 1, 3 do self:_addHatchParticle(scope, card.frame, Color3.fromRGB(255, 220, 70)) end
	end
	if presentation.baseVariant == "Rainbow" then
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 110)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(90, 230, 255)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(150, 100, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 220, 70)),
		})
		gradient.Parent = card.accent
		table.insert(scope.animatedGradients, gradient)
	end
	if presentation.isShiny then
		for _ = 1, 3 do self:_addHatchParticle(scope, card.frame, Color3.fromRGB(190, 250, 255)) end
		local strip = Instance.new("Frame")
		strip.Name = "ShinyLightStrip"
		strip.Size = UDim2.new(0, 18, 1.4, 0)
		strip.Position = UDim2.new(0, -24, -0.2, 0)
		strip.Rotation = 16
		strip.BackgroundColor3 = Color3.fromRGB(235, 255, 255)
		strip.BackgroundTransparency = 0.32
		strip.BorderSizePixel = 0
		strip.ZIndex = 7
		strip.Parent = card.result
		table.insert(scope.lightStrips, strip)
	end
	if entry.classification ~= "Normal" and not entry.isHero then
		trackTween(scope, TweenService:Create(card.stroke,
			TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 1, true),
			{ Thickness = math.max(card.stroke.Thickness, 4), Transparency = 0 }))
	end
end

function EffectsController:_startVariantAnimation(scope)
	if #scope.animatedGradients == 0 and #scope.lightStrips == 0 then return end
	local startedAt = os.clock()
	table.insert(scope.connections, RunService.RenderStepped:Connect(function()
		if self._activeHatchScope ~= scope or scope.finished then return end
		local elapsed = os.clock() - startedAt
		for _, gradient in ipairs(scope.animatedGradients) do
			if gradient.Parent then gradient.Rotation = (elapsed * 150) % 360 end
		end
		for _, strip in ipairs(scope.lightStrips) do
			if strip.Parent then strip.Position = UDim2.new((elapsed * 1.8) % 1.4 - 0.2, -10, -0.2, 0) end
		end
	end))
end

function EffectsController:_finalizeHatchScope(scope, reason)
	if not scope or scope.finished then return end
	scope.finished = true

	-- The presentation gate remains held through the result callback. This makes
	-- GUI/FOV teardown, result-grid presentation, discovery queueing, and FIFO
	-- advancement one serialized exactly-once operation.
	self._hatchPresentationActive = true
	self._finalizingHatchScope = scope
	if scope.heroFovOwned and findVisibleUpgradeTreeOverlay(self._playerGui) then
		releaseHeroFovOwnership(scope)
	end
	for _, tween in ipairs(scope.tweens) do safeCancel(tween) end
	for _, connection in ipairs(scope.connections) do safeDisconnect(connection) end
	for _, sound in ipairs(scope.sounds) do
		pcall(function() sound:Stop() sound:Destroy() end)
	end
	if scope.heroFovOwned and scope.camera and scope.cameraFieldOfView then
		pcall(function() scope.camera.FieldOfView = scope.cameraFieldOfView end)
		scope.heroFovOwned = false
	end
	scope.destroying = true
	if scope.screenGui and scope.screenGui.Parent then pcall(function() scope.screenGui:Destroy() end) end
	if self._activeHatchScope == scope then self._activeHatchScope = nil end
	self._lastHatchPosition = nil
	local onPresented = scope.onPresented
	scope.onPresented = nil
	task.defer(function()
		if type(onPresented) == "function" then
			local callbackSucceeded, callbackError = xpcall(function() onPresented(reason) end, debug.traceback)
			if not callbackSucceeded then
				warn("[EffectsController] Hatch callback recovered from an error:\n" .. tostring(callbackError))
			end
		end

		-- cleanup() may add callbacks while an active/finalizing scope is being
		-- torn down. Drain them in FIFO order under the same presentation gate.
		while #self._hatchCleanupCallbacks > 0 do
			local pending = table.remove(self._hatchCleanupCallbacks, 1)
			local callbackSucceeded, callbackError = xpcall(function()
				pending.onPresented(pending.reason)
			end, debug.traceback)
			if not callbackSucceeded then
				warn("[EffectsController] Queued hatch cleanup callback failed:\n" .. tostring(callbackError))
			end
		end

		-- A stale task from an older scope may arrive after cancellation. It must
		-- never release the gate owned by a newer finalizer.
		if self._finalizingHatchScope ~= scope then return end
		self._finalizingHatchScope = nil
		self._hatchPresentationActive = false
		self._isHatching = false
		self:_processHatchPresentationQueue()
	end)
end

function EffectsController:_runHatchPresentation(scope, item)
	task.spawn(function()
		local succeeded, failure = xpcall(function()
			local pets = item.payload.pets
			local plan = HatchCinematicPolicy.buildPlan(pets)
			if plan.count == 0 then return end
			scope.title.Text = plan.hasRare and "RARE HATCH!" or "HATCH RESULTS"
			scope.waitingForResult = false
			for _, tween in ipairs(scope.tweens) do safeCancel(tween) end
			scope.tweens = {}
			for _, card in ipairs(scope.cards) do card.egg.Rotation = 0 end

			if not scopeWait(self, scope, HatchCinematicPolicy.TIMINGS.IntroDuration) then return end
			local popStartedAt = os.clock()
			for index, entry in ipairs(plan.entries) do
				local remainingDelay = entry.delay - (os.clock() - popStartedAt)
				if remainingDelay > 0 and not scopeWait(self, scope, remainingDelay) then return end
				if self._activeHatchScope ~= scope or scope.finished then return end
				local card = scope.cards[index]
				card.egg.Visible = false
				card.result.Visible = true
				card.scale.Scale = 0.35
				self:_configureVariantCard(scope, card, pets[index], entry)
				trackTween(scope, TweenService:Create(card.scale,
					TweenInfo.new(HatchCinematicPolicy.TIMINGS.PopDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Scale = plan.hasRare and entry.isHero and 1.08 or 1 }))
				self:_playHatchSound(scope, "Pop")
				if entry.classification ~= "Normal" and not entry.isHero then self:_playHatchSound(scope, "RareAccent") end
			end
			self:_startVariantAnimation(scope)
			if not scopeWait(self, scope, HatchCinematicPolicy.TIMINGS.PopDuration) then return end

			local holdDuration = plan.hasRare and HatchCinematicPolicy.TIMINGS.HeroHoldDuration
				or HatchCinematicPolicy.TIMINGS.StandardHoldDuration
			if plan.hasRare then
				self:_playHatchSound(scope, "Hero")
				for index, card in ipairs(scope.cards) do
					if index ~= plan.heroIndex then
						card.frame.BackgroundTransparency = 0.55
						card.nameLabel.TextTransparency = 0.42
						card.rarityLabel.TextTransparency = 0.42
						card.variantLabel.TextTransparency = 0.42
					end
				end
				observeUpgradeTreeFovConflict(scope, self._playerGui)
				if not scope.heroFovOwnershipReleased and not findVisibleUpgradeTreeOverlay(self._playerGui) then
					local camera = workspace.CurrentCamera
					if camera then
						scope.camera = camera
						scope.cameraFieldOfView = camera.FieldOfView
						scope.heroFovOwned = true
						local heroFovTween = TweenService:Create(camera,
							TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
							{ FieldOfView = math.max(35, scope.cameraFieldOfView - 7) })
						scope.heroFovTween = heroFovTween
						trackTween(scope, heroFovTween)
					end
				end
			end
			if not scopeWait(self, scope, math.min(holdDuration, HatchCinematicPolicy.TIMINGS.HeroHoldDuration)) then return end
			if scope.heroFovOwned and scope.camera and scope.cameraFieldOfView then
				local restoreFovTween = TweenService:Create(scope.camera,
					TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ FieldOfView = scope.cameraFieldOfView })
				scope.heroFovTween = restoreFovTween
				trackTween(scope, restoreFovTween)
			end
			trackTween(scope, TweenService:Create(scope.overlay,
				TweenInfo.new(HatchCinematicPolicy.TIMINGS.OutroDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ BackgroundTransparency = 1 }))
			if not scopeWait(self, scope, HatchCinematicPolicy.TIMINGS.OutroDuration) then return end
		end, debug.traceback)
		if not succeeded then warn("[EffectsController] Hatch cinematic recovered from an error:\n" .. tostring(failure)) end
		self:_finalizeHatchScope(scope, succeeded and "completed" or "error")
	end)
end

function EffectsController:_processHatchPresentationQueue()
	local activeScope = self._activeHatchScope
	if activeScope and not activeScope.finished then
		if not activeScope.waitingForResult or #self._hatchPresentationQueue == 0 then return end
		local nextItem = self._hatchPresentationQueue[1]
		local idsMatch = activeScope.batchId == nil or nextItem.batchId == nil or activeScope.batchId == nextItem.batchId
		if not idsMatch or #activeScope.cards ~= #nextItem.payload.pets then
			self:_finalizeHatchScope(activeScope, "start_replaced")
			return
		end
		table.remove(self._hatchPresentationQueue, 1)
		activeScope.item = nextItem
		activeScope.onPresented = nextItem.onPresented
		activeScope.waitingForResult = false
		activeScope.skipButton.Active = true
		activeScope.skipButton.AutoButtonColor = true
		activeScope.skipButton.Text = "SKIP"
		self._hatchPresentationActive = true
		self:_runHatchPresentation(activeScope, nextItem)
		return
	end
	if self._hatchPresentationActive or #self._hatchPresentationQueue == 0 then return end
	local item = table.remove(self._hatchPresentationQueue, 1)
	self._hatchPresentationActive = true
	local partialScope = {}
	local created, scopeOrError = xpcall(function()
		return self:_createHatchScope(item.payload, false, partialScope)
	end, debug.traceback)
	if not created then
		warn("[EffectsController] Hatch surface recovered from an error:\n" .. tostring(scopeOrError))
		partialScope.onPresented = item.onPresented
		self:_finalizeHatchScope(partialScope, "error")
		return
	end
	local scope = scopeOrError
	scope.item = item
	scope.onPresented = item.onPresented
	self._activeHatchScope = scope
	self._isHatching = true
	self:_runHatchPresentation(scope, item)
end

function EffectsController:handleHatchStart(payload)
	if not self._initialized then return false end
	local eggType = type(payload) == "table" and payload.eggType or payload
	if type(eggType) ~= "string" or eggType == "" then return false end
	if self._activeHatchScope or self._hatchPresentationActive or #self._hatchPresentationQueue > 0 then return true end
	local startPayload = type(payload) == "table" and shallowCopy(payload) or { eggType = eggType, count = 1 }
	startPayload.count = math.clamp(math.floor(tonumber(startPayload.count) or 1), 1, HatchCinematicPolicy.MAX_PETS)
	local partialScope = {}
	local created, scopeOrError = xpcall(function()
		return self:_createHatchScope(startPayload, true, partialScope)
	end, debug.traceback)
	if not created then
		warn("[EffectsController] Hatch start feedback recovered from an error:\n" .. tostring(scopeOrError))
		self:_finalizeHatchScope(partialScope, "create_error")
		return false
	end
	local scope = scopeOrError
	self._activeHatchScope = scope
	self._isHatching = true
	task.delay(HATCH_START_TIMEOUT, function()
		if self._activeHatchScope == scope and scope.waitingForResult and not scope.finished then
			self:_finalizeHatchScope(scope, "start_timeout")
		end
	end)
	return true
end

function EffectsController:handleInvalidHatchResult(payload)
	local scope = self._activeHatchScope
	if not scope or scope.finished or not scope.waitingForResult then return false end
	local resultBatchId = getBatchId(payload)
	if scope.batchId and resultBatchId and scope.batchId ~= resultBatchId then return false end
	self:_finalizeHatchScope(scope, "invalid_result")
	return true
end

function EffectsController:enqueueHatchBatch(payload, onPresented)
	local normalized = normalizeHatchPayload(payload)
	if not normalized then
		self:handleInvalidHatchResult(payload)
		return false
	end
	if not self._initialized then
		if type(onPresented) == "function" then
			table.insert(self._hatchCleanupCallbacks, { onPresented = onPresented, reason = "not_initialized" })
			if not self._finalizingHatchScope then
				self:_finalizeHatchScope({ finished = false, tweens = {}, connections = {}, sounds = {} }, "not_initialized")
			end
		end
		return false
	end
	local batchId = normalized.batchId
	if batchId and self._seenHatchBatchIds[batchId] then return false end
	if batchId then
		self._seenHatchBatchIds[batchId] = true
		table.insert(self._seenHatchBatchOrder, batchId)
		if #self._seenHatchBatchOrder > HATCH_SEEN_CACHE_LIMIT then
			self._seenHatchBatchIds[table.remove(self._seenHatchBatchOrder, 1)] = nil
		end
	end
	table.insert(self._hatchPresentationQueue, { batchId = batchId, payload = normalized, onPresented = onPresented })
	self:_processHatchPresentationQueue()
	return true
end

--------------------------------------------------------------------------------
-- startEggWobble: shows overlay + egg and starts a smooth infinite wobble.
-- Called immediately when EggHatchStart fires so the player sees feedback right away.
--------------------------------------------------------------------------------
function EffectsController:startEggWobble()
	return self:handleHatchStart({ eggType = "Legacy", count = 1 })
end

function EffectsController:skipEggHatch()
	local scope = self._activeHatchScope
	if not scope or scope.finished or scope.waitingForResult then return false end
	self:_finalizeHatchScope(scope, "skipped")
	return true
end

function EffectsController:cancelEggHatch(reason)
	local scope = self._activeHatchScope
	if not scope or scope.finished then return false end
	self:_finalizeHatchScope(scope, reason or "cancelled")
	return true
end

--------------------------------------------------------------------------------
-- Legacy complete API accepts one pet, a pet array, or a complete batch DTO and
-- delegates to the same FIFO. No parallel single-egg reveal engine remains.
function EffectsController:completeEggHatch(petData, batchCount, onComplete)
	local payload
	if type(petData) == "table" and type(petData.pets) == "table" then
		payload = petData
	elseif type(petData) == "table" and #petData > 0 then
		payload = { pets = petData, count = #petData }
	else
		payload = {
			pets = { petData },
			count = math.max(1, math.floor(tonumber(batchCount) or 1)),
		}
	end
	return self:enqueueHatchBatch(payload, onComplete)
end

--------------------------------------------------------------------------------
-- showEggHatchAnimation: legacy fallback that calls both phases in sequence.
-- Retained for API compatibility. eggPosition is unused (screen-space animation).
--------------------------------------------------------------------------------
function EffectsController:showEggHatchAnimation(_eggPosition, resultPet)
	self:startEggWobble()
	task.delay(1.0, function()
		self:completeEggHatch(resultPet)
	end)
end

--------------------------------------------------------------------------------
-- Zone Unlock: gate dissolves with sparkle Parts
--------------------------------------------------------------------------------
function EffectsController:showZoneUnlock(gatePosition)
	if not self._initialized then return end

	-- Sparkle Parts fly outward from gate position
	for i = 1, 20 do
		local sparkle = Instance.new("Part")
		sparkle.Name = "ZoneSparkle"
		sparkle.Size = Vector3.new(0.4, 0.4, 0.4)
		sparkle.Shape = Enum.PartType.Ball
		sparkle.Position = gatePosition + Vector3.new(
			math.random(-2, 2),
			math.random(0, 4),
			math.random(-2, 2)
		)
		sparkle.Anchored = true
		sparkle.CanCollide = false
		sparkle.Color = Color3.fromRGB(255, 255, 100)
		sparkle.Material = Enum.Material.Neon
		sparkle.Parent = self._effectsFolder

		local angle = (i / 20) * math.pi * 2
		local distance = math.random(4, 8)
		local direction = Vector3.new(
			math.cos(angle) * distance,
			math.random(2, 6),
			math.sin(angle) * distance
		)

		local tweenInfo = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tween = TweenService:Create(sparkle, tweenInfo, {
			Position = gatePosition + direction,
			Transparency = 1,
			Size = Vector3.new(0.1, 0.1, 0.1),
		})
		tween:Play()
		tween.Completed:Connect(function()
			sparkle:Destroy()
		end)
	end

	-- Brief flash effect (white Part that fades quickly)
	local flash = Instance.new("Part")
	flash.Name = "ZoneFlash"
	flash.Size = Vector3.new(10, 10, 10)
	flash.Shape = Enum.PartType.Ball
	flash.Position = gatePosition
	flash.Anchored = true
	flash.CanCollide = false
	flash.Color = Color3.fromRGB(255, 255, 255)
	flash.Material = Enum.Material.Neon
	flash.Transparency = 0.5
	flash.Parent = self._effectsFolder

	local flashInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local flashTween = TweenService:Create(flash, flashInfo, {
		Transparency = 1,
		Size = Vector3.new(20, 20, 20),
	})
	flashTween:Play()
	flashTween.Completed:Connect(function()
		flash:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Progress Bar: BillboardGui above destructible showing HP
-- Enhanced: bigger (120x24), floats higher (4 studs), shows HP text, colored stroke
--------------------------------------------------------------------------------
function EffectsController:showProgressBar(destructible, currentHP, maxHP)
	if not self._initialized then return end
	if not destructible or not destructible:IsA("BasePart") then return end

	-- If a bar already exists for this destructible, update it instead of recreating
	if self._progressBars[destructible] then
		self:updateProgressBar(destructible, currentHP, maxHP)
		return
	end

	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "HPBar"
	billboardGui.Size = UDim2.fromOffset(120, 24)
	billboardGui.StudsOffset = Vector3.new(0, 4, 0)
	billboardGui.AlwaysOnTop = true
	billboardGui.Adornee = destructible
	billboardGui.Parent = self._playerGui

	-- Outer frame (dark background with colored stroke)
	local outerFrame = Instance.new("Frame")
	outerFrame.Name = "Outer"
	outerFrame.Size = UDim2.fromScale(1, 1)
	outerFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	outerFrame.BorderSizePixel = 0
	outerFrame.Parent = billboardGui

	local outerCorner = Instance.new("UICorner")
	outerCorner.CornerRadius = UDim.new(0, 6)
	outerCorner.Parent = outerFrame

	local outerStroke = Instance.new("UIStroke")
	outerStroke.Name = "BarStroke"
	outerStroke.Thickness = 2
	outerStroke.Color = Color3.fromRGB(80, 120, 200)
	outerStroke.Parent = outerFrame

	-- Inner fill frame
	local fillFraction = math.clamp(currentHP / math.max(maxHP, 1), 0, 1)
	local fillColor = Color3.fromRGB(0, 220, 60) -- bright green

	local fillFrame = Instance.new("Frame")
	fillFrame.Name = "Fill"
	fillFrame.Size = UDim2.fromScale(fillFraction * 0.96, 0.7)
	fillFrame.Position = UDim2.fromScale(0.02, 0.15)
	fillFrame.BackgroundColor3 = fillColor
	fillFrame.BorderSizePixel = 0
	fillFrame.Parent = outerFrame

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = fillFrame

	-- Gradient on the fill bar for extra juice
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(200, 200, 200)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 150, 150)),
	})
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(0.3, 0.85),
		NumberSequenceKeypoint.new(1, 0.9),
	})
	gradient.Rotation = 90
	gradient.Parent = fillFrame

	-- HP text overlay (shows current/max)
	local hpText = Instance.new("TextLabel")
	hpText.Name = "HPText"
	hpText.Size = UDim2.fromScale(1, 1)
	hpText.BackgroundTransparency = 1
	hpText.Text = tostring(math.ceil(currentHP)) .. "/" .. tostring(maxHP)
	hpText.TextColor3 = Color3.fromRGB(255, 255, 255)
	hpText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	hpText.TextStrokeTransparency = 0.3
	hpText.Font = Enum.Font.GothamBold
	hpText.TextScaled = true
	hpText.ZIndex = 3
	hpText.Parent = outerFrame

	-- Store reference
	self._progressBars[destructible] = billboardGui
end

function EffectsController:updateProgressBar(destructible, currentHP, maxHP)
	if not self._initialized then return end
	local gui = self._progressBars[destructible]
	if not gui then return end

	local outerFrame = gui:FindFirstChild("Outer")
	if not outerFrame then return end
	local fillFrame = outerFrame:FindFirstChild("Fill")
	if not fillFrame then return end
	local hpText = outerFrame:FindFirstChild("HPText")

	local fillFraction = math.clamp(currentHP / math.max(maxHP, 1), 0, 1)

	-- Change color based on HP percentage (green -> yellow -> orange -> red)
	local color
	if fillFraction > 0.6 then
		color = Color3.fromRGB(0, 220, 60)
	elseif fillFraction > 0.35 then
		color = Color3.fromRGB(255, 200, 0)
	elseif fillFraction > 0.15 then
		color = Color3.fromRGB(255, 120, 0)
	else
		color = Color3.fromRGB(255, 40, 40)
	end

	local tweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(fillFrame, tweenInfo, {
		Size = UDim2.fromScale(fillFraction * 0.96, 0.7),
		BackgroundColor3 = color,
	}):Play()

	-- Update HP text
	if hpText then
		hpText.Text = tostring(math.max(0, math.ceil(currentHP))) .. "/" .. tostring(maxHP)
	end

	-- Shake effect when hit (brief scale pulse on the billboard)
	local shakeInfo = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)
	TweenService:Create(gui, shakeInfo, {
		Size = UDim2.fromOffset(130, 28),
	}):Play()
end

function EffectsController:removeProgressBar(destructible)
	if not self._initialized then return end
	local gui = self._progressBars[destructible]
	if gui then
		gui:Destroy()
		self._progressBars[destructible] = nil
	end
end

--------------------------------------------------------------------------------
-- Level-Up Celebration: golden "LEVEL UP!" text + expanding particle ring
-- Called when the player levels up for a juicy celebration moment.
--------------------------------------------------------------------------------
function EffectsController:showLevelUpCelebration(newLevel)
	if not self._initialized then return end

	-- Large golden "LEVEL UP!" text on screen center
	local overlay = Instance.new("ScreenGui")
	overlay.Name = "LevelUpOverlay"
	overlay.ResetOnSpawn = false
	overlay.Parent = self._playerGui

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "LevelUpText"
	textLabel.Size = UDim2.fromScale(0.5, 0.15)
	textLabel.Position = UDim2.fromScale(0.25, 0.35)
	textLabel.BackgroundTransparency = 1
	textLabel.Text = "LEVEL UP!"
	textLabel.TextColor3 = Color3.fromRGB(255, 220, 0)
	textLabel.TextStrokeColor3 = Color3.fromRGB(180, 100, 0)
	textLabel.TextStrokeTransparency = 0
	textLabel.Font = Enum.Font.GothamBold
	textLabel.TextScaled = true
	textLabel.TextTransparency = 1
	textLabel.Parent = overlay

	local levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "NewLevelText"
	levelLabel.Size = UDim2.fromScale(0.3, 0.08)
	levelLabel.Position = UDim2.fromScale(0.35, 0.5)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Text = "Level " .. tostring(newLevel)
	levelLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	levelLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	levelLabel.TextStrokeTransparency = 0.3
	levelLabel.Font = Enum.Font.GothamBold
	levelLabel.TextScaled = true
	levelLabel.TextTransparency = 1
	levelLabel.Parent = overlay

	-- Animate text appearing with bounce scale
	local fadeInInfo = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(textLabel, fadeInInfo, {
		TextTransparency = 0,
		Size = UDim2.fromScale(0.6, 0.18),
	}):Play()

	task.delay(0.15, function()
		if not levelLabel or not levelLabel.Parent then return end
		TweenService:Create(levelLabel, fadeInInfo, {
			TextTransparency = 0,
		}):Play()
	end)

	-- Spawn a ring of golden particles around the player
	local character = self._player.Character
	if character then
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			local ringCenter = rootPart.Position

			-- Create ring particles (expanding golden spheres)
			for i = 1, 16 do
				local angle = (i / 16) * math.pi * 2
				local startRadius = 2
				local endRadius = 10
				local startPos = ringCenter + Vector3.new(math.cos(angle) * startRadius, 1, math.sin(angle) * startRadius)
				local endPos = ringCenter + Vector3.new(math.cos(angle) * endRadius, 2 + math.random() * 2, math.sin(angle) * endRadius)

				local particle = Instance.new("Part")
				particle.Name = "LevelUpParticle"
				particle.Shape = Enum.PartType.Ball
				particle.Size = Vector3.new(0.8, 0.8, 0.8)
				particle.Position = startPos
				particle.Anchored = true
				particle.CanCollide = false
				particle.Color = Color3.fromRGB(255, 200 + math.random(0, 55), 0)
				particle.Material = Enum.Material.Neon
				particle.Parent = self._effectsFolder

				local expandInfo = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				TweenService:Create(particle, expandInfo, {
					Position = endPos,
					Transparency = 1,
					Size = Vector3.new(0.2, 0.2, 0.2),
				}):Play()

				task.delay(1.3, function()
					if particle and particle.Parent then
						particle:Destroy()
					end
				end)
			end

			-- Central golden flash ring (flat expanding cylinder)
			local ring = Instance.new("Part")
			ring.Name = "LevelUpRing"
			ring.Shape = Enum.PartType.Cylinder
			ring.Size = Vector3.new(0.3, 2, 2)
			ring.Position = ringCenter + Vector3.new(0, 0.5, 0)
			ring.Anchored = true
			ring.CanCollide = false
			ring.Color = Color3.fromRGB(255, 220, 0)
			ring.Material = Enum.Material.Neon
			ring.Transparency = 0.3
			ring.CFrame = CFrame.new(ringCenter + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
			ring.Parent = self._effectsFolder

			local ringExpand = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(ring, ringExpand, {
				Size = Vector3.new(0.3, 20, 20),
				Transparency = 1,
			}):Play()

			task.delay(1.0, function()
				if ring and ring.Parent then
					ring:Destroy()
				end
			end)
		end
	end

	-- Fade out text after 2 seconds
	task.delay(2, function()
		if not overlay or not overlay.Parent then return end
		local fadeOutInfo = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(textLabel, fadeOutInfo, {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
		TweenService:Create(levelLabel, fadeOutInfo, {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()

		task.delay(1, function()
			if overlay and overlay.Parent then
				overlay:Destroy()
			end
		end)
	end)
end

--------------------------------------------------------------------------------
-- Crit Button: a single BillboardGui button (Fortnite-style weak point)
-- that appears on a destructible after clicking it. The button is a white
-- circle that randomly varies in size (22-40px) and teleports to a random
-- offset around the destructible each spawn, making it harder to click.
-- Only 1 crit button exists globally at a time (spawning a new one removes the
-- previous one). Clicking the button triggers crit (2x damage).
-- Button disappears after 3 seconds if not clicked.
--------------------------------------------------------------------------------
function EffectsController:spawnCritButton(destructiblePart, destructibleId, onCritClicked)
	if not self._initialized then return end
	if not destructiblePart or not destructiblePart:IsA("BasePart") then return end

	-- Only 1 crit button globally at a time: remove any existing one
	self:_removeGlobalCritButton()

	-- Create BillboardGui attached to the destructible (random offset each spawn)
	local critSize = math.random(22, 40)
	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "CritButton_" .. destructibleId
	billboardGui.Size = UDim2.fromOffset(critSize, critSize)
	billboardGui.StudsOffset = Vector3.new(math.random(-3, 3), math.random(0, 3), math.random(-3, 3))
	billboardGui.AlwaysOnTop = true
	billboardGui.Active = true
	billboardGui.Adornee = destructiblePart
	billboardGui.Parent = self._playerGui

	-- Create the circular button (plain white circle, no text)
	local button = Instance.new("TextButton")
	button.Name = "CritBtn"
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	button.BackgroundTransparency = 0
	button.Text = ""
	button.AutoButtonColor = true
	button.Parent = billboardGui

	-- Round the button with UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button

	-- Add glowing stroke (subtle glow instead of pulse animation)
	local stroke = Instance.new("UIStroke")
	stroke.Name = "GlowStroke"
	stroke.Thickness = 4
	stroke.Color = Color3.fromRGB(220, 220, 220)
	stroke.Transparency = 0.2
	stroke.Parent = button

	-- No pulse animation, no orbit - button is completely static (Fortnite weak point style)

	-- Handle button click: fire crit
	local clicked = false
	button.Activated:Connect(function()
		if clicked then return end
		clicked = true

		-- Show crit hit visual effect
		self:showCritButtonHitEffect(destructiblePart)

		-- Remove the button
		billboardGui:Destroy()
		self._critButtons[destructibleId] = nil
		self._globalCritButtonId = nil

		-- Fire the crit callback
		if onCritClicked then
			onCritClicked()
		end
	end)

	-- Timeout: disappear after 3 seconds if not clicked
	task.delay(3, function()
		if clicked then return end
		if not billboardGui or not billboardGui.Parent then return end

		-- Fade out
		local fadeInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(button, fadeInfo, {
			BackgroundTransparency = 1,
		}):Play()
		TweenService:Create(stroke, fadeInfo, {
			Transparency = 1,
		}):Play()

		task.delay(0.35, function()
			if billboardGui and billboardGui.Parent then
				billboardGui:Destroy()
			end
			self._critButtons[destructibleId] = nil
			if self._globalCritButtonId == destructibleId then
				self._globalCritButtonId = nil
			end
		end)
	end)

	-- Store reference for cleanup (only one globally)
	if not self._critButtons then
		self._critButtons = {}
	end
	self._critButtons[destructibleId] = billboardGui
	self._globalCritButtonId = destructibleId
end

--------------------------------------------------------------------------------
-- Remove the single global crit button (ensures only 1 exists at a time)
--------------------------------------------------------------------------------
function EffectsController:_removeGlobalCritButton()
	if not self._critButtons then
		self._critButtons = {}
		return
	end
	-- Remove any existing crit button (there should only be one globally)
	for id, gui in pairs(self._critButtons) do
		if gui and gui.Parent then
			gui:Destroy()
		end
		self._critButtons[id] = nil
	end
	self._globalCritButtonId = nil
end

--------------------------------------------------------------------------------
-- Check if a crit button is currently active (not yet consumed or timed out)
--------------------------------------------------------------------------------
function EffectsController:hasCritButtonActive()
	return self._globalCritButtonId ~= nil
end

--------------------------------------------------------------------------------
-- Remove existing crit button for a specific destructible
--------------------------------------------------------------------------------
function EffectsController:removeCritButton(destructibleId)
	if not self._critButtons then
		self._critButtons = {}
		return
	end
	local existing = self._critButtons[destructibleId]
	if existing and existing.Parent then
		existing:Destroy()
	end
	self._critButtons[destructibleId] = nil
	if self._globalCritButtonId == destructibleId then
		self._globalCritButtonId = nil
	end
end

--------------------------------------------------------------------------------
-- Crit Button Hit Effect: brief golden screen flash overlay when crit fires
-- Uses a ScreenGui with a yellow frame that fades quickly (no 3D Parts)
--------------------------------------------------------------------------------
function EffectsController:showCritButtonHitEffect(destructiblePart)
	if not self._initialized then return end

	-- Create a brief golden screen flash (ScreenGui overlay)
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CritFlashOverlay"
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 100
	screenGui.Parent = self._playerGui

	local flashFrame = Instance.new("Frame")
	flashFrame.Name = "FlashFrame"
	flashFrame.Size = UDim2.fromScale(1, 1)
	flashFrame.Position = UDim2.fromScale(0, 0)
	flashFrame.BackgroundColor3 = Color3.fromRGB(255, 220, 0)
	flashFrame.BackgroundTransparency = 0.6
	flashFrame.BorderSizePixel = 0
	flashFrame.Parent = screenGui

	-- Fade out rapidly
	local fadeInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(flashFrame, fadeInfo, {
		BackgroundTransparency = 1,
	}):Play()

	task.delay(0.3, function()
		if screenGui and screenGui.Parent then
			screenGui:Destroy()
		end
	end)
end

--------------------------------------------------------------------------------
-- Crit Sound: play a satisfying high-pitched "zing" sound for crit hits
--------------------------------------------------------------------------------
function EffectsController:playCritSound(position)
	if not self._initialized then return end

	local soundAnchor = Instance.new("Part")
	soundAnchor.Name = "CritSoundAnchor"
	soundAnchor.Size = Vector3.new(0.1, 0.1, 0.1)
	soundAnchor.Position = position
	soundAnchor.Anchored = true
	soundAnchor.CanCollide = false
	soundAnchor.Transparency = 1
	soundAnchor.Parent = self._effectsFolder

	local sound = Instance.new("Sound")
	sound.Name = "CritHitSound"
	-- Use a higher pitched version of the click sound for crit feedback
	sound.SoundId = "rbxassetid://6042053626"
	sound.Volume = 0.7
	sound.PlaybackSpeed = 1.8 + math.random() * 0.3 -- high pitch for crit
	sound.RollOffMaxDistance = 50
	sound.Parent = soundAnchor

	sound:Play()

	-- Cleanup after sound finishes
	sound.Ended:Connect(function()
		soundAnchor:Destroy()
	end)

	-- Safety cleanup
	task.delay(2, function()
		if soundAnchor and soundAnchor.Parent then
			soundAnchor:Destroy()
		end
	end)
end

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------
function EffectsController:cleanup()
	self._initialized = false
	local queuedPresentations = self._hatchPresentationQueue
	self._hatchPresentationQueue = {}
	for _, item in ipairs(queuedPresentations) do
		if type(item.onPresented) == "function" then
			table.insert(self._hatchCleanupCallbacks, {
				onPresented = item.onPresented,
				reason = "cleanup",
			})
		end
	end

	local activeScope = self._activeHatchScope
	if activeScope and not activeScope.finished then
		self:_finalizeHatchScope(activeScope, "cleanup")
	elseif not self._finalizingHatchScope and #self._hatchCleanupCallbacks > 0 then
		self:_finalizeHatchScope({ finished = false, tweens = {}, connections = {}, sounds = {} }, "cleanup")
	end
	safeDisconnect(self._characterRemovingConnection)
	self._characterRemovingConnection = nil
	for _, gui in pairs(self._progressBars) do
		gui:Destroy()
	end
	self._progressBars = {}
	for _, gui in pairs(self._critButtons) do
		if gui and gui.Parent then
			gui:Destroy()
		end
	end
	self._critButtons = {}
	for _, entry in ipairs(self._activePopups) do
		if entry.billboard and entry.billboard.Parent then
			entry.billboard:Destroy()
		end
		if entry.anchor and entry.anchor.Parent then
			entry.anchor:Destroy()
		end
	end
	self._activePopups = {}
	if self._effectsFolder then
		self._effectsFolder:Destroy()
	end
end

--------------------------------------------------------------------------------
-- Destructible Poof Effect: fades the destructible out with a transparency tween
-- No 3D particles are spawned - just a clean fade-out on the destructible itself
-- color: unused (kept for API compatibility)
--------------------------------------------------------------------------------
function EffectsController:showDestructiblePoof(position, color)
	if not self._initialized then return end
	-- No 3D particle effects - destructible removal is handled by the server
	-- The destructible simply disappears; currency popups provide visual feedback
end

--------------------------------------------------------------------------------
-- Click Hit Effect: brief flash + rotation shake on the destructible model
-- Makes the destructible wobble slightly when the player clicks on it.
--------------------------------------------------------------------------------
function EffectsController:showClickHitEffect(destructiblePart)
	if not self._initialized then return end
	if not destructiblePart or not destructiblePart:IsA("BasePart") then return end

	-- Find the parent model to shake all parts
	local model = destructiblePart.Parent
	if not model or not model:IsA("Model") then return end

	-- Brief white highlight flash on the main part
	local originalColor = destructiblePart.Color
	local originalMaterial = destructiblePart.Material

	-- Flash to white briefly
	destructiblePart.Color = Color3.fromRGB(255, 255, 255)
	task.delay(0.05, function()
		if destructiblePart and destructiblePart.Parent then
			destructiblePart.Color = originalColor
		end
	end)

	-- Rotation shake: tilt the model parts slightly and return
	-- Apply a small random rotation offset to all anchored parts in the model
	local shakeAngle = math.rad(3 + math.random() * 4) -- 3-7 degrees
	local shakeDir = (math.random() > 0.5) and 1 or -1

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.Anchored then
			local originalCFrame = part.CFrame
			-- Apply shake rotation around Z axis (wobble left-right)
			part.CFrame = originalCFrame * CFrame.Angles(0, 0, shakeAngle * shakeDir)

			-- Return to original after a brief delay
			task.delay(0.06, function()
				if part and part.Parent then
					part.CFrame = originalCFrame
				end
			end)
		end
	end
end

--------------------------------------------------------------------------------
-- Click Sound: play a satisfying "kling" sound per click using Roblox built-in
-- Uses a short pitched click/hit sound
--------------------------------------------------------------------------------
function EffectsController:playClickSound(position)
	if not self._initialized then return end

	-- Create a sound at the position (attach to an anchor part)
	local soundAnchor = Instance.new("Part")
	soundAnchor.Name = "ClickSoundAnchor"
	soundAnchor.Size = Vector3.new(0.1, 0.1, 0.1)
	soundAnchor.Position = position
	soundAnchor.Anchored = true
	soundAnchor.CanCollide = false
	soundAnchor.Transparency = 1
	soundAnchor.Parent = self._effectsFolder

	local sound = Instance.new("Sound")
	sound.Name = "ClickHitSound"
	-- Use Roblox built-in coin/hit sound (public asset)
	sound.SoundId = "rbxassetid://6042053626"
	sound.Volume = 0.5
	sound.PlaybackSpeed = 1.2 + math.random() * 0.3 -- slight pitch variation for satisfaction
	sound.RollOffMaxDistance = 50
	sound.Parent = soundAnchor

	sound:Play()

	-- Cleanup after sound finishes
	sound.Ended:Connect(function()
		soundAnchor:Destroy()
	end)

	-- Safety cleanup in case Ended never fires
	task.delay(2, function()
		if soundAnchor and soundAnchor.Parent then
			soundAnchor:Destroy()
		end
	end)
end

return EffectsController
