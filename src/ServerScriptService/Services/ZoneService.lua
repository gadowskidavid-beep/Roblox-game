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
ZoneService._questService = nil

-- Active destructibles tracked by unique ID
ZoneService._destructibles = {}
-- Workspace references
ZoneService._zonesFolder = nil

-- Rate limiting for attacks (per player)
ZoneService._attackCooldowns = {} -- [userId] = last attack time (os.clock)
ZoneService._clickCooldowns = {} -- [userId] = last click attack time (os.clock)
ZoneService._critCooldowns = {} -- [userId] = last crit attack time (os.clock)

-- Crit window tracking: [userId] = { [destructibleId] = expiry time (os.clock) }
ZoneService._critWindows = {}

-- Pet target assignments: [userId] = { [petInstanceId] = destructibleId }
ZoneService._petTargets = {}

-- Constants for security
local ATTACK_COOLDOWN = 0.5 -- seconds between pet attacks per player
local CLICK_ATTACK_COOLDOWN = 0.2 -- seconds between click attacks per player
local CRIT_ATTACK_COOLDOWN = 0.2 -- seconds between crit attacks per player
local CRIT_WINDOW_DURATION = 3 -- seconds a crit window stays active after click attack
local MAX_ATTACK_DISTANCE = 50 -- maximum studs between player and destructible

-- Zone position offsets (each zone is spaced apart - no gap between zones)
local ZONE_SIZE = Vector3.new(200, 0, 200)
local ZONE_SPACING = 200

-- How many destructibles to spawn per zone (distributed randomly)
local DESTRUCTIBLES_PER_ZONE = 20
-- Minimum distance between spawned destructibles (studs) - prevents overlap between all types
local MIN_SPAWN_DISTANCE = 15

function ZoneService.init(dataService, currencyService, petService)
	ZoneService._dataService = dataService
	ZoneService._currencyService = currencyService
	ZoneService._petService = petService
	ZoneService._questService = nil -- set later via setQuestService

	-- Create zones folder in workspace
	local workspace = game:GetService("Workspace")
	local zonesFolder = workspace:FindFirstChild("Zones")
	if not zonesFolder then
		zonesFolder = Instance.new("Folder")
		zonesFolder.Name = "Zones"
		zonesFolder.Parent = workspace
	end
	ZoneService._zonesFolder = zonesFolder

	-- Spawn the lobby island (safe spawn hub before Zone 1)
	ZoneService._spawnLobby()

	-- Spawn destructibles for all 8 zones
	for zoneId = 1, 8 do
		ZoneService.spawnZone(zoneId)
	end

	-- Spawn zone gates between adjacent zones
	ZoneService._spawnZoneGates()

	-- Spawn egg hatching stations in each zone
	ZoneService._spawnEggStations()

	-- Spawn world decoration (trees, rocks, flowers, lamps, benches)
	ZoneService._spawnWorldDecoration()

	-- Spawn colorful building walls along zone edges (replaces invisible barriers)
	ZoneService._spawnZoneWalls()
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

	-- Gather positions from ALL existing destructibles (all zones, all types) to prevent overlap
	local existingPositions = {}
	for _, d in pairs(ZoneService._destructibles) do
		if d.position then
			table.insert(existingPositions, d.position)
		end
	end

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

-- Create a single destructible with visually distinct appearance per type
-- CoinPile: golden stacked flat cylinders with golden PointLight
-- DiamondPile: cyan diamond shape (rotated cube on tip) with blue PointLight
-- Crate: large brown box with darker lid stripe, bigger than other types
-- fadeIn: if true, all parts start transparent and fade in over 0.5 seconds
function ZoneService._spawnSingleDestructible(zoneId, dtype, dDef, position, parent, fadeIn)
	local uniqueId = game:GetService("HttpService"):GenerateGUID(false)
	local model = Instance.new("Model")
	model.Name = "Destructible_" .. uniqueId

	local mainPart = nil

	if dtype == "CoinPile" then
		-- Stacked flat cylinders (coin pile) - 3 coins stacked
		local coin1 = Instance.new("Part")
		coin1.Name = "Coin1"
		coin1.Shape = Enum.PartType.Cylinder
		coin1.Size = Vector3.new(0.6, 4, 4)
		coin1.Color = Color3.fromRGB(255, 200, 0)
		coin1.Material = Enum.Material.SmoothPlastic
		coin1.Anchored = true
		coin1.CanCollide = true
		coin1.CFrame = CFrame.new(position + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
		coin1.Parent = model

		local coin2 = Instance.new("Part")
		coin2.Name = "Coin2"
		coin2.Shape = Enum.PartType.Cylinder
		coin2.Size = Vector3.new(0.6, 3.5, 3.5)
		coin2.Color = Color3.fromRGB(255, 215, 0)
		coin2.Material = Enum.Material.SmoothPlastic
		coin2.Anchored = true
		coin2.CanCollide = true
		coin2.CFrame = CFrame.new(position + Vector3.new(0.3, 0.9, 0.2)) * CFrame.Angles(0, 0, math.rad(90))
		coin2.Parent = model

		local coin3 = Instance.new("Part")
		coin3.Name = "Coin3"
		coin3.Shape = Enum.PartType.Cylinder
		coin3.Size = Vector3.new(0.6, 3, 3)
		coin3.Color = Color3.fromRGB(255, 230, 50)
		coin3.Material = Enum.Material.SmoothPlastic
		coin3.Anchored = true
		coin3.CanCollide = true
		coin3.CFrame = CFrame.new(position + Vector3.new(-0.2, 1.5, -0.1)) * CFrame.Angles(0, 0, math.rad(90))
		coin3.Parent = model

		-- Golden PointLight for glow
		local glow = Instance.new("PointLight")
		glow.Name = "CoinGlow"
		glow.Color = Color3.fromRGB(255, 200, 0)
		glow.Brightness = 1.5
		glow.Range = 8
		glow.Parent = coin2

		mainPart = coin2

	elseif dtype == "DiamondPile" then
		-- Diamond shape: a cube rotated 45 degrees on tip (like a diamond)
		local diamond = Instance.new("Part")
		diamond.Name = "Diamond"
		diamond.Shape = Enum.PartType.Block
		diamond.Size = Vector3.new(3, 3, 3)
		diamond.Color = Color3.fromRGB(0, 200, 255)
		diamond.Material = Enum.Material.Neon
		diamond.Anchored = true
		diamond.CanCollide = true
		-- Rotate 45 degrees on X and Z to sit on a corner (diamond orientation)
		diamond.CFrame = CFrame.new(position + Vector3.new(0, 2.5, 0)) * CFrame.Angles(math.rad(45), 0, math.rad(45))
		diamond.Parent = model

		-- Smaller inner diamond for depth effect
		local innerDiamond = Instance.new("Part")
		innerDiamond.Name = "InnerDiamond"
		innerDiamond.Shape = Enum.PartType.Block
		innerDiamond.Size = Vector3.new(1.8, 1.8, 1.8)
		innerDiamond.Color = Color3.fromRGB(100, 240, 255)
		innerDiamond.Material = Enum.Material.Neon
		innerDiamond.Transparency = 0.3
		innerDiamond.Anchored = true
		innerDiamond.CanCollide = false
		innerDiamond.CFrame = CFrame.new(position + Vector3.new(0, 2.5, 0)) * CFrame.Angles(math.rad(45), math.rad(30), math.rad(45))
		innerDiamond.Parent = model

		-- Blue PointLight for glow
		local glow = Instance.new("PointLight")
		glow.Name = "DiamondGlow"
		glow.Color = Color3.fromRGB(0, 150, 255)
		glow.Brightness = 2
		glow.Range = 10
		glow.Parent = diamond

		mainPart = diamond

	elseif dtype == "Crate" then
		-- Large brown box with darker lid on top (2 parts)
		local box = Instance.new("Part")
		box.Name = "CrateBody"
		box.Shape = Enum.PartType.Block
		box.Size = Vector3.new(5, 4, 5)
		box.Color = Color3.fromRGB(139, 90, 43)
		box.Material = Enum.Material.Wood
		box.Anchored = true
		box.CanCollide = true
		box.Position = position + Vector3.new(0, 2, 0)
		box.Parent = model

		-- Darker lid on top
		local lid = Instance.new("Part")
		lid.Name = "CrateLid"
		lid.Shape = Enum.PartType.Block
		lid.Size = Vector3.new(5.4, 0.8, 5.4)
		lid.Color = Color3.fromRGB(100, 65, 25)
		lid.Material = Enum.Material.Wood
		lid.Anchored = true
		lid.CanCollide = true
		lid.Position = position + Vector3.new(0, 4.2, 0)
		lid.Parent = model

		-- Horizontal dark stripe (band around the crate)
		local band = Instance.new("Part")
		band.Name = "CrateBand"
		band.Shape = Enum.PartType.Block
		band.Size = Vector3.new(5.1, 0.5, 5.1)
		band.Color = Color3.fromRGB(70, 45, 15)
		band.Material = Enum.Material.Wood
		band.Anchored = true
		band.CanCollide = false
		band.Position = position + Vector3.new(0, 2, 0)
		band.Parent = model

		mainPart = box
	end

	if not mainPart then
		model:Destroy()
		return
	end

	model.PrimaryPart = mainPart
	model.Parent = parent

	-- Store in tracking table (use mainPart as the reference for targeting)
	ZoneService._destructibles[uniqueId] = {
		id = uniqueId,
		zoneId = zoneId,
		dtype = dtype,
		hp = dDef.hp,
		maxHp = dDef.hp,
		drops = dDef.drops,
		part = mainPart,
		model = model,
		position = mainPart.Position,
	}

	-- Tag the main part with the destructible ID for client lookup
	local idValue = Instance.new("StringValue")
	idValue.Name = "DestructibleId"
	idValue.Value = uniqueId
	idValue.Parent = mainPart

	-- Fade-in animation for respawned destructibles (Transparency 1 -> 0 over 0.5 seconds)
	if fadeIn then
		local TweenService = game:GetService("TweenService")
		local fadeInInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				local targetTransparency = part.Transparency
				part.Transparency = 1
				TweenService:Create(part, fadeInInfo, {
					Transparency = targetTransparency,
				}):Play()
			end
		end
	end

	return uniqueId
end

--------------------------------------------------------------------------------
-- LOBBY ISLAND: Safe spawn hub before Zone 1 (Pet Simulator 1 style)
-- Players spawn here and walk through a portal/archway to enter Zone 1.
-- No destructibles spawn in the lobby - it is a safe area.
--------------------------------------------------------------------------------

-- Lobby constants
local LOBBY_CENTER_X = -150
local LOBBY_CENTER_Z = -100
local LOBBY_SIZE = 100 -- 100x100 platform

function ZoneService._spawnLobby()
	local workspace = game:GetService("Workspace")
	local lobbyFolder = workspace:FindFirstChild("Lobby")
	if not lobbyFolder then
		lobbyFolder = Instance.new("Folder")
		lobbyFolder.Name = "Lobby"
		lobbyFolder.Parent = workspace
	end

	-- Main lobby floor platform (100x1x100, light stone/marble feel)
	local floor = Instance.new("Part")
	floor.Name = "LobbyFloor"
	floor.Shape = Enum.PartType.Block
	floor.Size = Vector3.new(LOBBY_SIZE, 1, LOBBY_SIZE)
	floor.Position = Vector3.new(LOBBY_CENTER_X, -0.5, LOBBY_CENTER_Z)
	floor.Anchored = true
	floor.CanCollide = true
	floor.Color = Color3.fromRGB(220, 215, 200)
	floor.Material = Enum.Material.Marble
	floor.Parent = lobbyFolder

	-- Circular decorative ring on the floor (cylinder slightly above the platform)
	local ring = Instance.new("Part")
	ring.Name = "LobbyRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(1, 80, 80)
	ring.Color = Color3.fromRGB(180, 160, 120)
	ring.Material = Enum.Material.Marble
	ring.Anchored = true
	ring.CanCollide = true
	ring.CFrame = CFrame.new(LOBBY_CENTER_X, 0.1, LOBBY_CENTER_Z) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = lobbyFolder

	-- SpawnLocation on the lobby (where players appear)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = Vector3.new(LOBBY_CENTER_X, 1, LOBBY_CENTER_Z)
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.Color = Color3.fromRGB(255, 255, 255)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Parent = lobbyFolder

	-- ===== CENTRAL FOUNTAIN =====
	-- Base pool (flat cylinder)
	local fountainBase = Instance.new("Part")
	fountainBase.Name = "FountainBase"
	fountainBase.Shape = Enum.PartType.Cylinder
	fountainBase.Size = Vector3.new(2, 16, 16)
	fountainBase.Color = Color3.fromRGB(160, 160, 170)
	fountainBase.Material = Enum.Material.Marble
	fountainBase.Anchored = true
	fountainBase.CanCollide = true
	fountainBase.CFrame = CFrame.new(LOBBY_CENTER_X, 1, LOBBY_CENTER_Z) * CFrame.Angles(0, 0, math.rad(90))
	fountainBase.Parent = lobbyFolder

	-- Center pillar
	local fountainPillar = Instance.new("Part")
	fountainPillar.Name = "FountainPillar"
	fountainPillar.Shape = Enum.PartType.Cylinder
	fountainPillar.Size = Vector3.new(8, 2, 2)
	fountainPillar.Color = Color3.fromRGB(200, 200, 210)
	fountainPillar.Material = Enum.Material.Marble
	fountainPillar.Anchored = true
	fountainPillar.CanCollide = true
	fountainPillar.CFrame = CFrame.new(LOBBY_CENTER_X, 5, LOBBY_CENTER_Z) * CFrame.Angles(0, 0, math.rad(90))
	fountainPillar.Parent = lobbyFolder

	-- Top sphere (water orb / decorative top)
	local fountainTop = Instance.new("Part")
	fountainTop.Name = "FountainTop"
	fountainTop.Shape = Enum.PartType.Ball
	fountainTop.Size = Vector3.new(4, 4, 4)
	fountainTop.Color = Color3.fromRGB(100, 180, 255)
	fountainTop.Material = Enum.Material.Neon
	fountainTop.Transparency = 0.3
	fountainTop.Anchored = true
	fountainTop.CanCollide = false
	fountainTop.Position = Vector3.new(LOBBY_CENTER_X, 10, LOBBY_CENTER_Z)
	fountainTop.Parent = lobbyFolder

	-- Water glow
	local waterGlow = Instance.new("PointLight")
	waterGlow.Name = "WaterGlow"
	waterGlow.Color = Color3.fromRGB(100, 180, 255)
	waterGlow.Brightness = 2
	waterGlow.Range = 20
	waterGlow.Parent = fountainTop

	-- ===== BENCHES (4 around the fountain) =====
	local benchPositions = {
		{ x = LOBBY_CENTER_X - 20, z = LOBBY_CENTER_Z },
		{ x = LOBBY_CENTER_X + 20, z = LOBBY_CENTER_Z },
		{ x = LOBBY_CENTER_X, z = LOBBY_CENTER_Z - 20 },
		{ x = LOBBY_CENTER_X, z = LOBBY_CENTER_Z + 20 },
	}
	for i, pos in ipairs(benchPositions) do
		local seat = Instance.new("Part")
		seat.Name = "LobbyBench_Seat_" .. i
		seat.Shape = Enum.PartType.Block
		seat.Size = Vector3.new(6, 0.5, 2.5)
		seat.Color = Color3.fromRGB(139, 90, 43)
		seat.Material = Enum.Material.Wood
		seat.Anchored = true
		seat.CanCollide = true
		seat.Position = Vector3.new(pos.x, 1.25, pos.z)
		seat.Parent = lobbyFolder

		local back = Instance.new("Part")
		back.Name = "LobbyBench_Back_" .. i
		back.Shape = Enum.PartType.Block
		back.Size = Vector3.new(6, 1.5, 0.4)
		back.Color = Color3.fromRGB(120, 75, 35)
		back.Material = Enum.Material.Wood
		back.Anchored = true
		back.CanCollide = true
		back.Position = Vector3.new(pos.x, 2.25, pos.z - 1.05)
		back.Parent = lobbyFolder
	end

	-- ===== LAMP POSTS (6 around the perimeter) =====
	local lampPositions = {
		{ x = LOBBY_CENTER_X - 35, z = LOBBY_CENTER_Z - 35 },
		{ x = LOBBY_CENTER_X + 35, z = LOBBY_CENTER_Z - 35 },
		{ x = LOBBY_CENTER_X - 35, z = LOBBY_CENTER_Z + 35 },
		{ x = LOBBY_CENTER_X + 35, z = LOBBY_CENTER_Z + 35 },
		{ x = LOBBY_CENTER_X - 40, z = LOBBY_CENTER_Z },
		{ x = LOBBY_CENTER_X + 40, z = LOBBY_CENTER_Z },
	}
	for i, pos in ipairs(lampPositions) do
		-- Pole
		local pole = Instance.new("Part")
		pole.Name = "LobbyLamp_Pole_" .. i
		pole.Shape = Enum.PartType.Cylinder
		pole.Size = Vector3.new(8, 0.6, 0.6)
		pole.Color = Color3.fromRGB(50, 50, 55)
		pole.Material = Enum.Material.Metal
		pole.Anchored = true
		pole.CanCollide = true
		pole.CFrame = CFrame.new(pos.x, 4, pos.z) * CFrame.Angles(0, 0, math.rad(90))
		pole.Parent = lobbyFolder

		-- Globe
		local globe = Instance.new("Part")
		globe.Name = "LobbyLamp_Globe_" .. i
		globe.Shape = Enum.PartType.Ball
		globe.Size = Vector3.new(2.5, 2.5, 2.5)
		globe.Color = Color3.fromRGB(255, 240, 180)
		globe.Material = Enum.Material.Neon
		globe.Anchored = true
		globe.CanCollide = false
		globe.Position = Vector3.new(pos.x, 8.5, pos.z)
		globe.Parent = lobbyFolder

		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 230, 150)
		light.Brightness = 1.5
		light.Range = 18
		light.Parent = globe
	end

	-- ===== PORTAL / ARCHWAY to Zone 1 =====
	-- Position: right edge of lobby heading toward Zone 1 (X direction)
	local portalX = LOBBY_CENTER_X + LOBBY_SIZE / 2 -- right edge of lobby
	local portalZ = LOBBY_CENTER_Z

	-- Left pillar
	local portalLeftPillar = Instance.new("Part")
	portalLeftPillar.Name = "PortalLeftPillar"
	portalLeftPillar.Shape = Enum.PartType.Block
	portalLeftPillar.Size = Vector3.new(4, 18, 4)
	portalLeftPillar.Position = Vector3.new(portalX, 9, portalZ - 8)
	portalLeftPillar.Anchored = true
	portalLeftPillar.CanCollide = true
	portalLeftPillar.Color = Color3.fromRGB(80, 180, 80)
	portalLeftPillar.Material = Enum.Material.Marble
	portalLeftPillar.Parent = lobbyFolder

	-- Right pillar
	local portalRightPillar = Instance.new("Part")
	portalRightPillar.Name = "PortalRightPillar"
	portalRightPillar.Shape = Enum.PartType.Block
	portalRightPillar.Size = Vector3.new(4, 18, 4)
	portalRightPillar.Position = Vector3.new(portalX, 9, portalZ + 8)
	portalRightPillar.Anchored = true
	portalRightPillar.CanCollide = true
	portalRightPillar.Color = Color3.fromRGB(80, 180, 80)
	portalRightPillar.Material = Enum.Material.Marble
	portalRightPillar.Parent = lobbyFolder

	-- Top arch connecting the pillars
	local portalArch = Instance.new("Part")
	portalArch.Name = "PortalArch"
	portalArch.Shape = Enum.PartType.Block
	portalArch.Size = Vector3.new(4, 4, 20)
	portalArch.Position = Vector3.new(portalX, 20, portalZ)
	portalArch.Anchored = true
	portalArch.CanCollide = true
	portalArch.Color = Color3.fromRGB(80, 180, 80)
	portalArch.Material = Enum.Material.Marble
	portalArch.Parent = lobbyFolder

	-- Glowing portal fill (semi-transparent green Neon)
	local portalFill = Instance.new("Part")
	portalFill.Name = "PortalFill"
	portalFill.Shape = Enum.PartType.Block
	portalFill.Size = Vector3.new(1, 16, 12)
	portalFill.Position = Vector3.new(portalX, 9, portalZ)
	portalFill.Anchored = true
	portalFill.CanCollide = false
	portalFill.Color = Color3.fromRGB(100, 255, 100)
	portalFill.Material = Enum.Material.Neon
	portalFill.Transparency = 0.5
	portalFill.Parent = lobbyFolder

	-- Portal glow light
	local portalGlow = Instance.new("PointLight")
	portalGlow.Name = "PortalGlow"
	portalGlow.Color = Color3.fromRGB(100, 255, 100)
	portalGlow.Brightness = 3
	portalGlow.Range = 25
	portalGlow.Parent = portalFill

	-- Billboard sign above portal: "Zone 1: Gruene Wiesen"
	local portalBillboard = Instance.new("BillboardGui")
	portalBillboard.Name = "PortalSign"
	portalBillboard.Size = UDim2.fromOffset(280, 60)
	portalBillboard.StudsOffset = Vector3.new(0, 5, 0)
	portalBillboard.AlwaysOnTop = true
	portalBillboard.MaxDistance = 80
	portalBillboard.Adornee = portalArch
	portalBillboard.Parent = portalArch

	local portalSignBg = Instance.new("Frame")
	portalSignBg.Name = "Background"
	portalSignBg.Size = UDim2.fromScale(1, 1)
	portalSignBg.BackgroundColor3 = Color3.fromRGB(20, 60, 20)
	portalSignBg.BackgroundTransparency = 0.3
	portalSignBg.BorderSizePixel = 0
	portalSignBg.Parent = portalBillboard

	local portalSignCorner = Instance.new("UICorner")
	portalSignCorner.CornerRadius = UDim.new(0, 10)
	portalSignCorner.Parent = portalSignBg

	local portalSignText = Instance.new("TextLabel")
	portalSignText.Name = "ZoneLabel"
	portalSignText.Size = UDim2.fromScale(1, 1)
	portalSignText.BackgroundTransparency = 1
	portalSignText.Text = "Zone 1: Gruene Wiesen"
	portalSignText.TextColor3 = Color3.fromRGB(255, 255, 255)
	portalSignText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	portalSignText.TextStrokeTransparency = 0.2
	portalSignText.Font = Enum.Font.GothamBold
	portalSignText.TextScaled = true
	portalSignText.Parent = portalSignBg

	-- ===== WALKABLE PATH from lobby to Zone 1 =====
	-- Bridge the gap between lobby right edge (X=-100) and Zone 1 left edge (X=-100)
	-- Since Zone 1 starts at X=-100 and lobby ends at X=-100, we add a connector path
	local pathLength = 50 -- overlap/bridge into Zone 1
	local path = Instance.new("Part")
	path.Name = "LobbyToZonePath"
	path.Shape = Enum.PartType.Block
	path.Size = Vector3.new(pathLength, 1, 16)
	path.Position = Vector3.new(LOBBY_CENTER_X + LOBBY_SIZE / 2 + pathLength / 2, -0.5, LOBBY_CENTER_Z)
	path.Anchored = true
	path.CanCollide = true
	path.Color = Color3.fromRGB(200, 195, 180)
	path.Material = Enum.Material.Cobblestone
	path.Parent = lobbyFolder

	-- ===== LEADERBOARD DISPLAY =====
	-- A tall board near the spawn showing top players (placeholder with SurfaceGui)
	local lbX = LOBBY_CENTER_X - 25
	local lbZ = LOBBY_CENTER_Z + 25

	local lbBoard = Instance.new("Part")
	lbBoard.Name = "LeaderboardBoard"
	lbBoard.Shape = Enum.PartType.Block
	lbBoard.Size = Vector3.new(0.5, 10, 8)
	lbBoard.Position = Vector3.new(lbX, 6, lbZ)
	lbBoard.Anchored = true
	lbBoard.CanCollide = true
	lbBoard.Color = Color3.fromRGB(40, 40, 50)
	lbBoard.Material = Enum.Material.SmoothPlastic
	lbBoard.Parent = lobbyFolder

	-- SurfaceGui on the leaderboard (placeholder content)
	local lbGui = Instance.new("SurfaceGui")
	lbGui.Name = "LeaderboardGui"
	lbGui.Face = Enum.NormalId.Front
	lbGui.Adornee = lbBoard
	lbGui.Parent = lbBoard

	local lbTitle = Instance.new("TextLabel")
	lbTitle.Name = "Title"
	lbTitle.Size = UDim2.fromScale(1, 0.15)
	lbTitle.Position = UDim2.fromScale(0, 0)
	lbTitle.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
	lbTitle.BackgroundTransparency = 0.2
	lbTitle.Text = "LEADERBOARD"
	lbTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	lbTitle.Font = Enum.Font.GothamBold
	lbTitle.TextScaled = true
	lbTitle.Parent = lbGui

	-- Placeholder entries
	for rank = 1, 5 do
		local entry = Instance.new("TextLabel")
		entry.Name = "Rank_" .. rank
		entry.Size = UDim2.new(1, 0, 0.15, 0)
		entry.Position = UDim2.new(0, 0, 0.15 + (rank - 1) * 0.16, 0)
		entry.BackgroundTransparency = 0.5
		entry.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
		entry.Text = "#" .. rank .. " - Player" .. rank
		entry.TextColor3 = Color3.fromRGB(200, 200, 200)
		entry.Font = Enum.Font.Gotham
		entry.TextScaled = true
		entry.Parent = lbGui
	end

	-- Leaderboard stand/post
	local lbPost = Instance.new("Part")
	lbPost.Name = "LeaderboardPost"
	lbPost.Shape = Enum.PartType.Cylinder
	lbPost.Size = Vector3.new(6, 0.8, 0.8)
	lbPost.Color = Color3.fromRGB(60, 60, 70)
	lbPost.Material = Enum.Material.Metal
	lbPost.Anchored = true
	lbPost.CanCollide = true
	lbPost.CFrame = CFrame.new(lbX, 3, lbZ) * CFrame.Angles(0, 0, math.rad(90))
	lbPost.Parent = lobbyFolder

	-- ===== QUESTS BOARD =====
	local qbX = LOBBY_CENTER_X + 20
	local qbZ = LOBBY_CENTER_Z + 30

	local questBoard = Instance.new("Part")
	questBoard.Name = "QuestBoard"
	questBoard.Shape = Enum.PartType.Block
	questBoard.Size = Vector3.new(0.5, 8, 6)
	questBoard.Position = Vector3.new(qbX, 5, qbZ)
	questBoard.Anchored = true
	questBoard.CanCollide = true
	questBoard.Color = Color3.fromRGB(101, 67, 33)
	questBoard.Material = Enum.Material.Wood
	questBoard.Parent = lobbyFolder

	-- Quest board sign
	local qbBillboard = Instance.new("BillboardGui")
	qbBillboard.Name = "QuestBoardSign"
	qbBillboard.Size = UDim2.fromOffset(160, 40)
	qbBillboard.StudsOffset = Vector3.new(0, 5, 0)
	qbBillboard.AlwaysOnTop = true
	qbBillboard.MaxDistance = 30
	qbBillboard.Adornee = questBoard
	qbBillboard.Parent = questBoard

	local qbText = Instance.new("TextLabel")
	qbText.Name = "QuestLabel"
	qbText.Size = UDim2.fromScale(1, 1)
	qbText.BackgroundColor3 = Color3.fromRGB(60, 40, 20)
	qbText.BackgroundTransparency = 0.3
	qbText.Text = "QUESTS"
	qbText.TextColor3 = Color3.fromRGB(255, 220, 100)
	qbText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	qbText.TextStrokeTransparency = 0.3
	qbText.Font = Enum.Font.GothamBold
	qbText.TextScaled = true
	qbText.Parent = qbBillboard

	-- Quest board post
	local qbPost = Instance.new("Part")
	qbPost.Name = "QuestBoardPost"
	qbPost.Shape = Enum.PartType.Cylinder
	qbPost.Size = Vector3.new(5, 0.6, 0.6)
	qbPost.Color = Color3.fromRGB(80, 55, 25)
	qbPost.Material = Enum.Material.Wood
	qbPost.Anchored = true
	qbPost.CanCollide = true
	qbPost.CFrame = CFrame.new(qbX, 2.5, qbZ) * CFrame.Angles(0, 0, math.rad(90))
	qbPost.Parent = lobbyFolder

	-- ===== SHOP STAND =====
	local shopX = LOBBY_CENTER_X - 20
	local shopZ = LOBBY_CENTER_Z - 30

	-- Shop counter (table-like block)
	local shopCounter = Instance.new("Part")
	shopCounter.Name = "ShopCounter"
	shopCounter.Shape = Enum.PartType.Block
	shopCounter.Size = Vector3.new(8, 3, 4)
	shopCounter.Position = Vector3.new(shopX, 1.5, shopZ)
	shopCounter.Anchored = true
	shopCounter.CanCollide = true
	shopCounter.Color = Color3.fromRGB(180, 130, 60)
	shopCounter.Material = Enum.Material.Wood
	shopCounter.Parent = lobbyFolder

	-- Shop awning (roof)
	local shopAwning = Instance.new("Part")
	shopAwning.Name = "ShopAwning"
	shopAwning.Shape = Enum.PartType.Block
	shopAwning.Size = Vector3.new(10, 0.5, 6)
	shopAwning.Position = Vector3.new(shopX, 6, shopZ)
	shopAwning.Anchored = true
	shopAwning.CanCollide = true
	shopAwning.Color = Color3.fromRGB(200, 60, 60)
	shopAwning.Material = Enum.Material.Fabric
	shopAwning.Parent = lobbyFolder

	-- Shop awning support poles
	local shopPole1 = Instance.new("Part")
	shopPole1.Name = "ShopPole1"
	shopPole1.Shape = Enum.PartType.Cylinder
	shopPole1.Size = Vector3.new(6, 0.5, 0.5)
	shopPole1.Color = Color3.fromRGB(60, 60, 70)
	shopPole1.Material = Enum.Material.Metal
	shopPole1.Anchored = true
	shopPole1.CanCollide = true
	shopPole1.CFrame = CFrame.new(shopX - 4, 3, shopZ - 2.5) * CFrame.Angles(0, 0, math.rad(90))
	shopPole1.Parent = lobbyFolder

	local shopPole2 = Instance.new("Part")
	shopPole2.Name = "ShopPole2"
	shopPole2.Shape = Enum.PartType.Cylinder
	shopPole2.Size = Vector3.new(6, 0.5, 0.5)
	shopPole2.Color = Color3.fromRGB(60, 60, 70)
	shopPole2.Material = Enum.Material.Metal
	shopPole2.Anchored = true
	shopPole2.CanCollide = true
	shopPole2.CFrame = CFrame.new(shopX + 4, 3, shopZ - 2.5) * CFrame.Angles(0, 0, math.rad(90))
	shopPole2.Parent = lobbyFolder

	-- Shop sign
	local shopBillboard = Instance.new("BillboardGui")
	shopBillboard.Name = "ShopSign"
	shopBillboard.Size = UDim2.fromOffset(160, 40)
	shopBillboard.StudsOffset = Vector3.new(0, 3, 0)
	shopBillboard.AlwaysOnTop = true
	shopBillboard.MaxDistance = 30
	shopBillboard.Adornee = shopAwning
	shopBillboard.Parent = shopAwning

	local shopText = Instance.new("TextLabel")
	shopText.Name = "ShopLabel"
	shopText.Size = UDim2.fromScale(1, 1)
	shopText.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	shopText.BackgroundTransparency = 0.3
	shopText.Text = "SHOP"
	shopText.TextColor3 = Color3.fromRGB(255, 255, 255)
	shopText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	shopText.TextStrokeTransparency = 0.3
	shopText.Font = Enum.Font.GothamBold
	shopText.TextScaled = true
	shopText.Parent = shopBillboard

	-- ===== WELCOME SIGN near spawn =====
	local welcomeSign = Instance.new("Part")
	welcomeSign.Name = "WelcomeSign"
	welcomeSign.Shape = Enum.PartType.Block
	welcomeSign.Size = Vector3.new(0.3, 5, 10)
	welcomeSign.Position = Vector3.new(LOBBY_CENTER_X, 4, LOBBY_CENTER_Z + 15)
	welcomeSign.Anchored = true
	welcomeSign.CanCollide = true
	welcomeSign.Color = Color3.fromRGB(50, 50, 60)
	welcomeSign.Material = Enum.Material.SmoothPlastic
	welcomeSign.Parent = lobbyFolder

	local welcomeBillboard = Instance.new("BillboardGui")
	welcomeBillboard.Name = "WelcomeText"
	welcomeBillboard.Size = UDim2.fromOffset(300, 80)
	welcomeBillboard.StudsOffset = Vector3.new(0, 3, 0)
	welcomeBillboard.AlwaysOnTop = true
	welcomeBillboard.MaxDistance = 50
	welcomeBillboard.Adornee = welcomeSign
	welcomeBillboard.Parent = welcomeSign

	local welcomeText = Instance.new("TextLabel")
	welcomeText.Name = "WelcomeLabel"
	welcomeText.Size = UDim2.fromScale(1, 1)
	welcomeText.BackgroundTransparency = 1
	welcomeText.Text = "Welcome to Battle Pets!"
	welcomeText.TextColor3 = Color3.fromRGB(255, 255, 255)
	welcomeText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	welcomeText.TextStrokeTransparency = 0.2
	welcomeText.Font = Enum.Font.GothamBold
	welcomeText.TextScaled = true
	welcomeText.Parent = welcomeBillboard
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
		[3] = { eggType = "StrandEgg", name = "Strand Egg", cost = Config.EggCosts[3].Coins },
		[4] = { eggType = "WuesteEgg", name = "Wueste Egg", cost = Config.EggCosts[4].Coins },
		[5] = { eggType = "EisweltEgg", name = "Eiswelt Egg", cost = Config.EggCosts[5].Coins },
		[6] = { eggType = "VulkanEgg", name = "Vulkan Egg", cost = Config.EggCosts[6].Coins },
		[7] = { eggType = "HimmelEgg", name = "Himmel Egg", cost = Config.EggCosts[7].Coins },
		[8] = { eggType = "WeltraumEgg", name = "Weltraum Egg", cost = Config.EggCosts[8].Coins },
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
		egg.Color = ({
			[1] = Color3.fromRGB(200, 230, 180), -- green (Gruene Wiesen)
			[2] = Color3.fromRGB(180, 200, 255), -- blue-gray (Stadt)
			[3] = Color3.fromRGB(237, 201, 136), -- sandy (Strand)
			[4] = Color3.fromRGB(210, 180, 100), -- desert gold (Wueste)
			[5] = Color3.fromRGB(200, 230, 255), -- icy blue (Eiswelt)
			[6] = Color3.fromRGB(200, 80, 30),   -- fiery red (Vulkan)
			[7] = Color3.fromRGB(255, 255, 220), -- heavenly white (Himmel)
			[8] = Color3.fromRGB(100, 50, 200),  -- cosmic purple (Weltraum)
		})[zoneId] or Color3.fromRGB(200, 200, 200)
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
		billboard.MaxDistance = 25
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

		-- BillboardGui showing which pets are in this egg with their % chance
		local PetData = require(game.ReplicatedStorage.Shared.PetData)
		local eggDef = PetData.Eggs[stationDef.eggType]
		if eggDef and eggDef.petPool then
			-- Calculate total weight for percentage
			local totalWeight = 0
			for _, entry in ipairs(eggDef.petPool) do
				totalWeight = totalWeight + entry.weight
			end

			local numPets = #eggDef.petPool
			local petsBillboard = Instance.new("BillboardGui")
			petsBillboard.Name = "PetChancesLabel"
			petsBillboard.Size = UDim2.fromOffset(200, 20 + numPets * 22)
			petsBillboard.StudsOffset = Vector3.new(0, 7, 0)
			petsBillboard.AlwaysOnTop = true
			petsBillboard.MaxDistance = 12
			petsBillboard.Adornee = egg
			petsBillboard.Parent = egg

			local petsBg = Instance.new("Frame")
			petsBg.Name = "Background"
			petsBg.Size = UDim2.fromScale(1, 1)
			petsBg.BackgroundColor3 = Color3.fromRGB(20, 30, 60)
			petsBg.BackgroundTransparency = 0.3
			petsBg.BorderSizePixel = 0
			petsBg.Parent = petsBillboard

			local petsBgCorner = Instance.new("UICorner")
			petsBgCorner.CornerRadius = UDim.new(0, 8)
			petsBgCorner.Parent = petsBg

			local petsLayout = Instance.new("UIListLayout")
			petsLayout.FillDirection = Enum.FillDirection.Vertical
			petsLayout.Padding = UDim.new(0, 2)
			petsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
			petsLayout.Parent = petsBg

			local petsPadding = Instance.new("UIPadding")
			petsPadding.PaddingTop = UDim.new(0, 4)
			petsPadding.PaddingBottom = UDim.new(0, 4)
			petsPadding.PaddingLeft = UDim.new(0, 6)
			petsPadding.PaddingRight = UDim.new(0, 6)
			petsPadding.Parent = petsBg

			-- Rarity colors for pet chance display
			local rarityColors = {
				Common = Color3.fromRGB(255, 255, 255),
				Uncommon = Color3.fromRGB(0, 200, 0),
				Rare = Color3.fromRGB(0, 120, 255),
				Epic = Color3.fromRGB(180, 0, 255),
				Legendary = Color3.fromRGB(255, 200, 0),
			}

			for _, entry in ipairs(eggDef.petPool) do
				local petDef = PetData.Pets[entry.petId]
				if petDef then
					local percentage = math.floor((entry.weight / totalWeight) * 100 + 0.5)
					local petColor = rarityColors[petDef.rarity] or Color3.fromRGB(255, 255, 255)

					local petLine = Instance.new("TextLabel")
					petLine.Name = "Pet_" .. entry.petId
					petLine.Size = UDim2.new(1, 0, 0, 18)
					petLine.BackgroundTransparency = 1
					petLine.Text = petDef.name .. " (" .. petDef.rarity .. ") - " .. tostring(percentage) .. "%"
					petLine.TextColor3 = petColor
					petLine.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
					petLine.TextStrokeTransparency = 0.3
					petLine.Font = Enum.Font.GothamBold
					petLine.TextScaled = true
					petLine.Parent = petsBg
				end
			end
		end

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

		-- ProximityPrompt on the egg for E-key interaction
		local proximityPrompt = Instance.new("ProximityPrompt")
		proximityPrompt.Name = "HatchPrompt"
		proximityPrompt.ActionText = "Hatch"
		proximityPrompt.ObjectText = stationDef.name .. " (" .. tostring(stationDef.cost) .. " Coins)"
		proximityPrompt.KeyboardKeyCode = Enum.KeyCode.E
		proximityPrompt.HoldDuration = 0
		proximityPrompt.MaxActivationDistance = 10
		proximityPrompt.RequiresLineOfSight = false
		proximityPrompt.Parent = egg

		-- Tag the ProximityPrompt's parent egg with the egg type
		local promptEggTag = Instance.new("StringValue")
		promptEggTag.Name = "PromptEggType"
		promptEggTag.Value = stationDef.eggType
		promptEggTag.Parent = egg
	end
end

-- Zone gate pillar colors per zone (matching the zone's theme)
local GATE_PILLAR_COLORS = {
	[2] = Color3.fromRGB(140, 140, 160), -- Stadt: gray/blue-ish concrete
	[3] = Color3.fromRGB(194, 178, 128), -- Strand: sandy
	[4] = Color3.fromRGB(180, 140, 60),  -- Wueste: golden sand
	[5] = Color3.fromRGB(160, 200, 240), -- Eiswelt: icy blue
	[6] = Color3.fromRGB(120, 40, 20),   -- Vulkan: dark red/lava
	[7] = Color3.fromRGB(240, 240, 200), -- Himmel: bright gold/white
	[8] = Color3.fromRGB(40, 20, 80),    -- Weltraum: dark purple
}

-- Spawn large Pet Simulator 1 style zone gates between adjacent zones
-- Each gate consists of: two tall pillars, a connecting arch on top,
-- a semi-transparent barrier in the middle (disappears on unlock),
-- and a large BillboardGui showing zone name and cost.
function ZoneService._spawnZoneGates()
	local workspace = game:GetService("Workspace")
	local gatesFolder = workspace:FindFirstChild("ZoneGates")
	if not gatesFolder then
		gatesFolder = Instance.new("Folder")
		gatesFolder.Name = "ZoneGates"
		gatesFolder.Parent = workspace
	end

	-- Create gates between zone 1->2, 2->3, etc.
	for gateZone = 2, 8 do
		local zoneDef = ZoneData.Zones[gateZone]
		if not zoneDef then continue end

		-- Gate position: at the boundary between zones (halfway between zone centers)
		local prevCenter = (gateZone - 2) * ZONE_SPACING
		local currCenter = (gateZone - 1) * ZONE_SPACING
		local gateX = (prevCenter + currCenter) / 2
		local gateZ = -100 -- center Z of zones

		-- Gate dimensions
		local PILLAR_WIDTH = 4
		local PILLAR_HEIGHT = 20
		local PILLAR_DEPTH = 4
		local GATE_OPENING_WIDTH = 20 -- space between pillars for walking through
		local ARCH_HEIGHT = 4
		local BARRIER_THICKNESS = 2

		local pillarColor = GATE_PILLAR_COLORS[gateZone] or Color3.fromRGB(150, 150, 150)
		local pillarMaterial = Enum.Material.Concrete

		-- Create a model to hold all gate parts
		local gateModel = Instance.new("Model")
		gateModel.Name = "ZoneGateModel_" .. tostring(gateZone)
		gateModel.Parent = gatesFolder

		-- LEFT PILLAR (negative Z side)
		local leftPillar = Instance.new("Part")
		leftPillar.Name = "LeftPillar"
		leftPillar.Size = Vector3.new(PILLAR_WIDTH, PILLAR_HEIGHT, PILLAR_DEPTH)
		leftPillar.Position = Vector3.new(gateX, PILLAR_HEIGHT / 2, gateZ - GATE_OPENING_WIDTH / 2 - PILLAR_DEPTH / 2)
		leftPillar.Anchored = true
		leftPillar.CanCollide = true
		leftPillar.Color = pillarColor
		leftPillar.Material = pillarMaterial
		leftPillar.Parent = gateModel

		-- RIGHT PILLAR (positive Z side)
		local rightPillar = Instance.new("Part")
		rightPillar.Name = "RightPillar"
		rightPillar.Size = Vector3.new(PILLAR_WIDTH, PILLAR_HEIGHT, PILLAR_DEPTH)
		rightPillar.Position = Vector3.new(gateX, PILLAR_HEIGHT / 2, gateZ + GATE_OPENING_WIDTH / 2 + PILLAR_DEPTH / 2)
		rightPillar.Anchored = true
		rightPillar.CanCollide = true
		rightPillar.Color = pillarColor
		rightPillar.Material = pillarMaterial
		rightPillar.Parent = gateModel

		-- TOP ARCH (connects both pillars at the top)
		local archWidth = GATE_OPENING_WIDTH + PILLAR_DEPTH * 2 -- spans full width including pillars
		local topArch = Instance.new("Part")
		topArch.Name = "TopArch"
		topArch.Size = Vector3.new(PILLAR_WIDTH, ARCH_HEIGHT, archWidth)
		topArch.Position = Vector3.new(gateX, PILLAR_HEIGHT + ARCH_HEIGHT / 2, gateZ)
		topArch.Anchored = true
		topArch.CanCollide = true
		topArch.Color = pillarColor
		topArch.Material = pillarMaterial
		topArch.Parent = gateModel

		-- Decorative top trim (slightly wider, darker)
		local topTrim = Instance.new("Part")
		topTrim.Name = "TopTrim"
		topTrim.Size = Vector3.new(PILLAR_WIDTH + 1, 1, archWidth + 1)
		topTrim.Position = Vector3.new(gateX, PILLAR_HEIGHT + ARCH_HEIGHT + 0.5, gateZ)
		topTrim.Anchored = true
		topTrim.CanCollide = true
		topTrim.Color = Color3.fromRGB(
			math.max(0, pillarColor.R * 255 - 40),
			math.max(0, pillarColor.G * 255 - 40),
			math.max(0, pillarColor.B * 255 - 40)
		)
		topTrim.Material = Enum.Material.SmoothPlastic
		topTrim.Parent = gateModel

		-- Pillar caps (decorative top pieces on each pillar)
		local leftCap = Instance.new("Part")
		leftCap.Name = "LeftPillarCap"
		leftCap.Size = Vector3.new(PILLAR_WIDTH + 1, 1.5, PILLAR_DEPTH + 1)
		leftCap.Position = Vector3.new(gateX, PILLAR_HEIGHT + 0.75, leftPillar.Position.Z)
		leftCap.Anchored = true
		leftCap.CanCollide = true
		leftCap.Color = pillarColor
		leftCap.Material = Enum.Material.SmoothPlastic
		leftCap.Parent = gateModel

		local rightCap = Instance.new("Part")
		rightCap.Name = "RightPillarCap"
		rightCap.Size = Vector3.new(PILLAR_WIDTH + 1, 1.5, PILLAR_DEPTH + 1)
		rightCap.Position = Vector3.new(gateX, PILLAR_HEIGHT + 0.75, rightPillar.Position.Z)
		rightCap.Anchored = true
		rightCap.CanCollide = true
		rightCap.Color = pillarColor
		rightCap.Material = Enum.Material.SmoothPlastic
		rightCap.Parent = gateModel

		-- BARRIER (semi-transparent visual wall in the gate opening, reddish when locked)
		-- CanCollide is false so the Touched trigger can detect players reliably.
		-- A separate invisible Blocker part handles the physical collision.
		local barrier = Instance.new("Part")
		barrier.Name = "GateBarrier_" .. tostring(gateZone)
		barrier.Size = Vector3.new(BARRIER_THICKNESS, PILLAR_HEIGHT, GATE_OPENING_WIDTH)
		barrier.Position = Vector3.new(gateX, PILLAR_HEIGHT / 2, gateZ)
		barrier.Anchored = true
		barrier.CanCollide = false
		barrier.Color = Color3.fromRGB(255, 60, 60)
		barrier.Material = Enum.Material.ForceField
		barrier.Transparency = 0.5
		barrier.Parent = gateModel

		-- Invisible blocker part that physically stops players from walking through
		local blocker = Instance.new("Part")
		blocker.Name = "GateBlocker_" .. tostring(gateZone)
		blocker.Size = Vector3.new(BARRIER_THICKNESS + 1, PILLAR_HEIGHT, GATE_OPENING_WIDTH)
		blocker.Position = Vector3.new(gateX, PILLAR_HEIGHT / 2, gateZ)
		blocker.Anchored = true
		blocker.CanCollide = true
		blocker.Transparency = 1
		blocker.Parent = gateModel

		-- Tag blocker with the zone ID so it can be found per-player
		local blockerZoneTag = Instance.new("IntValue")
		blockerZoneTag.Name = "GateZoneId"
		blockerZoneTag.Value = gateZone
		blockerZoneTag.Parent = blocker

		-- Tag barrier so client can identify it
		local zoneTag = Instance.new("IntValue")
		zoneTag.Name = "GateZoneId"
		zoneTag.Value = gateZone
		zoneTag.Parent = barrier

		-- BILLBOARD GUI on the top arch (large, readable zone name and cost)
		local cost = Config.ZoneGateCosts[gateZone] or 0
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "GateLabel"
		billboard.Size = UDim2.fromOffset(300, 120)
		billboard.StudsOffset = Vector3.new(0, 6, 0)
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = 60
		billboard.Adornee = topArch
		billboard.Parent = topArch

		-- Background frame for the sign
		local signBg = Instance.new("Frame")
		signBg.Name = "SignBackground"
		signBg.Size = UDim2.fromScale(1, 1)
		signBg.BackgroundColor3 = Color3.fromRGB(30, 30, 50)
		signBg.BackgroundTransparency = 0.3
		signBg.BorderSizePixel = 0
		signBg.Parent = billboard

		local signCorner = Instance.new("UICorner")
		signCorner.CornerRadius = UDim.new(0, 12)
		signCorner.Parent = signBg

		local signPadding = Instance.new("UIPadding")
		signPadding.PaddingTop = UDim.new(0, 8)
		signPadding.PaddingBottom = UDim.new(0, 8)
		signPadding.PaddingLeft = UDim.new(0, 12)
		signPadding.PaddingRight = UDim.new(0, 12)
		signPadding.Parent = signBg

		-- Zone name label (top half)
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "ZoneName"
		nameLabel.Size = UDim2.fromScale(1, 0.5)
		nameLabel.Position = UDim2.fromScale(0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = zoneDef.name
		nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		nameLabel.TextStrokeTransparency = 0.2
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextScaled = true
		nameLabel.Parent = signBg

		-- Cost label (bottom half, gold color with coin icon text)
		local priceLabel = Instance.new("TextLabel")
		priceLabel.Name = "PriceText"
		priceLabel.Size = UDim2.fromScale(1, 0.45)
		priceLabel.Position = UDim2.fromScale(0, 0.55)
		priceLabel.BackgroundTransparency = 1
		priceLabel.Text = tostring(cost) .. " Coins"
		priceLabel.TextColor3 = Color3.fromRGB(255, 220, 0)
		priceLabel.TextStrokeColor3 = Color3.fromRGB(80, 60, 0)
		priceLabel.TextStrokeTransparency = 0.2
		priceLabel.Font = Enum.Font.GothamBold
		priceLabel.TextScaled = true
		priceLabel.Parent = signBg

		-- Connect Touched event on the barrier for zone unlocking
		-- Use a helper to resolve the player from either direct body part or accessory handle
		local function getPlayerFromHit(hit)
			local player = game:GetService("Players"):GetPlayerFromCharacter(hit.Parent)
			if not player and hit.Parent then
				player = game:GetService("Players"):GetPlayerFromCharacter(hit.Parent.Parent)
			end
			return player
		end

		barrier.Touched:Connect(function(hit)
			local player = getPlayerFromHit(hit)
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
				-- Remove the visual barrier and the physical blocker
				barrier.Transparency = 1
				if blocker and blocker.Parent then
					blocker:Destroy()
				end
				return
			end

			-- Try to unlock the zone
			local success, err = ZoneService.unlockZone(player, gateZone)
			if success then
				-- Remove the barrier (make invisible) and destroy the blocker
				local barrierPosition = barrier.Position
				barrier.Transparency = 1
				if blocker and blocker.Parent then
					blocker:Destroy()
				end

				-- Fire zone unlock effect with gate position for particle/flash effect
				local remotes = ReplicatedStorage:FindFirstChild("Remotes")
				if remotes then
					local event = remotes:FindFirstChild("ZoneUnlocked")
					if event then
						event:FireClient(player, gateZone, barrierPosition)
					end
				end

				-- Create a brief unlock flash effect on the pillars (Neon flash)
				local TweenService = game:GetService("TweenService")
				local flashInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

				-- Flash pillars and arch briefly to white then back
				local partsToFlash = { leftPillar, rightPillar, topArch }
				for _, flashPart in ipairs(partsToFlash) do
					local originalColor = flashPart.Color
					flashPart.Color = Color3.fromRGB(255, 255, 255)
					flashPart.Material = Enum.Material.Neon
					TweenService:Create(flashPart, flashInfo, {
						Color = originalColor,
					}):Play()
					-- Restore material after flash
					task.delay(0.5, function()
						flashPart.Material = pillarMaterial
					end)
				end

				-- Spawn particles at the barrier position for unlock celebration
				local particlePart = Instance.new("Part")
				particlePart.Name = "UnlockParticles"
				particlePart.Size = Vector3.new(1, 1, 1)
				particlePart.Position = barrierPosition
				particlePart.Anchored = true
				particlePart.CanCollide = false
				particlePart.Transparency = 1
				particlePart.Parent = workspace

				local particles = Instance.new("ParticleEmitter")
				particles.Color = ColorSequence.new(Color3.fromRGB(255, 220, 0), Color3.fromRGB(255, 255, 255))
				particles.Size = NumberSequence.new(1, 0)
				particles.Lifetime = NumberRange.new(0.5, 1.5)
				particles.Speed = NumberRange.new(10, 25)
				particles.SpreadAngle = Vector2.new(180, 180)
				particles.Rate = 200
				particles.Parent = particlePart

				-- Stop emitting after a short burst, then clean up
				task.delay(0.5, function()
					particles.Rate = 0
				end)
				task.delay(2, function()
					particlePart:Destroy()
				end)

				-- Update billboard to show "UNLOCKED" text
				nameLabel.Text = zoneDef.name .. " - UNLOCKED!"
				nameLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
				priceLabel.Text = "Welcome!"
				priceLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
			end
		end)

		-- Also connect Touched on the blocker so players hitting the invisible wall
		-- can still trigger unlock logic (the blocker is what they physically contact)
		blocker.Touched:Connect(function(hit)
			local player = getPlayerFromHit(hit)
			if not player then return end

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
				-- Player already owns this zone - remove barrier and blocker
				barrier.Transparency = 1
				if blocker and blocker.Parent then
					blocker:Destroy()
				end
				return
			end

			-- Try to unlock the zone
			local success, err = ZoneService.unlockZone(player, gateZone)
			if success then
				local barrierPosition = barrier.Position
				barrier.Transparency = 1
				if blocker and blocker.Parent then
					blocker:Destroy()
				end

				-- Fire zone unlock effect
				local remotes = ReplicatedStorage:FindFirstChild("Remotes")
				if remotes then
					local event = remotes:FindFirstChild("ZoneUnlocked")
					if event then
						event:FireClient(player, gateZone, barrierPosition)
					end
				end

				-- Update billboard to show "UNLOCKED" text
				nameLabel.Text = zoneDef.name .. " - UNLOCKED!"
				nameLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
				priceLabel.Text = "Welcome!"
				priceLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
			end
		end)
	end

	-- Proactive barrier removal: when a player spawns, remove blockers for zones
	-- they have already unlocked. This prevents the "can see UNLOCKED but can't walk
	-- through" issue caused by unreliable Touched event firing.
	game:GetService("Players").PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			-- Small delay to ensure DataService has loaded the player data
			task.delay(1, function()
				local data = ZoneService._dataService.getPlayerData(player)
				if not data then return end

				local workspace = game:GetService("Workspace")
				local gatesFolder = workspace:FindFirstChild("ZoneGates")
				if not gatesFolder then return end

				for _, unlockedZoneId in ipairs(data.unlockedZones) do
					-- Find and remove blockers for this zone
					for _, gateModel in ipairs(gatesFolder:GetChildren()) do
						if gateModel:IsA("Model") then
							for _, part in ipairs(gateModel:GetChildren()) do
								if part:IsA("BasePart") then
									local tag = part:FindFirstChild("GateZoneId")
									if tag and tag.Value == unlockedZoneId then
										if part.Name:find("GateBlocker_") then
											part:Destroy()
										elseif part.Name:find("GateBarrier_") then
											part.Transparency = 1
										end
									end
								end
							end
						end
					end
				end
			end)
		end)
	end)
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

-- Assign a pet to target a specific destructible (called by client)
function ZoneService.assignPetTarget(player, petInstanceId, destructibleId)
	if not player or type(petInstanceId) ~= "string" then
		return false, "Invalid parameters"
	end

	local userId = player.UserId

	-- Initialize target table for this player if needed
	if not ZoneService._petTargets[userId] then
		ZoneService._petTargets[userId] = {}
	end

	-- Allow clearing a target (nil destructibleId)
	if destructibleId == nil or destructibleId == "" then
		ZoneService._petTargets[userId][petInstanceId] = nil
		return true, nil
	end

	if type(destructibleId) ~= "string" then
		return false, "Invalid destructible ID"
	end

	-- Validate the destructible exists
	if not ZoneService._destructibles[destructibleId] then
		return false, "Destructible not found"
	end

	-- Validate the pet belongs to this player and is equipped
	local data = ZoneService._dataService.getPlayerData(player)
	if not data then
		return false, "No player data"
	end

	local petFound = false
	for _, pet in ipairs(data.pets) do
		if pet.id == petInstanceId and pet.equipped then
			petFound = true
			break
		end
	end

	if not petFound then
		return false, "Pet not found or not equipped"
	end

	ZoneService._petTargets[userId][petInstanceId] = destructibleId
	return true, nil
end

-- Cleanup player rate limits and pet targets (call on player removing)
function ZoneService.onPlayerRemoving(player)
	if player then
		local userId = player.UserId
		ZoneService._attackCooldowns[userId] = nil
		ZoneService._clickCooldowns[userId] = nil
		ZoneService._critCooldowns[userId] = nil
		ZoneService._critWindows[userId] = nil
		ZoneService._petTargets[userId] = nil
	end
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

	-- Rate limiting: 0.5 second cooldown between attacks per player
	local userId = player.UserId
	local now = os.clock()
	local lastAttack = ZoneService._attackCooldowns[userId] or 0
	if now - lastAttack < ATTACK_COOLDOWN then
		return false, "Attack on cooldown"
	end
	ZoneService._attackCooldowns[userId] = now

	-- Distance check: player must be within 50 studs of the destructible
	local character = player.Character
	if not character then
		return false, "No character"
	end
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return false, "No HumanoidRootPart"
	end
	local playerPos = humanoidRootPart.Position
	local destructiblePos = destructible.position
	local distance = (playerPos - destructiblePos).Magnitude
	if distance > MAX_ATTACK_DISTANCE then
		return false, "Too far from destructible"
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

	-- Only count pets that are assigned to THIS target
	local playerTargets = ZoneService._petTargets[userId] or {}
	local attackingPets = {}
	for _, pet in ipairs(data.pets) do
		if pet.equipped then
			local assignedTarget = playerTargets[pet.id]
			if assignedTarget == destructibleId then
				table.insert(attackingPets, pet)
			end
		end
	end

	if #attackingPets == 0 then
		return false, "No pets assigned to this target"
	end

	-- Calculate total damage from pets attacking this target
	local totalDamage = 0
	for _, pet in ipairs(attackingPets) do
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

		-- Track quest progress: destructible destroyed
		if ZoneService._questService then
			ZoneService._questService.incrementStat(player, "destroyDestructibles", 1)
		end

		-- Track coins earned for quest progress
		if resolvedDrops.Coins and resolvedDrops.Coins > 0 and ZoneService._questService then
			ZoneService._questService.incrementStat(player, "earnCoins", resolvedDrops.Coins)
		end

		-- Fire destroyed event to all clients so everyone sees the destruction
		if remotes then
			local event = remotes:FindFirstChild("DestructibleDestroyed")
			if event then
				event:FireAllClients(destructibleId, resolvedDrops)
			end
		end

		-- Remove model (or part) from workspace
		if destructible.model and destructible.model.Parent then
			destructible.model:Destroy()
		elseif destructible.part and destructible.part.Parent then
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
				-- Gather positions of ALL existing destructibles (all zones) to prevent overlap
				local existingPositions = {}
				for _, d in pairs(ZoneService._destructibles) do
					if d.position then
						table.insert(existingPositions, d.position)
					end
				end
				local newPosition = getRandomPositionInZone(origin, existingPositions)
				ZoneService._spawnSingleDestructible(zoneId, dtype, dDef, newPosition, zoneFolder, true)
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

-- Click-attack a destructible (player tap/click damage, always 1 damage per click)
-- This is separate from pet auto-attack and does not require equipped pets.
function ZoneService.clickAttackDestructible(player, destructibleId)
	if not player or type(destructibleId) ~= "string" then
		return false, "Invalid parameters"
	end

	local destructible = ZoneService._destructibles[destructibleId]
	if not destructible then
		return false, "Destructible not found"
	end

	-- Rate limiting: 0.2 second cooldown between click attacks per player
	local userId = player.UserId
	local now = os.clock()
	local lastClick = ZoneService._clickCooldowns[userId] or 0
	if now - lastClick < CLICK_ATTACK_COOLDOWN then
		return false, "Click attack on cooldown"
	end
	ZoneService._clickCooldowns[userId] = now

	-- Distance check: player must be within 50 studs of the destructible
	local character = player.Character
	if not character then
		return false, "No character"
	end
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return false, "No HumanoidRootPart"
	end
	local playerPos = humanoidRootPart.Position
	local destructiblePos = destructible.position
	local distance = (playerPos - destructiblePos).Magnitude
	if distance > MAX_ATTACK_DISTANCE then
		return false, "Too far from destructible"
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

	-- Player click always deals exactly 1 damage
	local clickDamage = 1

	-- Open a crit window for this player on this destructible (lasts CRIT_WINDOW_DURATION seconds)
	if not ZoneService._critWindows[userId] then
		ZoneService._critWindows[userId] = {}
	end
	ZoneService._critWindows[userId][destructibleId] = os.clock() + CRIT_WINDOW_DURATION

	-- Apply damage
	destructible.hp = destructible.hp - clickDamage

	local remotes = ReplicatedStorage:FindFirstChild("Remotes")

	if destructible.hp <= 0 then
		-- Destructible destroyed
		destructible.hp = 0

		-- Resolve drops
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

		-- Award XP
		local xpReward = destructible.zoneId * 5
		ZoneService._awardXP(player, xpReward)

		-- Track quest progress
		if ZoneService._questService then
			ZoneService._questService.incrementStat(player, "destroyDestructibles", 1)
		end
		if resolvedDrops.Coins and resolvedDrops.Coins > 0 and ZoneService._questService then
			ZoneService._questService.incrementStat(player, "earnCoins", resolvedDrops.Coins)
		end

		-- Fire destroyed event
		if remotes then
			local event = remotes:FindFirstChild("DestructibleDestroyed")
			if event then
				event:FireAllClients(destructibleId, resolvedDrops)
			end
		end

		-- Remove model from workspace
		if destructible.model and destructible.model.Parent then
			destructible.model:Destroy()
		elseif destructible.part and destructible.part.Parent then
			destructible.part:Destroy()
		end

		-- Schedule respawn
		local zoneId = destructible.zoneId
		local dtype = destructible.dtype
		local dDef = ZoneData.Zones[zoneId].destructibles[dtype]

		ZoneService._destructibles[destructibleId] = nil

		task.delay(10, function()
			local zoneFolder = ZoneService._zonesFolder:FindFirstChild("Zone_" .. tostring(zoneId))
			if zoneFolder then
				local origin = getZoneOrigin(zoneId)
				local existingPositions = {}
				for _, d in pairs(ZoneService._destructibles) do
					if d.position then
						table.insert(existingPositions, d.position)
					end
				end
				local newPosition = getRandomPositionInZone(origin, existingPositions)
				ZoneService._spawnSingleDestructible(zoneId, dtype, dDef, newPosition, zoneFolder, true)
			end
		end)
	else
		-- Fire damaged event with click damage
		if remotes then
			local event = remotes:FindFirstChild("DestructibleDamaged")
			if event then
				event:FireAllClients(destructibleId, destructible.hp, destructible.maxHp, clickDamage)
			end
		end
	end

	return true, nil
end

-- Crit-attack a destructible (player clicked a crit circle, deals 2 damage if crit window active)
function ZoneService.critAttackDestructible(player, destructibleId)
	if not player or type(destructibleId) ~= "string" then
		return false, "Invalid parameters"
	end

	local destructible = ZoneService._destructibles[destructibleId]
	if not destructible then
		return false, "Destructible not found"
	end

	-- Rate limiting: 0.2 second cooldown between crit attacks per player
	local userId = player.UserId
	local now = os.clock()
	local lastCrit = ZoneService._critCooldowns[userId] or 0
	if now - lastCrit < CRIT_ATTACK_COOLDOWN then
		return false, "Crit attack on cooldown"
	end
	ZoneService._critCooldowns[userId] = now

	-- Distance check: player must be within 50 studs of the destructible
	local character = player.Character
	if not character then
		return false, "No character"
	end
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return false, "No HumanoidRootPart"
	end
	local playerPos = humanoidRootPart.Position
	local destructiblePos = destructible.position
	local distance = (playerPos - destructiblePos).Magnitude
	if distance > MAX_ATTACK_DISTANCE then
		return false, "Too far from destructible"
	end

	-- Validate crit window is active for this player and destructible
	local playerCritWindows = ZoneService._critWindows[userId]
	if not playerCritWindows then
		return false, "No crit window active"
	end
	local critExpiry = playerCritWindows[destructibleId]
	if not critExpiry or now > critExpiry then
		-- Crit window expired or never existed
		playerCritWindows[destructibleId] = nil
		return false, "Crit window expired"
	end

	-- Consume the crit window immediately (one crit per click - prevents exploit)
	playerCritWindows[destructibleId] = nil

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

	-- Crit deals 2 damage
	local critDamage = 2

	-- Apply damage
	destructible.hp = destructible.hp - critDamage

	local remotes = ReplicatedStorage:FindFirstChild("Remotes")

	if destructible.hp <= 0 then
		-- Destructible destroyed
		destructible.hp = 0

		-- Resolve drops
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

		-- Award XP
		local xpReward = destructible.zoneId * 5
		ZoneService._awardXP(player, xpReward)

		-- Track quest progress
		if ZoneService._questService then
			ZoneService._questService.incrementStat(player, "destroyDestructibles", 1)
		end
		if resolvedDrops.Coins and resolvedDrops.Coins > 0 and ZoneService._questService then
			ZoneService._questService.incrementStat(player, "earnCoins", resolvedDrops.Coins)
		end

		-- Fire destroyed event
		if remotes then
			local event = remotes:FindFirstChild("DestructibleDestroyed")
			if event then
				event:FireAllClients(destructibleId, resolvedDrops)
			end
		end

		-- Remove model from workspace
		if destructible.model and destructible.model.Parent then
			destructible.model:Destroy()
		elseif destructible.part and destructible.part.Parent then
			destructible.part:Destroy()
		end

		-- Clean up crit window for this destructible
		if playerCritWindows then
			playerCritWindows[destructibleId] = nil
		end

		-- Schedule respawn
		local zoneId = destructible.zoneId
		local dtype = destructible.dtype
		local dDef = ZoneData.Zones[zoneId].destructibles[dtype]

		ZoneService._destructibles[destructibleId] = nil

		task.delay(10, function()
			local zoneFolder = ZoneService._zonesFolder:FindFirstChild("Zone_" .. tostring(zoneId))
			if zoneFolder then
				local origin = getZoneOrigin(zoneId)
				local existingPositions = {}
				for _, d in pairs(ZoneService._destructibles) do
					if d.position then
						table.insert(existingPositions, d.position)
					end
				end
				local newPosition = getRandomPositionInZone(origin, existingPositions)
				ZoneService._spawnSingleDestructible(zoneId, dtype, dDef, newPosition, zoneFolder, true)
			end
		end)
	else
		-- Fire damaged event with crit damage
		if remotes then
			local event = remotes:FindFirstChild("DestructibleDamaged")
			if event then
				event:FireAllClients(destructibleId, destructible.hp, destructible.maxHp, critDamage)
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

	-- Apply XP Boost mastery buff if available
	if ZoneService._masteryService then
		local xpBoost = ZoneService._masteryService.getBuffBonus(player, "XPBoost")
		if xpBoost > 0 then
			amount = math.floor(amount * xpBoost)
		end
	end

	data.xp = (data.xp or 0) + amount

	-- Check for level up
	local xpNeeded = (data.level or 1) * 100
	local leveledUp = false
	while data.xp >= xpNeeded do
		data.xp = data.xp - xpNeeded
		data.level = (data.level or 1) + 1
		xpNeeded = data.level * 100
		leveledUp = true
		-- Award mastery point on level-up
		if ZoneService._masteryService then
			ZoneService._masteryService.awardMasteryPoint(player)
		end
	end

	-- Track level-based quests when player levels up
	if leveledUp and ZoneService._questService then
		ZoneService._questService.setStat(player, "reachLevel", data.level)
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

-- Set quest service reference (called after init to avoid circular deps)
function ZoneService.setQuestService(questService)
	ZoneService._questService = questService
end

-- Set mastery service reference
function ZoneService.setMasteryService(masteryService)
	ZoneService._masteryService = masteryService
end

--------------------------------------------------------------------------------
-- WORLD DECORATION: Procedural zone-themed decorations for all 8 zones.
-- These are purely visual (Anchored=true, CanCollide=false) and do not affect gameplay.
-- Each zone spawns 8-12 decorations using getRandomPositionInZone with MIN_SPAWN_DISTANCE.
--------------------------------------------------------------------------------
function ZoneService._spawnWorldDecoration()
	local workspace = game:GetService("Workspace")
	local decoFolder = workspace:FindFirstChild("WorldDecoration")
	if not decoFolder then
		decoFolder = Instance.new("Folder")
		decoFolder.Name = "WorldDecoration"
		decoFolder.Parent = workspace
	end

	-- Zone 1: Gruene Wiesen - green trees, flowers, rocks
	ZoneService._spawnZone1Deco(decoFolder)

	-- Zone 2: Stadt - street lamps, benches, trash cans, bushes
	ZoneService._spawnZone2Deco(decoFolder)

	-- Zone 3: Strand - palm trees, beach umbrellas, shells
	ZoneService._spawnZone3Deco(decoFolder)

	-- Zone 4: Wueste - cacti, dead trees, sand dunes
	ZoneService._spawnZone4Deco(decoFolder)

	-- Zone 5: Eiswelt - ice crystals, frozen trees, snowmen
	ZoneService._spawnZone5Deco(decoFolder)

	-- Zone 6: Vulkan - lava rocks, fire crystals, charred trees
	ZoneService._spawnZone6Deco(decoFolder)

	-- Zone 7: Himmel - clouds, floating islands, rainbows, stars
	ZoneService._spawnZone7Deco(decoFolder)

	-- Zone 8: Weltraum - asteroids, crystals, alien plants
	ZoneService._spawnZone8Deco(decoFolder)
end

-- Helper: get zone origin for decoration spawning (bottom-left corner)
local function getDecoZoneOrigin(zoneId)
	local centerX = (zoneId - 1) * ZONE_SPACING
	local centerZ = -100
	return Vector3.new(centerX - ZONE_SIZE.X / 2, 0, centerZ - ZONE_SIZE.Z / 2)
end

--------------------------------------------------------------------------------
-- ZONE 1: Gruene Wiesen - Green trees (brown trunk + green sphere), flowers, rocks
--------------------------------------------------------------------------------
function ZoneService._spawnZone1Deco(decoFolder)
	local zone1Folder = Instance.new("Folder")
	zone1Folder.Name = "Zone1_Deco"
	zone1Folder.Parent = decoFolder

	local origin = getDecoZoneOrigin(1)
	local existingPositions = {}

	math.randomseed(12345)

	-- Spawn 4 green trees (brown trunk cylinder + green sphere top)
	for i = 1, 4 do
		local pos = getRandomPositionInZone(origin, existingPositions)
		table.insert(existingPositions, pos)

		local trunk = Instance.new("Part")
		trunk.Name = "Tree_Trunk_" .. i
		trunk.Shape = Enum.PartType.Cylinder
		trunk.Size = Vector3.new(7 + math.random() * 2, 1.5, 1.5)
		trunk.Color = Color3.fromRGB(101, 67, 33)
		trunk.Material = Enum.Material.Wood
		trunk.Anchored = true
		trunk.CanCollide = false
		trunk.CFrame = CFrame.new(pos.X, trunk.Size.X / 2, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
		trunk.Parent = zone1Folder

		local canopy = Instance.new("Part")
		canopy.Name = "Tree_Canopy_" .. i
		canopy.Shape = Enum.PartType.Ball
		canopy.Size = Vector3.new(7 + math.random() * 3, 6 + math.random() * 2, 7 + math.random() * 3)
		canopy.Color = Color3.fromRGB(34 + math.random(0, 30), 139 + math.random(0, 40), 34)
		canopy.Material = Enum.Material.Grass
		canopy.Anchored = true
		canopy.CanCollide = false
		canopy.Position = Vector3.new(pos.X, trunk.Size.X + canopy.Size.Y / 2 - 1, pos.Z)
		canopy.Parent = zone1Folder
	end

	-- Spawn 4 flowers (small colorful cylinders)
	local flowerColors = {
		Color3.fromRGB(255, 100, 100),
		Color3.fromRGB(255, 200, 50),
		Color3.fromRGB(200, 100, 255),
		Color3.fromRGB(255, 150, 200),
	}
	for i = 1, 4 do
		local pos = getRandomPositionInZone(origin, existingPositions)
		table.insert(existingPositions, pos)

		local flower = Instance.new("Part")
		flower.Name = "Flower_" .. i
		flower.Shape = Enum.PartType.Cylinder
		flower.Size = Vector3.new(1.5, 1.2, 1.2)
		flower.Color = flowerColors[((i - 1) % #flowerColors) + 1]
		flower.Material = Enum.Material.SmoothPlastic
		flower.Anchored = true
		flower.CanCollide = false
		flower.CFrame = CFrame.new(pos.X, 0.75, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
		flower.Parent = zone1Folder
	end

	-- Spawn 4 rocks (gray boulders)
	for i = 1, 4 do
		local pos = getRandomPositionInZone(origin, existingPositions)
		table.insert(existingPositions, pos)

		local rock = Instance.new("Part")
		rock.Name = "Rock_" .. i
		rock.Shape = Enum.PartType.Ball
		rock.Size = Vector3.new(2 + math.random() * 3, 1.5 + math.random() * 2, 2 + math.random() * 3)
		rock.Color = Color3.fromRGB(120 + math.random(0, 40), 120 + math.random(0, 30), 110 + math.random(0, 30))
		rock.Material = Enum.Material.Slate
		rock.Anchored = true
		rock.CanCollide = false
		rock.Position = Vector3.new(pos.X, rock.Size.Y / 2, pos.Z)
		rock.Parent = zone1Folder
	end

	math.randomseed(os.time())
end

--------------------------------------------------------------------------------
-- ZONE 2: Stadt - Street lamps (gray pole + yellow ball), benches, trash cans, bushes
--------------------------------------------------------------------------------
function ZoneService._spawnZone2Deco(decoFolder)
	local zone2Folder = Instance.new("Folder")
	zone2Folder.Name = "Zone2_Deco"
	zone2Folder.Parent = decoFolder

	local origin = getDecoZoneOrigin(2)
	local existingPositions = {}

	math.randomseed(54321)

	-- Spawn 3 street lamps (tall gray pole + yellow ball on top)
	for i = 1, 3 do
		local pos = getRandomPositionInZone(origin, existingPositions)
		table.insert(existingPositions, pos)

		local pole = Instance.new("Part")
		pole.Name = "Lamp_Pole_" .. i
		pole.Shape = Enum.PartType.Cylinder
		pole.Size = Vector3.new(10, 0.6, 0.6)
		pole.Color = Color3.fromRGB(100, 100, 110)
		pole.Material = Enum.Material.Metal
		pole.Anchored = true
		pole.CanCollide = false
		pole.CFrame = CFrame.new(pos.X, 5, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
		pole.Parent = zone2Folder

		local globe = Instance.new("Part")
		globe.Name = "Lamp_Globe_" .. i
		globe.Shape = Enum.PartType.Ball
		globe.Size = Vector3.new(2, 2, 2)
		globe.Color = Color3.fromRGB(255, 230, 80)
		globe.Material = Enum.Material.Neon
		globe.Anchored = true
		globe.CanCollide = false
		globe.Position = Vector3.new(pos.X, 10.5, pos.Z)
		globe.Parent = zone2Folder

		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 230, 150)
		light.Brightness = 1.5
		light.Range = 20
		light.Parent = globe
	end

	-- Spawn 3 benches (brown planks)
	for i = 1, 3 do
		local pos = getRandomPositionInZone(origin, existingPositions)
		table.insert(existingPositions, pos)

		local seat = Instance.new("Part")
		seat.Name = "Bench_Seat_" .. i
		seat.Shape = Enum.PartType.Block
		seat.Size = Vector3.new(5, 0.4, 2)
		seat.Color = Color3.fromRGB(139, 90, 43)
		seat.Material = Enum.Material.Wood
		seat.Anchored = true
		seat.CanCollide = false
		seat.Position = Vector3.new(pos.X, 1.2, pos.Z)
		seat.Parent = zone2Folder

		local back = Instance.new("Part")
		back.Name = "Bench_Back_" .. i
		back.Shape = Enum.PartType.Block
		back.Size = Vector3.new(5, 1.5, 0.3)
		back.Color = Color3.fromRGB(120, 75, 35)
		back.Material = Enum.Material.Wood
		back.Anchored = true
		back.CanCollide = false
		back.Position = Vector3.new(pos.X, 2.0, pos.Z - 0.85)
		back.Parent = zone2Folder
	end

	-- Spawn 3 trash cans (gray cylinders)
	for i = 1, 3 do
		local pos = getRandomPositionInZone(origin, existingPositions)
		table.insert(existingPositions, pos)

		local can = Instance.new("Part")
		can.Name = "TrashCan_" .. i
		can.Shape = Enum.PartType.Cylinder
		can.Size = Vector3.new(3, 2, 2)
		can.Color = Color3.fromRGB(80, 80, 85)
		can.Material = Enum.Material.Metal
		can.Anchored = true
		can.CanCollide = false
		can.CFrame = CFrame.new(pos.X, 1.5, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
		can.Parent = zone2Folder
	end

	-- Spawn 3 bushes (dark green spheres)
	for i = 1, 3 do
		local pos = getRandomPositionInZone(origin, existingPositions)
		table.insert(existingPositions, pos)

		local bush = Instance.new("Part")
		bush.Name = "Bush_" .. i
		bush.Shape = Enum.PartType.Ball
		bush.Size = Vector3.new(3 + math.random() * 2, 2.5 + math.random(), 3 + math.random() * 2)
		bush.Color = Color3.fromRGB(20, 80, 20)
		bush.Material = Enum.Material.Grass
		bush.Anchored = true
		bush.CanCollide = false
		bush.Position = Vector3.new(pos.X, bush.Size.Y / 2, pos.Z)
		bush.Parent = zone2Folder
	end

	math.randomseed(os.time())
end

--------------------------------------------------------------------------------
-- ZONE 3: Strand - Palm trees (tan trunk + green flat top), beach umbrellas, shells
--------------------------------------------------------------------------------
function ZoneService._spawnZone3Deco(decoFolder)
	local zone3Folder = Instance.new("Folder")
	zone3Folder.Name = "Zone3_Deco"
	zone3Folder.Parent = decoFolder

	local origin = getDecoZoneOrigin(3)
	local existingPositions = {}

	math.randomseed(33333)

	-- Spawn 4 palm trees (tan trunk + green flat sphere top)
	for i = 1, 4 do
		local pos = getRandomPositionInZone(origin, existingPositions)
		table.insert(existingPositions, pos)

		local trunk = Instance.new("Part")
		trunk.Name = "Palm_Trunk_" .. i
		trunk.Shape = Enum.PartType.Cylinder
		trunk.Size = Vector3.new(9 + math.random() * 2, 1.2, 1.2)
		trunk.Color = Color3.fromRGB(194, 154, 90)
		trunk.Material = Enum.Material.Wood
		trunk.Anchored = true
		trunk.CanCollide = false
		trunk.CFrame = CFrame.new(pos.X, trunk.Size.X / 2, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
		trunk.Parent = zone3Folder

		-- Flat green top (wider than tall)
		local top = Instance.new("Part")
		top.Name = "Palm_Top_" .. i
		top.Shape = Enum.PartType.Ball
		top.Size = Vector3.new(6 + math.random() * 2, 3, 6 + math.random() * 2)
		top.Color = Color3.fromRGB(34, 139, 34)
		top.Material = Enum.Material.Grass
		top.Anchored = true
		top.CanCollide = false
		top.Position = Vector3.new(pos.X, trunk.Size.X + 1, pos.Z)
		top.Parent = zone3Folder
	end

	-- Spawn 4 beach umbrellas (thin pole + colored wedge top)
	local umbrellaColors = {
		Color3.fromRGB(255, 80, 80),
		Color3.fromRGB(80, 150, 255),
		Color3.fromRGB(255, 200, 50),
		Color3.fromRGB(255, 130, 200),
	}
	for i = 1, 4 do
		local pos = getRandomPositionInZone(origin, existingPositions)
		table.insert(existingPositions, pos)

		local pole = Instance.new("Part")
		pole.Name = "Umbrella_Pole_" .. i
		pole.Shape = Enum.PartType.Cylinder
		pole.Size = Vector3.new(5, 0.3, 0.3)
		pole.Color = Color3.fromRGB(200, 200, 200)
		pole.Material = Enum.Material.Metal
		pole.Anchored = true
		pole.CanCollide = false
		pole.CFrame = CFrame.new(pos.X, 2.5, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
		pole.Parent = zone3Folder

		local canopy = Instance.new("Part")
		canopy.Name = "Umbrella_Top_" .. i
		canopy.Shape = Enum.PartType.Block
		canopy.Size = Vector3.new(4, 0.5, 4)
		canopy.Color = umbrellaColors[((i - 1) % #umbrellaColors) + 1]
		canopy.Material = Enum.Material.Fabric
		canopy.Anchored = true
		canopy.CanCollide = false
		canopy.CFrame = CFrame.new(pos.X, 5.2, pos.Z) * CFrame.Angles(0, 0, math.rad(5))
		canopy.Parent = zone3Folder
	end

	-- Spawn 4 shells (small pink/white balls)
	for i = 1, 4 do
		local pos = getRandomPositionInZone(origin, existingPositions)
		table.insert(existingPositions, pos)

		local shell = Instance.new("Part")
		shell.Name = "Shell_" .. i
		shell.Shape = Enum.PartType.Ball
		shell.Size = Vector3.new(0.8 + math.random() * 0.5, 0.6, 0.8 + math.random() * 0.5)
		if i % 2 == 0 then
			shell.Color = Color3.fromRGB(255, 200, 200) -- pink
		else
			shell.Color = Color3.fromRGB(245, 240, 235) -- white
		end
		shell.Material = Enum.Material.SmoothPlastic
		shell.Anchored = true
		shell.CanCollide = false
		shell.Position = Vector3.new(pos.X, 0.3, pos.Z)
		shell.Parent = zone3Folder
	end

	math.randomseed(os.time())
end

--------------------------------------------------------------------------------
-- ZONE 4: Wueste - Cacti (green cylinders with arms), dead trees, sand dunes
--------------------------------------------------------------------------------
function ZoneService._spawnZone4Deco(decoFolder)
	local zone4Folder = Instance.new("Folder")
	zone4Folder.Name = "Zone4_Deco"
	zone4Folder.Parent = decoFolder

	local origin = getDecoZoneOrigin(4)
	local existingPositions = {}

	math.randomseed(44444)

	-- Spawn 4 cacti (green cylinder body + arm cylinder)
	for i = 1, 4 do
		local pos = getRandomPositionInZone(origin, existingPositions)
		table.insert(existingPositions, pos)

		-- Main body
		local body = Instance.new("Part")
		body.Name = "Cactus_Body_" .. i
		body.Shape = Enum.PartType.Cylinder
		body.Size = Vector3.new(5 + math.random() * 2, 1.5, 1.5)
		body.Color = Color3.fromRGB(34, 120, 34)
		body.Material = Enum.Material.SmoothPlastic
		body.Anchored = true
		body.CanCollide = false
		body.CFrame = CFrame.new(pos.X, body.Size.X / 2, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
		body.Parent = zone4Folder

		-- Arm (smaller cylinder sticking out to the side)
		local arm = Instance.new("Part")
		arm.Name = "Cactus_Arm_" .. i
		arm.Shape = Enum.PartType.Cylinder
		arm.Size = Vector3.new(2.5, 0.8, 0.8)
		arm.Color = Color3.fromRGB(34, 120, 34)
		arm.Material = Enum.Material.SmoothPlastic
		arm.Anchored = true
		arm.CanCollide = false
		arm.CFrame = CFrame.new(pos.X + 1.2, body.Size.X * 0.6, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
		arm.Parent = zone4Folder
	end

	-- Spawn 4 dead trees (brown thin cylinders)
	for i = 1, 4 do
		local pos = getRandomPositionInZone(origin, existingPositions)
		table.insert(existingPositions, pos)

		local deadTree = Instance.new("Part")
		deadTree.Name = "DeadTree_" .. i
		deadTree.Shape = Enum.PartType.Cylinder
		deadTree.Size = Vector3.new(6 + math.random() * 2, 0.8, 0.8)
		deadTree.Color = Color3.fromRGB(101, 67, 33)
		deadTree.Material = Enum.Material.Wood
		deadTree.Anchored = true
		deadTree.CanCollide = false
		deadTree.CFrame = CFrame.new(pos.X, deadTree.Size.X / 2, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
		deadTree.Parent = zone4Folder

		-- A thin branch sticking out
		local branch = Instance.new("Part")
		branch.Name = "DeadTree_Branch_" .. i
		branch.Shape = Enum.PartType.Cylinder
		branch.Size = Vector3.new(2, 0.4, 0.4)
		branch.Color = Color3.fromRGB(80, 50, 25)
		branch.Material = Enum.Material.Wood
		branch.Anchored = true
		branch.CanCollide = false
		branch.CFrame = CFrame.new(pos.X + 1, deadTree.Size.X * 0.7, pos.Z) * CFrame.Angles(0, 0, math.rad(45))
		branch.Parent = zone4Folder
	end

	-- Spawn 4 sand dunes (tan wedge-like parts)
	for i = 1, 4 do
		local pos = getRandomPositionInZone(origin, existingPositions)
		table.insert(existingPositions, pos)

		local dune = Instance.new("Part")
		dune.Name = "SandDune_" .. i
		dune.Shape = Enum.PartType.Block
		dune.Size = Vector3.new(8 + math.random() * 4, 2 + math.random(), 6 + math.random() * 3)
		dune.Color = Color3.fromRGB(210, 180, 120)
		dune.Material = Enum.Material.Sand
		dune.Anchored = true
		dune.CanCollide = false
		dune.CFrame = CFrame.new(pos.X, dune.Size.Y / 2 - 0.5, pos.Z) * CFrame.Angles(0, math.rad(math.random(0, 180)), math.rad(8))
		dune.Parent = zone4Folder
	end

	math.randomseed(os.time())
end

--------------------------------------------------------------------------------
-- ZONE 5: Eiswelt - Ice crystals (cyan/blue wedges), frozen trees, snowmen
--------------------------------------------------------------------------------
function ZoneService._spawnZone5Deco(decoFolder)
	local zone5Folder = Instance.new("Folder")
	zone5Folder.Name = "Zone5_Deco"
	zone5Folder.Parent = decoFolder

	local origin = getDecoZoneOrigin(5)
	local existingPositions = {}

	math.randomseed(55555)

	-- Spawn 4 ice crystals (cyan/blue wedge-shaped parts)
	local crystalColors = {
		Color3.fromRGB(100, 220, 255),
		Color3.fromRGB(150, 240, 255),
		Color3.fromRGB(80, 180, 240),
		Color3.fromRGB(120, 200, 255),
	}
	for i = 1, 4 do
		local pos = getRandomPositionInZone(origin, existingPositions)
		table.insert(existingPositions, pos)

		local crystal = Instance.new("Part")
		crystal.Name = "IceCrystal_" .. i
		crystal.Shape = Enum.PartType.Block
		crystal.Size = Vector3.new(1.5 + math.random(), 4 + math.random() * 3, 1.5 + math.random())
		crystal.Color = crystalColors[((i - 1) % #crystalColors) + 1]
		crystal.Material = Enum.Material.Ice
		crystal.Transparency = 0.2
		crystal.Anchored = true
		crystal.CanCollide = false
		crystal.CFrame = CFrame.new(pos.X, crystal.Size.Y / 2, pos.Z) * CFrame.Angles(0, math.rad(math.random(0, 90)), math.rad(math.random(-15, 15)))
		crystal.Parent = zone5Folder
	end

	-- Spawn 4 frozen trees (white trunk + light blue sphere top)
	for i = 1, 4 do
		local pos = getRandomPositionInZone(origin, existingPositions)
		table.insert(existingPositions, pos)

		local trunk = Instance.new("Part")
		trunk.Name = "FrozenTree_Trunk_" .. i
		trunk.Shape = Enum.PartType.Cylinder
		trunk.Size = Vector3.new(6 + math.random() * 2, 1.2, 1.2)
		trunk.Color = Color3.fromRGB(220, 220, 230)
		trunk.Material = Enum.Material.Ice
		trunk.Anchored = true
		trunk.CanCollide = false
		trunk.CFrame = CFrame.new(pos.X, trunk.Size.X / 2, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
		trunk.Parent = zone5Folder

		local canopy = Instance.new("Part")
		canopy.Name = "FrozenTree_Top_" .. i
		canopy.Shape = Enum.PartType.Ball
		canopy.Size = Vector3.new(5 + math.random() * 2, 4 + math.random(), 5 + math.random() * 2)
		canopy.Color = Color3.fromRGB(180, 220, 255)
		canopy.Material = Enum.Material.Ice
		canopy.Transparency = 0.1
		canopy.Anchored = true
		canopy.CanCollide = false
		canopy.Position = Vector3.new(pos.X, trunk.Size.X + canopy.Size.Y / 2 - 1, pos.Z)
		canopy.Parent = zone5Folder
	end

	-- Spawn 4 snowmen (3 stacked white balls)
	for i = 1, 4 do
		local pos = getRandomPositionInZone(origin, existingPositions)
		table.insert(existingPositions, pos)

		-- Bottom ball (largest)
		local bottom = Instance.new("Part")
		bottom.Name = "Snowman_Bottom_" .. i
		bottom.Shape = Enum.PartType.Ball
		bottom.Size = Vector3.new(3, 3, 3)
		bottom.Color = Color3.fromRGB(245, 245, 250)
		bottom.Material = Enum.Material.SmoothPlastic
		bottom.Anchored = true
		bottom.CanCollide = false
		bottom.Position = Vector3.new(pos.X, 1.5, pos.Z)
		bottom.Parent = zone5Folder

		-- Middle ball
		local middle = Instance.new("Part")
		middle.Name = "Snowman_Middle_" .. i
		middle.Shape = Enum.PartType.Ball
		middle.Size = Vector3.new(2.2, 2.2, 2.2)
		middle.Color = Color3.fromRGB(245, 245, 250)
		middle.Material = Enum.Material.SmoothPlastic
		middle.Anchored = true
		middle.CanCollide = false
		middle.Position = Vector3.new(pos.X, 3.6, pos.Z)
		middle.Parent = zone5Folder

		-- Head ball (smallest)
		local head = Instance.new("Part")
		head.Name = "Snowman_Head_" .. i
		head.Shape = Enum.PartType.Ball
		head.Size = Vector3.new(1.5, 1.5, 1.5)
		head.Color = Color3.fromRGB(245, 245, 250)
		head.Material = Enum.Material.SmoothPlastic
		head.Anchored = true
		head.CanCollide = false
		head.Position = Vector3.new(pos.X, 5.2, pos.Z)
		head.Parent = zone5Folder
	end

	math.randomseed(os.time())
end

--------------------------------------------------------------------------------
-- ZONE 6: Vulkan - Lava rocks (dark red/black boulders), fire crystals, charred trees
--------------------------------------------------------------------------------
function ZoneService._spawnZone6Deco(decoFolder)
	local zone6Folder = Instance.new("Folder")
	zone6Folder.Name = "Zone6_Deco"
	zone6Folder.Parent = decoFolder

	local origin = getDecoZoneOrigin(6)
	local existingPositions = {}

	math.randomseed(66666)

	-- Spawn 4 lava rocks (dark red/black boulders)
	for i = 1, 4 do
		local pos = getRandomPositionInZone(origin, existingPositions)
		table.insert(existingPositions, pos)

		local rock = Instance.new("Part")
		rock.Name = "LavaRock_" .. i
		rock.Shape = Enum.PartType.Ball
		rock.Size = Vector3.new(3 + math.random() * 2, 2.5 + math.random() * 2, 3 + math.random() * 2)
		if i % 2 == 0 then
			rock.Color = Color3.fromRGB(40, 20, 20) -- black
		else
			rock.Color = Color3.fromRGB(120, 30, 20) -- dark red
		end
		rock.Material = Enum.Material.Basalt
		rock.Anchored = true
		rock.CanCollide = false
		rock.Position = Vector3.new(pos.X, rock.Size.Y / 2, pos.Z)
		rock.Parent = zone6Folder
	end

	-- Spawn 4 fire crystals (orange neon wedge-like blocks)
	for i = 1, 4 do
		local pos = getRandomPositionInZone(origin, existingPositions)
		table.insert(existingPositions, pos)

		local crystal = Instance.new("Part")
		crystal.Name = "FireCrystal_" .. i
		crystal.Shape = Enum.PartType.Block
		crystal.Size = Vector3.new(1.2 + math.random(), 3 + math.random() * 3, 1.2 + math.random())
		crystal.Color = Color3.fromRGB(255, 120 + math.random(0, 60), 0)
		crystal.Material = Enum.Material.Neon
		crystal.Anchored = true
		crystal.CanCollide = false
		crystal.CFrame = CFrame.new(pos.X, crystal.Size.Y / 2, pos.Z) * CFrame.Angles(0, math.rad(math.random(0, 180)), math.rad(math.random(-10, 10)))
		crystal.Parent = zone6Folder
	end

	-- Spawn 4 charred trees (black thin cylinders)
	for i = 1, 4 do
		local pos = getRandomPositionInZone(origin, existingPositions)
		table.insert(existingPositions, pos)

		local tree = Instance.new("Part")
		tree.Name = "CharredTree_" .. i
		tree.Shape = Enum.PartType.Cylinder
		tree.Size = Vector3.new(5 + math.random() * 3, 0.7, 0.7)
		tree.Color = Color3.fromRGB(20, 20, 20)
		tree.Material = Enum.Material.Slate
		tree.Anchored = true
		tree.CanCollide = false
		tree.CFrame = CFrame.new(pos.X, tree.Size.X / 2, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
		tree.Parent = zone6Folder
	end

	math.randomseed(os.time())
end

--------------------------------------------------------------------------------
-- ZONE 7: Himmel - Clouds (white flat spheres), floating islands, rainbows, stars
--------------------------------------------------------------------------------
function ZoneService._spawnZone7Deco(decoFolder)
	local zone7Folder = Instance.new("Folder")
	zone7Folder.Name = "Zone7_Deco"
	zone7Folder.Parent = decoFolder

	local origin = getDecoZoneOrigin(7)
	local existingPositions = {}

	math.randomseed(77777)

	-- Spawn 3 clouds (white flat spheres floating above ground)
	for i = 1, 3 do
		local pos = getRandomPositionInZone(origin, existingPositions)
		table.insert(existingPositions, pos)

		local cloud = Instance.new("Part")
		cloud.Name = "Cloud_" .. i
		cloud.Shape = Enum.PartType.Ball
		cloud.Size = Vector3.new(8 + math.random() * 4, 3 + math.random(), 6 + math.random() * 3)
		cloud.Color = Color3.fromRGB(245, 245, 255)
		cloud.Material = Enum.Material.SmoothPlastic
		cloud.Transparency = 0.3
		cloud.Anchored = true
		cloud.CanCollide = false
		cloud.Position = Vector3.new(pos.X, 8 + math.random() * 5, pos.Z)
		cloud.Parent = zone7Folder
	end

	-- Spawn 3 floating islands (small parts elevated in the air)
	for i = 1, 3 do
		local pos = getRandomPositionInZone(origin, existingPositions)
		table.insert(existingPositions, pos)

		local island = Instance.new("Part")
		island.Name = "FloatingIsland_" .. i
		island.Shape = Enum.PartType.Block
		island.Size = Vector3.new(5 + math.random() * 3, 2, 5 + math.random() * 3)
		island.Color = Color3.fromRGB(100, 200, 100)
		island.Material = Enum.Material.Grass
		island.Anchored = true
		island.CanCollide = false
		island.Position = Vector3.new(pos.X, 6 + math.random() * 4, pos.Z)
		island.Parent = zone7Folder
	end

	-- Spawn 3 rainbows (arched neon parts)
	for i = 1, 3 do
		local pos = getRandomPositionInZone(origin, existingPositions)
		table.insert(existingPositions, pos)

		local rainbow = Instance.new("Part")
		rainbow.Name = "Rainbow_" .. i
		rainbow.Shape = Enum.PartType.Block
		rainbow.Size = Vector3.new(12, 1, 1)
		rainbow.Color = Color3.fromRGB(255, 100 + math.random(0, 155), math.random(0, 255))
		rainbow.Material = Enum.Material.Neon
		rainbow.Transparency = 0.3
		rainbow.Anchored = true
		rainbow.CanCollide = false
		rainbow.CFrame = CFrame.new(pos.X, 10, pos.Z) * CFrame.Angles(0, math.rad(math.random(0, 180)), math.rad(30))
		rainbow.Parent = zone7Folder
	end

	-- Spawn 3 stars (yellow neon balls)
	for i = 1, 3 do
		local pos = getRandomPositionInZone(origin, existingPositions)
		table.insert(existingPositions, pos)

		local star = Instance.new("Part")
		star.Name = "Star_" .. i
		star.Shape = Enum.PartType.Ball
		star.Size = Vector3.new(1.5 + math.random(), 1.5 + math.random(), 1.5 + math.random())
		star.Color = Color3.fromRGB(255, 255, 50)
		star.Material = Enum.Material.Neon
		star.Anchored = true
		star.CanCollide = false
		star.Position = Vector3.new(pos.X, 12 + math.random() * 5, pos.Z)
		star.Parent = zone7Folder
	end

	math.randomseed(os.time())
end

--------------------------------------------------------------------------------
-- ZONE 8: Weltraum - Asteroids (dark gray boulders), crystals (purple neon), alien plants
--------------------------------------------------------------------------------
function ZoneService._spawnZone8Deco(decoFolder)
	local zone8Folder = Instance.new("Folder")
	zone8Folder.Name = "Zone8_Deco"
	zone8Folder.Parent = decoFolder

	local origin = getDecoZoneOrigin(8)
	local existingPositions = {}

	math.randomseed(88888)

	-- Spawn 4 asteroids (dark gray boulders)
	for i = 1, 4 do
		local pos = getRandomPositionInZone(origin, existingPositions)
		table.insert(existingPositions, pos)

		local asteroid = Instance.new("Part")
		asteroid.Name = "Asteroid_" .. i
		asteroid.Shape = Enum.PartType.Ball
		asteroid.Size = Vector3.new(3 + math.random() * 3, 2.5 + math.random() * 2, 3 + math.random() * 3)
		asteroid.Color = Color3.fromRGB(50 + math.random(0, 30), 50 + math.random(0, 30), 55 + math.random(0, 30))
		asteroid.Material = Enum.Material.Slate
		asteroid.Anchored = true
		asteroid.CanCollide = false
		asteroid.Position = Vector3.new(pos.X, asteroid.Size.Y / 2 + math.random() * 3, pos.Z)
		asteroid.Parent = zone8Folder
	end

	-- Spawn 4 crystals (purple neon wedge-like blocks)
	for i = 1, 4 do
		local pos = getRandomPositionInZone(origin, existingPositions)
		table.insert(existingPositions, pos)

		local crystal = Instance.new("Part")
		crystal.Name = "SpaceCrystal_" .. i
		crystal.Shape = Enum.PartType.Block
		crystal.Size = Vector3.new(1.2 + math.random(), 4 + math.random() * 3, 1.2 + math.random())
		crystal.Color = Color3.fromRGB(150 + math.random(0, 50), 50, 220 + math.random(0, 35))
		crystal.Material = Enum.Material.Neon
		crystal.Anchored = true
		crystal.CanCollide = false
		crystal.CFrame = CFrame.new(pos.X, crystal.Size.Y / 2, pos.Z) * CFrame.Angles(0, math.rad(math.random(0, 180)), math.rad(math.random(-15, 15)))
		crystal.Parent = zone8Folder
	end

	-- Spawn 4 alien plants (green neon cylinders)
	for i = 1, 4 do
		local pos = getRandomPositionInZone(origin, existingPositions)
		table.insert(existingPositions, pos)

		local plant = Instance.new("Part")
		plant.Name = "AlienPlant_" .. i
		plant.Shape = Enum.PartType.Cylinder
		plant.Size = Vector3.new(3 + math.random() * 2, 1 + math.random(), 1 + math.random())
		plant.Color = Color3.fromRGB(50, 255, 80 + math.random(0, 80))
		plant.Material = Enum.Material.Neon
		plant.Anchored = true
		plant.CanCollide = false
		plant.CFrame = CFrame.new(pos.X, plant.Size.X / 2, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
		plant.Parent = zone8Folder
	end

	math.randomseed(os.time())
end

--------------------------------------------------------------------------------
-- ZONE WALLS: Colorful cartoon building skylines along zone edges.
-- Instead of invisible barriers, tall candy-colored buildings line the N, S,
-- and one outer edge of each zone (like Pet Simulator 1 style city skylines).
-- Between adjacent zones (shared east/west edges) there are NO buildings
-- because that is where the gates connect the zones.
--
-- Zone color palettes:
--   Zone 1: pastels
--   Zone 2: city grays
--   Zone 3: beach tans/corals
--   Zone 4: desert oranges
--   Zone 5: ice blues/whites
--   Zone 6: dark reds
--   Zone 7: whites/golds
--   Zone 8: dark purples/neons
--------------------------------------------------------------------------------

-- Color palettes per zone for building walls
local ZONE_WALL_PALETTES = {
	[1] = { -- Pastels
		Color3.fromRGB(255, 182, 193), -- pink
		Color3.fromRGB(200, 170, 255), -- lavender
		Color3.fromRGB(173, 216, 230), -- light blue
		Color3.fromRGB(180, 255, 180), -- light green
		Color3.fromRGB(255, 255, 180), -- light yellow
		Color3.fromRGB(255, 200, 150), -- peach
		Color3.fromRGB(200, 255, 255), -- light cyan
		Color3.fromRGB(255, 180, 255), -- light magenta
		Color3.fromRGB(200, 255, 200), -- light lime
	},
	[2] = { -- City grays
		Color3.fromRGB(140, 140, 150),
		Color3.fromRGB(100, 110, 120),
		Color3.fromRGB(160, 160, 170),
		Color3.fromRGB(120, 120, 130),
		Color3.fromRGB(180, 180, 190),
		Color3.fromRGB(90, 95, 105),
		Color3.fromRGB(150, 155, 160),
		Color3.fromRGB(110, 115, 125),
		Color3.fromRGB(170, 170, 180),
	},
	[3] = { -- Beach tans/corals
		Color3.fromRGB(237, 201, 136), -- sandy
		Color3.fromRGB(255, 127, 80),  -- coral
		Color3.fromRGB(210, 180, 140), -- tan
		Color3.fromRGB(244, 164, 96),  -- sandy brown
		Color3.fromRGB(255, 160, 122), -- light salmon
		Color3.fromRGB(222, 184, 135), -- burlywood
		Color3.fromRGB(255, 200, 150), -- light coral
		Color3.fromRGB(240, 220, 170), -- pale sand
		Color3.fromRGB(255, 140, 105), -- deep coral
	},
	[4] = { -- Desert oranges
		Color3.fromRGB(210, 140, 50),
		Color3.fromRGB(230, 160, 60),
		Color3.fromRGB(190, 120, 40),
		Color3.fromRGB(240, 180, 80),
		Color3.fromRGB(200, 130, 30),
		Color3.fromRGB(220, 150, 50),
		Color3.fromRGB(180, 110, 20),
		Color3.fromRGB(250, 190, 90),
		Color3.fromRGB(170, 100, 30),
	},
	[5] = { -- Ice blues/whites
		Color3.fromRGB(200, 230, 255),
		Color3.fromRGB(220, 240, 255),
		Color3.fromRGB(180, 220, 250),
		Color3.fromRGB(240, 250, 255),
		Color3.fromRGB(160, 210, 245),
		Color3.fromRGB(230, 245, 255),
		Color3.fromRGB(190, 225, 250),
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(210, 235, 255),
	},
	[6] = { -- Dark reds
		Color3.fromRGB(140, 30, 20),
		Color3.fromRGB(160, 40, 30),
		Color3.fromRGB(120, 20, 15),
		Color3.fromRGB(180, 50, 35),
		Color3.fromRGB(100, 15, 10),
		Color3.fromRGB(150, 35, 25),
		Color3.fromRGB(170, 45, 30),
		Color3.fromRGB(130, 25, 18),
		Color3.fromRGB(190, 55, 40),
	},
	[7] = { -- Whites/golds
		Color3.fromRGB(255, 255, 240),
		Color3.fromRGB(255, 215, 0),
		Color3.fromRGB(250, 250, 230),
		Color3.fromRGB(255, 223, 100),
		Color3.fromRGB(245, 245, 220),
		Color3.fromRGB(255, 200, 50),
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(240, 230, 200),
		Color3.fromRGB(255, 210, 70),
	},
	[8] = { -- Dark purples/neons
		Color3.fromRGB(80, 20, 150),
		Color3.fromRGB(150, 0, 255),
		Color3.fromRGB(60, 10, 120),
		Color3.fromRGB(200, 50, 255),
		Color3.fromRGB(100, 30, 180),
		Color3.fromRGB(170, 20, 230),
		Color3.fromRGB(50, 0, 100),
		Color3.fromRGB(130, 10, 200),
		Color3.fromRGB(220, 80, 255),
	},
}

function ZoneService._spawnZoneWalls()
	local workspace = game:GetService("Workspace")
	local wallsFolder = workspace:FindFirstChild("ZoneWalls")
	if not wallsFolder then
		wallsFolder = Instance.new("Folder")
		wallsFolder.Name = "ZoneWalls"
		wallsFolder.Parent = workspace
	end

	-- Also spawn lobby barriers (these remain invisible since lobby doesn't need buildings)
	local lobbyHalfW = LOBBY_SIZE / 2
	local lobbyHalfD = LOBBY_SIZE / 2
	local BARRIER_HEIGHT = 40
	local BARRIER_THICKNESS = 4

	-- Lobby North wall (invisible)
	local lobbyWallN = Instance.new("Part")
	lobbyWallN.Name = "Barrier_Lobby_N"
	lobbyWallN.Size = Vector3.new(LOBBY_SIZE + BARRIER_THICKNESS, BARRIER_HEIGHT, BARRIER_THICKNESS)
	lobbyWallN.Position = Vector3.new(LOBBY_CENTER_X, BARRIER_HEIGHT / 2, LOBBY_CENTER_Z + lobbyHalfD + BARRIER_THICKNESS / 2)
	lobbyWallN.Anchored = true
	lobbyWallN.CanCollide = true
	lobbyWallN.Transparency = 1
	lobbyWallN.Parent = wallsFolder

	-- Lobby South wall (invisible)
	local lobbyWallS = Instance.new("Part")
	lobbyWallS.Name = "Barrier_Lobby_S"
	lobbyWallS.Size = Vector3.new(LOBBY_SIZE + BARRIER_THICKNESS, BARRIER_HEIGHT, BARRIER_THICKNESS)
	lobbyWallS.Position = Vector3.new(LOBBY_CENTER_X, BARRIER_HEIGHT / 2, LOBBY_CENTER_Z - lobbyHalfD - BARRIER_THICKNESS / 2)
	lobbyWallS.Anchored = true
	lobbyWallS.CanCollide = true
	lobbyWallS.Transparency = 1
	lobbyWallS.Parent = wallsFolder

	-- Lobby West wall (invisible)
	local lobbyWallW = Instance.new("Part")
	lobbyWallW.Name = "Barrier_Lobby_W"
	lobbyWallW.Size = Vector3.new(BARRIER_THICKNESS, BARRIER_HEIGHT, LOBBY_SIZE + BARRIER_THICKNESS)
	lobbyWallW.Position = Vector3.new(LOBBY_CENTER_X - lobbyHalfW - BARRIER_THICKNESS / 2, BARRIER_HEIGHT / 2, LOBBY_CENTER_Z)
	lobbyWallW.Anchored = true
	lobbyWallW.CanCollide = true
	lobbyWallW.Transparency = 1
	lobbyWallW.Parent = wallsFolder

	-- Spawn building walls for all 8 zones
	for zoneId = 1, 8 do
		ZoneService._spawnZoneWallsForZone(zoneId, wallsFolder)
	end
end

-- Spawn colorful building walls for a single zone along N, S, and one outer edge.
-- The east edge (positive X) between adjacent zones is left open for gates,
-- except for zone 8 which has buildings on its east edge (end of the map).
-- The west edge (negative X) is also open for gates except for zone 1 (start of map, connects to lobby).
function ZoneService._spawnZoneWallsForZone(zoneId, wallsFolder)
	local zoneFolder = Instance.new("Folder")
	zoneFolder.Name = "ZoneWall_" .. tostring(zoneId)
	zoneFolder.Parent = wallsFolder

	local centerX = (zoneId - 1) * ZONE_SPACING
	local centerZ = -100
	local halfW = ZONE_SIZE.X / 2  -- 100
	local halfD = ZONE_SIZE.Z / 2  -- 100

	local palette = ZONE_WALL_PALETTES[zoneId] or ZONE_WALL_PALETTES[1]

	-- Seed random for deterministic building placement per zone
	math.randomseed(7000 + zoneId * 100)

	-- Building spacing: every 12-15 studs along edges
	local BUILDING_SPACING = 13

	-- North edge (Z = centerZ + halfD = Z=0): buildings along the full width
	local northZ = centerZ + halfD
	local northStartX = centerX - halfW
	local northEndX = centerX + halfW
	local buildingCount = 0

	local x = northStartX + 5
	while x < northEndX - 5 do
		local height = 20 + math.random() * 20  -- 20-40
		local width = 8 + math.random() * 7     -- 8-15
		local depth = 4 + math.random() * 2     -- 4-6
		local color = palette[math.random(1, #palette)]

		local building = Instance.new("Part")
		building.Name = "Building_N_" .. buildingCount
		building.Shape = Enum.PartType.Block
		building.Size = Vector3.new(width, height, depth)
		building.Position = Vector3.new(x, height / 2, northZ + depth / 2)
		building.Anchored = true
		building.CanCollide = true
		building.Color = color
		building.Material = Enum.Material.SmoothPlastic
		building.Parent = zoneFolder

		-- Add white window squares on the front face (facing into the zone, negative Z)
		ZoneService._addBuildingWindows(building, height, width, depth, "south", zoneFolder, buildingCount, "N")

		buildingCount = buildingCount + 1
		x = x + width + (12 + math.random() * 3 - width)
		if x < x then break end -- safety
		-- Ensure we advance at least BUILDING_SPACING
		local nextX = northStartX + 5 + buildingCount * BUILDING_SPACING
		if x < nextX then x = nextX end
	end

	-- South edge (Z = centerZ - halfD = Z=-200): buildings along the full width
	local southZ = centerZ - halfD
	local southStartX = centerX - halfW
	local southEndX = centerX + halfW
	buildingCount = 0

	x = southStartX + 5
	while x < southEndX - 5 do
		local height = 20 + math.random() * 20
		local width = 8 + math.random() * 7
		local depth = 4 + math.random() * 2
		local color = palette[math.random(1, #palette)]

		local building = Instance.new("Part")
		building.Name = "Building_S_" .. buildingCount
		building.Shape = Enum.PartType.Block
		building.Size = Vector3.new(width, height, depth)
		building.Position = Vector3.new(x, height / 2, southZ - depth / 2)
		building.Anchored = true
		building.CanCollide = true
		building.Color = color
		building.Material = Enum.Material.SmoothPlastic
		building.Parent = zoneFolder

		-- Add white window squares on the front face (facing into the zone, positive Z)
		ZoneService._addBuildingWindows(building, height, width, depth, "north", zoneFolder, buildingCount, "S")

		buildingCount = buildingCount + 1
		local nextX = southStartX + 5 + buildingCount * BUILDING_SPACING
		if x + BUILDING_SPACING > nextX then
			x = x + BUILDING_SPACING
		else
			x = nextX
		end
	end

	-- Outer side edge: zone 1 gets west wall, zone 8 gets east wall
	-- All other zones share edges with adjacent zones so no building walls there
	if zoneId == 1 then
		-- West edge (X = centerX - halfW): buildings along full depth (lobby path area excluded)
		local westX = centerX - halfW
		local wallStartZ = centerZ - halfD
		local wallEndZ = centerZ + halfD
		buildingCount = 0

		local z = wallStartZ + 5
		while z < wallEndZ - 5 do
			local height = 20 + math.random() * 20
			local width = 8 + math.random() * 7
			local depth = 4 + math.random() * 2
			local color = palette[math.random(1, #palette)]

			-- Skip the area where the lobby path connects (around Z=-100, +/-10)
			if z > (LOBBY_CENTER_Z - 12) and z < (LOBBY_CENTER_Z + 12) then
				z = LOBBY_CENTER_Z + 12
				if z >= wallEndZ - 5 then break end
			end

			local building = Instance.new("Part")
			building.Name = "Building_W_" .. buildingCount
			building.Shape = Enum.PartType.Block
			building.Size = Vector3.new(depth, height, width)
			building.Position = Vector3.new(westX - depth / 2, height / 2, z)
			building.Anchored = true
			building.CanCollide = true
			building.Color = color
			building.Material = Enum.Material.SmoothPlastic
			building.Parent = zoneFolder

			-- Add windows on the front face (facing into the zone, positive X)
			ZoneService._addBuildingWindows(building, height, width, depth, "east", zoneFolder, buildingCount, "W")

			buildingCount = buildingCount + 1
			local nextZ = wallStartZ + 5 + buildingCount * BUILDING_SPACING
			if z + BUILDING_SPACING > nextZ then
				z = z + BUILDING_SPACING
			else
				z = nextZ
			end
		end
	end

	if zoneId == 8 then
		-- East edge (X = centerX + halfW): buildings along full depth
		local eastX = centerX + halfW
		local wallStartZ = centerZ - halfD
		local wallEndZ = centerZ + halfD
		buildingCount = 0

		local z = wallStartZ + 5
		while z < wallEndZ - 5 do
			local height = 20 + math.random() * 20
			local width = 8 + math.random() * 7
			local depth = 4 + math.random() * 2
			local color = palette[math.random(1, #palette)]

			local building = Instance.new("Part")
			building.Name = "Building_E_" .. buildingCount
			building.Shape = Enum.PartType.Block
			building.Size = Vector3.new(depth, height, width)
			building.Position = Vector3.new(eastX + depth / 2, height / 2, z)
			building.Anchored = true
			building.CanCollide = true
			building.Color = color
			building.Material = Enum.Material.SmoothPlastic
			building.Parent = zoneFolder

			-- Add windows on the front face (facing into the zone, negative X)
			ZoneService._addBuildingWindows(building, height, width, depth, "west", zoneFolder, buildingCount, "E")

			buildingCount = buildingCount + 1
			local nextZ = wallStartZ + 5 + buildingCount * BUILDING_SPACING
			if z + BUILDING_SPACING > nextZ then
				z = z + BUILDING_SPACING
			else
				z = nextZ
			end
		end
	end

	-- Reset random seed
	math.randomseed(os.time())
end

-- Add white window squares to a building face.
-- direction: "north" (front facing +Z), "south" (-Z), "east" (+X), "west" (-X)
function ZoneService._addBuildingWindows(building, height, width, depth, direction, parent, buildingIdx, edge)
	-- Only add windows to ~60% of buildings (randomized)
	if math.random() > 0.6 then return end

	-- Determine how many windows (2-4 rows, 1-2 columns)
	local rows = math.random(2, 4)
	local cols = math.random(1, 2)
	local windowSize = 2

	for row = 1, rows do
		for col = 1, cols do
			local window = Instance.new("Part")
			window.Name = "Window_" .. edge .. buildingIdx .. "_" .. row .. "_" .. col
			window.Shape = Enum.PartType.Block
			window.Color = Color3.fromRGB(255, 255, 255)
			window.Material = Enum.Material.SmoothPlastic
			window.Anchored = true
			window.CanCollide = false

			-- Calculate window position offset relative to building center
			local yOffset = -height / 2 + row * (height / (rows + 1))
			local colOffset = (col - (cols + 1) / 2) * (windowSize + 1.5)

			if direction == "south" then
				-- Front face is -Z
				window.Size = Vector3.new(windowSize, windowSize, 0.3)
				window.Position = Vector3.new(
					building.Position.X + colOffset,
					building.Position.Y + yOffset,
					building.Position.Z - depth / 2 - 0.15
				)
			elseif direction == "north" then
				-- Front face is +Z
				window.Size = Vector3.new(windowSize, windowSize, 0.3)
				window.Position = Vector3.new(
					building.Position.X + colOffset,
					building.Position.Y + yOffset,
					building.Position.Z + depth / 2 + 0.15
				)
			elseif direction == "east" then
				-- Front face is +X
				window.Size = Vector3.new(0.3, windowSize, windowSize)
				window.Position = Vector3.new(
					building.Position.X + depth / 2 + 0.15,
					building.Position.Y + yOffset,
					building.Position.Z + colOffset
				)
			elseif direction == "west" then
				-- Front face is -X
				window.Size = Vector3.new(0.3, windowSize, windowSize)
				window.Position = Vector3.new(
					building.Position.X - depth / 2 - 0.15,
					building.Position.Y + yOffset,
					building.Position.Z + colOffset
				)
			end

			window.Parent = parent
		end
	end
end

return ZoneService
