--[[
	PetController.lua - Pet visual management for Battle Pets
	Creates procedural pet models (Part-based), handles pets following behind the
	player in a trailing formation, animates pets toward destructibles to attack,
	and shows floating damage numbers. All visuals are procedural with no external assets.

	IMPORTANT: Only ONE model per equipped pet must exist at any time.
	The updateEquippedPets method enforces this by destroying all old models
	before creating new ones when the equipped list changes.
]]

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local PetController = {}
PetController.__index = PetController

-- Rarity colors
local RARITY_COLORS = {
	Common = Color3.fromRGB(255, 255, 255),
	Uncommon = Color3.fromRGB(0, 200, 0),
	Rare = Color3.fromRGB(0, 120, 255),
	Epic = Color3.fromRGB(180, 0, 255),
	Legendary = Color3.fromRGB(255, 200, 0),
}

function PetController.new()
	local self = setmetatable({}, PetController)
	self._remotes = nil
	self._equippedPets = {} -- { uniqueId = { model = Model, data = petData, followIndex = number } }
	self._petsFolder = nil
	-- Follow-behind settings
	self._followDistance = 5 -- distance behind the player per pet slot
	self._followSpread = 3 -- lateral spread for multiple pets in same row
	self._followHeight = 2.5 -- height offset above ground (floating)
	self._followLerpSpeed = 6 -- smoothing speed for following
	self._petsPerRow = 3 -- max pets per row behind the player
	self._initialized = false
	self._initGuard = false -- prevents double initialization
	self._attackingPets = {} -- pets currently attacking a destructible
	-- Auto-attack state
	self._autoAttackEnabled = true
	self._autoAttackInterval = 1.5 -- seconds between auto-attacks
	self._autoAttackRange = 40 -- studs detection range
	self._lastAutoAttackTime = 0
	self._autoAttackConnection = nil
	return self
end

function PetController:init(remotes)
	-- Guard against double initialization (prevents duplicate models)
	if self._initGuard then
		return
	end
	self._initGuard = true

	self._remotes = remotes
	self._player = Players.LocalPlayer

	-- Create folder for pet models in workspace (destroy any pre-existing one)
	local existingFolder = workspace:FindFirstChild("ClientPets")
	if existingFolder then
		existingFolder:Destroy()
	end

	self._petsFolder = Instance.new("Folder")
	self._petsFolder.Name = "ClientPets"
	self._petsFolder.Parent = workspace

	-- Load shared Config for upgrade bonuses
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	self._config = require(Shared:WaitForChild("Config"))

	self._initialized = true

	-- Start auto-attack loop
	self:_startAutoAttack()
end

--------------------------------------------------------------------------------
-- Create a procedural pet model: body sphere + shadow + nametag
-- Simple placeholder model - actual pet assets will be added later via Blender.
-- The pet floats 2.5 studs above ground with a circular shadow beneath it.
--------------------------------------------------------------------------------
function PetController:createPetModel(petData)
	local rarity = petData.rarity or "Common"
	local bodyColor = RARITY_COLORS[rarity] or RARITY_COLORS.Common
	local petName = petData.name or "Pet"

	local model = Instance.new("Model")
	model.Name = petName .. "_Model"

	-- Body: sphere (placeholder for future Blender model)
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(2.2, 2.2, 2.2)
	body.Color = bodyColor
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = false
	body.Parent = model

	-- Shadow: flat dark cylinder beneath the pet (visual ground shadow)
	local shadow = Instance.new("Part")
	shadow.Name = "Shadow"
	shadow.Shape = Enum.PartType.Cylinder
	shadow.Size = Vector3.new(0.1, 2.2, 2.2)
	shadow.Color = Color3.fromRGB(20, 20, 20)
	shadow.Material = Enum.Material.SmoothPlastic
	shadow.Transparency = 0.6
	shadow.Anchored = true
	shadow.CanCollide = false
	-- Shadow is placed on the ground below the pet (will be repositioned in update)
	shadow.CFrame = CFrame.new(body.Position - Vector3.new(0, self._followHeight - 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90))
	shadow.Parent = model

	-- Name label above pet (nametag with pet name and rarity)
	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "NameLabel"
	billboardGui.Size = UDim2.fromOffset(120, 30)
	billboardGui.StudsOffset = Vector3.new(0, 1.8, 0)
	billboardGui.AlwaysOnTop = true
	billboardGui.Adornee = body
	billboardGui.Parent = model

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameText"
	nameLabel.Size = UDim2.fromScale(1, 0.65)
	nameLabel.Position = UDim2.fromScale(0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = petName
	nameLabel.TextColor3 = bodyColor
	nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.Parent = billboardGui

	-- Rarity subtitle under name
	local rarityLabel = Instance.new("TextLabel")
	rarityLabel.Name = "RarityText"
	rarityLabel.Size = UDim2.fromScale(1, 0.35)
	rarityLabel.Position = UDim2.fromScale(0, 0.65)
	rarityLabel.BackgroundTransparency = 1
	rarityLabel.Text = rarity
	rarityLabel.TextColor3 = bodyColor
	rarityLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	rarityLabel.TextStrokeTransparency = 0.5
	rarityLabel.Font = Enum.Font.Gotham
	rarityLabel.TextScaled = true
	rarityLabel.Parent = billboardGui

	-- PointLight for glow effect (subtle)
	local light = Instance.new("PointLight")
	light.Name = "PetGlow"
	light.Color = bodyColor
	light.Brightness = 0.5
	light.Range = 4
	light.Parent = body

	model.PrimaryPart = body
	return model
end

--------------------------------------------------------------------------------
-- Update equipped pets: create/remove pet models as needed.
-- CRITICAL: This method ensures EXACTLY 1 model per equipped pet exists.
-- It is safe to call multiple times with the same or different lists.
-- equippedList is an array of pet data tables, each with .id field
--------------------------------------------------------------------------------
function PetController:updateEquippedPets(equippedList)
	if not self._initialized then return end

	-- Build set of currently equipped IDs from the new list
	local newIds = {}
	for _, petData in ipairs(equippedList) do
		if petData.id then
			newIds[petData.id] = petData
		end
	end

	-- Remove old models that are no longer equipped
	for uniqueId, petInfo in pairs(self._equippedPets) do
		if not newIds[uniqueId] then
			if petInfo.model and petInfo.model.Parent then
				petInfo.model:Destroy()
			end
			self._equippedPets[uniqueId] = nil
		end
	end

	-- Safety: destroy any orphaned models in the pets folder that are not tracked
	-- This prevents duplicates from race conditions or script restarts
	if self._petsFolder then
		local trackedModelNames = {}
		for _, petInfo in pairs(self._equippedPets) do
			if petInfo.model then
				trackedModelNames[petInfo.model] = true
			end
		end
		for _, child in ipairs(self._petsFolder:GetChildren()) do
			if child:IsA("Model") and not trackedModelNames[child] then
				child:Destroy()
			end
		end
	end

	-- Create new models ONLY for newly equipped pets (not already tracked)
	local idx = 1
	for i, petData in ipairs(equippedList) do
		if petData.id and not self._equippedPets[petData.id] then
			local model = self:createPetModel(petData)
			model.Parent = self._petsFolder

			self._equippedPets[petData.id] = {
				model = model,
				data = petData,
				followIndex = i,
			}
		end
	end

	-- Reassign follow indices to ensure proper formation
	idx = 1
	for _, petInfo in pairs(self._equippedPets) do
		petInfo.followIndex = idx
		idx = idx + 1
	end
end

--------------------------------------------------------------------------------
-- Per-frame update: pets follow behind the player in a trailing formation
-- Pets float 2.5 studs above the ground with a shadow beneath them
--------------------------------------------------------------------------------
function PetController:update(deltaTime)
	if not self._initialized then return end

	local character = self._player.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local playerPos = rootPart.Position
	-- Get the direction the player is facing (look vector)
	local lookVector = rootPart.CFrame.LookVector
	-- The "behind" direction is opposite to look
	local behindVector = -lookVector
	-- Right vector for lateral offset
	local rightVector = rootPart.CFrame.RightVector

	-- Apply FasterPets upgrade to follow speed
	local effectiveLerpSpeed = self._followLerpSpeed
	if self._fasterPetsMultiplier and self._fasterPetsMultiplier > 0 then
		effectiveLerpSpeed = effectiveLerpSpeed * self._fasterPetsMultiplier
	end

	for uniqueId, petInfo in pairs(self._equippedPets) do
		if not self._attackingPets[uniqueId] then
			local index = petInfo.followIndex or 1
			-- Calculate row and column in the formation
			local row = math.ceil(index / self._petsPerRow) -- which row (1, 2, 3...)
			local col = ((index - 1) % self._petsPerRow) + 1 -- position in the row

			-- Calculate total pets to determine this row's actual count
			local totalPets = 0
			for _ in pairs(self._equippedPets) do
				totalPets = totalPets + 1
			end
			local actualPetsInRow = math.min(self._petsPerRow, totalPets - (row - 1) * self._petsPerRow)

			-- Lateral offset: center the pets in the row
			local lateralOffset = (col - (actualPetsInRow + 1) / 2) * self._followSpread

			-- Distance behind: each row is further back
			local distanceBehind = row * self._followDistance

			-- Calculate target position behind the player, floating above ground
			local targetPos = playerPos
				+ behindVector * distanceBehind
				+ rightVector * lateralOffset
				+ Vector3.new(0, self._followHeight, 0)

			-- Move pet model smoothly toward target
			local model = petInfo.model
			if model and model.PrimaryPart and model.PrimaryPart.Parent then
				local currentPos = model.PrimaryPart.Position
				local newPos = currentPos:Lerp(targetPos, math.min(1, deltaTime * effectiveLerpSpeed))
				local offset = newPos - model.PrimaryPart.Position

				-- Move all parts in model (except shadow which is repositioned separately)
				for _, part in ipairs(model:GetDescendants()) do
					if part:IsA("BasePart") and part.Name ~= "Shadow" then
						part.Position = part.Position + offset
					end
				end

				-- Position shadow on the ground directly below the pet body
				local shadowPart = model:FindFirstChild("Shadow")
				if shadowPart then
					local groundY = playerPos.Y - 2 -- approximate ground level (player feet minus a bit)
					local shadowPos = Vector3.new(newPos.X, groundY + 0.05, newPos.Z)
					shadowPart.CFrame = CFrame.new(shadowPos) * CFrame.Angles(0, 0, math.rad(90))
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Send pet to attack a destructible (visual animation + remote call)
-- destructibleId: string ID of the destructible
-- destructiblePart: optional Part reference for tween target position
-- Moves the entire pet model (all parts) to the destructible and back.
--------------------------------------------------------------------------------
function PetController:sendPetToAttack(uniqueId, destructibleId, destructiblePart)
	if not self._initialized then return end
	local petInfo = self._equippedPets[uniqueId]
	if not petInfo or not petInfo.model then return end
	if self._attackingPets[uniqueId] then return end

	self._attackingPets[uniqueId] = true

	local model = petInfo.model

	-- If we have the Part, use its position for the tween target
	local targetPos
	if destructiblePart and typeof(destructiblePart) == "Instance" and destructiblePart:IsA("BasePart") then
		targetPos = destructiblePart.Position
	else
		-- Fallback: attack in front of player
		local character = self._player.Character
		if character and character:FindFirstChild("HumanoidRootPart") then
			targetPos = character.HumanoidRootPart.Position + character.HumanoidRootPart.CFrame.LookVector * 5
		else
			self._attackingPets[uniqueId] = nil
			return
		end
	end

	-- Move entire model (all parts) to the destructible using a coroutine-based animation
	if model.PrimaryPart and model.PrimaryPart.Parent then
		local startPos = model.PrimaryPart.Position
		local attackPos = targetPos + Vector3.new(0, 1.5, -2)
		local attackDuration = 0.35
		local returnDuration = 0.4

		-- Animate toward destructible
		task.spawn(function()
			local startTime = tick()
			while true do
				local elapsed = tick() - startTime
				local alpha = math.min(elapsed / attackDuration, 1)
				-- Ease out quad
				local easedAlpha = 1 - (1 - alpha) * (1 - alpha)

				if not model or not model.PrimaryPart or not model.PrimaryPart.Parent then
					self._attackingPets[uniqueId] = nil
					return
				end

				local currentPos = model.PrimaryPart.Position
				local desiredPos = startPos:Lerp(attackPos, easedAlpha)
				local offset = desiredPos - currentPos

				-- Move all parts in model together
				for _, part in ipairs(model:GetDescendants()) do
					if part:IsA("BasePart") and part.Name ~= "Shadow" then
						part.Position = part.Position + offset
					end
				end

				-- Reposition shadow on the ground below
				local shadowPart = model:FindFirstChild("Shadow")
				if shadowPart then
					local groundY = desiredPos.Y - self._followHeight + 0.05
					shadowPart.CFrame = CFrame.new(desiredPos.X, groundY, desiredPos.Z) * CFrame.Angles(0, 0, math.rad(90))
				end

				if alpha >= 1 then break end
				task.wait()
			end

			-- Brief pause at destructible (impact moment)
			task.wait(0.2)

			-- Return to follow position (let the update loop take over)
			self._attackingPets[uniqueId] = nil
		end)
	else
		self._attackingPets[uniqueId] = nil
	end
end

--------------------------------------------------------------------------------
-- Fire attack remote once with string destructibleId (called from Main.client)
--------------------------------------------------------------------------------
function PetController:fireAttackRemote(destructibleId)
	if not self._initialized then return end
	if not self._remotes then return end

	local attackRemote = self._remotes:FindFirstChild("AttackDestructible")
	if attackRemote then
		attackRemote:InvokeServer(destructibleId)
	end
end

--------------------------------------------------------------------------------
-- Show floating damage text above a destructible
--------------------------------------------------------------------------------
function PetController:showDamageText(position, damage)
	if not self._initialized then return end

	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "DamagePopup"
	billboardGui.Size = UDim2.fromOffset(80, 30)
	billboardGui.StudsOffset = Vector3.new(math.random(-1, 1), 2, 0)
	billboardGui.AlwaysOnTop = true

	local anchor = Instance.new("Part")
	anchor.Name = "DmgAnchor"
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Position = position + Vector3.new(0, 1, 0)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Parent = self._petsFolder

	billboardGui.Adornee = anchor
	billboardGui.Parent = self._player:WaitForChild("PlayerGui")

	local label = Instance.new("TextLabel")
	label.Name = "DmgText"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "-" .. tostring(damage)
	label.TextColor3 = Color3.fromRGB(255, 80, 80)
	label.TextStrokeColor3 = Color3.fromRGB(50, 0, 0)
	label.TextStrokeTransparency = 0.3
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = billboardGui

	-- Float upward and fade
	local tweenInfo = TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local moveTween = TweenService:Create(anchor, tweenInfo, {
		Position = position + Vector3.new(0, 4, 0),
	})
	local fadeTween = TweenService:Create(label, tweenInfo, {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})

	moveTween:Play()
	fadeTween:Play()

	fadeTween.Completed:Connect(function()
		billboardGui:Destroy()
		anchor:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Get nearest destructible to player within a radius
-- Searches workspace.Zones recursively for Parts with a DestructibleId child
--------------------------------------------------------------------------------
function PetController:getNearestDestructible(maxDistance)
	if not self._initialized then return nil end

	local character = self._player.Character
	if not character then return nil end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return nil end

	local playerPos = rootPart.Position
	local nearest = nil
	local nearestDist = maxDistance or 30

	-- Look for destructibles recursively under workspace.Zones
	local zonesFolder = workspace:FindFirstChild("Zones")
	if not zonesFolder then return nil end

	for _, obj in ipairs(zonesFolder:GetDescendants()) do
		if obj:IsA("BasePart") and obj:FindFirstChild("DestructibleId") then
			local dist = (obj.Position - playerPos).Magnitude
			if dist < nearestDist then
				nearestDist = dist
				nearest = obj
			end
		end
	end

	return nearest
end

--------------------------------------------------------------------------------
-- Auto-attack system: pets automatically find and attack nearby destructibles
--------------------------------------------------------------------------------
function PetController:_startAutoAttack()
	if self._autoAttackConnection then return end

	self._autoAttackConnection = RunService.Heartbeat:Connect(function()
		if not self._autoAttackEnabled then return end
		if not self._initialized then return end

		-- Check if enough time has passed since last attack
		local now = tick()
		if now - self._lastAutoAttackTime < self._autoAttackInterval then
			return
		end

		-- Check if we have any equipped pets
		local hasPets = false
		for _ in pairs(self._equippedPets) do
			hasPets = true
			break
		end
		if not hasPets then return end

		-- Find nearest destructible within range
		local nearest = self:getNearestDestructible(self._autoAttackRange)
		if not nearest then return end

		-- Get the destructible ID
		local idValue = nearest:FindFirstChild("DestructibleId")
		if not idValue then return end
		local destructibleId = idValue.Value

		-- Update last attack time
		self._lastAutoAttackTime = now

		-- Send all equipped pets to visually attack
		for uniqueId, _ in pairs(self._equippedPets) do
			self:sendPetToAttack(uniqueId, destructibleId, nearest)
		end

		-- Fire the attack remote to server
		self:fireAttackRemote(destructibleId)
	end)
end

function PetController:_stopAutoAttack()
	if self._autoAttackConnection then
		self._autoAttackConnection:Disconnect()
		self._autoAttackConnection = nil
	end
end

--------------------------------------------------------------------------------
-- Set FasterPets upgrade multiplier (called from Main.client when upgrades update)
--------------------------------------------------------------------------------
function PetController:setFasterPetsMultiplier(multiplier)
	self._fasterPetsMultiplier = multiplier or 0
end

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------
function PetController:cleanup()
	self:_stopAutoAttack()
	for _, petInfo in pairs(self._equippedPets) do
		if petInfo.model then
			petInfo.model:Destroy()
		end
	end
	self._equippedPets = {}
	self._attackingPets = {}
	if self._petsFolder then
		self._petsFolder:Destroy()
	end
end

return PetController
