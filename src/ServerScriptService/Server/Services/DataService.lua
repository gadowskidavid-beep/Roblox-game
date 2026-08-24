local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local DataService = {}
DataService.__index = DataService

local DEFAULT_PROFILE = {
	Flux = 0,
	Wins = 0,
	Upgrades = {
		Capacity = 0,
		Speed = 0,
		Pulse = 0,
	},
}

local function copyProfile(source)
	if typeof(source) ~= "table" then
		source = nil
	end
	local sourceUpgrades = source and typeof(source.Upgrades) == "table" and source.Upgrades or nil
	local profile = {
		Flux = tonumber(source and source.Flux) or DEFAULT_PROFILE.Flux,
		Wins = tonumber(source and source.Wins) or DEFAULT_PROFILE.Wins,
		Upgrades = {},
	}

	for _, upgradeName in Config.Upgrades.Order do
		local value = sourceUpgrades and tonumber(sourceUpgrades[upgradeName]) or 0
		local definition = Config.Upgrades.Definitions[upgradeName]
		profile.Upgrades[upgradeName] = math.clamp(math.floor(value), 0, #definition.Costs)
	end

	return profile
end

function DataService.new()
	local self = setmetatable({}, DataService)
	self._store = DataStoreService:GetDataStore(Config.DataStoreName)
	self._profiles = {}
	self._canSave = {}
	self._started = false
	return self
end

function DataService:_load(player)
	local storedProfile = nil
	local loadedPersistently = false
	local lastError = nil

	for attempt = 1, 3 do
		local success, result = pcall(function()
			return self._store:GetAsync(tostring(player.UserId))
		end)
		if success then
			if result == nil or typeof(result) == "table" then
				storedProfile = result
				loadedPersistently = true
			else
				lastError = "Gespeichertes Profil hat ein ungültiges Format."
			end
			break
		end
		lastError = result
		if attempt < 3 then
			task.wait(attempt)
		end
	end

	if not loadedPersistently then
		warn(string.format("[SHIFT//BREAK] Profildaten für %s konnten nicht geladen werden; diese Sitzung wird NICHT gespeichert, um vorhandene Daten zu schützen: %s", player.Name, tostring(lastError)))
	end

	if not player.Parent then
		return
	end

	self._profiles[player] = copyProfile(storedProfile)
	self._canSave[player] = loadedPersistently
	self:_createLeaderstats(player)
	self:SyncAttributes(player)
	player:SetAttribute("DataPersistent", loadedPersistently)
end

function DataService:_createLeaderstats(player)
	local oldLeaderstats = player:FindFirstChild("leaderstats")
	if oldLeaderstats then
		oldLeaderstats:Destroy()
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local flux = Instance.new("IntValue")
	flux.Name = "Flux"
	flux.Parent = leaderstats

	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Parent = leaderstats
end

function DataService:GetProfile(player)
	return self._profiles[player]
end

function DataService:IsLoaded(player)
	return self._profiles[player] ~= nil
end

function DataService:GetUpgradeBonus(player, upgradeName)
	local profile = self._profiles[player]
	local definition = Config.Upgrades.Definitions[upgradeName]
	if not profile or not definition then
		return 0
	end

	local level = profile.Upgrades[upgradeName] or 0
	return definition.Bonuses[level] or 0
end

function DataService:SyncAttributes(player)
	local profile = self._profiles[player]
	if not profile or not player.Parent then
		return
	end

	player:SetAttribute("DataLoaded", true)
	player:SetAttribute("Flux", profile.Flux)
	player:SetAttribute("Wins", profile.Wins)
	player:SetAttribute("UpgradeCapacity", profile.Upgrades.Capacity)
	player:SetAttribute("UpgradeSpeed", profile.Upgrades.Speed)
	player:SetAttribute("UpgradePulse", profile.Upgrades.Pulse)
	player:SetAttribute("MaxCapacity", Config.Player.StartingCapacity + self:GetUpgradeBonus(player, "Capacity"))
	player:SetAttribute("Stamina", player:GetAttribute("Stamina") or Config.Player.MaxStamina)
	player:SetAttribute("HeldEchoes", player:GetAttribute("HeldEchoes") or 0)
	player:SetAttribute("PulseCooldownEnd", player:GetAttribute("PulseCooldownEnd") or 0)

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		leaderstats.Flux.Value = profile.Flux
		leaderstats.Wins.Value = profile.Wins
	end
end

function DataService:AddFlux(player, amount)
	local profile = self._profiles[player]
	if not profile then
		return
	end

	profile.Flux = math.max(0, profile.Flux + math.floor(amount))
	self:SyncAttributes(player)
end

function DataService:AddWin(player)
	local profile = self._profiles[player]
	if not profile then
		return
	end

	profile.Wins += 1
	self:SyncAttributes(player)
end

function DataService:PurchaseUpgrade(player, upgradeName)
	local profile = self._profiles[player]
	local definition = Config.Upgrades.Definitions[upgradeName]
	if not profile then
		return false, "Dein Profil wird noch geladen."
	end
	if not definition then
		return false, "Unbekanntes Upgrade."
	end

	local currentLevel = profile.Upgrades[upgradeName] or 0
	if currentLevel >= #definition.Costs then
		return false, "Dieses Upgrade ist bereits maximal."
	end

	local cost = definition.Costs[currentLevel + 1]
	if profile.Flux < cost then
		return false, string.format("Dir fehlen %d Flux.", cost - profile.Flux)
	end

	profile.Flux -= cost
	profile.Upgrades[upgradeName] = currentLevel + 1
	self:SyncAttributes(player)
	return true, string.format("%s ist jetzt Stufe %d.", definition.DisplayName, currentLevel + 1)
end

function DataService:Save(player)
	local profile = self._profiles[player]
	if not profile then
		return true
	end
	if not self._canSave[player] then
		warn(string.format("[SHIFT//BREAK] Sitzung von %s wird nicht gespeichert, weil der ursprüngliche Datensatz nicht sicher geladen wurde.", player.Name))
		return false
	end

	local payload = copyProfile(profile)
	local success, result = pcall(function()
		self._store:SetAsync(tostring(player.UserId), payload)
	end)

	if not success then
		warn(string.format("[SHIFT//BREAK] Profildaten für %s konnten nicht gespeichert werden: %s", player.Name, tostring(result)))
	end
	return success
end

function DataService:Start()
	if self._started then
		return
	end
	self._started = true

	Players.PlayerAdded:Connect(function(player)
		self:_load(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:Save(player)
		self._profiles[player] = nil
		self._canSave[player] = nil
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:_load(player)
		end)
	end

	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			self:Save(player)
		end
	end)
end

return DataService
