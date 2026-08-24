--[[
	ZoneService.lua - Zone unlocking and destructible management
	Spawns procedural Part-based destructibles, handles damage and drops.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(game.ReplicatedStorage.Shared.Config)
local ZoneData = require(game.ReplicatedStorage.Shared.ZoneData)

local ZoneService = {}

-- References to other services
ZoneService._dataService = nil
ZoneService._currencyService = nil
ZoneService._petService = nil

-- Active destructibles tracked by unique ID
ZoneService._destructibles = {}
-- Workspace references
ZoneService._zonesFolder = nil

-- Zone position offsets (each zone is spaced apart)
local ZONE_SIZE = Vector3.new(200, 0, 200)
local ZONE_SPACING = 250

-- How many destructibles to spawn per zone (distributed randomly)
local DESTRUCTIBLES_PER_ZONE = 20
-- Minimum distance between spawned destructibles (studs) - prevents overlap between all types
local MIN_SPAWN_DISTANCE = 15

function ZoneService.init(dataService, currencyService, petService)
	ZoneService._dataService = dataService
	ZoneService._currencyService = currencyService
	ZoneService._petService = petService

	-- Create zones folder in workspace
	local workspace = game:GetService("Workspace")
	local zonesFolder = workspace:FindFirstChild("Zones")
	if not zonesFolder then
		zonesFolder = Instance.new("Folder")
		zonesFolder.Name = "Zones"
		zonesFolder.Parent = workspace
	end
	ZoneService._zonesFolder = zonesFolder

	-- Spawn destructibles for zones 1 and 2 (MVP)
	ZoneService.spawnZone(1)
	ZoneService.spawnZone(2)

	-- Spawn zone gates between adjacent zones
	ZoneService._spawnZoneGates()

	-- Spawn egg hatching stations in each zone
	ZoneService._spawnEggStations()
end

-- Get zone origin position (bottom-left corner of the zone floor)
-- The zone floor parts in the .rbxlx are centered at (zoneId-1)*ZONE_SPACING, 0, -100
-- with size 200x2x200, so the floor spans from origin-100 to origin+100 on X and Z
local function getZoneOrigin(zoneId)
	local centerX = (zoneId - 1) * ZONE_SPACING
	local centerZ = -100
	-- Return the bottom-left corner of the zone
	return Vector3.new(centerX - ZONE_SIZE.X / 2, 0, centerZ - ZONE_SIZE.Z / 2)
end

-- Spawn a full zone with ground and destructibles
function ZoneService.spawnZone(zoneId)
	local zoneDef = ZoneData.Zones[zoneId]
	if not zoneDef then
		return
	end

	local origin = getZoneOrigin(zoneId)

	-- Create zone folder
	local zoneFolder = Instance.new("Folder")
	zoneFolder.Name = "Zone_" .. tostring(zoneId)
	zoneFolder.Parent = ZoneService._zonesFolder

	-- Create ground part
	local ground = Instance.new("Part")
	ground.Name = "Ground"
	ground.Anchored = true
	ground.Size = Vector3.new(ZONE_SIZE.X, 1, ZONE_SIZE.Z)
	ground.Position = origin + Vector3.new(ZONE_SIZE.X / 2, -0.5, ZONE_SIZE.Z / 2)
	ground.Color = zoneDef.groundColor
	ground.Material = Enum.Material.Grass
	ground.Parent = zoneFolder

	-- Spawn destructibles
	ZoneService.spawnDestructibles(zoneId, zoneFolder, origin)
end

-- Generate a random position within the zone floor, ensuring minimum distance from existing positions
local function getRandomPositionInZone(origin, existingPositions)
	local maxAttempts = 50
	for _ = 1, maxAttempts do
		-- Random X and Z within the zone floor area with some padding from edges
		local padding = 10
		local rx = origin.X + padding + math.random() * (ZONE_SIZE.X - padding * 2)
		local rz = origin.Z + padding + math.random() * (ZONE_SIZE.Z - padding * 2)
		local candidate = Vector3.new(rx, origin.Y, rz)

		-- Check minimum distance from all existing positions
		local tooClose = false
		for _, pos in ipairs(existingPositions) do
			local dist = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(candidate.X, 0, candidate.Z)).Magnitude
			if dist < MIN_SPAWN_DISTANCE then
				tooClose = true
				break
			end
		end

		if not tooClose then
			return candidate
		end
	end

	-- Fallback: return a random position even if spacing constraint fails
	local rx = origin.X + 10 + math.random() * (ZONE_SIZE.X - 20)
	local rz = origin.Z + 10 + math.random() * (ZONE_SIZE.Z - 20)
	return Vector3.new(rx, origin.Y, rz)
end

-- Spawn destructibles within a zone
function ZoneService.spawnDestructibles(zoneId, zoneFolder, origin)
	local zoneDef = ZoneData.Zones[zoneId]
	if not zoneDef then
		return
	end

	if not zoneFolder then
		zoneFolder = ZoneService._zonesFolder:FindFirstChild("Zone_" .. tostring(zoneId))
		if not zoneFolder then
			return
		end
	end

	if not origin then
		origin = getZoneOrigin(zoneId)
	end

	-- Distribute destructibles randomly across the zone floor
	local destructibleTypes = { "CoinPile", "DiamondPile", "Crate" }
	-- Weight distribution: more CoinPiles, fewer DiamondPiles, some Crates
	local typeWeights = { "CoinPile", "CoinPile", "CoinPile", "CoinPile", "CoinPile",
		"CoinPile", "CoinPile", "DiamondPile", "DiamondPile", "DiamondPile",
		"DiamondPile", "Crate", "Crate", "Crate", "Crate",
		"Crate", "CoinPile", "CoinPile", "DiamondPile", "Crate" }

	local existingPositions = {}

	for i = 1, DESTRUCTIBLES_PER_ZONE do
		-- Pick a type from the weighted list
		local dtype = typeWeights[((i - 1) % #typeWeights) + 1]
		local dDef = zoneDef.destructibles[dtype]
		if dDef then
			local position = getRandomPositionInZone(origin, existingPositions)
			table.insert(existingPositions, position)
			ZoneService._spawnSingleDestructible(zoneId, dtype, dDef, position, zoneFolder)
		end
	end
end

-- Create a single destructible Part
function ZoneService._spawnSingleDestructible(zoneId, dtype, dDef, position, parent)
	local part = nil
	local uniqueId = game:GetService("HttpService"):GenerateGUID(false)

	if dtype == "CoinPile" then
		-- Yellow cylinder (larger for better visibility and targeting)
		part = Instance.new("Part")
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(3, 4, 4)
		part.Color = Color3.fromRGB(255, 215, 0)
		part.Material = Enum.Material.SmoothPlastic
	elseif dtype == "DiamondPile" then
		-- Blue wedge (larger for better visibility and targeting)
		part = Instance.new("WedgePart")
		part.Size = Vector3.new(3, 4, 4)
		part.Color = Color3.fromRGB(0, 150, 255)
		part.Material = Enum.Material.Neon
	elseif dtype == "Crate" then
		-- Brown cube (larger for better visibility and targeting)
		part = Instance.new("Part")
		part.Shape = Enum.PartType.Block
		part.Size = Vector3.new(4, 4, 4)
		part.Color = Color3.fromRGB(139, 90, 43)
		part.Material = Enum.Material.Wood
	end

	if not part then
		return
	end

	part.Name = "Destructible_" .. uniqueId
	part.Anchored = true
	part.Position = position + Vector3.new(0, 2, 0)
	part.Parent = parent

	-- Store in tracking table
	ZoneService._destructibles[uniqueId] = {
		id = uniqueId,
		zoneId = zoneId,
		dtype = dtype,
		hp = dDef.hp,
		maxHp = dDef.hp,
		drops = dDef.drops,
		part = part,
		position = part.Position,
	}

	-- Tag the part with the destructible ID for lookup
	local idValue = Instance.new("StringValue")
	idValue.Name = "DestructibleId"
	idValue.Value = uniqueId
	idValue.Parent = part

	return uniqueId
end

-- Spawn egg hatching stations in each zone (like Pet Simulator egg pedestals)
function ZoneService._spawnEggStations()
	local workspace = game:GetService("Workspace")
	local stationsFolder = workspace:FindFirstChild("EggStations")
	if not stationsFolder then
		stationsFolder = Instance.new("Folder")
		stationsFolder.Name = "EggStations"
		stationsFolder.Parent = workspace
	end

	-- Egg station definitions per zone (type maps to PetData.Eggs keys)
	local stationDefs = {
		[1] = { eggType = "BasicEgg", name = "Basic Egg", cost = Config.EggCosts[1].Coins },
		[2] = { eggType = "PremiumEgg", name = "Premium Egg", cost = Config.EggCosts[2].Coins },
	}

	for zoneId, stationDef in pairs(stationDefs) do
		-- Position the egg station at a prominent spot near the zone entrance
		local zoneCenter = (zoneId - 1) * ZONE_SPACING
		local stationPos = Vector3.new(zoneCenter - 40, 0, -70)

		-- Base pedestal
		local pedestal = Instance.new("Part")
		pedestal.Name = "EggStation_" .. stationDef.eggType
		pedestal.Shape = Enum.PartType.Cylinder
		pedestal.Size = Vector3.new(3, 8, 8)
		pedestal.Position = stationPos + Vector3.new(0, 1.5, 0)
		pedestal.Anchored = true
		pedestal.CanCollide = true
		pedestal.Color = Color3.fromRGB(200, 180, 140)
		pedestal.Material = Enum.Material.Marble
		pedestal.CFrame = CFrame.new(stationPos + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
		pedestal.Parent = stationsFolder

		-- Egg on top (ball)
		local egg = Instance.new("Part")
		egg.Name = "EggModel"
		egg.Shape = Enum.PartType.Ball
		egg.Size = Vector3.new(4, 5, 4)
		egg.Position = stationPos + Vector3.new(0, 5, 0)
		egg.Anchored = true
		egg.CanCollide = false
		egg.Color = zoneId == 1 and Color3.fromRGB(200, 230, 180) or Color3.fromRGB(180, 200, 255)
		egg.Material = Enum.Material.SmoothPlastic
		egg.Parent = stationsFolder

		-- Tag the egg with station info
		local eggTypeTag = Instance.new("StringValue")
		eggTypeTag.Name = "EggType"
		eggTypeTag.Value = stationDef.eggType
		eggTypeTag.Parent = egg

		local zoneTag = Instance.new("IntValue")
		zoneTag.Name = "StationZone"
		zoneTag.Value = zoneId
		zoneTag.Parent = egg

		-- Billboard label above the egg showing name and cost
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "StationLabel"
		billboard.Size = UDim2.fromOffset(180, 70)
		billboard.StudsOffset = Vector3.new(0, 4, 0)
		billboard.AlwaysOnTop = true
		billboard.Adornee = egg
		billboard.Parent = egg

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "EggName"
		nameLabel.Size = UDim2.fromScale(1, 0.5)
		nameLabel.Position = UDim2.fromScale(0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = stationDef.name
		nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		nameLabel.TextStrokeTransparency = 0.3
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextScaled = true
		nameLabel.Parent = billboard

		local costLabel = Instance.new("TextLabel")
		costLabel.Name = "EggCost"
		costLabel.Size = UDim2.fromScale(1, 0.5)
		costLabel.Position = UDim2.fromScale(0, 0.5)
		costLabel.BackgroundTransparency = 1
		costLabel.Text = tostring(stationDef.cost) .. " Coins"
		costLabel.TextColor3 = Color3.fromRGB(255, 220, 0)
		costLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		costLabel.TextStrokeTransparency = 0.3
		costLabel.Font = Enum.Font.GothamBold
		costLabel.TextScaled = true
		costLabel.Parent = billboard

		-- Interaction zone: invisible larger part around the station for proximity detection
		local interactZone = Instance.new("Part")
		interactZone.Name = "InteractZone_" .. stationDef.eggType
		interactZone.Size = Vector3.new(12, 10, 12)
		interactZone.Position = stationPos + Vector3.new(0, 5, 0)
		interactZone.Anchored = true
		interactZone.CanCollide = false
		interactZone.Transparency = 1
		interactZone.Parent = stationsFolder

		-- Tag for client detection
		local interactTag = Instance.new("StringValue")
		interactTag.Name = "EggType"
		interactTag.Value = stationDef.eggType
		interactTag.Parent = interactZone
	end
end

-- Spawn zone gates between adjacent zones (visible barriers with cost labels)
function ZoneService._spawnZoneGates()
	local workspace = game:GetService("Workspace")
	local gatesFolder = workspace:FindFirstChild("ZoneGates")
	if not gatesFolder then
		gatesFolder = Instance.new("Folder")
		gatesFolder.Name = "ZoneGates"
		gatesFolder.Parent = workspace
	end

	-- Create gates between zone 1->2, 2->3, etc. (MVP: only 1->2)
	for gateZone = 2, 2 do
		local zoneDef = ZoneData.Zones[gateZone]
		if not zoneDef then continue end

		-- Gate position: at the boundary between zones (halfway between zone centers)
		local prevCenter = (gateZone - 2) * ZONE_SPACING
		local currCenter = (gateZone - 1) * ZONE_SPACING
		local gateX = (prevCenter + currCenter) / 2
		local gateZ = -100 -- center Z of zones

		-- Gate wall (tall translucent barrier)
		local gate = Instance.new("Part")
		gate.Name = "ZoneGate_" .. tostring(gateZone)
		gate.Size = Vector3.new(4, 20, 60)
		gate.Position = Vector3.new(gateX, 10, gateZ)
		gate.Anchored = true
		gate.CanCollide = true
		gate.Color = Color3.fromRGB(255, 80, 80)
		gate.Material = Enum.Material.ForceField
		gate.Transparency = 0.4
		gate.Parent = gatesFolder

		-- Tag it so client can identify it
		local zoneTag = Instance.new("IntValue")
		zoneTag.Name = "GateZoneId"
		zoneTag.Value = gateZone
		zoneTag.Parent = gate

		-- Cost label (BillboardGui with the unlock cost)
		local cost = Config.ZoneGateCosts[gateZone] or 0
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "GateLabel"
		billboard.Size = UDim2.fromOffset(200, 80)
		billboard.StudsOffset = Vector3.new(0, 12, 0)
		billboard.AlwaysOnTop = true
		billboard.Adornee = gate
		billboard.Parent = gate

		local costLabel = Instance.new("TextLabel")
		costLabel.Name = "CostText"
		costLabel.Size = UDim2.fromScale(1, 0.5)
		costLabel.Position = UDim2.fromScale(0, 0)
		costLabel.BackgroundTransparency = 1
		costLabel.Text = zoneDef.name
		costLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		costLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		costLabel.TextStrokeTransparency = 0.3
		costLabel.Font = Enum.Font.GothamBold
		costLabel.TextScaled = true
		costLabel.Parent = billboard

		local priceLabel = Instance.new("TextLabel")
		priceLabel.Name = "PriceText"
		priceLabel.Size = UDim2.fromScale(1, 0.5)
		priceLabel.Position = UDim2.fromScale(0, 0.5)
		priceLabel.BackgroundTransparency = 1
		priceLabel.Text = tostring(cost) .. " Coins"
		priceLabel.TextColor3 = Color3.fromRGB(255, 220, 0)
		priceLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		priceLabel.TextStrokeTransparency = 0.3
		priceLabel.Font = Enum.Font.GothamBold
		priceLabel.TextScaled = true
		priceLabel.Parent = billboard

		-- Connect Touched event so players can unlock by walking into the gate
		gate.Touched:Connect(function(hit)
			local player = game:GetService("Players"):GetPlayerFromCharacter(hit.Parent)
			if not player then return end

			-- Check if player already unlocked this zone
			local data = ZoneService._dataService.getPlayerData(player)
			if not data then return end

			local alreadyUnlocked = false
			for _, unlockedId in ipairs(data.unlockedZones) do
				if unlockedId == gateZone then
					alreadyUnlocked = true
					break
				end
			end

			if alreadyUnlocked then
				-- Remove the gate for this player (destroy it since single-player focus)
				gate:Destroy()
				return
			end

			-- Try to unlock the zone
			local success, err = ZoneService.unlockZone(player, gateZone)
			if success then
				-- Store gate position before destroying
				local gatePosition = gate.Position
				gate:Destroy()
				-- Fire zone unlock effect with gate position
				local remotes = ReplicatedStorage:FindFirstChild("Remotes")
				if remotes then
					local event = remotes:FindFirstChild("ZoneUnlocked")
					if event then
						event:FireClient(player, gateZone, gatePosition)
					end
				end
			end
		end)
	end
end

-- Unlock a zone for a player
function ZoneService.unlockZone(player, zoneId)
	if not player or type(zoneId) ~= "number" then
		return false, "Invalid parameters"
	end

	-- Validate zone exists
	if not ZoneData.Zones[zoneId] then
		return false, "Invalid zone"
	end

	local data = ZoneService._dataService.getPlayerData(player)
	if not data then
		return false, "No player data"
	end

	-- Check if already unlocked
	for _, unlockedId in ipairs(data.unlockedZones) do
		if unlockedId == zoneId then
			return false, "Zone already unlocked"
		end
	end

	-- Validate cost
	local cost = Config.ZoneGateCosts[zoneId]
	if not cost then
		return false, "No cost defined for zone"
	end

	-- Zone 1 is always free
	if cost > 0 then
		local success = ZoneService._currencyService.removeCoins(player, cost)
		if not success then
			return false, "Not enough coins"
		end
	end

	-- Add zone to player unlocked list
	table.insert(data.unlockedZones, zoneId)

	-- Fire client event
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local event = remotes:FindFirstChild("ZoneUnlocked")
		if event then
			event:FireClient(player, zoneId)
		end
	end

	return true, nil
end

-- Attack a destructible (called when a player's pets attack)
function ZoneService.attackDestructible(player, destructibleId)
	if not player or type(destructibleId) ~= "string" then
		return false, "Invalid parameters"
	end

	local destructible = ZoneService._destructibles[destructibleId]
	if not destructible then
		return false, "Destructible not found"
	end

	local data = ZoneService._dataService.getPlayerData(player)
	if not data then
		return false, "No player data"
	end

	-- Validate player has unlocked the zone
	local zoneUnlocked = false
	for _, unlockedId in ipairs(data.unlockedZones) do
		if unlockedId == destructible.zoneId then
			zoneUnlocked = true
			break
		end
	end
	if not zoneUnlocked then
		return false, "Zone not unlocked"
	end

	-- Validate player has equipped pets
	local equippedPets = {}
	for _, pet in ipairs(data.pets) do
		if pet.equipped then
			table.insert(equippedPets, pet)
		end
	end
	if #equippedPets == 0 then
		return false, "No equipped pets"
	end

	-- Calculate total damage from all equipped pets
	local totalDamage = 0
	for _, pet in ipairs(equippedPets) do
		totalDamage = totalDamage + ZoneService._petService.getPetDamage(pet, player)
	end

	-- Apply damage
	destructible.hp = destructible.hp - totalDamage

	local remotes = ReplicatedStorage:FindFirstChild("Remotes")

	if destructible.hp <= 0 then
		-- Destructible destroyed
		destructible.hp = 0

		-- Resolve drops: support both fixed numbers and {min, max} tables for randomization
		local resolvedDrops = {}
		for currencyType, dropValue in pairs(destructible.drops) do
			if type(dropValue) == "table" and dropValue.min and dropValue.max then
				resolvedDrops[currencyType] = math.random(dropValue.min, dropValue.max)
			else
				resolvedDrops[currencyType] = dropValue
			end
		end

		-- Award drops
		if resolvedDrops.Coins and resolvedDrops.Coins > 0 then
			ZoneService._currencyService.addCoins(player, resolvedDrops.Coins)
		end
		if resolvedDrops.Diamonds and resolvedDrops.Diamonds > 0 then
			ZoneService._currencyService.addDiamonds(player, resolvedDrops.Diamonds)
		end

		-- Award XP for destroying a destructible
		local xpReward = destructible.zoneId * 5
		ZoneService._awardXP(player, xpReward)

		-- Fire destroyed event to all clients so everyone sees the destruction
		if remotes then
			local event = remotes:FindFirstChild("DestructibleDestroyed")
			if event then
				event:FireAllClients(destructibleId, resolvedDrops)
			end
		end

		-- Remove part from workspace
		if destructible.part and destructible.part.Parent then
			destructible.part:Destroy()
		end

		-- Schedule respawn after 10 seconds
		local zoneId = destructible.zoneId
		local dtype = destructible.dtype
		local dDef = ZoneData.Zones[zoneId].destructibles[dtype]

		-- Remove from tracking
		ZoneService._destructibles[destructibleId] = nil

		-- Respawn after delay at a new random position within the zone
		task.delay(10, function()
			local zoneFolder = ZoneService._zonesFolder:FindFirstChild("Zone_" .. tostring(zoneId))
			if zoneFolder then
				local origin = getZoneOrigin(zoneId)
				-- Gather positions of all existing destructibles in this zone to prevent overlap
				local existingPositions = {}
				for _, d in pairs(ZoneService._destructibles) do
					if d.zoneId == zoneId and d.position then
						table.insert(existingPositions, d.position)
					end
				end
				local newPosition = getRandomPositionInZone(origin, existingPositions)
				ZoneService._spawnSingleDestructible(zoneId, dtype, dDef, newPosition, zoneFolder)
			end
		end)
	else
		-- Fire damaged event to all clients so everyone sees HP changes
		if remotes then
			local event = remotes:FindFirstChild("DestructibleDamaged")
			if event then
				event:FireAllClients(destructibleId, destructible.hp, destructible.maxHp, totalDamage)
			end
		end
	end

	return true, nil
end

-- Award XP to a player and handle level-ups
-- XP needed for next level: level * 100 (linear scaling)
function ZoneService._awardXP(player, amount)
	if not player or not amount or amount <= 0 then return end

	local data = ZoneService._dataService.getPlayerData(player)
	if not data then return end

	data.xp = (data.xp or 0) + amount

	-- Check for level up
	local xpNeeded = (data.level or 1) * 100
	while data.xp >= xpNeeded do
		data.xp = data.xp - xpNeeded
		data.level = (data.level or 1) + 1
		xpNeeded = data.level * 100
	end

	-- Fire XP update to client
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local event = remotes:FindFirstChild("XPUpdated")
		if event then
			event:FireClient(player, data.level, data.xp, data.level * 100)
		end
	end
end

return ZoneService
