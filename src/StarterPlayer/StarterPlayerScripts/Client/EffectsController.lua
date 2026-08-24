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
-- Egg Hatch Animation: egg shakes, cracks, breaks, reveals pet
--------------------------------------------------------------------------------
function EffectsController:showEggHatchAnimation(eggPosition, resultPet)
	if not self._initialized then return end
	if not eggPosition then return end

	local rarity = resultPet and resultPet.rarity or "Common"
	local petName = resultPet and resultPet.name or "Pet"
	local rarityColor = RARITY_COLORS[rarity] or RARITY_COLORS.Common

	-- Create egg model (ellipsoid Part)
	local egg = Instance.new("Part")
	egg.Name = "HatchingEgg"
	egg.Shape = Enum.PartType.Ball
	egg.Size = Vector3.new(3, 4, 3)
	egg.Position = eggPosition + Vector3.new(0, 2, 0)
	egg.Anchored = true
	egg.CanCollide = false
	egg.Color = Color3.fromRGB(255, 240, 200)
	egg.Material = Enum.Material.SmoothPlastic
	egg.Parent = self._effectsFolder

	-- Shake animation (short CFrame tweens left-right)
	local basePos = egg.Position
	local shakeInfo = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, 6, true)
	local shakeTween = TweenService:Create(egg, shakeInfo, {
		CFrame = CFrame.new(basePos) * CFrame.Angles(0, 0, math.rad(10)),
	})
	shakeTween:Play()

	-- After shake, crack effect
	shakeTween.Completed:Connect(function()
		-- Color change to indicate cracking
		local crackInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local crackTween = TweenService:Create(egg, crackInfo, {
			Color = rarityColor,
			Size = Vector3.new(3.5, 4.5, 3.5),
		})
		crackTween:Play()

		crackTween.Completed:Connect(function()
			-- Break: destroy egg, spawn particle-like Parts flying outward
			egg:Destroy()
			self:_spawnBreakParticles(basePos + Vector3.new(0, 2, 0), rarityColor)

			-- Reveal pet model in center with glow
			task.delay(0.3, function()
				self:_showPetReveal(basePos + Vector3.new(0, 2, 0), petName, rarity, rarityColor)
			end)
		end)
	end)
end

-- Internal: spawn small Parts flying outward to simulate egg breaking
function EffectsController:_spawnBreakParticles(position, color)
	for i = 1, 12 do
		local particle = Instance.new("Part")
		particle.Name = "EggParticle"
		particle.Size = Vector3.new(0.3, 0.3, 0.3)
		particle.Shape = Enum.PartType.Ball
		particle.Position = position
		particle.Anchored = true
		particle.CanCollide = false
		particle.Color = color
		particle.Material = Enum.Material.Neon
		particle.Parent = self._effectsFolder

		local angle = (i / 12) * math.pi * 2
		local direction = Vector3.new(math.cos(angle) * 5, math.random(2, 5), math.sin(angle) * 5)

		local tweenInfo = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
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

-- Internal: show pet model reveal with glow and name
function EffectsController:_showPetReveal(position, petName, rarity, rarityColor)
	-- Pet model: simple sphere
	local petPart = Instance.new("Part")
	petPart.Name = "RevealedPet"
	petPart.Shape = Enum.PartType.Ball
	petPart.Size = Vector3.new(0.1, 0.1, 0.1) -- start small
	petPart.Position = position
	petPart.Anchored = true
	petPart.CanCollide = false
	petPart.Color = rarityColor
	petPart.Material = Enum.Material.SmoothPlastic
	petPart.Parent = self._effectsFolder

	-- PointLight for glow
	local light = Instance.new("PointLight")
	light.Color = rarityColor
	light.Brightness = 5
	light.Range = 10
	light.Parent = petPart

	-- Scale from 0 to full size
	local revealInfo = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local revealTween = TweenService:Create(petPart, revealInfo, {
		Size = Vector3.new(2.5, 2.5, 2.5),
	})
	revealTween:Play()

	-- Floating pet name and rarity text
	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "PetRevealLabel"
	billboardGui.Size = UDim2.fromOffset(200, 60)
	billboardGui.StudsOffset = Vector3.new(0, 3, 0)
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

	-- Fade out after 3 seconds
	task.delay(3, function()
		local fadeInfo = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
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

	-- Remove existing bar if present
	self:removeProgressBar(destructible)

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
	local fillFraction = math.clamp(currentHP / maxHP, 0, 1)
	local fillFrame = Instance.new("Frame")
	fillFrame.Name = "Fill"
	fillFrame.Size = UDim2.fromScale(fillFraction, 0.8)
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

	local fillFraction = math.clamp(currentHP / maxHP, 0, 1)

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
