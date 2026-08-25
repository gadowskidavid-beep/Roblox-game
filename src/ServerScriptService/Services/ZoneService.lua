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

	-- Spawn invisible barriers at zone edges to prevent falling off
	ZoneService._spawnBarriers()
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

		-- BARRIER (semi-transparent wall in the gate opening, reddish when locked)
		local barrier = Instance.new("Part")
		barrier.Name = "GateBarrier_" .. tostring(gateZone)
		barrier.Size = Vector3.new(BARRIER_THICKNESS, PILLAR_HEIGHT, GATE_OPENING_WIDTH)
		barrier.Position = Vector3.new(gateX, PILLAR_HEIGHT / 2, gateZ)
		barrier.Anchored = true
		barrier.CanCollide = true
		barrier.Color = Color3.fromRGB(255, 60, 60)
		barrier.Material = Enum.Material.ForceField
		barrier.Transparency = 0.5
		barrier.Parent = gateModel

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
		barrier.Touched:Connect(function(hit)
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
				-- Remove only the barrier (pillars and arch stay)
				barrier.CanCollide = false
				barrier.Transparency = 1
				return
			end

			-- Try to unlock the zone
			local success, err = ZoneService.unlockZone(player, gateZone)
			if success then
				-- Remove the barrier (make invisible and non-collidable)
				local barrierPosition = barrier.Position
				barrier.CanCollide = false
				barrier.Transparency = 1

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

	-- Consume the crit window (one crit per window per circle click is fine,
	-- but we keep the window open so multiple circles can crit within the window)

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
-- WORLD DECORATION: Procedural trees, rocks, flowers (Zone 1), lamps, benches (Zone 2)
-- These are purely visual (CanCollide = false) and do not affect gameplay.
--------------------------------------------------------------------------------
function ZoneService._spawnWorldDecoration()
	local workspace = game:GetService("Workspace")
	local decoFolder = workspace:FindFirstChild("WorldDecoration")
	if not decoFolder then
		decoFolder = Instance.new("Folder")
		decoFolder.Name = "WorldDecoration"
		decoFolder.Parent = workspace
	end

	-- Zone 1: Gruene Wiesen - trees, rocks, flowers
	ZoneService._spawnZone1Deco(decoFolder)

	-- Zone 2: Stadt - street lamps, benches, planters
	ZoneService._spawnZone2Deco(decoFolder)
end

function ZoneService._spawnZone1Deco(decoFolder)
	local zone1Folder = Instance.new("Folder")
	zone1Folder.Name = "Zone1_Deco"
	zone1Folder.Parent = decoFolder

	local origin = Vector3.new(-100, 0, -200) -- Zone 1 extends from -100..100 X, -200..0 Z
	local zoneWidth = 200
	local zoneDepth = 200

	-- Seed random for consistent decoration
	math.randomseed(12345)

	-- Spawn 12 trees (trunk cylinder + canopy sphere)
	for i = 1, 12 do
		local tx = origin.X + 15 + math.random() * (zoneWidth - 30)
		local tz = origin.Z + 15 + math.random() * (zoneDepth - 30)

		-- Trunk
		local trunk = Instance.new("Part")
		trunk.Name = "Tree_Trunk_" .. i
		trunk.Shape = Enum.PartType.Cylinder
		trunk.Size = Vector3.new(6 + math.random() * 3, 1.5, 1.5)
		trunk.Color = Color3.fromRGB(101, 67, 33)
		trunk.Material = Enum.Material.Wood
		trunk.Anchored = true
		trunk.CanCollide = false
		trunk.CFrame = CFrame.new(tx, trunk.Size.X / 2, tz) * CFrame.Angles(0, 0, math.rad(90))
		trunk.Parent = zone1Folder

		-- Canopy
		local canopy = Instance.new("Part")
		canopy.Name = "Tree_Canopy_" .. i
		canopy.Shape = Enum.PartType.Ball
		canopy.Size = Vector3.new(7 + math.random() * 4, 6 + math.random() * 3, 7 + math.random() * 4)
		canopy.Color = Color3.fromRGB(34 + math.random(0, 30), 139 + math.random(0, 40), 34)
		canopy.Material = Enum.Material.Grass
		canopy.Anchored = true
		canopy.CanCollide = false
		canopy.Position = Vector3.new(tx, trunk.Size.X + canopy.Size.Y / 2 - 1, tz)
		canopy.Parent = zone1Folder
	end

	-- Spawn 8 rocks (slightly squished spheres)
	for i = 1, 8 do
		local rx = origin.X + 10 + math.random() * (zoneWidth - 20)
		local rz = origin.Z + 10 + math.random() * (zoneDepth - 20)

		local rock = Instance.new("Part")
		rock.Name = "Rock_" .. i
		rock.Shape = Enum.PartType.Ball
		rock.Size = Vector3.new(2 + math.random() * 3, 1.5 + math.random() * 2, 2 + math.random() * 3)
		rock.Color = Color3.fromRGB(120 + math.random(0, 40), 120 + math.random(0, 30), 110 + math.random(0, 30))
		rock.Material = Enum.Material.Slate
		rock.Anchored = true
		rock.CanCollide = false
		rock.Position = Vector3.new(rx, rock.Size.Y / 2, rz)
		rock.Parent = zone1Folder
	end

	-- Reset random seed
	math.randomseed(os.time())
end

function ZoneService._spawnZone2Deco(decoFolder)
	local zone2Folder = Instance.new("Folder")
	zone2Folder.Name = "Zone2_Deco"
	zone2Folder.Parent = decoFolder

	local originX = 150 -- Zone 2 extends from 150..350 X, -200..0 Z
	local originZ = -200
	local zoneWidth = 200
	local zoneDepth = 200

	math.randomseed(54321)

	-- Spawn 10 street lamps (tall pole + light sphere on top)
	for i = 1, 10 do
		local lx = originX + 20 + (i - 1) * (zoneWidth / 10)
		local lz = originZ + 30 + math.random() * (zoneDepth - 60)

		-- Pole (tall thin cylinder)
		local pole = Instance.new("Part")
		pole.Name = "Lamp_Pole_" .. i
		pole.Shape = Enum.PartType.Cylinder
		pole.Size = Vector3.new(10, 0.6, 0.6)
		pole.Color = Color3.fromRGB(60, 60, 70)
		pole.Material = Enum.Material.Metal
		pole.Anchored = true
		pole.CanCollide = false
		pole.CFrame = CFrame.new(lx, 5, lz) * CFrame.Angles(0, 0, math.rad(90))
		pole.Parent = zone2Folder

		-- Light globe (sphere with PointLight)
		local globe = Instance.new("Part")
		globe.Name = "Lamp_Globe_" .. i
		globe.Shape = Enum.PartType.Ball
		globe.Size = Vector3.new(2, 2, 2)
		globe.Color = Color3.fromRGB(255, 240, 180)
		globe.Material = Enum.Material.Neon
		globe.Anchored = true
		globe.CanCollide = false
		globe.Position = Vector3.new(lx, 10.5, lz)
		globe.Parent = zone2Folder

		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 230, 150)
		light.Brightness = 1.5
		light.Range = 20
		light.Parent = globe
	end

	-- Spawn 8 benches (flat rectangular box with shorter legs)
	for i = 1, 8 do
		local bx = originX + 20 + math.random() * (zoneWidth - 40)
		local bz = originZ + 20 + math.random() * (zoneDepth - 40)

		-- Seat surface
		local seat = Instance.new("Part")
		seat.Name = "Bench_Seat_" .. i
		seat.Shape = Enum.PartType.Block
		seat.Size = Vector3.new(5, 0.4, 2)
		seat.Color = Color3.fromRGB(139, 90, 43)
		seat.Material = Enum.Material.Wood
		seat.Anchored = true
		seat.CanCollide = false
		seat.Position = Vector3.new(bx, 1.2, bz)
		seat.Parent = zone2Folder

		-- Back rest
		local back = Instance.new("Part")
		back.Name = "Bench_Back_" .. i
		back.Shape = Enum.PartType.Block
		back.Size = Vector3.new(5, 1.5, 0.3)
		back.Color = Color3.fromRGB(120, 75, 35)
		back.Material = Enum.Material.Wood
		back.Anchored = true
		back.CanCollide = false
		back.Position = Vector3.new(bx, 2.0, bz - 0.85)
		back.Parent = zone2Folder

		-- Leg 1
		local leg1 = Instance.new("Part")
		leg1.Name = "Bench_Leg1_" .. i
		leg1.Shape = Enum.PartType.Block
		leg1.Size = Vector3.new(0.3, 1.2, 0.3)
		leg1.Color = Color3.fromRGB(60, 60, 70)
		leg1.Material = Enum.Material.Metal
		leg1.Anchored = true
		leg1.CanCollide = false
		leg1.Position = Vector3.new(bx - 2, 0.6, bz)
		leg1.Parent = zone2Folder

		-- Leg 2
		local leg2 = Instance.new("Part")
		leg2.Name = "Bench_Leg2_" .. i
		leg2.Shape = Enum.PartType.Block
		leg2.Size = Vector3.new(0.3, 1.2, 0.3)
		leg2.Color = Color3.fromRGB(60, 60, 70)
		leg2.Material = Enum.Material.Metal
		leg2.Anchored = true
		leg2.CanCollide = false
		leg2.Position = Vector3.new(bx + 2, 0.6, bz)
		leg2.Parent = zone2Folder
	end

	-- Spawn 6 small planters (colorful flower boxes for city color)
	for i = 1, 6 do
		local px = originX + 25 + math.random() * (zoneWidth - 50)
		local pz = originZ + 25 + math.random() * (zoneDepth - 50)

		local planter = Instance.new("Part")
		planter.Name = "Planter_" .. i
		planter.Shape = Enum.PartType.Block
		planter.Size = Vector3.new(3, 1.5, 3)
		planter.Color = Color3.fromRGB(80, 80, 90)
		planter.Material = Enum.Material.Concrete
		planter.Anchored = true
		planter.CanCollide = false
		planter.Position = Vector3.new(px, 0.75, pz)
		planter.Parent = zone2Folder

		-- Flowers on top
		local flowers = Instance.new("Part")
		flowers.Name = "PlanterFlowers_" .. i
		flowers.Shape = Enum.PartType.Ball
		flowers.Size = Vector3.new(2.5, 1.5, 2.5)
		flowers.Color = Color3.fromRGB(200 + math.random(0, 55), 80 + math.random(0, 100), 100 + math.random(0, 100))
		flowers.Material = Enum.Material.Grass
		flowers.Anchored = true
		flowers.CanCollide = false
		flowers.Position = Vector3.new(px, 2.0, pz)
		flowers.Parent = zone2Folder
	end

	math.randomseed(os.time())
end

--------------------------------------------------------------------------------
-- BARRIERS: Invisible walls at zone edges to prevent falling off
-- Each zone gets 4 walls around its perimeter (tall, invisible, collidable).
--------------------------------------------------------------------------------
function ZoneService._spawnBarriers()
	local workspace = game:GetService("Workspace")
	local barrierFolder = workspace:FindFirstChild("Barriers")
	if not barrierFolder then
		barrierFolder = Instance.new("Folder")
		barrierFolder.Name = "Barriers"
		barrierFolder.Parent = workspace
	end

	local BARRIER_HEIGHT = 40
	local BARRIER_THICKNESS = 4

	-- Spawn barriers for all 8 zones
	for zoneId = 1, 8 do
		local centerX = (zoneId - 1) * ZONE_SPACING
		local centerZ = -100
		local halfW = ZONE_SIZE.X / 2
		local halfD = ZONE_SIZE.Z / 2

		-- North wall (positive Z edge)
		local wallN = Instance.new("Part")
		wallN.Name = "Barrier_Z" .. zoneId .. "_N"
		wallN.Size = Vector3.new(ZONE_SIZE.X + BARRIER_THICKNESS, BARRIER_HEIGHT, BARRIER_THICKNESS)
		wallN.Position = Vector3.new(centerX, BARRIER_HEIGHT / 2, centerZ + halfD + BARRIER_THICKNESS / 2)
		wallN.Anchored = true
		wallN.CanCollide = true
		wallN.Transparency = 1
		wallN.Parent = barrierFolder

		-- South wall (negative Z edge)
		local wallS = Instance.new("Part")
		wallS.Name = "Barrier_Z" .. zoneId .. "_S"
		wallS.Size = Vector3.new(ZONE_SIZE.X + BARRIER_THICKNESS, BARRIER_HEIGHT, BARRIER_THICKNESS)
		wallS.Position = Vector3.new(centerX, BARRIER_HEIGHT / 2, centerZ - halfD - BARRIER_THICKNESS / 2)
		wallS.Anchored = true
		wallS.CanCollide = true
		wallS.Transparency = 1
		wallS.Parent = barrierFolder

		-- West wall (negative X edge) - only for zone 1
		if zoneId == 1 then
			local wallW = Instance.new("Part")
			wallW.Name = "Barrier_Z" .. zoneId .. "_W"
			wallW.Size = Vector3.new(BARRIER_THICKNESS, BARRIER_HEIGHT, ZONE_SIZE.Z + BARRIER_THICKNESS)
			wallW.Position = Vector3.new(centerX - halfW - BARRIER_THICKNESS / 2, BARRIER_HEIGHT / 2, centerZ)
			wallW.Anchored = true
			wallW.CanCollide = true
			wallW.Transparency = 1
			wallW.Parent = barrierFolder
		end

		-- East wall (positive X edge) - only for zone 2 (last zone)
		if zoneId == 2 then
			local wallE = Instance.new("Part")
			wallE.Name = "Barrier_Z" .. zoneId .. "_E"
			wallE.Size = Vector3.new(BARRIER_THICKNESS, BARRIER_HEIGHT, ZONE_SIZE.Z + BARRIER_THICKNESS)
			wallE.Position = Vector3.new(centerX + halfW + BARRIER_THICKNESS / 2, BARRIER_HEIGHT / 2, centerZ)
			wallE.Anchored = true
			wallE.CanCollide = true
			wallE.Transparency = 1
			wallE.Parent = barrierFolder
		end
	end
end

return ZoneService
