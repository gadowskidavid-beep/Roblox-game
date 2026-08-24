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
local ZONE_SIZE = Vector3.new(100, 0, 100)
local ZONE_SPACING = 120

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
end

-- Get zone origin position
local function getZoneOrigin(zoneId)
	return Vector3.new((zoneId - 1) * ZONE_SPACING, 0, 0)
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

	-- Configuration for destructible layout
	local destructibleTypes = { "CoinPile", "DiamondPile", "Crate" }
	local gridSpacing = 12
	local startOffset = Vector3.new(10, 0, 10)

	local index = 0
	for _, dtype in ipairs(destructibleTypes) do
		local dDef = zoneDef.destructibles[dtype]
		if dDef then
			-- Place 4 of each type in a grid pattern
			for i = 1, 4 do
				index = index + 1
				local row = math.floor((index - 1) / 4)
				local col = (index - 1) % 4

				local position = origin + startOffset + Vector3.new(col * gridSpacing, 0, row * gridSpacing)

				ZoneService._spawnSingleDestructible(zoneId, dtype, dDef, position, zoneFolder)
			end
		end
	end
end

-- Create a single destructible Part
function ZoneService._spawnSingleDestructible(zoneId, dtype, dDef, position, parent)
	local part = nil
	local uniqueId = game:GetService("HttpService"):GenerateGUID(false)

	if dtype == "CoinPile" then
		-- Yellow cylinder
		part = Instance.new("Part")
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(2, 3, 3)
		part.Color = Color3.fromRGB(255, 215, 0)
		part.Material = Enum.Material.SmoothPlastic
	elseif dtype == "DiamondPile" then
		-- Blue wedge
		part = Instance.new("WedgePart")
		part.Size = Vector3.new(2, 3, 3)
		part.Color = Color3.fromRGB(0, 150, 255)
		part.Material = Enum.Material.Neon
	elseif dtype == "Crate" then
		-- Brown cube
		part = Instance.new("Part")
		part.Shape = Enum.PartType.Block
		part.Size = Vector3.new(3, 3, 3)
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

		-- Award drops
		if destructible.drops.Coins then
			ZoneService._currencyService.addCoins(player, destructible.drops.Coins)
		end
		if destructible.drops.Diamonds then
			ZoneService._currencyService.addDiamonds(player, destructible.drops.Diamonds)
		end

		-- Fire destroyed event to all clients so everyone sees the destruction
		if remotes then
			local event = remotes:FindFirstChild("DestructibleDestroyed")
			if event then
				event:FireAllClients(destructibleId, destructible.drops)
			end
		end

		-- Remove part from workspace
		if destructible.part and destructible.part.Parent then
			destructible.part:Destroy()
		end

		-- Schedule respawn after 10 seconds
		local zoneId = destructible.zoneId
		local dtype = destructible.dtype
		local position = destructible.position
		local dDef = ZoneData.Zones[zoneId].destructibles[dtype]

		-- Remove from tracking
		ZoneService._destructibles[destructibleId] = nil

		-- Respawn after delay
		task.delay(10, function()
			local zoneFolder = ZoneService._zonesFolder:FindFirstChild("Zone_" .. tostring(zoneId))
			if zoneFolder then
				ZoneService._spawnSingleDestructible(zoneId, dtype, dDef, position - Vector3.new(0, 2, 0), zoneFolder)
			end
		end)
	else
		-- Fire damaged event to all clients so everyone sees HP changes
		if remotes then
			local event = remotes:FindFirstChild("DestructibleDamaged")
			if event then
				event:FireAllClients(destructibleId, destructible.hp, destructible.maxHp)
			end
		end
	end

	return true, nil
end

return ZoneService
