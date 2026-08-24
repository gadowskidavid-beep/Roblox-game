--[[
	PetController.lua - Pet visual management for Battle Pets
	Creates procedural pet models (Part-based), handles following/orbiting the player,
	animates pets toward destructibles to attack, and shows floating damage numbers.
	All visuals are procedural with no external assets.
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
	self._equippedPets = {} -- { uniqueId = { model = Model, data = petData, orbitAngle = number } }
	self._petsFolder = nil
	self._orbitRadius = 4
	self._orbitSpeed = 1.5
	self._orbitHeightBase = 2
	self._initialized = false
	self._attackingPets = {} -- pets currently attacking a destructible
	return self
end

function PetController:init(remotes)
	self._remotes = remotes
	self._player = Players.LocalPlayer

	-- Create folder for pet models in workspace
	self._petsFolder = Instance.new("Folder")
	self._petsFolder.Name = "ClientPets"
	self._petsFolder.Parent = workspace

	self._initialized = true
end

--------------------------------------------------------------------------------
-- Create a procedural pet model: body sphere + head sphere + eyes, welded together
--------------------------------------------------------------------------------
function PetController:createPetModel(petData)
	local rarity = petData.rarity or "Common"
	local bodyColor = RARITY_COLORS[rarity] or RARITY_COLORS.Common
	local petName = petData.name or "Pet"

	local model = Instance.new("Model")
	model.Name = petName .. "_Model"

	-- Body: larger sphere
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(1.8, 1.8, 1.8)
	body.Color = bodyColor
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = false
	body.Parent = model

	-- Head: smaller sphere on top
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.Color = bodyColor
	head.Material = Enum.Material.SmoothPlastic
	head.Anchored = true
	head.CanCollide = false
	head.CFrame = body.CFrame + Vector3.new(0, 1.2, 0)
	head.Parent = model

	-- Left eye: tiny black sphere
	local leftEye = Instance.new("Part")
	leftEye.Name = "LeftEye"
	leftEye.Shape = Enum.PartType.Ball
	leftEye.Size = Vector3.new(0.25, 0.25, 0.25)
	leftEye.Color = Color3.fromRGB(10, 10, 10)
	leftEye.Material = Enum.Material.SmoothPlastic
	leftEye.Anchored = true
	leftEye.CanCollide = false
	leftEye.CFrame = head.CFrame + Vector3.new(-0.25, 0.1, -0.5)
	leftEye.Parent = model

	-- Right eye: tiny black sphere
	local rightEye = Instance.new("Part")
	rightEye.Name = "RightEye"
	rightEye.Shape = Enum.PartType.Ball
	rightEye.Size = Vector3.new(0.25, 0.25, 0.25)
	rightEye.Color = Color3.fromRGB(10, 10, 10)
	rightEye.Material = Enum.Material.SmoothPlastic
	rightEye.Anchored = true
	rightEye.CanCollide = false
	rightEye.CFrame = head.CFrame + Vector3.new(0.25, 0.1, -0.5)
	rightEye.Parent = model

	-- Name label above pet
	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "NameLabel"
	billboardGui.Size = UDim2.fromOffset(100, 24)
	billboardGui.StudsOffset = Vector3.new(0, 2, 0)
	billboardGui.AlwaysOnTop = true
	billboardGui.Adornee = head
	billboardGui.Parent = model

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameText"
	nameLabel.Size = UDim2.fromScale(1, 1)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = petName
	nameLabel.TextColor3 = bodyColor
	nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.Parent = billboardGui

	model.PrimaryPart = body
	return model
end

--------------------------------------------------------------------------------
-- Update equipped pets: create/remove pet models as needed
-- equippedList is an array of pet data tables, each with .id field
--------------------------------------------------------------------------------
function PetController:updateEquippedPets(equippedList)
	if not self._initialized then return end

	-- Build set of currently equipped IDs from the new list
	local newIds = {}
	for _, petData in ipairs(equippedList) do
		newIds[petData.id] = true
	end

	-- Remove old models that are no longer equipped
	for uniqueId, petInfo in pairs(self._equippedPets) do
		if not newIds[uniqueId] then
			if petInfo.model then
				petInfo.model:Destroy()
			end
			self._equippedPets[uniqueId] = nil
		end
	end

	-- Create new models for newly equipped pets
	for i, petData in ipairs(equippedList) do
		if not self._equippedPets[petData.id] then
			local model = self:createPetModel(petData)
			model.Parent = self._petsFolder

			self._equippedPets[petData.id] = {
				model = model,
				data = petData,
				orbitAngle = (i / #equippedList) * math.pi * 2,
				orbitHeight = self._orbitHeightBase + (i - 1) * 0.5,
			}
		end
	end
end

--------------------------------------------------------------------------------
-- Per-frame update: pets orbit around the player character
--------------------------------------------------------------------------------
function PetController:update(deltaTime)
	if not self._initialized then return end

	local character = self._player.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local playerPos = rootPart.Position

	for uniqueId, petInfo in pairs(self._equippedPets) do
		if not self._attackingPets[uniqueId] then
			-- Update orbit angle
			petInfo.orbitAngle = petInfo.orbitAngle + self._orbitSpeed * deltaTime

			-- Calculate orbit position
			local orbitX = math.cos(petInfo.orbitAngle) * self._orbitRadius
			local orbitZ = math.sin(petInfo.orbitAngle) * self._orbitRadius
			local targetPos = playerPos + Vector3.new(orbitX, petInfo.orbitHeight, orbitZ)

			-- Move pet model
			local model = petInfo.model
			if model and model.PrimaryPart then
				local currentPos = model.PrimaryPart.Position
				local newPos = currentPos:Lerp(targetPos, math.min(1, deltaTime * 5))
				local offset = newPos - model.PrimaryPart.Position

				-- Move all parts in model
				for _, part in ipairs(model:GetDescendants()) do
					if part:IsA("BasePart") then
						part.Position = part.Position + offset
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Send pet to attack a destructible (visual animation + remote call)
-- destructibleId: string ID of the destructible
-- destructiblePart: optional Part reference for tween target position
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

	-- Tween pet toward destructible
	if model.PrimaryPart then
		local attackPos = targetPos + Vector3.new(0, 1, -2)
		local tweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tween = TweenService:Create(model.PrimaryPart, tweenInfo, {
			Position = attackPos,
		})
		tween:Play()

		tween.Completed:Connect(function()
			-- Return to orbit after a short delay
			task.delay(0.3, function()
				self._attackingPets[uniqueId] = nil
			end)
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
-- Cleanup
--------------------------------------------------------------------------------
function PetController:cleanup()
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
