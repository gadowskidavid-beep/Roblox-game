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
--------------------------------------------------------------------------------
function EffectsController:showCurrencyPopup(position, amount, currencyType)
	if not self._initialized then return end

	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "CurrencyPopup"
	billboardGui.Size = UDim2.fromOffset(120, 50)
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

	local color = Color3.fromRGB(255, 220, 0)  -- yellow for coins
	if currencyType == "Diamonds" then
		color = Color3.fromRGB(0, 220, 255)  -- cyan for diamonds
	end

	local label = Instance.new("TextLabel")
	label.Name = "PopupText"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "+" .. tostring(amount)
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0.3
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = billboardGui

	-- Animate upward and fade
	local tweenInfo = TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(anchor, tweenInfo, {
		Position = position + Vector3.new(0, 4, 0),
	})
	local fadeTween = TweenService:Create(label, tweenInfo, {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})

	tween:Play()
	fadeTween:Play()

	-- Cleanup
	fadeTween.Completed:Connect(function()
		billboardGui:Destroy()
		anchor:Destroy()
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

	-- Store original camera settings for restore
	local camera = workspace.CurrentCamera
	local originalCameraType = camera and camera.CameraType or nil

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

	-- Camera zoom: swing camera to focus on the egg
	local eggPos = egg.Position
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
		local lookFrom = eggPos + Vector3.new(6, 3, 6)
		local zoomInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local zoomTween = TweenService:Create(camera, zoomInfo, {
			CFrame = CFrame.new(lookFrom, eggPos),
		})
		zoomTween:Play()
	end

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

		-- Restore camera after 2 seconds
		task.wait(2)
		if camera and originalCameraType then
			camera.CameraType = originalCameraType
		end
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
	billboardGui.Size = UDim2.fromOffset(80, 16)
	billboardGui.StudsOffset = Vector3.new(0, 3, 0)
	billboardGui.AlwaysOnTop = true
	billboardGui.Adornee = destructible
	billboardGui.Parent = self._playerGui

	-- Outer frame (dark background)
	local outerFrame = Instance.new("Frame")
	outerFrame.Name = "Outer"
	outerFrame.Size = UDim2.fromScale(1, 1)
	outerFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	outerFrame.BorderSizePixel = 0
	outerFrame.Parent = billboardGui

	local outerCorner = Instance.new("UICorner")
	outerCorner.CornerRadius = UDim.new(0, 4)
	outerCorner.Parent = outerFrame

	-- Inner fill frame
	local fillFraction = math.clamp(currentHP / math.max(maxHP, 1), 0, 1)
	local fillFrame = Instance.new("Frame")
	fillFrame.Name = "Fill"
	fillFrame.Size = UDim2.fromScale(fillFraction * 0.98, 0.8)
	fillFrame.Position = UDim2.fromScale(0.01, 0.1)
	fillFrame.BackgroundColor3 = Color3.fromRGB(0, 200, 50)
	fillFrame.BorderSizePixel = 0
	fillFrame.Parent = outerFrame

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 3)
	fillCorner.Parent = fillFrame

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

	local fillFraction = math.clamp(currentHP / math.max(maxHP, 1), 0, 1)

	-- Change color based on HP percentage
	local color
	if fillFraction > 0.5 then
		color = Color3.fromRGB(0, 200, 50)
	elseif fillFraction > 0.25 then
		color = Color3.fromRGB(255, 180, 0)
	else
		color = Color3.fromRGB(255, 50, 50)
	end

	local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(fillFrame, tweenInfo, {
		Size = UDim2.fromScale(fillFraction * 0.98, 0.8),
		BackgroundColor3 = color,
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
-- Cleanup
--------------------------------------------------------------------------------
function EffectsController:cleanup()
	for _, gui in pairs(self._progressBars) do
		gui:Destroy()
	end
	self._progressBars = {}
	if self._effectsFolder then
		self._effectsFolder:Destroy()
	end
end

return EffectsController
