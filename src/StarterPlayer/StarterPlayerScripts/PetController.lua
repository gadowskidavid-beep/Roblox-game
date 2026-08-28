--[[
	PetController.lua - Pet visual management for Battle Pets
	Creates procedural pet models (Part-based), handles pets following behind the
	player in a trailing formation, animates pets toward destructibles to attack,
	and shows floating damage numbers. All visuals are procedural with no external assets.

	TARGETING SYSTEM (Pet Simulator 1 style):
	- Single click: Send only 1 pet to the clicked target
	- Hold click (0.3s+): Send ALL pets to the clicked target
	- Manually assigned pets keep attacking until their target is gone

	IMPORTANT: Only ONE model per equipped pet must exist at any time.
	The updateEquippedPets method enforces this by destroying all old models
	before creating new ones when the equipped list changes.
]]

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetVariantPresentation = require(Shared:WaitForChild("PetVariantPresentation"))

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

local RARITY_GLOW_SETTINGS = {
	Common = { brightness = 0.3, range = 3, color = Color3.fromRGB(255, 255, 255) },
	Uncommon = { brightness = 0.7, range = 5, color = Color3.fromRGB(0, 220, 50) },
	Rare = { brightness = 1.2, range = 7, color = Color3.fromRGB(0, 120, 255) },
	Epic = { brightness = 1.8, range = 9, color = Color3.fromRGB(180, 50, 255) },
	Legendary = { brightness = 3.0, range = 12, color = Color3.fromRGB(255, 200, 0) },
}

local function rgbToColor(rgb)
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function stableHuePhase(value)
	local hash = 0
	for index = 1, #value do
		hash = (hash * 31 + string.byte(value, index)) % 997
	end
	return hash / 997
end

function PetController.new()
	local self = setmetatable({}, PetController)
	self._remotes = nil
	self._equippedPets = {} -- { uniqueId = { model, data, followIndex, attackMarker, attackMarkerGui } }
	self._petsFolder = nil
	-- Follow-behind settings
	self._followDistance = 5 -- distance behind the player per pet slot
	self._followSpread = 3 -- lateral spread for multiple pets in same row
	self._followHeight = 0 -- NO height offset: pets walk on the ground surface
	self._followLerpSpeed = 1.5 -- smoothing speed for following (very slow for natural walking)
	self._petsPerRow = 3 -- max pets per row behind the player
	self._initialized = false
	self._initGuard = false -- prevents double initialization
	self._attackingPets = {} -- pets currently animating attack on a destructible
	-- Pet attacks keep ticking for manually assigned targets. Automatic target
	-- discovery is a separate future AutoFarm upgrade and starts disabled.
	self._autoAttackEnabled = true
	self._autoFarmEnabled = false
	self._autoAttackInterval = 1.5 -- seconds between attacks per assigned pet
	self._autoAttackRange = 40 -- studs detection range
	self._autoAttackConnection = nil
	-- Per-pet targeting: each pet has its own assigned target
	self._petTargets = {} -- { uniqueId = { destructibleId, part, lastAttackTime, assignedAt, assignmentConfirmed } }
	self._assignmentSequence = 0 -- monotonic order for deterministic queue stealing
	self._destructibleIndex = {}
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
	self._assignPetTarget = remotes:WaitForChild("AssignPetTarget")
	self._serverAssignments = {} -- last target confirmed by the server per pet
	self._desiredAssignments = {} -- newest requested target per pet
	self._assignmentVersions = {}
	self._confirmedAssignmentVersions = {}
	self._assignmentStates = {} -- serializes/coalesces RemoteFunction calls per pet
	self._clearRetryCounts = {}
	self._manualOrderVersion = 0

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

	-- Start periodic attacks for manually assigned pets
	self:_startAutoAttack()
end

function PetController:setDestructibleIndex(index)
	self._destructibleIndex = index or {}
end

local function deferAssignmentCallback(callback, accepted)
	if not callback then return end
	task.defer(function()
		local ok, err = pcall(callback, accepted)
		if not ok then
			warn("[Battle Pets] Pet assignment callback failed: " .. tostring(err))
		end
	end)
end

-- Queue assignment changes per pet so RemoteFunction calls cannot arrive at the
-- server out of order. Pending requests are coalesced to the newest target, and
-- every callback receives one terminal result (accepted or superseded/failed).
function PetController:_requestPetTarget(uniqueId, destructibleId, onSettled)
	if not self._assignPetTarget then
		deferAssignmentCallback(onSettled, false)
		return
	end

	local state = self._assignmentStates[uniqueId]
	if not state then
		state = { inFlight = nil, queued = nil }
		self._assignmentStates[uniqueId] = state
	end

	-- Join an equivalent queued request. For A -> B -> A, supersede B and
	-- promote the already in-flight A operation instead of sending A twice.
	if state.queued and state.queued.target == destructibleId then
		if onSettled then table.insert(state.queued.callbacks, onSettled) end
		return
	end
	if state.inFlight and state.inFlight.target == destructibleId then
		if state.queued then
			for _, callback in ipairs(state.queued.callbacks) do
				deferAssignmentCallback(callback, false)
			end
			state.queued = nil

			for _, callback in ipairs(state.inFlight.callbacks) do
				deferAssignmentCallback(callback, false)
			end
			local promotedVersion = (self._assignmentVersions[uniqueId] or 0) + 1
			self._assignmentVersions[uniqueId] = promotedVersion
			self._desiredAssignments[uniqueId] = destructibleId
			state.inFlight.version = promotedVersion
			state.inFlight.callbacks = onSettled and { onSettled } or {}
		elseif onSettled then
			table.insert(state.inFlight.callbacks, onSettled)
		end
		return
	end

	local version = (self._assignmentVersions[uniqueId] or 0) + 1
	self._assignmentVersions[uniqueId] = version
	self._desiredAssignments[uniqueId] = destructibleId
	if destructibleId ~= nil then
		self._clearRetryCounts[uniqueId] = nil
	end

	-- Only the newest not-yet-sent target matters. Superseded callbacks still
	-- complete so Hold aggregations cannot remain pending forever.
	if state.queued then
		for _, callback in ipairs(state.queued.callbacks) do
			deferAssignmentCallback(callback, false)
		end
	end
	state.queued = {
		target = destructibleId,
		version = version,
		callbacks = onSettled and { onSettled } or {},
	}

	if state.inFlight then return end

	local function processNext()
		local operation = state.queued
		if not operation then
			self._assignmentStates[uniqueId] = nil
			return
		end
		state.queued = nil
		state.inFlight = operation

		task.spawn(function()
			local invoked, accepted = pcall(function()
				return self._assignPetTarget:InvokeServer(uniqueId, operation.target)
			end)
			local serverAccepted = invoked and accepted == true
			if serverAccepted then
				self._serverAssignments[uniqueId] = operation.target
				self._confirmedAssignmentVersions[uniqueId] = operation.version
				if operation.target == nil then
					self._clearRetryCounts[uniqueId] = nil
				end
			end

			local isCurrent = self._assignmentVersions[uniqueId] == operation.version
				and self._desiredAssignments[uniqueId] == operation.target
			local currentAccepted = serverAccepted and isCurrent
			local shouldRetryClear = false
			if isCurrent and not serverAccepted then
				if operation.target == nil and self._serverAssignments[uniqueId] ~= nil then
					local retryCount = (self._clearRetryCounts[uniqueId] or 0) + 1
					self._clearRetryCounts[uniqueId] = retryCount
					shouldRetryClear = retryCount <= 3
				else
					self._desiredAssignments[uniqueId] = nil
					if operation.target and self._attackingPets[uniqueId] == operation.target then
						self._attackingPets[uniqueId] = nil
						self._petTargets[uniqueId] = nil
					end
				end
			end

			-- Release the serializer before user callbacks run. Callback errors or
			-- slow AttackDestructible calls cannot block later target changes.
			local callbacks = operation.callbacks
			state.inFlight = nil
			processNext()
			for _, callback in ipairs(callbacks) do
				deferAssignmentCallback(callback, currentAccepted)
			end

			if shouldRetryClear then
				local failedVersion = operation.version
				local retryDelay = 0.2 * (self._clearRetryCounts[uniqueId] or 1)
				task.delay(retryDelay, function()
					if self._assignmentVersions[uniqueId] == failedVersion
						and self._serverAssignments[uniqueId] ~= nil then
						self:_requestPetTarget(uniqueId, nil)
					end
				end)
			end
		end)
	end

	processNext()
end

function PetController:_clearAllPetTargetRequests()
	local assignedPetIds = {}
	for petId in pairs(self._serverAssignments) do
		assignedPetIds[petId] = true
	end
	for petId in pairs(self._desiredAssignments) do
		assignedPetIds[petId] = true
	end
	for petId in pairs(assignedPetIds) do
		self:_requestPetTarget(petId, nil)
	end
end

function PetController:_hasPetTargetRequest(uniqueId)
	return self._desiredAssignments[uniqueId] ~= nil or self._serverAssignments[uniqueId] ~= nil
end

function PetController:_isPetTargetConfirmed(uniqueId, destructibleId)
	return self._serverAssignments[uniqueId] == destructibleId
		and self._desiredAssignments[uniqueId] == destructibleId
		and self._confirmedAssignmentVersions[uniqueId] == self._assignmentVersions[uniqueId]
end

--------------------------------------------------------------------------------
-- Raycast downward to find the ground surface Y at a given XZ position.
-- Returns the ground Y + half the pet body size so the pet sits on the surface.
-- If no ground is found, falls back to the player's HumanoidRootPart Y.
--------------------------------------------------------------------------------
function PetController:_getGroundY(position, fallbackY, extraIgnore, bodyHalfHeight)
	local rayOrigin = Vector3.new(position.X, position.Y + 50, position.Z)
	local rayDirection = Vector3.new(0, -200, 0)

	-- Only collidable surfaces can be pet ground. Explicitly exclude decorative
	-- trees/rocks and the current destructible so pets cannot stand on top of them.
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.RespectCanCollide = true
	local filterList = {}
	if self._petsFolder then
		table.insert(filterList, self._petsFolder)
	end
	local character = self._player and self._player.Character
	if character then
		table.insert(filterList, character)
	end
	local worldDecoration = workspace:FindFirstChild("WorldDecoration")
	if worldDecoration then
		table.insert(filterList, worldDecoration)
	end
	if extraIgnore then
		if typeof(extraIgnore) == "Instance" then
			table.insert(filterList, extraIgnore)
		elseif type(extraIgnore) == "table" then
			for _, instance in ipairs(extraIgnore) do
				if typeof(instance) == "Instance" then
					table.insert(filterList, instance)
				end
			end
		end
	end
	rayParams.FilterDescendantsInstances = filterList

	local result = workspace:Raycast(rayOrigin, rayDirection, rayParams)
	if result then
		-- Ground hit: place the body on the surface using its cached visual size.
		return result.Position.Y + (bodyHalfHeight or 1.1)
	end

	-- No ground found: use fallback (player ground level)
	return (fallbackY or position.Y)
end

--------------------------------------------------------------------------------
-- Apply a canonical variant style to cached model references. Variant changes
-- are idempotent and keep attack/follow state intact; every effect is model-scoped.
--------------------------------------------------------------------------------
function PetController:_applyPetPresentation(visualRefs, petData)
	local descriptor = PetVariantPresentation.resolve(petData)
	local rarity = petData.rarity or "Common"
	local rarityColor = RARITY_COLORS[rarity] or RARITY_COLORS.Common
	local glow = RARITY_GLOW_SETTINGS[rarity] or RARITY_GLOW_SETTINGS.Common
	local baseAccent = descriptor.baseVariant == "Normal"
		and rarityColor
		or rgbToColor(descriptor.accentRGB)
	local shinyColor = rgbToColor(descriptor.shinyRGB)
	local body = visualRefs.body
	local light = visualRefs.light

	body.Size = Vector3.new(2.2, 2.2, 2.2)
	body.Material = Enum.Material.SmoothPlastic
	body.Color = rarityColor
	light.Brightness = glow.brightness
	light.Range = glow.range
	light.Color = glow.color
	visualRefs.bodyHalfHeight = 1.1

	if descriptor.baseVariant == "Golden" then
		body.Size = Vector3.new(2.6, 2.6, 2.6)
		body.Material = Enum.Material.Neon
		body.Color = rgbToColor(descriptor.bodyRGB)
		light.Brightness = 4
		light.Range = 14
		light.Color = baseAccent
		visualRefs.bodyHalfHeight = 1.3
	elseif descriptor.baseVariant == "Rainbow" then
		body.Size = Vector3.new(2.4, 2.4, 2.4)
		body.Material = Enum.Material.Neon
		body.Color = rgbToColor(descriptor.bodyRGB)
		light.Brightness = 3.6
		light.Range = 14
		light.Color = baseAccent
		visualRefs.bodyHalfHeight = 1.2
	end

	visualRefs.nameLabel.Text = descriptor.displayPetName
	visualRefs.nameLabel.TextColor3 = baseAccent
	visualRefs.variantLabel.Text = descriptor.variantLabel .. " • " .. rarity
	visualRefs.variantLabel.TextColor3 = descriptor.isShiny and shinyColor or baseAccent
	for _, particle in ipairs(visualRefs.glowParticles) do
		particle.Color = baseAccent
	end

	if descriptor.isShiny then
		if not visualRefs.shinyHighlight or not visualRefs.shinyHighlight.Parent then
			local highlight = Instance.new("Highlight")
			highlight.Name = "ShinyHighlight"
			highlight.Adornee = visualRefs.model
			highlight.FillColor = shinyColor
			highlight.FillTransparency = 0.72
			highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
			highlight.OutlineTransparency = 0.08
			highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			highlight.Parent = visualRefs.model
			visualRefs.shinyHighlight = highlight
		end
		if not visualRefs.shinyAttachment or not visualRefs.shinyAttachment.Parent then
			local attachment = Instance.new("Attachment")
			attachment.Name = "ShinySparkleAttachment"
			attachment.Parent = body

			local emitter = Instance.new("ParticleEmitter")
			emitter.Name = "ShinySparkles"
			emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			emitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), shinyColor)
			emitter.LightEmission = 0.8
			emitter.Rate = 7
			emitter.Lifetime = NumberRange.new(0.55, 0.9)
			emitter.Speed = NumberRange.new(0.3, 0.8)
			emitter.SpreadAngle = Vector2.new(180, 180)
			emitter.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.18),
				NumberSequenceKeypoint.new(0.5, 0.3),
				NumberSequenceKeypoint.new(1, 0),
			})
			emitter.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.15),
				NumberSequenceKeypoint.new(1, 1),
			})
			emitter.Parent = attachment
			visualRefs.shinyAttachment = attachment
			visualRefs.shinyEmitter = emitter
		end
		if not visualRefs.shinyLight or not visualRefs.shinyLight.Parent then
			local shinyLight = Instance.new("PointLight")
			shinyLight.Name = "ShinyGlow"
			shinyLight.Color = shinyColor
			shinyLight.Brightness = 1
			shinyLight.Range = 7
			shinyLight.Parent = body
			visualRefs.shinyLight = shinyLight
		end
	else
		for _, effect in ipairs({
			visualRefs.shinyHighlight,
			visualRefs.shinyAttachment,
			visualRefs.shinyLight,
		}) do
			if effect and effect.Parent then effect:Destroy() end
		end
		visualRefs.shinyHighlight = nil
		visualRefs.shinyAttachment = nil
		visualRefs.shinyEmitter = nil
		visualRefs.shinyLight = nil
	end

	visualRefs.descriptor = descriptor
	visualRefs.visualKey = descriptor.visualKey
	return descriptor
end

--------------------------------------------------------------------------------
-- Create a procedural pet model: body sphere + shadow + nametag + rarity glow.
-- Returns cached references so the single controller update never scans for
-- variant effects.
--------------------------------------------------------------------------------
function PetController:createPetModel(petData)
	local rarity = petData.rarity or "Common"
	local bodyColor = RARITY_COLORS[rarity] or RARITY_COLORS.Common
	local petName = petData.name or "Pet"

	local model = Instance.new("Model")
	model.Name = petName .. "_Model"

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(2.2, 2.2, 2.2)
	body.Color = bodyColor
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = false
	body.CanTouch = false
	body.CanQuery = false
	body.Parent = model

	local shadow = Instance.new("Part")
	shadow.Name = "Shadow"
	shadow.Shape = Enum.PartType.Cylinder
	shadow.Size = Vector3.new(0.1, 2.2, 2.2)
	shadow.Color = Color3.fromRGB(20, 20, 20)
	shadow.Material = Enum.Material.SmoothPlastic
	shadow.Transparency = 0.6
	shadow.Anchored = true
	shadow.CanCollide = false
	shadow.CanTouch = false
	shadow.CanQuery = false
	shadow.CFrame = CFrame.new(body.Position - Vector3.new(0, 1.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	shadow.Parent = model

	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "NameLabel"
	billboardGui.Size = UDim2.fromOffset(160, 42)
	billboardGui.StudsOffset = Vector3.new(0, 2, 0)
	billboardGui.AlwaysOnTop = true
	billboardGui.Adornee = body
	billboardGui.Parent = model

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameText"
	nameLabel.Size = UDim2.fromScale(1, 0.6)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = petName
	nameLabel.TextColor3 = bodyColor
	nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.Parent = billboardGui

	local variantLabel = Instance.new("TextLabel")
	variantLabel.Name = "VariantText"
	variantLabel.Size = UDim2.fromScale(1, 0.4)
	variantLabel.Position = UDim2.fromScale(0, 0.6)
	variantLabel.BackgroundTransparency = 1
	variantLabel.Text = rarity
	variantLabel.TextColor3 = bodyColor
	variantLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	variantLabel.TextStrokeTransparency = 0.45
	variantLabel.Font = Enum.Font.Gotham
	variantLabel.TextScaled = true
	variantLabel.Parent = billboardGui

	local glow = RARITY_GLOW_SETTINGS[rarity] or RARITY_GLOW_SETTINGS.Common
	local light = Instance.new("PointLight")
	light.Name = "PetGlow"
	light.Color = glow.color
	light.Brightness = glow.brightness
	light.Range = glow.range
	light.Parent = body

	local glowParticles = {}
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
			particle.CanTouch = false
			particle.CanQuery = false
			particle.Position = body.Position + Vector3.new(1.5, 0, 0)
			particle.Parent = model
			table.insert(glowParticles, particle)
		end
	end

	model.PrimaryPart = body
	local visualRefs = {
		model = model,
		body = body,
		shadow = shadow,
		light = light,
		nameLabel = nameLabel,
		variantLabel = variantLabel,
		glowParticles = glowParticles,
		visualPhase = stableHuePhase(tostring(petData.id or petData.uniqueId or petData.petId or petName)),
	}
	self:_applyPetPresentation(visualRefs, petData)
	return model, visualRefs
end

-- Create a flat client-only marker whose asymmetric ring makes rotation visible.
-- It stays parented to the pet model so normal visual cleanup destroys it too.
function PetController:_createAttackMarker(model)
	local marker = Instance.new("Part")
	marker.Name = "AttackMarker"
	marker.Size = Vector3.new(3.8, 0.05, 3.8)
	marker.Transparency = 1
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanTouch = false
	marker.CanQuery = false
	marker.CastShadow = false
	marker.Parent = model

	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "AttackMarkerSurface"
	surfaceGui.Face = Enum.NormalId.Top
	surfaceGui.CanvasSize = Vector2.new(256, 256)
	surfaceGui.LightInfluence = 0
	surfaceGui.Enabled = false
	surfaceGui.Parent = marker

	for i = 1, 16 do
		local angle = ((i - 1) / 16) * math.pi * 2
		local dotSize = i == 1 and 28 or (i % 4 == 0 and 18 or 13)
		local dot = Instance.new("Frame")
		dot.Name = "RingDot_" .. tostring(i)
		dot.Size = UDim2.fromOffset(dotSize, dotSize)
		dot.Position = UDim2.fromOffset(
			128 + math.cos(angle) * 82 - dotSize / 2,
			128 + math.sin(angle) * 82 - dotSize / 2
		)
		dot.BackgroundColor3 = i == 1
			and Color3.fromRGB(255, 245, 120)
			or Color3.fromRGB(255, 145, 35)
		dot.BackgroundTransparency = i % 2 == 0 and 0.15 or 0
		dot.BorderSizePixel = 0
		dot.Parent = surfaceGui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = dot
	end

	local accent = Instance.new("Frame")
	accent.Name = "DirectionAccent"
	accent.Size = UDim2.fromOffset(42, 12)
	accent.Position = UDim2.fromOffset(152, 122)
	accent.BackgroundColor3 = Color3.fromRGB(255, 245, 120)
	accent.BorderSizePixel = 0
	accent.Rotation = -18
	accent.Parent = surfaceGui

	local accentCorner = Instance.new("UICorner")
	accentCorner.CornerRadius = UDim.new(1, 0)
	accentCorner.Parent = accent

	return marker, surfaceGui
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
			self._petTargets[uniqueId] = nil
			self._attackingPets[uniqueId] = nil
			-- Serialize a clear after any in-flight assignment so an unequipped
			-- pet cannot remain authoritative on the server.
			if self._assignPetTarget and self:_hasPetTargetRequest(uniqueId) then
				self:_requestPetTarget(uniqueId, nil)
			end
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

	-- Create new models and synchronize existing entries in the stable order
	-- supplied by equippedList. Never derive followIndex from pairs(), because
	-- dictionary iteration order is not guaranteed in Luau.
	for i, petData in ipairs(equippedList) do
		if petData.id then
			local petInfo = self._equippedPets[petData.id]
			if not petInfo then
				local model, visualRefs = self:createPetModel(petData)
				local attackMarker, attackMarkerGui = self:_createAttackMarker(model)
				model.Parent = self._petsFolder

				petInfo = {
					model = model,
					data = petData,
					followIndex = i,
					attackMarker = attackMarker,
					attackMarkerGui = attackMarkerGui,
					attackMarkerAngle = 0,
					visualRefs = visualRefs,
					bodyHalfHeight = visualRefs.bodyHalfHeight,
				}
				self._equippedPets[petData.id] = petInfo
			else
				local descriptor = PetVariantPresentation.resolve(petData)
				if petInfo.visualRefs and petInfo.visualRefs.visualKey ~= descriptor.visualKey then
					self:_applyPetPresentation(petInfo.visualRefs, petData)
					petInfo.bodyHalfHeight = petInfo.visualRefs.bodyHalfHeight
				end
				petInfo.data = petData
				petInfo.followIndex = i
			end
		end
	end
end

-- Keep the attack marker independently ground-snapped so pet translation and
-- bounce animations cannot lift it. The current breakable is excluded from the
-- ground raycast, just like the attacking pet's own stationing raycasts.
function PetController:_updateAttackMarker(uniqueId, petInfo, deltaTime)
	local marker = petInfo.attackMarker
	local surfaceGui = petInfo.attackMarkerGui
	local model = petInfo.model
	local body = model and model.PrimaryPart
	local isAttacking = self._attackingPets[uniqueId] ~= nil

	if surfaceGui and surfaceGui.Parent then
		surfaceGui.Enabled = isAttacking
	end
	-- Hidden markers need no placement raycast or rotation work.
	if not isAttacking then return end
	if not marker or not marker.Parent or not body or not body.Parent then return end

	local targetInfo = self._petTargets[uniqueId]
	local targetIgnore = nil
	if targetInfo and targetInfo.part and targetInfo.part.Parent then
		targetIgnore = targetInfo.part.Parent:IsA("Model") and targetInfo.part.Parent or targetInfo.part
	end

	local bodyPosition = body.Position
	local bodyHalfHeight = petInfo.bodyHalfHeight or 1.1
	local groundY = self:_getGroundY(bodyPosition, bodyPosition.Y, targetIgnore, bodyHalfHeight) - bodyHalfHeight
	petInfo.attackMarkerAngle = ((petInfo.attackMarkerAngle or 0) + deltaTime * math.rad(110)) % (math.pi * 2)
	marker.CFrame = CFrame.new(
		bodyPosition.X,
		groundY + marker.Size.Y / 2 + 0.02,
		bodyPosition.Z
	) * CFrame.Angles(0, petInfo.attackMarkerAngle, 0)
end

--------------------------------------------------------------------------------
-- Per-frame update: pets follow behind the player in a trailing formation
-- Pets are raycast-snapped to the ground with a shadow beneath them
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

	-- One shared timer drives all bounded orbit and Rainbow presentation work.
	if not self._orbitTimer then
		self._orbitTimer = 0
	end
	self._orbitTimer = self._orbitTimer + deltaTime

	local totalPets = 0
	for _ in pairs(self._equippedPets) do
		totalPets = totalPets + 1
	end

	for uniqueId, petInfo in pairs(self._equippedPets) do
		if not self._attackingPets[uniqueId] then
			local index = petInfo.followIndex or 1
			local row = math.ceil(index / self._petsPerRow)
			local col = ((index - 1) % self._petsPerRow) + 1
			local actualPetsInRow = math.min(self._petsPerRow, totalPets - (row - 1) * self._petsPerRow)

			local lateralOffset = (col - (actualPetsInRow + 1) / 2) * self._followSpread
			local distanceBehind = row * self._followDistance

			local rawTargetPos = playerPos
				+ behindVector * distanceBehind
				+ rightVector * lateralOffset

			local bodyHalfHeight = petInfo.bodyHalfHeight or 1.1
			local fallbackY = playerPos.Y - 2 + bodyHalfHeight
			local groundY = self:_getGroundY(rawTargetPos, fallbackY, nil, bodyHalfHeight)
			local targetPos = Vector3.new(rawTargetPos.X, groundY, rawTargetPos.Z)

			local model = petInfo.model
			if model and model.PrimaryPart and model.PrimaryPart.Parent then
				local currentPos = model.PrimaryPart.Position
				local newPos = currentPos:Lerp(targetPos, math.min(1, deltaTime * effectiveLerpSpeed))
				local offset = newPos - model.PrimaryPart.Position

				for _, part in ipairs(model:GetDescendants()) do
					if part:IsA("BasePart")
						and part.Name ~= "Shadow"
						and part.Name ~= "AttackMarker"
						and not part.Name:find("GlowParticle") then
						part.Position = part.Position + offset
					end
				end

				local shadowPart = petInfo.visualRefs and petInfo.visualRefs.shadow or model:FindFirstChild("Shadow")
				if shadowPart then
					local shadowY = newPos.Y - bodyHalfHeight + 0.05
					local shadowPos = Vector3.new(newPos.X, shadowY, newPos.Z)
					shadowPart.CFrame = CFrame.new(shadowPos) * CFrame.Angles(0, 0, math.rad(90))
				end

				self:_updateGlowParticles(petInfo, newPos, index)
			end
		end

		self:_updateVariantAnimation(petInfo)
		self:_updateAttackMarker(uniqueId, petInfo, deltaTime)
	end
end

-- Animate cached rarity particles without scanning model children every frame.
function PetController:_updateGlowParticles(petInfo, bodyPos, petIndex)
	local visualRefs = petInfo.visualRefs
	if not visualRefs then return end
	for particleIdx, part in ipairs(visualRefs.glowParticles) do
		if part and part.Parent then
			local angleOffset = (particleIdx / 5) * math.pi * 2
			local angle = self._orbitTimer * 2.5 + angleOffset + petIndex * 1.2
			local orbitX = math.cos(angle) * 1.6
			local orbitZ = math.sin(angle) * 1.6
			local orbitY = math.sin(self._orbitTimer * 3 + particleIdx) * 0.4
			part.Position = bodyPos + Vector3.new(orbitX, orbitY, orbitZ)
		end
	end
end

-- Rainbow color motion is folded into the existing PetController update loop.
-- No per-pet connection, descendant scan, allocation, or unbounded particle work.
function PetController:_updateVariantAnimation(petInfo)
	local visualRefs = petInfo.visualRefs
	local descriptor = visualRefs and visualRefs.descriptor
	if not descriptor or descriptor.baseVariant ~= "Rainbow" then return end
	if not visualRefs.body.Parent or not visualRefs.light.Parent then return end

	local hue = (self._orbitTimer * 0.11 + visualRefs.visualPhase) % 1
	local color = Color3.fromHSV(hue, 0.76, 1)
	visualRefs.body.Color = color
	visualRefs.light.Color = color
	visualRefs.nameLabel.TextColor3 = color
	if not descriptor.isShiny then
		visualRefs.variantLabel.TextColor3 = color
	end
	for _, particle in ipairs(visualRefs.glowParticles) do
		if particle and particle.Parent then
			particle.Color = color
		end
	end
end

--------------------------------------------------------------------------------
-- Send pet to attack a destructible (visual animation)
-- destructibleId: string ID of the destructible
-- destructiblePart: optional Part reference for tween target position
-- The pet moves SLOWLY to the destructible and STAYS THERE bouncing until the
-- destructible is destroyed or the player moves >50 studs away.
-- Pet hovers ~1 stud beside the destructible (offset so it is not inside it).
--------------------------------------------------------------------------------
function PetController:sendPetToAttack(uniqueId, destructibleId, destructiblePart, onAssigned)
	if not self._initialized then
		if onAssigned then task.defer(onAssigned, false) end
		return
	end
	local petInfo = self._equippedPets[uniqueId]
	if not petInfo or not petInfo.model then
		if onAssigned then task.defer(onAssigned, false) end
		return
	end
	-- If already stationed at THIS destructible, do not restart the movement.
	-- Still settle the caller so queued attacks cannot wait forever.
	if self._attackingPets[uniqueId] == destructibleId then
		if self:_isPetTargetConfirmed(uniqueId, destructibleId) then
			if onAssigned then task.defer(onAssigned, true) end
		elseif self._assignPetTarget then
			self:_requestPetTarget(uniqueId, destructibleId, onAssigned)
		elseif onAssigned then
			task.defer(onAssigned, false)
		end
		return
	end

	-- Mark as attacking this specific destructible
	self._attackingPets[uniqueId] = destructibleId

	-- Notify server of pet assignment (only if changed). The optional callback
	-- lets manual attacks wait until the authoritative assignment is accepted.
	if self._assignPetTarget and not self:_isPetTargetConfirmed(uniqueId, destructibleId) then
		self:_requestPetTarget(uniqueId, destructibleId, onAssigned)
	elseif onAssigned then
		task.defer(onAssigned, self:_isPetTargetConfirmed(uniqueId, destructibleId))
	end

	local model = petInfo.model
	local destructibleIgnore = nil
	if destructiblePart and typeof(destructiblePart) == "Instance" then
		if destructiblePart.Parent and destructiblePart.Parent:IsA("Model") then
			destructibleIgnore = destructiblePart.Parent
		else
			destructibleIgnore = destructiblePart
		end
	end

	-- Keep the target's horizontal station fixed, but derive its Y from the
	-- current visual body size. An in-place variant change therefore cannot leave
	-- an attacking pet floating or clipping until the attack ends.
	local targetRawPos
	local targetGroundFallback
	local targetNeedsGroundSnap = false
	if destructiblePart and typeof(destructiblePart) == "Instance" and destructiblePart:IsA("BasePart") then
		local petIndex = petInfo.followIndex or 1
		local angle = (petIndex - 1) * (math.pi * 2 / 6)
		targetRawPos = destructiblePart.Position + Vector3.new(
			math.cos(angle) * 2.5,
			0,
			math.sin(angle) * 2.5
		)
		targetGroundFallback = destructiblePart.Position.Y - destructiblePart.Size.Y / 2
		targetNeedsGroundSnap = true
	else
		local character = self._player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			targetRawPos = rootPart.Position + rootPart.CFrame.LookVector * 5
			targetGroundFallback = targetRawPos.Y - (petInfo.bodyHalfHeight or 1.1)
			targetNeedsGroundSnap = true
		else
			self._attackingPets[uniqueId] = nil
			if self._assignPetTarget and self:_hasPetTargetRequest(uniqueId) then
				self:_requestPetTarget(uniqueId, nil)
			end
			return
		end
	end

	local function getGroundedTargetPosition()
		local currentBodyHalfHeight = petInfo.bodyHalfHeight or 1.1
		if not targetNeedsGroundSnap then return targetRawPos end
		local fallbackY = targetGroundFallback + currentBodyHalfHeight
		local groundY = self:_getGroundY(
			targetRawPos,
			fallbackY,
			destructibleIgnore,
			currentBodyHalfHeight
		)
		return Vector3.new(targetRawPos.X, groundY, targetRawPos.Z)
	end

	local targetPos = getGroundedTargetPosition()

	-- Slow approach using per-frame lerp at speed 1.5 (very slow and natural, walking pace)
	if model.PrimaryPart and model.PrimaryPart.Parent then
		task.spawn(function()
			local APPROACH_SPEED = 1.5 -- very slow lerp speed (walking)
			local BOUNCE_SPEED = 3.0 -- oscillation speed when stationed
			local BOUNCE_HEIGHT = 0.3 -- how much it bobs up and down
			local MAX_PLAYER_DIST = 50 -- match the server attack/return threshold

			-- Phase 1: Slow approach to the destructible
			while self._attackingPets[uniqueId] == destructibleId
				and self._equippedPets[uniqueId] == petInfo do
				if not model or not model.PrimaryPart or not model.PrimaryPart.Parent then
					self._attackingPets[uniqueId] = nil
					if self._assignPetTarget and self:_hasPetTargetRequest(uniqueId) then
						self:_requestPetTarget(uniqueId, nil)
					end
					return
				end

				-- Check if destructible still exists
				if destructiblePart and typeof(destructiblePart) == "Instance" then
					if not destructiblePart.Parent then
						-- Destructible was destroyed, return to follow
						self._attackingPets[uniqueId] = nil
						if self._assignPetTarget and self:_hasPetTargetRequest(uniqueId) then
							self:_requestPetTarget(uniqueId, nil)
						end
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
							if self._assignPetTarget and self:_hasPetTargetRequest(uniqueId) then
								self:_requestPetTarget(uniqueId, nil)
							end
							return
						end
					end
				end

				targetPos = getGroundedTargetPosition()
				local currentPos = model.PrimaryPart.Position
				local dist = (currentPos - targetPos).Magnitude
				if dist < 0.5 then
					break -- close enough, transition to bounce phase
				end

				-- Slow lerp toward target
				local dt = task.wait()
				local alpha = math.min(1, dt * APPROACH_SPEED)
				local newPos = currentPos:Lerp(targetPos, alpha)
				-- Snap Y to ground via raycast during approach
				local currentBodyHalfHeight = petInfo.bodyHalfHeight or 1.1
				local approachGroundY = self:_getGroundY(
					newPos,
					targetPos.Y,
					destructibleIgnore,
					currentBodyHalfHeight
				)
				newPos = Vector3.new(newPos.X, approachGroundY, newPos.Z)
				local offset = newPos - currentPos

				for _, part in ipairs(model:GetDescendants()) do
					if part:IsA("BasePart") and part.Name ~= "Shadow" and part.Name ~= "AttackMarker" then
						part.Position = part.Position + offset
					end
				end

				-- Update shadow
				local shadowPart = petInfo.visualRefs and petInfo.visualRefs.shadow or model:FindFirstChild("Shadow")
				if shadowPart then
					local groundY = newPos.Y - currentBodyHalfHeight + 0.05
					shadowPart.CFrame = CFrame.new(newPos.X, groundY, newPos.Z) * CFrame.Angles(0, 0, math.rad(90))
				end
			end

			-- Phase 2: Stay at destructible with bounce animation (attack wobble)
			local bounceTime = 0
			while self._attackingPets[uniqueId] == destructibleId
				and self._equippedPets[uniqueId] == petInfo do
				if not model or not model.PrimaryPart or not model.PrimaryPart.Parent then
					self._attackingPets[uniqueId] = nil
					if self._assignPetTarget and self:_hasPetTargetRequest(uniqueId) then
						self:_requestPetTarget(uniqueId, nil)
					end
					return
				end

				-- Check if destructible still exists
				if destructiblePart and typeof(destructiblePart) == "Instance" then
					if not destructiblePart.Parent then
						-- Destructible destroyed, return to follow
						self._attackingPets[uniqueId] = nil
						if self._assignPetTarget and self:_hasPetTargetRequest(uniqueId) then
							self:_requestPetTarget(uniqueId, nil)
						end
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
							if self._assignPetTarget and self:_hasPetTargetRequest(uniqueId) then
								self:_requestPetTarget(uniqueId, nil)
							end
							return
						end
					end
				end

				local dt = task.wait()
				bounceTime = bounceTime + dt

				-- Gentle bounce (bob up and down)
				local bounceOffset = math.sin(bounceTime * BOUNCE_SPEED) * BOUNCE_HEIGHT
				targetPos = getGroundedTargetPosition()
				local currentBodyHalfHeight = petInfo.bodyHalfHeight or 1.1
				local desiredPos = targetPos + Vector3.new(0, bounceOffset, 0)
				local currentPos = model.PrimaryPart.Position
				local offset = desiredPos - currentPos

				for _, part in ipairs(model:GetDescendants()) do
					if part:IsA("BasePart") and part.Name ~= "Shadow" and part.Name ~= "AttackMarker" then
						part.Position = part.Position + offset
					end
				end

				-- Update shadow
				local shadowPart = petInfo.visualRefs and petInfo.visualRefs.shadow or model:FindFirstChild("Shadow")
				if shadowPart then
					local groundY = desiredPos.Y - currentBodyHalfHeight + 0.05
					shadowPart.CFrame = CFrame.new(desiredPos.X, groundY, desiredPos.Z) * CFrame.Angles(0, 0, math.rad(90))
				end
			end
		end)
	else
		self._attackingPets[uniqueId] = nil
		if self._assignPetTarget and self:_hasPetTargetRequest(uniqueId) then
			self:_requestPetTarget(uniqueId, nil)
		end
	end
end

--------------------------------------------------------------------------------
-- Fire attack remote once with string destructibleId (called from Main.client)
-- numPets: how many pets are attacking (1 for single click, all for hold)
--------------------------------------------------------------------------------
function PetController:fireAttackRemote(destructibleId)
	if not self._initialized then return false end
	if not self._remotes then return false end

	-- Never send pet damage while the player has no active character. Assignments
	-- may finish asynchronously during respawn, so this guard must be central.
	local character = self._player and self._player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return false
	end

	local attackRemote = self._remotes:FindFirstChild("AttackDestructible")
	if attackRemote then
		local invoked = pcall(function()
			attackRemote:InvokeServer(destructibleId)
		end)
		return invoked
	end
	return false
end

--------------------------------------------------------------------------------
-- Show floating damage text above a destructible
--------------------------------------------------------------------------------
function PetController:showDamageText(position, damage, isCrit)
	if not self._initialized then return end

	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "DamagePopup"
	billboardGui.Size = UDim2.fromOffset(isCrit and 120 or 80, isCrit and 45 or 30)
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
	if isCrit then
		label.Text = "CRIT! -" .. tostring(damage)
		label.TextColor3 = Color3.fromRGB(255, 180, 0)
		label.TextStrokeColor3 = Color3.fromRGB(180, 80, 0)
	else
		label.Text = "-" .. tostring(damage)
		label.TextColor3 = Color3.fromRGB(255, 80, 80)
		label.TextStrokeColor3 = Color3.fromRGB(50, 0, 0)
	end
	label.TextStrokeTransparency = 0.3
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = billboardGui

	-- Crit popups scale in with bounce for extra emphasis
	if isCrit then
		billboardGui.Size = UDim2.fromOffset(30, 12)
		local scaleIn = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		TweenService:Create(billboardGui, scaleIn, {
			Size = UDim2.fromOffset(120, 45),
		}):Play()
	end

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

	for id, part in pairs(self._destructibleIndex) do
		if part and part.Parent then
			local dist = (part.Position - playerPos).Magnitude
			if dist < (maxDistance or 40) then
				table.insert(results, {
					part = part,
					id = id,
					distance = dist,
				})
			end
		else
			self._destructibleIndex[id] = nil
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

function PetController:_nextAssignmentSequence()
	self._assignmentSequence = self._assignmentSequence + 1
	return self._assignmentSequence
end

-- Return equipped pet IDs in the same stable order used by the follow formation.
function PetController:_getQueuedPetIds()
	local queuedPets = {}
	for uniqueId, petInfo in pairs(self._equippedPets) do
		table.insert(queuedPets, {
			uniqueId = uniqueId,
			followIndex = petInfo.followIndex or math.huge,
		})
	end
	table.sort(queuedPets, function(a, b)
		if a.followIndex == b.followIndex then
			return tostring(a.uniqueId) < tostring(b.uniqueId)
		end
		return a.followIndex < b.followIndex
	end)

	local queuedIds = {}
	for _, entry in ipairs(queuedPets) do
		table.insert(queuedIds, entry.uniqueId)
	end
	return queuedIds
end

-- Prefer the first idle pet in follow order. If every pet is assigned, steal
-- the oldest assignment; followIndex remains the deterministic tie-breaker.
function PetController:_getNextQueuedPet()
	local queuedIds = self:_getQueuedPetIds()
	local oldestPetId = nil
	local oldestAssignment = math.huge

	for _, uniqueId in ipairs(queuedIds) do
		local targetInfo = self._petTargets[uniqueId]
		local targetIsValid = targetInfo
			and targetInfo.part
			and targetInfo.part.Parent
			and self._attackingPets[uniqueId] == targetInfo.destructibleId

		if not targetIsValid then
			return uniqueId, true
		end

		local assignedAt = targetInfo.assignedAt or -math.huge
		if assignedAt < oldestAssignment then
			oldestAssignment = assignedAt
			oldestPetId = uniqueId
		end
	end

	return oldestPetId, false
end

function PetController:_hasActivePetAtTarget(destructibleId)
	for uniqueId, targetInfo in pairs(self._petTargets) do
		if targetInfo.destructibleId == destructibleId
			and targetInfo.part
			and targetInfo.part.Parent
			and self._attackingPets[uniqueId] == destructibleId then
			return true
		end
	end
	return false
end

function PetController:_clearPetTarget(uniqueId)
	self._petTargets[uniqueId] = nil
	self._attackingPets[uniqueId] = nil
	if self._assignPetTarget and self:_hasPetTargetRequest(uniqueId) then
		self:_requestPetTarget(uniqueId, nil)
	end
end

-- Keep manually assigned pets attacking without allowing them to discover or
-- switch to new targets. This remains active while AutoFarm is disabled.
function PetController:_updateAssignedPetAttacks(now)
	local character = self._player and self._player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	for _, uniqueId in ipairs(self:_getQueuedPetIds()) do
		local targetInfo = self._petTargets[uniqueId]
		if targetInfo then
			local part = targetInfo.part
			local targetIsValid = part and part.Parent ~= nil
			if targetIsValid and rootPart then
				targetIsValid = (rootPart.Position - part.Position).Magnitude <= 50
			end

			if not targetIsValid then
				self:_clearPetTarget(uniqueId)
			else
				if self._attackingPets[uniqueId] ~= targetInfo.destructibleId then
					self:_sendAutoPetToTarget(uniqueId, targetInfo)
				end
				if targetInfo.assignmentConfirmed
					and self:_isPetTargetConfirmed(uniqueId, targetInfo.destructibleId)
					and (now - targetInfo.lastAttackTime >= self._autoAttackInterval) then
					targetInfo.lastAttackTime = now
					self:fireAttackRemote(targetInfo.destructibleId)
				end
			end
		end
	end
end

function PetController:_sendAutoPetToTarget(uniqueId, targetInfo)
	local assignmentId = targetInfo.assignedAt
	self:sendPetToAttack(uniqueId, targetInfo.destructibleId, targetInfo.part, function(accepted)
		local currentTarget = self._petTargets[uniqueId]
		if currentTarget and currentTarget.assignedAt == assignmentId then
			currentTarget.assignmentConfirmed = accepted
			if accepted then
				currentTarget.lastAttackTime = tick()
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- ASSIGNED PET ATTACK LOOP
-- Only already-manually-assigned pets are maintained here. Automatic discovery
-- and next-target selection are intentionally disabled for current gameplay.
--------------------------------------------------------------------------------
function PetController:_startAutoAttack()
	if self._autoAttackConnection then return end

	self._autoAttackConnection = RunService.Heartbeat:Connect(function()
		if not self._autoAttackEnabled then return end
		if not self._initialized then return end

		self:_updateAssignedPetAttacks(tick())
	end)
end

function PetController:setAutoFarmEnabled(_enabled)
	-- Future upgrade point: enabling AutoFarm must not restore target discovery
	-- until that behavior is deliberately redesigned and reintroduced.
	self._autoFarmEnabled = false
end

function PetController:_stopAutoAttack()
	if self._autoAttackConnection then
		self._autoAttackConnection:Disconnect()
		self._autoAttackConnection = nil
	end
end

--------------------------------------------------------------------------------
-- MANUAL TARGETING: Send exactly 1 pet to a target (single click)
-- Uses a deterministic queue: idle pets by followIndex, then oldest assignment.
--------------------------------------------------------------------------------
function PetController:sendOnePetToTarget(destructibleId, destructiblePart)
	if not self._initialized then return end

	local sentPetId, petWasIdle = self:_getNextQueuedPet()
	if not sentPetId then return false end

	-- If every pet is already busy and this breakable is already being attacked,
	-- this click is damage/Crit-QTE only. Do not restart movement or assignment.
	if not petWasIdle and self:_hasActivePetAtTarget(destructibleId) then
		self._manualTargetMode = true
		self._manualTargetExpiry = tick() + self._manualTargetDuration
		return false
	end

	self._manualOrderVersion = self._manualOrderVersion + 1

	-- Release from previous station if any and create a fresh queue assignment.
	self._attackingPets[sentPetId] = nil
	local now = tick()
	local assignmentId = self:_nextAssignmentSequence()
	self._petTargets[sentPetId] = {
		destructibleId = destructibleId,
		part = destructiblePart,
		lastAttackTime = now,
		assignedAt = assignmentId,
		assignmentConfirmed = false,
	}

	-- Fire only after the server accepted this pet's target, avoiding the race
	-- where AttackDestructible arrives before AssignPetTarget.
	self:sendPetToAttack(sentPetId, destructibleId, destructiblePart, function(accepted)
		local currentTarget = self._petTargets[sentPetId]
		if accepted
			and currentTarget
			and currentTarget.assignedAt == assignmentId
			and currentTarget.destructibleId == destructibleId then
			currentTarget.assignmentConfirmed = true
			currentTarget.lastAttackTime = tick()
			self:fireAttackRemote(destructibleId)
		end
	end)

	-- Enter manual target mode briefly so auto-attack doesn't immediately override
	self._manualTargetMode = true
	self._manualTargetExpiry = now + self._manualTargetDuration
end

--------------------------------------------------------------------------------
-- MANUAL TARGETING: Send ALL pets to a target (hold click)
--------------------------------------------------------------------------------
function PetController:sendAllPetsToTarget(destructibleId, destructiblePart)
	if not self._initialized then return end

	local queuedIds = self:_getQueuedPetIds()
	if #queuedIds == 0 then return end

	local now = tick()
	local petsToAssign = {}

	-- Preserve every pet already active on this breakable. A repeated or partial
	-- same-target hold must never restart, clear, or roll back existing work.
	for _, uniqueId in ipairs(queuedIds) do
		local targetInfo = self._petTargets[uniqueId]
		local alreadyTargeting = self._attackingPets[uniqueId] == destructibleId
			and targetInfo
			and targetInfo.destructibleId == destructibleId
			and targetInfo.part
			and targetInfo.part.Parent ~= nil
		if not alreadyTargeting then
			table.insert(petsToAssign, uniqueId)
		end
	end

	if #petsToAssign == 0 then
		self._manualTargetMode = true
		self._manualTargetExpiry = now + self._manualTargetDuration
		return
	end

	local pendingAssignments = #petsToAssign
	local expectedAssignments = #petsToAssign
	local acceptedAssignments = 0
	local holdAssignments = {}
	self._manualOrderVersion = self._manualOrderVersion + 1
	local orderVersion = self._manualOrderVersion

	-- Assign only pets that are not already on this target. Sequential assignedAt
	-- values keep later single-click queue stealing deterministic.
	for _, uniqueId in ipairs(petsToAssign) do
		local petId = uniqueId
		self._attackingPets[petId] = nil
		local assignmentId = self:_nextAssignmentSequence()
		holdAssignments[petId] = assignmentId
		self._petTargets[petId] = {
			destructibleId = destructibleId,
			part = destructiblePart,
			lastAttackTime = now,
			assignedAt = assignmentId,
			assignmentConfirmed = false,
		}
		self:sendPetToAttack(petId, destructibleId, destructiblePart, function(accepted)
			pendingAssignments = pendingAssignments - 1
			local currentTarget = self._petTargets[petId]
			if accepted
				and self._manualOrderVersion == orderVersion
				and currentTarget
				and currentTarget.assignedAt == holdAssignments[petId]
				and currentTarget.destructibleId == destructibleId then
				acceptedAssignments = acceptedAssignments + 1
			end
			if pendingAssignments == 0 then
				local holdSucceeded = self._manualOrderVersion == orderVersion
					and expectedAssignments > 0
					and acceptedAssignments == expectedAssignments
				if holdSucceeded then
					local holdAttackTime = tick()
					for confirmedPetId, confirmedAssignment in pairs(holdAssignments) do
						local confirmedTarget = self._petTargets[confirmedPetId]
						if confirmedTarget and confirmedTarget.assignedAt == confirmedAssignment then
							confirmedTarget.assignmentConfirmed = true
							confirmedTarget.lastAttackTime = holdAttackTime
						end
					end
					self:fireAttackRemote(destructibleId)
				else
					-- Hold is atomic: if any member failed or a newer order replaced it,
					-- roll back only pets that still belong to this exact hold.
					for rollbackPetId, rollbackAssignment in pairs(holdAssignments) do
						local rollbackTarget = self._petTargets[rollbackPetId]
						if rollbackTarget and rollbackTarget.assignedAt == rollbackAssignment then
							self._petTargets[rollbackPetId] = nil
							self._attackingPets[rollbackPetId] = nil
							if self._assignPetTarget and self:_hasPetTargetRequest(rollbackPetId) then
								self:_requestPetTarget(rollbackPetId, nil)
							end
						end
					end
					if self._manualOrderVersion == orderVersion then
						self._manualOrderVersion = self._manualOrderVersion + 1
						self._manualTargetMode = false
					end
				end
			end
		end)
	end

	-- Enter manual target mode
	self._manualTargetMode = true
	self._manualTargetExpiry = now + self._manualTargetDuration
end

--------------------------------------------------------------------------------
-- Clear manual targeting (return to auto-distribute)
--------------------------------------------------------------------------------
function PetController:clearManualTarget()
	self._manualOrderVersion = self._manualOrderVersion + 1
	self._manualTargetMode = false
	-- Clear server assignments for all pets
	if self._assignPetTarget then
		self:_clearAllPetTargetRequests()
	end
	-- Clear all pet targets and release stationing so they re-distribute on next frame
	self._petTargets = {}
	self._attackingPets = {}
end

--------------------------------------------------------------------------------
-- Cancel all pet attacks and return them to following the player
-- Called when player clicks elsewhere or moves away
--------------------------------------------------------------------------------
function PetController:cancelAllAttacks()
	self._manualOrderVersion = self._manualOrderVersion + 1
	self._manualTargetMode = false
	-- Clear server assignments for all pets
	if self._assignPetTarget then
		self:_clearAllPetTargetRequests()
	end
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
	self._manualOrderVersion = self._manualOrderVersion + 1
	self:_stopAutoAttack()
	-- Clear server assignments for all pets
	if self._assignPetTarget then
		self:_clearAllPetTargetRequests()
	end
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
