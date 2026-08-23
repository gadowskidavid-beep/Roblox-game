local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local GameService = {}
GameService.__index = GameService

local function makeRemote(parent, className, name)
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = parent
	return remote
end

function GameService.new(dataService, arenaService, enemyService)
	local self = setmetatable({}, GameService)
	self._data = dataService
	self._arena = arenaService
	self._enemies = enemyService
	self._status = "Waiting"
	self._phase = "STABLE"
	self._timeRemaining = 0
	self._shiftRemaining = 0
	self._wave = 0
	self._banked = 0
	self._target = 0
	self._orbCount = 0
	self._sprinting = {}
	self._fullMessageAt = {}
	self._promptConnection = nil
	self._heartbeatConnection = nil
	self._started = false
	self:_createRemotes()
	return self
end

function GameService:_createRemotes()
	local previous = ReplicatedStorage:FindFirstChild("ShiftBreakRemotes")
	if previous then
		previous:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "ShiftBreakRemotes"
	folder.Parent = ReplicatedStorage

	self._stateRemote = makeRemote(folder, "RemoteEvent", "GameState")
	self._messageRemote = makeRemote(folder, "RemoteEvent", "PlayerMessage")
	self._actionRemote = makeRemote(folder, "RemoteEvent", "Action")
	self._purchaseRemote = makeRemote(folder, "RemoteFunction", "PurchaseUpgrade")
end

function GameService:_activePlayerCount()
	local count = 0
	for _, player in Players:GetPlayers() do
		if self._data:IsLoaded(player) then
			count += 1
		end
	end
	return count
end

function GameService:_allPlayersReady()
	for _, player in Players:GetPlayers() do
		if not self._data:IsLoaded(player) then
			return false
		end
	end
	return true
end

function GameService:_snapshot()
	return {
		gameName = Config.GameName,
		status = self._status,
		phase = self._phase,
		timeRemaining = math.max(0, math.ceil(self._timeRemaining)),
		shiftRemaining = math.max(0, math.ceil(self._shiftRemaining)),
		wave = self._wave,
		maxWaves = Config.Round.Waves,
		banked = self._banked,
		target = self._target,
		playerCount = #Players:GetPlayers(),
		minimumPlayers = Config.MinimumPlayers,
	}
end

function GameService:_broadcast(targetPlayer)
	local snapshot = self:_snapshot()
	if targetPlayer then
		self._stateRemote:FireClient(targetPlayer, snapshot)
	else
		self._stateRemote:FireAllClients(snapshot)
	end
end

function GameService:_message(player, text, tone)
	self._messageRemote:FireClient(player, text, tone or "Info")
end

function GameService:_messageAll(text, tone)
	self._messageRemote:FireAllClients(text, tone or "Info")
end

function GameService:_setStatus(status)
	self._status = status
	self:_broadcast()
end

function GameService:_walkSpeed(player)
	return Config.Player.BaseWalkSpeed + self._data:GetUpgradeBonus(player, "Speed")
end

function GameService:_pulseCooldown(player)
	return math.max(2, Config.Player.PulseCooldown - self._data:GetUpgradeBonus(player, "Pulse"))
end

function GameService:_setupCharacter(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root then
		return
	end

	humanoid.WalkSpeed = self:_walkSpeed(player)
	player:SetAttribute("HeldEchoes", 0)
	player:SetAttribute("Stamina", Config.Player.MaxStamina)
	self._sprinting[player] = false

	humanoid.Died:Connect(function()
		player:SetAttribute("HeldEchoes", 0)
		self._sprinting[player] = false
		self:_message(player, "Deine getragenen Echos sind im Riss verloren gegangen.", "Danger")
	end)

	task.defer(function()
		if (self._status == "Running" or self._status == "WaveClear") and self._data:IsLoaded(player) then
			self._arena:TeleportToArena(character, player.UserId)
		else
			self._arena:TeleportToLobby(character)
		end
	end)
end

function GameService:_connectPlayer(player)
	player:GetAttributeChangedSignal("DataLoaded"):Connect(function()
		if player:GetAttribute("DataLoaded") and (self._status == "Running" or self._status == "WaveClear") and player.Character then
			self._arena:TeleportToArena(player.Character, player.UserId)
		end
	end)

	player.CharacterAdded:Connect(function(character)
		self:_setupCharacter(player, character)
	end)

	if player.Character then
		task.spawn(function()
			self:_setupCharacter(player, player.Character)
		end)
	end

	task.delay(1, function()
		if player.Parent then
			self:_broadcast(player)
		end
	end)
end

function GameService:_attachDepositPrompt()
	if self._promptConnection then
		self._promptConnection:Disconnect()
		self._promptConnection = nil
	end

	local prompt = self._arena:GetDepositPrompt()
	if not prompt then
		return
	end

	self._promptConnection = prompt.Triggered:Connect(function(player)
		if self._status ~= "Running" or not self._data:IsLoaded(player) then
			return
		end
		if self._phase ~= "STABLE" then
			self:_message(player, "Der Anker ist in dieser Dimension desynchronisiert.", "Danger")
			return
		end

		local held = player:GetAttribute("HeldEchoes") or 0
		if held <= 0 then
			self:_message(player, "Du trägst noch keine Echos.", "Info")
			return
		end

		player:SetAttribute("HeldEchoes", 0)
		self._banked += held
		self._data:AddFlux(player, held * Config.Rewards.EchoFlux)
		self:_message(player, string.format("%d Echos synchronisiert · +%d Flux", held, held * Config.Rewards.EchoFlux), "Success")
		self:_broadcast()
	end)
end

function GameService:_spawnEcho()
	if self._status ~= "Running" then
		return
	end
	local folder = self._arena:GetOrbFolder()
	if not folder then
		return
	end

	local orb = nil
	local touchPart = nil
	local assets = ServerStorage:FindFirstChild("ShiftBreakAssets")
	local template = assets and assets:FindFirstChild("Echo")
	if template and (template:IsA("Model") or template:IsA("BasePart")) then
		orb = template:Clone()
		if not orb then
			warn("[SHIFT//BREAK] ShiftBreakAssets/Echo ist nicht klonbar. Aktiviere Archivable; Platzhalter wird verwendet.")
		elseif orb:IsA("Model") then
			local namedHitbox = orb:FindFirstChild("Hitbox", true)
			touchPart = namedHitbox and namedHitbox:IsA("BasePart") and namedHitbox or orb.PrimaryPart or orb:FindFirstChildWhichIsA("BasePart", true)
		else
			touchPart = orb
		end
		if orb and (not touchPart or not touchPart:IsA("BasePart")) then
			warn("[SHIFT//BREAK] ShiftBreakAssets/Echo benötigt einen BasePart namens Hitbox oder eine Model-PrimaryPart; Platzhalter wird verwendet.")
			orb:Destroy()
			orb = nil
			touchPart = nil
		end
	end

	if not orb then
		orb = Instance.new("Part")
		orb.Shape = Enum.PartType.Ball
		orb.Size = Vector3.new(2.4, 2.4, 2.4)
		orb.Color = Config.Colors.Echo
		orb.Material = Enum.Material.Neon
		touchPart = orb
	end

	orb.Name = "Echo"
	orb.Parent = folder
	local spawnCFrame = CFrame.new(self._arena:GetRandomEchoPosition())
	if orb:IsA("Model") then
		for _, descendant in orb:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanTouch = descendant == touchPart
				descendant.CanQuery = false
			end
		end
		orb:PivotTo(spawnCFrame)
	else
		orb.Anchored = true
		orb.CanCollide = false
		orb.CanTouch = true
		orb.CanQuery = false
		orb.CFrame = spawnCFrame
	end
	self._orbCount += 1

	if not touchPart:FindFirstChildOfClass("PointLight") then
		local light = Instance.new("PointLight")
		light.Color = Config.Colors.Echo
		light.Brightness = 2
		light.Range = 11
		light.Parent = touchPart
	end

	if not orb:FindFirstChildOfClass("Highlight") then
		local highlight = Instance.new("Highlight")
		highlight.Name = "EchoOutline"
		highlight.Adornee = orb
		highlight.FillTransparency = 0.72
		highlight.OutlineColor = Config.Colors.Text
		highlight.OutlineTransparency = 0.15
		highlight.Parent = orb
	end

	local released = false
	orb.Destroying:Connect(function()
		if not released then
			released = true
			self._orbCount = math.max(0, self._orbCount - 1)
		end
	end)

	local consumed = false
	touchPart.Touched:Connect(function(hit)
		if consumed or self._status ~= "Running" then
			return
		end

		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not player or not humanoid or humanoid.Health <= 0 or not self._data:IsLoaded(player) then
			return
		end

		local held = player:GetAttribute("HeldEchoes") or 0
		local capacity = player:GetAttribute("MaxCapacity") or Config.Player.StartingCapacity
		if held >= capacity then
			local now = workspace:GetServerTimeNow()
			if now - (self._fullMessageAt[player] or 0) > 2 then
				self._fullMessageAt[player] = now
				self:_message(player, "Echo-Tasche voll — zurück zum Anker!", "Danger")
			end
			return
		end

		consumed = true
		player:SetAttribute("HeldEchoes", held + 1)
		orb:Destroy()
	end)

	task.delay(Config.Echo.Lifetime, function()
		if orb.Parent then
			orb:Destroy()
		end
	end)
end

function GameService:_clearEchoes()
	local folder = self._arena:GetOrbFolder()
	if folder then
		for _, child in folder:GetChildren() do
			child:Destroy()
		end
	end
	self._orbCount = 0
end

function GameService:_setPhase(phase)
	self._phase = phase
	self._arena:SetPhase(phase)
	self._arena:SetDepositEnabled(self._status == "Running" and phase == "STABLE")
	self._enemies:SetActive(phase == "FRACTURED" and self._status == "Running")

	if phase == "STABLE" then
		self._enemies:Clear()
		self:_messageAll("STABILE DIMENSION — sammelt und synchronisiert Echos!", "Stable")
	else
		self:_messageAll("DIMENSIONSBRUCH — der Anker ist offline. Überlebt!", "Fractured")
	end
	self:_broadcast()
end

function GameService:_resetPlayersForWave()
	for index, player in Players:GetPlayers() do
		player:SetAttribute("HeldEchoes", 0)
		player:SetAttribute("Stamina", Config.Player.MaxStamina)
		self._sprinting[player] = false
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = humanoid.MaxHealth
			self._arena:TeleportToArena(character, index)
		end
	end
end

function GameService:_quotaForWave(wave)
	return Config.Round.BaseQuota
		+ (self:_activePlayerCount() * Config.Round.QuotaPerPlayer)
		+ ((wave - 1) * Config.Round.QuotaGrowthPerWave)
end

function GameService:_runWave(wave)
	self._wave = wave
	self._banked = 0
	self._target = self:_quotaForWave(wave)
	self._enemies:Clear()
	self._enemies:SetWave(wave)
	self:_clearEchoes()
	self:_resetPlayersForWave()
	self:_setStatus("Running")
	self:_setPhase("STABLE")

	for _ = 1, math.min(12, self._target) do
		self:_spawnEcho()
	end

	local waveEndsAt = workspace:GetServerTimeNow() + Config.Round.WaveDuration
	local nextShiftAt = workspace:GetServerTimeNow() + Config.Round.ShiftInterval
	local nextEchoAt = 0
	local nextEnemyAt = 0
	local lastSecond = -1

	while self:_activePlayerCount() >= Config.MinimumPlayers do
		local now = workspace:GetServerTimeNow()
		self._target = self:_quotaForWave(wave)
		if self._banked >= self._target then
			break
		end
		self._timeRemaining = waveEndsAt - now
		self._shiftRemaining = nextShiftAt - now
		if self._timeRemaining <= 0 then
			break
		end

		if now >= nextShiftAt then
			nextShiftAt = now + Config.Round.ShiftInterval
			self._shiftRemaining = Config.Round.ShiftInterval
			self:_setPhase(self._phase == "STABLE" and "FRACTURED" or "STABLE")
		end

		local maximumEchoes = Config.Echo.MaximumBase + (#Players:GetPlayers() * Config.Echo.MaximumPerPlayer)
		if now >= nextEchoAt and self._orbCount < maximumEchoes then
			self:_spawnEcho()
			nextEchoAt = now + Config.Echo.SpawnInterval
		end

		local maximumEnemies = Config.Enemy.BaseMaximum + (wave * Config.Enemy.MaximumPerWave)
		if self._phase == "FRACTURED" and now >= nextEnemyAt and self._enemies:Count() < maximumEnemies then
			self._enemies:Spawn(self._arena:GetRandomEnemyPosition())
			nextEnemyAt = now + Config.Enemy.SpawnInterval
		end

		local currentSecond = math.ceil(self._timeRemaining)
		if currentSecond ~= lastSecond then
			lastSecond = currentSecond
			self:_broadcast()
		end

		task.wait(0.1)
	end

	local succeeded = self._banked >= self._target
	self._timeRemaining = 0
	self._shiftRemaining = 0
	self._arena:SetDepositEnabled(false)
	self._enemies:SetActive(false)
	self._enemies:Clear()
	self:_clearEchoes()

	if succeeded then
		for _, player in Players:GetPlayers() do
			self._data:AddFlux(player, Config.Rewards.WaveFlux)
		end
	end
	return succeeded
end

function GameService:_countdown(status, duration)
	self:_setStatus(status)
	for remaining = duration, 1, -1 do
		if #Players:GetPlayers() < Config.MinimumPlayers or not self:_allPlayersReady() then
			self._timeRemaining = 0
			self:_broadcast()
			return false
		end
		self._timeRemaining = remaining
		self:_broadcast()
		task.wait(1)
	end
	self._timeRemaining = 0
	return true
end

function GameService:_prepareRound()
	self._arena:BuildArena()
	self:_attachDepositPrompt()
	for index, player in Players:GetPlayers() do
		player:SetAttribute("HeldEchoes", 0)
		if player.Character then
			self._arena:TeleportToArena(player.Character, index)
		end
	end
end

function GameService:_finishRound(victory)
	self._enemies:SetActive(false)
	self._enemies:Clear()
	self:_clearEchoes()
	self._arena:SetDepositEnabled(false)
	self._phase = "STABLE"
	self._arena:SetPhase("STABLE")

	if victory then
		self._status = "Victory"
		self:_messageAll("RISS VERSIEGELT — die Realität hält. Vorerst.", "Success")
		for _, player in Players:GetPlayers() do
			self._data:AddFlux(player, Config.Rewards.VictoryFlux)
			self._data:AddWin(player)
		end
	else
		self._status = "Defeat"
		self:_messageAll("DER RISS HAT EUCH ZURÜCKGEWORFEN — Upgrades bleiben erhalten.", "Danger")
		for _, player in Players:GetPlayers() do
			self._data:AddFlux(player, Config.Rewards.ParticipationFlux)
		end
	end

	self._timeRemaining = Config.Round.ResultDuration
	self:_broadcast()
	for remaining = Config.Round.ResultDuration, 1, -1 do
		self._timeRemaining = remaining
		self:_broadcast()
		task.wait(1)
	end

	for _, player in Players:GetPlayers() do
		player:SetAttribute("HeldEchoes", 0)
		if player.Character then
			self._arena:TeleportToLobby(player.Character)
		end
	end
end

function GameService:_runGameLoop()
	while true do
		while #Players:GetPlayers() < Config.MinimumPlayers or not self:_allPlayersReady() do
			self._status = "Waiting"
			self._wave = 0
			self._banked = 0
			self._target = 0
			self._timeRemaining = 0
			self._shiftRemaining = 0
			self:_broadcast()
			task.wait(1)
		end

		for _, player in Players:GetPlayers() do
			if player.Character then
				self._arena:TeleportToLobby(player.Character)
			end
		end

		local canStart = self:_countdown("Intermission", Config.Round.IntermissionDuration)
		if not canStart then
			continue
		end

		self:_prepareRound()
		local victory = true
		for wave = 1, Config.Round.Waves do
			if not self:_runWave(wave) then
				victory = false
				break
			end

			if wave < Config.Round.Waves then
				self._status = "WaveClear"
				self._timeRemaining = Config.Round.WaveClearDuration
				self:_messageAll(string.format("WELLE %d STABILISIERT · +%d Flux", wave, Config.Rewards.WaveFlux), "Success")
				for remaining = Config.Round.WaveClearDuration, 1, -1 do
					self._timeRemaining = remaining
					self:_broadcast()
					task.wait(1)
				end
			end
		end

		self:_finishRound(victory)
	end
end

function GameService:_handleAction(player, actionName, active)
	if actionName == "Sprint" then
		self._sprinting[player] = active == true
		return
	end

	if actionName ~= "Pulse" or self._status ~= "Running" then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then
		return
	end

	local now = workspace:GetServerTimeNow()
	local cooldownEnd = player:GetAttribute("PulseCooldownEnd") or 0
	if now < cooldownEnd then
		return
	end

	player:SetAttribute("PulseCooldownEnd", now + self:_pulseCooldown(player))
	local hitCount = self._enemies:Pulse(root.Position, Config.Player.PulseRadius, Config.Player.PulseStunDuration)
	if hitCount > 0 then
		self:_message(player, string.format("PULS: %d Schatten destabilisiert.", hitCount), "Stable")
	else
		self:_message(player, "PULS: kein Schatten in Reichweite.", "Info")
	end
end

function GameService:_stepPlayers(deltaTime)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoid or not root or humanoid.Health <= 0 then
			continue
		end

		local stamina = player:GetAttribute("Stamina") or Config.Player.MaxStamina
		local isMoving = humanoid.MoveDirection.Magnitude > 0.05
		local isSprinting = self._sprinting[player] and stamina > 0 and isMoving
		if isSprinting then
			stamina = math.max(0, stamina - Config.Player.StaminaDrainPerSecond * deltaTime)
		else
			stamina = math.min(Config.Player.MaxStamina, stamina + Config.Player.StaminaRegenPerSecond * deltaTime)
		end
		if stamina <= 0 then
			self._sprinting[player] = false
		end

		player:SetAttribute("Stamina", stamina)
		humanoid.WalkSpeed = isSprinting and (Config.Player.SprintWalkSpeed + self._data:GetUpgradeBonus(player, "Speed")) or self:_walkSpeed(player)

		if self._status == "Running" and root.Position.Y < self._arena:GetKillHeight() then
			humanoid.Health = 0
		end
	end
end

function GameService:_handlePurchase(player, upgradeName)
	if self._status == "Running" or self._status == "WaveClear" then
		return false, "Upgrades können nur zwischen Runden gekauft werden."
	end
	if typeof(upgradeName) ~= "string" then
		return false, "Ungültige Anfrage."
	end

	local success, message = self._data:PurchaseUpgrade(player, upgradeName)
	if success then
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = self:_walkSpeed(player)
		end
	end
	return success, message
end

function GameService:Start()
	if self._started then
		return
	end
	self._started = true
	Players.RespawnTime = 3

	Players.PlayerAdded:Connect(function(player)
		self:_connectPlayer(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self._sprinting[player] = nil
		self._fullMessageAt[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		self:_connectPlayer(player)
	end

	self._actionRemote.OnServerEvent:Connect(function(player, actionName, active)
		if typeof(actionName) == "string" then
			self:_handleAction(player, actionName, active)
		end
	end)
	self._purchaseRemote.OnServerInvoke = function(player, upgradeName)
		return self:_handlePurchase(player, upgradeName)
	end

	local accumulator = 0
	self._heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
		accumulator += deltaTime
		if accumulator >= 0.1 then
			self:_stepPlayers(accumulator)
			accumulator = 0
		end
	end)

	self:_attachDepositPrompt()
	task.spawn(function()
		self:_runGameLoop()
	end)
end

return GameService
