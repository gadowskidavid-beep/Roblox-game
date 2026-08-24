--[[
	PetController.lua - Pet visual management for Battle Pets
	Creates procedural pet models (Part-based), handles pets following behind the
	player in a trailing formation, animates pets toward destructibles to attack,
	and shows floating damage numbers. All visuals are procedural with no external assets.

	TARGETING SYSTEM (Pet Simulator 1 style):
	- Idle mode: Each pet auto-distributes to a DIFFERENT nearby destructible
	- Single click: Send only 1 pet to the clicked target
	- Hold click (0.3s+): Send ALL pets to the clicked target
	- When a destructible is destroyed, pet auto-finds next available target

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
	self._followHeight = 0.5 -- height offset above ground (ground level walking)
	self._followLerpSpeed = 1.5 -- smoothing speed for following (very slow for natural walking)
	self._petsPerRow = 3 -- max pets per row behind the player
	self._initialized = false
	self._initGuard = false -- prevents double initialization
	self._attackingPets = {} -- pets currently animating attack on a destructible
	-- Auto-attack state (distributed targeting)
	self._autoAttackEnabled = true
	self._autoAttackInterval = 1.5 -- seconds between auto-attacks per pet
	self._autoAttackRange = 40 -- studs detection range
	self._autoAttackConnection = nil
	-- Per-pet targeting: each pet has its own assigned target
	self._petTargets = {} -- { uniqueId = { destructibleId = string, part = BasePart, lastAttackTime = number } }
	-- Manual targeting mode
	self._manualTargetMode = false -- when true, pets follow manual orders instead of auto
	self._manualTargetExpiry = 0 -- tick() when manual mode expires
	self._manualTargetDuration = 5 -- seconds before reverting to auto-distribute
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

	-- Start auto-attack loop (distributed targeting)
	self:_startAutoAttack()
end

--------------------------------------------------------------------------------
-- Create a procedural pet model: body sphere + shadow + nametag + rarity glow
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
	shadow.CFrame = CFrame.new(body.Position - Vector3.new(0, self._followHeight + 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90))
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

	-- Rarity-based glow (PointLight with brightness/range varying by rarity)
	-- Common=white dim, Uncommon=green, Rare=blue, Epic=purple, Legendary=gold strong
	local glowSettings = {
		Common = { brightness = 0.3, range = 3, color = Color3.fromRGB(255, 255, 255) },
		Uncommon = { brightness = 0.7, range = 5, color = Color3.fromRGB(0, 220, 50) },
		Rare = { brightness = 1.2, range = 7, color = Color3.fromRGB(0, 120, 255) },
		Epic = { brightness = 1.8, range = 9, color = Color3.fromRGB(180, 50, 255) },
		Legendary = { brightness = 3.0, range = 12, color = Color3.fromRGB(255, 200, 0) },
	}

	local glow = glowSettings[rarity] or glowSettings.Common
	local light = Instance.new("PointLight")
	light.Name = "PetGlow"
	light.Color = glow.color
	light.Brightness = glow.brightness
	light.Range = glow.range
	light.Parent = body

	-- Rarity particle ring (orbiting small sphere for Rare+)
	-- Creates 2-4 tiny orbiting particles for rarer pets
	if rarity == "Rare" or rarity == "Epic" or rarity == "Legendary" then
		local numParticles = rarity == "Legendary" and 4 or (rarity == "Epic" and 3 or 2)
		for i = 1, numParticles do
			local particle = Instance.new("Part")
			particle.Name = "GlowParticle_" .. i
			particle.Shape = Enum.PartType.Ball
			particle.Size = Vector3.new(0.4, 0.4, 0.4)
			particle.Color = glow.color
			particle.Material = Enum.Material.Neon
			particle.Transparency = 0.3
			particle.Anchored = true
			particle.CanCollide = false
			particle.Position = body.Position + Vector3.new(1.5, 0, 0)
			particle.Parent = model
		end
	end

	-- Golden pets get extra sparkle effect (larger size, extra glow)
	if petData.golden then
		body.Size = Vector3.new(2.6, 2.6, 2.6)
		body.Material = Enum.Material.Neon
		body.Color = Color3.fromRGB(255, 215, 0)
		light.Brightness = 4
		light.Range = 14
		light.Color = Color3.fromRGB(255, 200, 0)
	end

	model.PrimaryPart = body
	return model
end

--------------------------------------------------------------------------------
-- Update equipped pets: create/remove pet models as needed.
-- CRITICAL: This method ensures EXACTLY 1 model per equipped pet exists.
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
			-- Clear targeting info for removed pet
			self._petTargets[uniqueId] = nil
		end
	end

	-- Safety: destroy any orphaned models in the pets folder that are not tracked
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
	local idx = 1
	for _, petInfo in pairs(self._equippedPets) do
		petInfo.followIndex = idx
		idx = idx + 1
	end
end

--------------------------------------------------------------------------------
-- Per-frame update: pets follow behind the player in a trailing formation
-- Pets float 2.5 studs above the ground with a shadow beneath them
-- Rarity glow particles orbit the pet body for Rare+ pets
--------------------------------------------------------------------------------
function PetController:update(deltaTime)
	if not self._initialized then return end

	local character = self._player.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local playerPos = rootPart.Position
	local lookVector = rootPart.CFrame.LookVector
	local behindVector = -lookVector
	local rightVector = rootPart.CFrame.RightVector

	-- Apply FasterPets upgrade to follow speed
	local effectiveLerpSpeed = self._followLerpSpeed
	if self._fasterPetsMultiplier and self._fasterPetsMultiplier > 0 then
		effectiveLerpSpeed = effectiveLerpSpeed * self._fasterPetsMultiplier
	end

	-- Check if manual target mode has expired
	if self._manualTargetMode and tick() > self._manualTargetExpiry then
		self._manualTargetMode = false
	end

	-- Increment orbit timer for glow particles
	if not self._orbitTimer then
		self._orbitTimer = 0
	end
	self._orbitTimer = self._orbitTimer + deltaTime

	for uniqueId, petInfo in pairs(self._equippedPets) do
		if not self._attackingPets[uniqueId] then
			local index = petInfo.followIndex or 1
			local row = math.ceil(index / self._petsPerRow)
			local col = ((index - 1) % self._petsPerRow) + 1

			local totalPets = 0
			for _ in pairs(self._equippedPets) do
				totalPets = totalPets + 1
			end
			local actualPetsInRow = math.min(self._petsPerRow, totalPets - (row - 1) * self._petsPerRow)

			local lateralOffset = (col - (actualPetsInRow + 1) / 2) * self._followSpread
			local distanceBehind = row * self._followDistance

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

				for _, part in ipairs(model:GetDescendants()) do
					if part:IsA("BasePart") and part.Name ~= "Shadow" and not part.Name:find("GlowParticle") then
						part.Position = part.Position + offset
					end
				end

				-- Position shadow on the ground directly below the pet body
				local shadowPart = model:FindFirstChild("Shadow")
				if shadowPart then
					local groundY = playerPos.Y - 2
					local shadowPos = Vector3.new(newPos.X, groundY + 0.05, newPos.Z)
					shadowPart.CFrame = CFrame.new(shadowPos) * CFrame.Angles(0, 0, math.rad(90))
				end

				-- Orbit glow particles around the pet body
				self:_updateGlowParticles(model, newPos, index)
			end
		end
	end
end

-- Animate glow particles orbiting around the pet (for Rare+ pets)
function PetController:_updateGlowParticles(model, bodyPos, petIndex)
	local particleIdx = 0
	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") and part.Name:find("GlowParticle") then
			particleIdx = particleIdx + 1
			local angleOffset = (particleIdx / 5) * math.pi * 2
			local orbitRadius = 1.6
			local orbitSpeed = 2.5
			local bobSpeed = 3.0

			local angle = self._orbitTimer * orbitSpeed + angleOffset + petIndex * 1.2
			local orbitX = math.cos(angle) * orbitRadius
			local orbitZ = math.sin(angle) * orbitRadius
			local orbitY = math.sin(self._orbitTimer * bobSpeed + particleIdx) * 0.4

			part.Position = bodyPos + Vector3.new(orbitX, orbitY, orbitZ)
		end
	end
end

--------------------------------------------------------------------------------
-- Send pet to attack a destructible (visual animation)
-- destructibleId: string ID of the destructible
-- destructiblePart: optional Part reference for tween target position
-- The pet moves SLOWLY to the destructible and STAYS THERE bouncing until the
-- destructible is destroyed or the player moves >60 studs away.
-- Pet hovers ~1 stud beside the destructible (offset so it is not inside it).
--------------------------------------------------------------------------------
function PetController:sendPetToAttack(uniqueId, destructibleId, destructiblePart)
	if not self._initialized then return end
	local petInfo = self._equippedPets[uniqueId]
	if not petInfo or not petInfo.model then return end
	-- If already stationed at THIS destructible, do not restart the movement
	if self._attackingPets[uniqueId] and self._attackingPets[uniqueId] == destructibleId then
		return
	end

	-- Mark as attacking this specific destructible
	self._attackingPets[uniqueId] = destructibleId

	local model = petInfo.model

	-- Determine target position: on the ground beside the destructible
	local targetPos
	if destructiblePart and typeof(destructiblePart) == "Instance" and destructiblePart:IsA("BasePart") then
		-- Offset to the side (use a per-pet angle to distribute around the destructible)
		local petIndex = petInfo.followIndex or 1
		local angle = (petIndex - 1) * (math.pi * 2 / 6) -- distribute evenly around
		local offsetX = math.cos(angle) * 2.5
		local offsetZ = math.sin(angle) * 2.5
		targetPos = destructiblePart.Position + Vector3.new(offsetX, 0, offsetZ)
		-- Keep pet at ground level (use followHeight offset)
		targetPos = Vector3.new(targetPos.X, destructiblePart.Position.Y - destructiblePart.Size.Y / 2 + self._followHeight, targetPos.Z)
	else
		local character = self._player.Character
		if character and character:FindFirstChild("HumanoidRootPart") then
			targetPos = character.HumanoidRootPart.Position + character.HumanoidRootPart.CFrame.LookVector * 5
		else
			self._attackingPets[uniqueId] = nil
			return
		end
	end

	-- Slow approach using per-frame lerp at speed 1.5 (very slow and natural, walking pace)
	if model.PrimaryPart and model.PrimaryPart.Parent then
		task.spawn(function()
			local APPROACH_SPEED = 1.5 -- very slow lerp speed (walking)
			local BOUNCE_SPEED = 3.0 -- oscillation speed when stationed
			local BOUNCE_HEIGHT = 0.3 -- how much it bobs up and down
			local MAX_PLAYER_DIST = 60 -- return threshold

			-- Phase 1: Slow approach to the destructible
			while self._attackingPets[uniqueId] == destructibleId do
				if not model or not model.PrimaryPart or not model.PrimaryPart.Parent then
					self._attackingPets[uniqueId] = nil
					return
				end

				-- Check if destructible still exists
				if destructiblePart and typeof(destructiblePart) == "Instance" then
					if not destructiblePart.Parent then
						-- Destructible was destroyed, return to follow
						self._attackingPets[uniqueId] = nil
						return
					end
				end

				-- Check player distance
				local character = self._player.Character
				if character then
					local rootPart = character:FindFirstChild("HumanoidRootPart")
					if rootPart then
						local playerDist = (rootPart.Position - model.PrimaryPart.Position).Magnitude
						if playerDist > MAX_PLAYER_DIST then
							-- Too far from player, return
							self._attackingPets[uniqueId] = nil
							return
						end
					end
				end

				local currentPos = model.PrimaryPart.Position
				local dist = (currentPos - targetPos).Magnitude
				if dist < 0.5 then
					break -- close enough, transition to bounce phase
				end

				-- Slow lerp toward target
				local dt = task.wait()
				local alpha = math.min(1, dt * APPROACH_SPEED)
				local newPos = currentPos:Lerp(targetPos, alpha)
				local offset = newPos - currentPos

				for _, part in ipairs(model:GetDescendants()) do
					if part:IsA("BasePart") and part.Name ~= "Shadow" then
						part.Position = part.Position + offset
					end
				end

				-- Update shadow
				local shadowPart = model:FindFirstChild("Shadow")
				if shadowPart then
					local groundY = newPos.Y - self._followHeight + 0.05
					shadowPart.CFrame = CFrame.new(newPos.X, groundY, newPos.Z) * CFrame.Angles(0, 0, math.rad(90))
				end
			end

			-- Phase 2: Stay at destructible with bounce animation (attack wobble)
			local bounceTime = 0
			while self._attackingPets[uniqueId] == destructibleId do
				if not model or not model.PrimaryPart or not model.PrimaryPart.Parent then
					self._attackingPets[uniqueId] = nil
					return
				end

				-- Check if destructible still exists
				if destructiblePart and typeof(destructiblePart) == "Instance" then
					if not destructiblePart.Parent then
						-- Destructible destroyed, return to follow
						self._attackingPets[uniqueId] = nil
						return
					end
				end

				-- Check player distance
				local character = self._player.Character
				if character then
					local rootPart = character:FindFirstChild("HumanoidRootPart")
					if rootPart then
						local playerDist = (rootPart.Position - model.PrimaryPart.Position).Magnitude
						if playerDist > MAX_PLAYER_DIST then
							self._attackingPets[uniqueId] = nil
							return
						end
					end
				end

				local dt = task.wait()
				bounceTime = bounceTime + dt

				-- Gentle bounce (bob up and down)
				local bounceOffset = math.sin(bounceTime * BOUNCE_SPEED) * BOUNCE_HEIGHT
				local desiredPos = targetPos + Vector3.new(0, bounceOffset, 0)
				local currentPos = model.PrimaryPart.Position
				local offset = desiredPos - currentPos

				for _, part in ipairs(model:GetDescendants()) do
					if part:IsA("BasePart") and part.Name ~= "Shadow" then
						part.Position = part.Position + offset
					end
				end

				-- Update shadow
				local shadowPart = model:FindFirstChild("Shadow")
				if shadowPart then
					local groundY = desiredPos.Y - self._followHeight + 0.05
					shadowPart.CFrame = CFrame.new(desiredPos.X, groundY, desiredPos.Z) * CFrame.Angles(0, 0, math.rad(90))
				end
			end
		end)
	else
		self._attackingPets[uniqueId] = nil
	end
end

--------------------------------------------------------------------------------
-- Fire attack remote once with string destructibleId (called from Main.client)
-- numPets: how many pets are attacking (1 for single click, all for hold)
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
-- Get ALL destructibles within range, sorted by distance
-- Returns array of { part = BasePart, id = string, distance = number }
--------------------------------------------------------------------------------
function PetController:getAllDestructiblesInRange(maxDistance)
	if not self._initialized then return {} end

	local character = self._player.Character
	if not character then return {} end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return {} end

	local playerPos = rootPart.Position
	local results = {}

	local zonesFolder = workspace:FindFirstChild("Zones")
	if not zonesFolder then return {} end

	for _, obj in ipairs(zonesFolder:GetDescendants()) do
		if obj:IsA("BasePart") and obj:FindFirstChild("DestructibleId") then
			local dist = (obj.Position - playerPos).Magnitude
			if dist < (maxDistance or 40) then
				table.insert(results, {
					part = obj,
					id = obj:FindFirstChild("DestructibleId").Value,
					distance = dist,
				})
			end
		end
	end

	-- Sort by distance (nearest first)
	table.sort(results, function(a, b)
		return a.distance < b.distance
	end)

	return results
end

--------------------------------------------------------------------------------
-- Get nearest destructible (legacy helper)
--------------------------------------------------------------------------------
function PetController:getNearestDestructible(maxDistance)
	local all = self:getAllDestructiblesInRange(maxDistance)
	if #all > 0 then
		return all[1].part
	end
	return nil
end

--------------------------------------------------------------------------------
-- DISTRIBUTED AUTO-ATTACK: Each pet picks its own unique target
-- Pets spread out to different destructibles instead of all attacking the same one.
-- Pets STAY at their target (sendPetToAttack handles stationing) and the remote
-- is fired periodically for damage while the pet is stationed there.
--------------------------------------------------------------------------------
function PetController:_startAutoAttack()
	if self._autoAttackConnection then return end

	self._autoAttackConnection = RunService.Heartbeat:Connect(function()
		if not self._autoAttackEnabled then return end
		if not self._initialized then return end
		-- Skip auto-attack while in manual target mode
		if self._manualTargetMode then return end

		-- Check if we have any equipped pets
		local hasPets = false
		for _ in pairs(self._equippedPets) do
			hasPets = true
			break
		end
		if not hasPets then return end

		-- Get all destructibles within range
		local destructibles = self:getAllDestructiblesInRange(self._autoAttackRange)
		if #destructibles == 0 then
			-- Clear all targets if nothing in range
			for petId, _ in pairs(self._petTargets) do
				self._petTargets[petId] = nil
				-- Release the pet from stationed state
				if self._attackingPets[petId] then
					self._attackingPets[petId] = nil
				end
			end
			return
		end

		-- Build a set of which destructible IDs are already targeted by a pet
		local targetedIds = {}
		for petId, targetInfo in pairs(self._petTargets) do
			-- Only count as targeted if the pet still exists
			if self._equippedPets[petId] then
				targetedIds[targetInfo.destructibleId] = true
			end
		end

		-- For each equipped pet, assign a target if it does not have one or its target is gone
		local now = tick()
		for uniqueId, _ in pairs(self._equippedPets) do
			local currentTarget = self._petTargets[uniqueId]

			-- Check if current target is still valid (exists in destructibles list)
			local targetStillValid = false
			if currentTarget then
				for _, d in ipairs(destructibles) do
					if d.id == currentTarget.destructibleId then
						targetStillValid = true
						break
					end
				end
			end

			-- If target is invalid/missing, assign a new one
			if not targetStillValid then
				self._petTargets[uniqueId] = nil
				-- Release stationing
				if self._attackingPets[uniqueId] then
					self._attackingPets[uniqueId] = nil
				end
				-- Remove from targeted set
				if currentTarget then
					targetedIds[currentTarget.destructibleId] = nil
				end

				-- Find the nearest destructible NOT already targeted by another pet
				local assigned = false
				for _, d in ipairs(destructibles) do
					if not targetedIds[d.id] then
						self._petTargets[uniqueId] = {
							destructibleId = d.id,
							part = d.part,
							lastAttackTime = 0,
						}
						targetedIds[d.id] = true
						assigned = true
						-- Send pet to the new target (it will station there)
						self:sendPetToAttack(uniqueId, d.id, d.part)
						break
					end
				end

				-- If all destructibles are taken, allow sharing (pick nearest)
				if not assigned and #destructibles > 0 then
					local nearest = destructibles[1]
					self._petTargets[uniqueId] = {
						destructibleId = nearest.id,
						part = nearest.part,
						lastAttackTime = 0,
					}
					self:sendPetToAttack(uniqueId, nearest.id, nearest.part)
				end
			else
				-- Target is still valid; ensure the pet is sent there (idempotent)
				if currentTarget and not self._attackingPets[uniqueId] then
					self:sendPetToAttack(uniqueId, currentTarget.destructibleId, currentTarget.part)
				end
			end

			-- Fire attack remote periodically for damage while stationed
			local targetInfo = self._petTargets[uniqueId]
			if targetInfo and (now - targetInfo.lastAttackTime >= self._autoAttackInterval) then
				targetInfo.lastAttackTime = now
				self:fireAttackRemote(targetInfo.destructibleId)
			end
		end
	end)
end

function PetController:_stopAutoAttack()
	if self._autoAttackConnection then
		self._autoAttackConnection:Disconnect()
		self._autoAttackConnection = nil
	end
end

--------------------------------------------------------------------------------
-- MANUAL TARGETING: Send exactly 1 pet to a target (single click)
-- Picks the first available (non-attacking) pet
--------------------------------------------------------------------------------
function PetController:sendOnePetToTarget(destructibleId, destructiblePart)
	if not self._initialized then return end

	-- Find the first pet that is not currently stationed at a target
	local sentPetId = nil
	for uniqueId, _ in pairs(self._equippedPets) do
		if not self._attackingPets[uniqueId] then
			sentPetId = uniqueId
			break
		end
	end

	-- If all pets are busy, pick the first one (will re-assign it)
	if not sentPetId then
		for uniqueId, _ in pairs(self._equippedPets) do
			sentPetId = uniqueId
			break
		end
	end

	if not sentPetId then return end

	-- Release from previous station if any
	self._attackingPets[sentPetId] = nil

	-- Assign this pet's target manually
	self._petTargets[sentPetId] = {
		destructibleId = destructibleId,
		part = destructiblePart,
		lastAttackTime = tick(),
	}

	-- Send the pet visually (it will station there)
	self:sendPetToAttack(sentPetId, destructibleId, destructiblePart)

	-- Fire ONE attack remote (server calculates damage for 1 pet)
	self:fireAttackRemote(destructibleId)

	-- Enter manual target mode briefly so auto-attack doesn't immediately override
	self._manualTargetMode = true
	self._manualTargetExpiry = tick() + self._manualTargetDuration
end

--------------------------------------------------------------------------------
-- MANUAL TARGETING: Send ALL pets to a target (hold click)
--------------------------------------------------------------------------------
function PetController:sendAllPetsToTarget(destructibleId, destructiblePart)
	if not self._initialized then return end

	-- Assign all pets to the same target
	for uniqueId, _ in pairs(self._equippedPets) do
		-- Release from previous station
		self._attackingPets[uniqueId] = nil

		self._petTargets[uniqueId] = {
			destructibleId = destructibleId,
			part = destructiblePart,
			lastAttackTime = tick(),
		}
		self:sendPetToAttack(uniqueId, destructibleId, destructiblePart)
	end

	-- Fire attack remote (server sums all equipped pet damage)
	self:fireAttackRemote(destructibleId)

	-- Enter manual target mode
	self._manualTargetMode = true
	self._manualTargetExpiry = tick() + self._manualTargetDuration
end

--------------------------------------------------------------------------------
-- Clear manual targeting (return to auto-distribute)
--------------------------------------------------------------------------------
function PetController:clearManualTarget()
	self._manualTargetMode = false
	-- Clear all pet targets and release stationing so they re-distribute on next frame
	self._petTargets = {}
	self._attackingPets = {}
end

--------------------------------------------------------------------------------
-- Cancel all pet attacks and return them to following the player
-- Called when player clicks elsewhere or moves away
--------------------------------------------------------------------------------
function PetController:cancelAllAttacks()
	self._manualTargetMode = false
	self._petTargets = {}
	self._attackingPets = {}
end

--------------------------------------------------------------------------------
-- Set FasterPets upgrade multiplier
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
	self._petTargets = {}
	if self._petsFolder then
		self._petsFolder:Destroy()
	end
end

return PetController
