local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local ArenaService = {}
ArenaService.__index = ArenaService

local ARENA_CENTER = Vector3.new(0, 30, 220)

local function makePart(parent, name, size, cframe, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function addMarker(parent, name, position, tag)
	local marker = makePart(parent, name, Vector3.new(2, 1, 2), CFrame.new(position), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	marker.Transparency = 1
	marker.CanCollide = false
	marker.CanTouch = false
	marker.CanQuery = false
	CollectionService:AddTag(marker, tag)
	return marker
end

function ArenaService.new()
	local self = setmetatable({}, ArenaService)
	self._runtime = nil
	self._arena = nil
	self._lobbySpawn = nil
	self._playerSpawns = {}
	self._echoSpawns = {}
	self._enemySpawns = {}
	self._stableParts = {}
	self._fracturedParts = {}
	self._anchor = nil
	self._prompt = nil
	self._orbFolder = nil
	self._enemyFolder = nil
	return self
end

function ArenaService:_tryCustomLobby(runtime)
	local template = ServerStorage:FindFirstChild("CustomLobby")
	if not template then
		return false
	end

	local clone = template:Clone()
	if not clone then
		warn("[SHIFT//BREAK] CustomLobby ist nicht klonbar. Aktiviere Archivable; die prozedurale Lobby wird verwendet.")
		return false
	end
	clone.Name = "Lobby"
	clone.Parent = runtime
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("BasePart") and CollectionService:HasTag(descendant, Config.Tags.LobbySpawn) then
			self._lobbySpawn = descendant
			print("[SHIFT//BREAK] CustomLobby geladen.")
			return true
		end
	end

	warn("[SHIFT//BREAK] CustomLobby fehlt der Tag SB_LobbySpawn; die prozedurale Lobby wird verwendet.")
	clone:Destroy()
	return false
end

function ArenaService:_createRuntime()
	local previous = Workspace:FindFirstChild("ShiftBreakRuntime")
	if previous then
		previous:Destroy()
	end

	local runtime = Instance.new("Folder")
	runtime.Name = "ShiftBreakRuntime"
	runtime.Parent = Workspace
	self._runtime = runtime

	if self:_tryCustomLobby(runtime) then
		return
	end

	local lobby = Instance.new("Folder")
	lobby.Name = "Lobby"
	lobby.Parent = runtime

	local floor = makePart(lobby, "LobbyFloor", Vector3.new(90, 2, 90), CFrame.new(0, 15, 0), Config.Colors.Panel, Enum.Material.Slate)
	floor:SetAttribute("ReplaceWithYourLobbyModel", true)

	local rim = makePart(lobby, "PortalRing", Vector3.new(18, 1, 18), CFrame.new(0, 16.2, -22), Config.Colors.Stable, Enum.Material.Neon)
	rim.Shape = Enum.PartType.Cylinder
	rim.Orientation = Vector3.new(0, 0, 90)
	rim.CanCollide = false

	local spawnPlatform = Workspace:FindFirstChild("SpawnPlatform")
	if spawnPlatform and not spawnPlatform:IsA("BasePart") then
		spawnPlatform = nil
	end
	if not spawnPlatform then
		spawnPlatform = makePart(
			lobby,
			"SpawnPlatform",
			Vector3.new(30, 2, 30),
			CFrame.new(0, 17, 8),
			Color3.fromRGB(72, 82, 112),
			Enum.Material.SmoothPlastic
		)
	end
	spawnPlatform.Anchored = true
	spawnPlatform.CanCollide = true
	spawnPlatform.CanTouch = true
	spawnPlatform.CanQuery = true
	spawnPlatform:SetAttribute("PermanentSpawnPlatform", true)

	local spawn = Workspace:FindFirstChild("LobbySpawn")
	if spawn and not spawn:IsA("SpawnLocation") then
		spawn = nil
	end
	if not spawn then
		spawn = Instance.new("SpawnLocation")
		spawn.Name = "LobbySpawn"
		spawn.Parent = lobby
	end
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = spawnPlatform.CFrame + Vector3.new(0, 1.5, 0)
	spawn.Color = Config.Colors.Stable
	spawn.Material = Enum.Material.Neon
	spawn.Transparency = 0.2
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.CanTouch = true
	spawn.CanQuery = true
	spawn.Neutral = true
	spawn.AllowTeamChangeOnTouch = false
	spawn.Duration = 0
	self._lobbySpawn = spawn
end

function ArenaService:_resetArenaReferences()
	self._playerSpawns = {}
	self._echoSpawns = {}
	self._enemySpawns = {}
	self._stableParts = {}
	self._fracturedParts = {}
	self._anchor = nil
	self._prompt = nil
end

function ArenaService:_rememberPhasePart(part, phase)
	if part:GetAttribute("SBOriginalTransparency") == nil then
		part:SetAttribute("SBOriginalTransparency", part.Transparency)
		part:SetAttribute("SBOriginalCanCollide", part.CanCollide)
		part:SetAttribute("SBOriginalCanTouch", part.CanTouch)
	end

	if phase == "STABLE" then
		table.insert(self._stableParts, part)
	else
		table.insert(self._fracturedParts, part)
	end
end

function ArenaService:_indexTaggedArena(arena)
	for _, descendant in arena:GetDescendants() do
		if descendant:IsA("BasePart") then
			if CollectionService:HasTag(descendant, Config.Tags.PlayerSpawn) then
				table.insert(self._playerSpawns, descendant)
			end
			if CollectionService:HasTag(descendant, Config.Tags.EchoSpawn) then
				table.insert(self._echoSpawns, descendant)
			end
			if CollectionService:HasTag(descendant, Config.Tags.EnemySpawn) then
				table.insert(self._enemySpawns, descendant)
			end
			if CollectionService:HasTag(descendant, Config.Tags.DepositAnchor) then
				self._anchor = descendant
			end
			if CollectionService:HasTag(descendant, Config.Tags.StableOnly) then
				self:_rememberPhasePart(descendant, "STABLE")
			end
			if CollectionService:HasTag(descendant, Config.Tags.FracturedOnly) then
				self:_rememberPhasePart(descendant, "FRACTURED")
			end
		end
	end

	return #self._playerSpawns > 0 and #self._echoSpawns > 0 and #self._enemySpawns > 0 and self._anchor ~= nil
end

function ArenaService:_makeBridge(parent, destination, phase)
	local origin = ARENA_CENTER + Vector3.new(0, 1, 0)
	local target = destination + Vector3.new(0, 1, 0)
	local distance = (target - origin).Magnitude
	local midpoint = origin:Lerp(target, 0.5)
	local color = phase == "STABLE" and Config.Colors.Stable or Config.Colors.Fractured
	local bridge = makePart(parent, phase .. "Bridge", Vector3.new(10, 1.5, math.max(8, distance - 25)), CFrame.lookAt(midpoint, target), color, Enum.Material.Neon)
	bridge.Transparency = 0.12
	CollectionService:AddTag(bridge, phase == "STABLE" and Config.Tags.StableOnly or Config.Tags.FracturedOnly)
end

function ArenaService:_buildProceduralArena()
	local arena = Instance.new("Model")
	arena.Name = "Arena"
	arena.Parent = self._runtime
	self._arena = arena

	local geometry = Instance.new("Folder")
	geometry.Name = "Geometry"
	geometry.Parent = arena

	local centerPlatform = makePart(geometry, "AnchorIsland", Vector3.new(34, 2, 34), CFrame.new(ARENA_CENTER), Color3.fromRGB(28, 33, 54), Enum.Material.Slate)
	centerPlatform:SetAttribute("ReplaceWithYourModel", true)

	local positions = {
		ARENA_CENTER + Vector3.new(0, 0, -54),
		ARENA_CENTER + Vector3.new(54, 0, 0),
		ARENA_CENTER + Vector3.new(0, 0, 54),
		ARENA_CENTER + Vector3.new(-54, 0, 0),
		ARENA_CENTER + Vector3.new(45, 0, -45),
		ARENA_CENTER + Vector3.new(45, 0, 45),
		ARENA_CENTER + Vector3.new(-45, 0, 45),
		ARENA_CENTER + Vector3.new(-45, 0, -45),
	}

	for index, position in positions do
		local island = makePart(geometry, "EchoIsland" .. index, Vector3.new(28, 2, 28), CFrame.new(position), Color3.fromRGB(22, 27, 47), Enum.Material.Slate)
		island:SetAttribute("ReplaceWithYourModel", true)

		local phase = index <= 4 and "STABLE" or "FRACTURED"
		self:_makeBridge(geometry, position, phase)

		addMarker(arena, "PlayerSpawn" .. index, position + Vector3.new(0, 4, 0), Config.Tags.PlayerSpawn)
		addMarker(arena, "EnemySpawn" .. index, position + Vector3.new(0, 4, 0), Config.Tags.EnemySpawn)
		for echoIndex = 1, 4 do
			local angle = (math.pi * 2 / 4) * echoIndex + index * 0.31
			local offset = Vector3.new(math.cos(angle) * 8, 3, math.sin(angle) * 8)
			addMarker(arena, string.format("EchoSpawn%d_%d", index, echoIndex), position + offset, Config.Tags.EchoSpawn)
		end
	end

	addMarker(arena, "CenterPlayerSpawn", ARENA_CENTER + Vector3.new(0, 4, 10), Config.Tags.PlayerSpawn)
	for index = 1, 6 do
		local angle = math.pi * 2 * index / 6
		addMarker(arena, "CenterEchoSpawn" .. index, ARENA_CENTER + Vector3.new(math.cos(angle) * 10, 3, math.sin(angle) * 10), Config.Tags.EchoSpawn)
	end

	local anchor = makePart(arena, "DepositAnchor", Vector3.new(9, 9, 9), CFrame.new(ARENA_CENTER + Vector3.new(0, 5.5, 0)), Config.Colors.Echo, Enum.Material.Neon)
	anchor.Shape = Enum.PartType.Ball
	anchor.CanCollide = false
	CollectionService:AddTag(anchor, Config.Tags.DepositAnchor)
	self._anchor = anchor

	local light = Instance.new("PointLight")
	light.Name = "AnchorGlow"
	light.Color = Config.Colors.Echo
	light.Brightness = 3
	light.Range = 28
	light.Parent = anchor
end

function ArenaService:_tryCustomArena()
	local template = ServerStorage:FindFirstChild("CustomArena")
	if not template then
		return false
	end

	local clone = template:Clone()
	if not clone then
		warn("[SHIFT//BREAK] CustomArena ist nicht klonbar. Aktiviere Archivable; die prozedurale Arena wird verwendet.")
		return false
	end
	clone.Name = "Arena"
	clone.Parent = self._runtime
	self._arena = clone

	if self:_indexTaggedArena(clone) then
		print("[SHIFT//BREAK] CustomArena geladen.")
		return true
	end

	warn("[SHIFT//BREAK] CustomArena fehlen notwendige Tags; die prozedurale Arena wird verwendet.")
	clone:Destroy()
	self._arena = nil
	self:_resetArenaReferences()
	return false
end

function ArenaService:_createRuntimeFolders()
	self._orbFolder = Instance.new("Folder")
	self._orbFolder.Name = "Echoes"
	self._orbFolder.Parent = self._arena

	self._enemyFolder = Instance.new("Folder")
	self._enemyFolder.Name = "Shades"
	self._enemyFolder.Parent = self._arena
end

function ArenaService:_createPrompt()
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DepositPrompt"
	prompt.ActionText = "Echos übertragen"
	prompt.ObjectText = "RISS-ANKER"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.35
	prompt.MaxActivationDistance = 13
	prompt.RequiresLineOfSight = false
	prompt.Parent = self._anchor
	self._prompt = prompt
end

function ArenaService:BuildArena()
	if self._arena then
		self._arena:Destroy()
	end
	self:_resetArenaReferences()

	if not self:_tryCustomArena() then
		self:_buildProceduralArena()
	end

	if #self._playerSpawns == 0 then
		self:_indexTaggedArena(self._arena)
	end
	self:_createRuntimeFolders()
	self:_createPrompt()
	self:SetPhase("STABLE")
end

function ArenaService:Start()
	self:_createRuntime()
	self:BuildArena()
end

function ArenaService:SetPhase(phase)
	local function apply(parts, active)
		for _, part in parts do
			if part.Parent then
				local originalTransparency = part:GetAttribute("SBOriginalTransparency") or 0
				part.Transparency = active and originalTransparency or math.max(originalTransparency, 0.86)
				part.CanCollide = active and (part:GetAttribute("SBOriginalCanCollide") ~= false) or false
				part.CanTouch = active and (part:GetAttribute("SBOriginalCanTouch") ~= false) or false
			end
		end
	end

	apply(self._stableParts, phase == "STABLE")
	apply(self._fracturedParts, phase == "FRACTURED")
	if self._anchor then
		self._anchor.Color = phase == "STABLE" and Config.Colors.Echo or Config.Colors.Fractured
	end
end

function ArenaService:SetDepositEnabled(enabled)
	if self._prompt then
		self._prompt.Enabled = enabled
	end
end

function ArenaService:GetDepositPrompt()
	return self._prompt
end

function ArenaService:GetAnchor()
	return self._anchor
end

function ArenaService:GetOrbFolder()
	return self._orbFolder
end

function ArenaService:GetEnemyFolder()
	return self._enemyFolder
end

function ArenaService:GetRandomEchoPosition()
	if #self._echoSpawns == 0 then
		return ARENA_CENTER + Vector3.new(0, 4, 0)
	end
	return self._echoSpawns[math.random(1, #self._echoSpawns)].Position
end

function ArenaService:GetRandomEnemyPosition()
	if #self._enemySpawns == 0 then
		return ARENA_CENTER + Vector3.new(30, 4, 0)
	end
	return self._enemySpawns[math.random(1, #self._enemySpawns)].Position
end

function ArenaService:TeleportToArena(character, index)
	if not character or not character.Parent then
		return
	end
	local spawnPart = self._playerSpawns[((index or 1) - 1) % math.max(1, #self._playerSpawns) + 1]
	local position = spawnPart and spawnPart.Position or ARENA_CENTER + Vector3.new(0, 5, 0)
	character:PivotTo(CFrame.new(position + Vector3.new(0, 3, 0)))
end

function ArenaService:TeleportToLobby(character)
	if character and character.Parent and self._lobbySpawn then
		character:PivotTo(self._lobbySpawn.CFrame + Vector3.new(0, 4, 0))
	end
end

function ArenaService:GetKillHeight()
	if self._anchor then
		return self._anchor.Position.Y - 60
	end
	return -30
end

return ArenaService
