local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local EnemyService = {}
EnemyService.__index = EnemyService

function EnemyService.new(arenaService)
	local self = setmetatable({}, EnemyService)
	self._arena = arenaService
	self._entries = {}
	self._active = false
	self._wave = 1
	self._connection = nil
	return self
end

local function makeVisual(parent, name, size, color, transparency)
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Transparency = transparency or 0
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Parent = parent
	return part
end

function EnemyService:Spawn(position)
	local folder = self._arena:GetEnemyFolder()
	if not folder then
		return
	end

	local model = nil
	local core = nil
	local assets = ServerStorage:FindFirstChild("ShiftBreakAssets")
	local template = assets and assets:FindFirstChild("Shade")
	if template then
		if template:IsA("Model") then
			model = template:Clone()
			if model then
				local namedCore = model:FindFirstChild("Core", true)
				core = model.PrimaryPart or (namedCore and namedCore:IsA("BasePart") and namedCore) or model:FindFirstChildWhichIsA("BasePart", true)
			end
		elseif template:IsA("BasePart") then
			local clonedPart = template:Clone()
			if clonedPart then
				model = Instance.new("Model")
				core = clonedPart
				core.Parent = model
			end
		end

		if model and core and core:IsA("BasePart") then
			for _, descendant in model:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.Anchored = true
					descendant.CanCollide = false
					descendant.CanTouch = false
					descendant.CanQuery = false
				end
			end
			model.PrimaryPart = core
		else
			warn("[SHIFT//BREAK] ShiftBreakAssets/Shade ist nicht klonbar oder benötigt ein Model mit PrimaryPart/Core bzw. einen BasePart; Platzhalter wird verwendet.")
			if model then
				model:Destroy()
			end
			model = nil
			core = nil
		end
	end

	if not model then
		model = Instance.new("Model")
		core = makeVisual(model, "Core", Vector3.new(4.5, 4.5, 4.5), Config.Colors.Fractured, 0.05)
		local aura = makeVisual(model, "Aura", Vector3.new(6.5, 6.5, 6.5), Config.Colors.Fractured, 0.68)
		aura.CFrame = core.CFrame
		local eye = makeVisual(model, "Eye", Vector3.new(1.1, 1.1, 1.1), Config.Colors.Text, 0)
		eye.CFrame = core.CFrame * CFrame.new(0, 0.3, -2.1)

		local light = Instance.new("PointLight")
		light.Name = "FractureGlow"
		light.Color = Config.Colors.Fractured
		light.Brightness = 2
		light.Range = 14
		light.Parent = core
		model.PrimaryPart = core
	end

	model.Name = "Shade"
	model:SetAttribute("StunnedUntil", 0)
	model.Parent = folder
	model:PivotTo(CFrame.new(position + Vector3.new(0, 3, 0)))
	self._entries[model] = {
		lastHits = {},
		seed = math.random() * 10,
		normalColor = core.Color,
	}
end

function EnemyService:Count()
	local count = 0
	for model in self._entries do
		if model.Parent then
			count += 1
		end
	end
	return count
end

function EnemyService:SetWave(wave)
	self._wave = wave
end

function EnemyService:SetActive(active)
	self._active = active
end

function EnemyService:Clear()
	for model in self._entries do
		model:Destroy()
	end
	table.clear(self._entries)
end

function EnemyService:Pulse(origin, radius, stunDuration)
	local now = workspace:GetServerTimeNow()
	local hitCount = 0
	for model in self._entries do
		if model.Parent and model.PrimaryPart then
			local offset = model.PrimaryPart.Position - origin
			local distance = offset.Magnitude
			if distance <= radius then
				model:SetAttribute("StunnedUntil", now + stunDuration)
				local direction = distance > 0.01 and offset.Unit or Vector3.new(1, 0, 0)
				local pushedPosition = model.PrimaryPart.Position + Vector3.new(direction.X, 0, direction.Z) * 9
				model:PivotTo(CFrame.new(pushedPosition))
				hitCount += 1
			end
		end
	end
	return hitCount
end

function EnemyService:_nearestTarget(position)
	local nearestPlayer = nil
	local nearestRoot = nil
	local nearestDistance = math.huge

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and root and humanoid.Health > 0 then
			local distance = (root.Position - position).Magnitude
			if distance < nearestDistance then
				nearestPlayer = player
				nearestRoot = root
				nearestDistance = distance
			end
		end
	end

	return nearestPlayer, nearestRoot, nearestDistance
end

function EnemyService:_step(deltaTime)
	if not self._active then
		return
	end

	local now = workspace:GetServerTimeNow()
	local speed = Config.Enemy.BaseSpeed + (self._wave - 1) * Config.Enemy.SpeedPerWave

	for model, entry in self._entries do
		if not model.Parent or not model.PrimaryPart then
			self._entries[model] = nil
			continue
		end

		local core = model.PrimaryPart
		local stunned = (model:GetAttribute("StunnedUntil") or 0) > now
		core.Color = stunned and Config.Colors.Stable or entry.normalColor

		if stunned then
			continue
		end

		local player, targetRoot, distance = self:_nearestTarget(core.Position)
		if not player or not targetRoot then
			continue
		end

		local flatOffset = Vector3.new(targetRoot.Position.X - core.Position.X, 0, targetRoot.Position.Z - core.Position.Z)
		if flatOffset.Magnitude > 0.1 then
			local step = math.min(flatOffset.Magnitude, speed * deltaTime)
			local nextPosition = core.Position + flatOffset.Unit * step
			nextPosition = Vector3.new(nextPosition.X, targetRoot.Position.Y + 2 + math.sin(now * 3 + entry.seed), nextPosition.Z)
			model:PivotTo(CFrame.lookAt(nextPosition, Vector3.new(targetRoot.Position.X, nextPosition.Y, targetRoot.Position.Z)))
		end

		if distance <= Config.Enemy.DamageRadius then
			local lastHit = entry.lastHits[player] or 0
			if now - lastHit >= Config.Enemy.DamageCooldown then
				entry.lastHits[player] = now
				local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid:TakeDamage(Config.Enemy.Damage)
				end
			end
		end
	end
end

function EnemyService:Start()
	if self._connection then
		return
	end
	self._connection = RunService.Heartbeat:Connect(function(deltaTime)
		self:_step(deltaTime)
	end)
end

return EnemyService
