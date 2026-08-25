--[[
	EffectsController.lua - Visual effects system for Battle Pets
	Handles floating number popups, egg hatching animations, zone unlock effects,
	and progress bars above destructibles. All visuals are procedural (no external assets).
]]

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

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

function EffectsController.new()
	local self = setmetatable({}, EffectsController)
	self._progressBars = {}
	self._critButtons = {}
	self._activePopups = {}
	self._initialized = false
	self._lastHatchPosition = nil
	return self
end

function EffectsController:init()
	self._player = Players.LocalPlayer
	self._playerGui = self._player:WaitForChild("PlayerGui")
	self._effectsFolder = Instance.new("Folder")
	self._effectsFolder.Name = "ClientEffects"
	self._effectsFolder.Parent = workspace
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
-- Egg Hatch Animation: large egg appears, wobbles 2-3 times, breaks with
-- particle/light flash, pet revealed with rarity color/name, camera zoom (~3s)
--------------------------------------------------------------------------------
function EffectsController:showEggHatchAnimation(eggPosition, resultPet)
	if not self._initialized then return end
	if not eggPosition then return end

	local rarity = resultPet and resultPet.rarity or "Common"
	local petName = resultPet and resultPet.name or "Pet"
	local rarityColor = RARITY_COLORS[rarity] or RARITY_COLORS.Common

	-- NO camera manipulation - camera stays in normal player-controlled mode

	-- Create LARGE egg model (much bigger for visibility)
	local egg = Instance.new("Part")
	egg.Name = "HatchingEgg"
	egg.Shape = Enum.PartType.Ball
	egg.Size = Vector3.new(5, 7, 5)
	egg.Position = eggPosition + Vector3.new(0, 4, 0)
	egg.Anchored = true
	egg.CanCollide = false
	egg.Color = Color3.fromRGB(255, 245, 210)
	egg.Material = Enum.Material.SmoothPlastic
	egg.Parent = self._effectsFolder

	-- Add a PointLight to the egg so it glows during animation
	local eggLight = Instance.new("PointLight")
	eggLight.Color = Color3.fromRGB(255, 255, 200)
	eggLight.Brightness = 2
	eggLight.Range = 12
	eggLight.Parent = egg

	-- Wobble animation: egg tilts left-right 3 times with increasing intensity
	local basePos = egg.Position
	task.spawn(function()
		-- Wobble 1 (small)
		local w1 = TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, true)
		local wobble1 = TweenService:Create(egg, w1, {
			CFrame = CFrame.new(basePos) * CFrame.Angles(0, 0, math.rad(8)),
		})
		wobble1:Play()
		wobble1.Completed:Wait()
		task.wait(0.15)

		-- Wobble 2 (medium)
		local w2 = TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, true)
		local wobble2 = TweenService:Create(egg, w2, {
			CFrame = CFrame.new(basePos) * CFrame.Angles(0, 0, math.rad(-12)),
		})
		wobble2:Play()
		wobble2.Completed:Wait()
		task.wait(0.15)

		-- Wobble 3 (large)
		local w3 = TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, true)
		local wobble3 = TweenService:Create(egg, w3, {
			CFrame = CFrame.new(basePos) * CFrame.Angles(0, 0, math.rad(15)),
		})
		wobble3:Play()
		wobble3.Completed:Wait()
		task.wait(0.1)

		-- Crack phase: egg glows and expands slightly, changes to rarity color
		local crackInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local crackTween = TweenService:Create(egg, crackInfo, {
			Color = rarityColor,
			Size = Vector3.new(6, 8, 6),
		})
		local lightFlash = TweenService:Create(eggLight, crackInfo, {
			Brightness = 8,
			Range = 20,
			Color = rarityColor,
		})
		crackTween:Play()
		lightFlash:Play()
		crackTween.Completed:Wait()

		-- BREAK: destroy egg, spawn bright flash + particles
		egg:Destroy()
		self:_spawnLightFlash(basePos + Vector3.new(0, 4, 0), rarityColor)
		self:_spawnBreakParticles(basePos + Vector3.new(0, 4, 0), rarityColor)

		-- Reveal pet after a short delay
		task.wait(0.4)
		self:_showPetReveal(basePos + Vector3.new(0, 4, 0), petName, rarity, rarityColor)
	end)
end

-- Internal: bright expanding flash sphere when egg breaks
function EffectsController:_spawnLightFlash(position, color)
	local flash = Instance.new("Part")
	flash.Name = "EggFlash"
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(2, 2, 2)
	flash.Position = position
	flash.Anchored = true
	flash.CanCollide = false
	flash.Color = color
	flash.Material = Enum.Material.Neon
	flash.Transparency = 0.2
	flash.Parent = self._effectsFolder

	-- PointLight for a bright burst
	local flashLight = Instance.new("PointLight")
	flashLight.Color = color
	flashLight.Brightness = 10
	flashLight.Range = 30
	flashLight.Parent = flash

	-- Expand and fade rapidly
	local flashInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local expandTween = TweenService:Create(flash, flashInfo, {
		Size = Vector3.new(16, 16, 16),
		Transparency = 1,
	})
	local lightFade = TweenService:Create(flashLight, flashInfo, {
		Brightness = 0,
	})
	expandTween:Play()
	lightFade:Play()
	expandTween.Completed:Connect(function()
		flash:Destroy()
	end)
end

-- Internal: spawn small Parts flying outward to simulate egg breaking
function EffectsController:_spawnBreakParticles(position, color)
	for i = 1, 16 do
		local particle = Instance.new("Part")
		particle.Name = "EggParticle"
		particle.Size = Vector3.new(0.5, 0.5, 0.5)
		particle.Shape = Enum.PartType.Ball
		particle.Position = position
		particle.Anchored = true
		particle.CanCollide = false
		particle.Color = color
		particle.Material = Enum.Material.Neon
		particle.Parent = self._effectsFolder

		local angle = (i / 16) * math.pi * 2
		local upAngle = math.random(20, 60) / 10
		local distance = math.random(4, 8)
		local direction = Vector3.new(
			math.cos(angle) * distance,
			upAngle,
			math.sin(angle) * distance
		)

		local tweenInfo = TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tween = TweenService:Create(particle, tweenInfo, {
			Position = position + direction,
			Transparency = 1,
			Size = Vector3.new(0.1, 0.1, 0.1),
		})
		tween:Play()
		tween.Completed:Connect(function()
			particle:Destroy()
		end)
	end
end

-- Internal: show pet model reveal with glow, name, and scale-in bounce
function EffectsController:_showPetReveal(position, petName, rarity, rarityColor)
	-- Pet model: sphere with glow
	local petPart = Instance.new("Part")
	petPart.Name = "RevealedPet"
	petPart.Shape = Enum.PartType.Ball
	petPart.Size = Vector3.new(0.1, 0.1, 0.1)
	petPart.Position = position
	petPart.Anchored = true
	petPart.CanCollide = false
	petPart.Color = rarityColor
	petPart.Material = Enum.Material.SmoothPlastic
	petPart.Parent = self._effectsFolder

	-- PointLight for glow
	local light = Instance.new("PointLight")
	light.Color = rarityColor
	light.Brightness = 6
	light.Range = 14
	light.Parent = petPart

	-- Scale from 0 to full size with bounce (Back easing)
	local revealInfo = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local revealTween = TweenService:Create(petPart, revealInfo, {
		Size = Vector3.new(3, 3, 3),
	})
	revealTween:Play()

	-- Floating pet name and rarity text
	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "PetRevealLabel"
	billboardGui.Size = UDim2.fromOffset(240, 80)
	billboardGui.StudsOffset = Vector3.new(0, 3.5, 0)
	billboardGui.AlwaysOnTop = true
	billboardGui.Adornee = petPart
	billboardGui.Parent = self._playerGui

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "PetName"
	nameLabel.Size = UDim2.fromScale(1, 0.6)
	nameLabel.Position = UDim2.fromScale(0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = petName
	nameLabel.TextColor3 = rarityColor
	nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	nameLabel.TextStrokeTransparency = 0.2
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.Parent = billboardGui

	local rarityLabel = Instance.new("TextLabel")
	rarityLabel.Name = "RarityText"
	rarityLabel.Size = UDim2.fromScale(1, 0.4)
	rarityLabel.Position = UDim2.fromScale(0, 0.6)
	rarityLabel.BackgroundTransparency = 1
	rarityLabel.Text = rarity
	rarityLabel.TextColor3 = rarityColor
	rarityLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	rarityLabel.TextStrokeTransparency = 0.3
	rarityLabel.Font = Enum.Font.GothamBold
	rarityLabel.TextScaled = true
	rarityLabel.Parent = billboardGui

	-- Fade out after 2.5 seconds
	task.delay(2.5, function()
		local fadeInfo = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local fadePet = TweenService:Create(petPart, fadeInfo, { Transparency = 1 })
		local fadeLight = TweenService:Create(light, fadeInfo, { Brightness = 0 })
		local fadeName = TweenService:Create(nameLabel, fadeInfo, { TextTransparency = 1 })
		local fadeRarity = TweenService:Create(rarityLabel, fadeInfo, { TextTransparency = 1 })

		fadePet:Play()
		fadeLight:Play()
		fadeName:Play()
		fadeRarity:Play()

		fadePet.Completed:Connect(function()
			petPart:Destroy()
			billboardGui:Destroy()
		end)
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
-- Crit Button: a single STATIC BillboardGui button (Fortnite-style weak point)
-- that appears on a destructible after clicking it. The button is a golden
-- circle with a crosshair icon, fixed in position on the destructible surface.
-- Only 1 crit button exists globally at a time (spawning a new one removes the
-- previous one). Clicking the button triggers crit (2x damage).
-- Button disappears after 2 seconds if not clicked.
--------------------------------------------------------------------------------
function EffectsController:spawnCritButton(destructiblePart, destructibleId, onCritClicked)
	if not self._initialized then return end
	if not destructiblePart or not destructiblePart:IsA("BasePart") then return end

	-- Only 1 crit button globally at a time: remove any existing one
	self:_removeGlobalCritButton()

	-- Create BillboardGui attached to the destructible (centered, no random offset)
	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "CritButton_" .. destructibleId
	billboardGui.Size = UDim2.fromOffset(80, 80)
	billboardGui.StudsOffset = Vector3.new(0, 0, 0)
	billboardGui.AlwaysOnTop = true
	billboardGui.Active = true
	billboardGui.Adornee = destructiblePart
	billboardGui.Parent = self._playerGui

	-- Create the circular button (plain golden circle, no text)
	local button = Instance.new("TextButton")
	button.Name = "CritBtn"
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
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
	stroke.Color = Color3.fromRGB(255, 255, 100)
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
