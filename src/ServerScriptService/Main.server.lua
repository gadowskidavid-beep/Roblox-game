--[[
	Main.server.lua - Server entry point for Battle Pets
	Initializes all services, creates RemoteEvents/RemoteFunctions,
	and connects player lifecycle events.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Require all services
local DataService = require(script.Parent.Services.DataService)
local CurrencyService = require(script.Parent.Services.CurrencyService)
local UpgradeService = require(script.Parent.Services.UpgradeService)
local PetService = require(script.Parent.Services.PetService)
local ZoneService = require(script.Parent.Services.ZoneService)
local CampaignService = require(script.Parent.Services.CampaignService)
local EggService = require(script.Parent.Services.EggService)
local QuestService = require(script.Parent.Services.QuestService)
local MasteryService = require(script.Parent.Services.MasteryService)

----------------------------------------------
-- Central Rate Limiter
----------------------------------------------

local rateLimits = {}
local function canCall(player, action, cooldown)
	rateLimits[player.UserId] = rateLimits[player.UserId] or {}
	local now = os.clock()
	local last = rateLimits[player.UserId][action] or 0
	if now - last < cooldown then
		return false
	end
	rateLimits[player.UserId][action] = now
	return true
end

----------------------------------------------
-- Create Remotes Folder in ReplicatedStorage
----------------------------------------------

local remotesFolder = Instance.new("Folder")
remotesFolder.Name = "Remotes"
remotesFolder.Parent = ReplicatedStorage

-- Create all RemoteEvents
local remoteEvents = {
	"CurrencyUpdated",
	"PetInventoryUpdated",
	"PetEquipped",
	"PetUnequipped",
	"ZoneUnlocked",
	"DestructibleDamaged",
	"DestructibleDestroyed",
	"EggHatchStart",
	"EggHatchResult",
	"CampaignBattleUpdate",
	"CampaignVictory",
	"CampaignDefeat",
	"UpgradeUpdated",
	"CollectCurrency",
	"XPUpdated",
	"QuestProgressUpdated",
	"MasteryUpdated",
}

for _, eventName in ipairs(remoteEvents) do
	local event = Instance.new("RemoteEvent")
	event.Name = eventName
	event.Parent = remotesFolder
end

-- Create all RemoteFunctions
local remoteFunctions = {
	"HatchEgg",
	"EquipPet",
	"UnequipPet",
	"DeletePet",
	"DeletePets",
	"UnlockZone",
	"PurchaseUpgrade",
	"GetPlayerData",
	"StartCampaignLevel",
	"DeployPetInCampaign",
	"AttackDestructible",
	"ClickAttackDestructible",
	"CritAttackDestructible",
	"GetQuestProgress",
	"PurchaseMasteryBuff",
	"GetMasteryState",
	"ConvertToGoldenPet",
	"AssignPetTarget",
}

for _, funcName in ipairs(remoteFunctions) do
	local func = Instance.new("RemoteFunction")
	func.Name = funcName
	func.Parent = remotesFolder
end

----------------------------------------------
-- Initialize Services (order matters for dependencies)
----------------------------------------------

-- Init currency first (with nil upgradeService, we set it after)
CurrencyService.init(DataService, nil)
UpgradeService.init(DataService, CurrencyService)
-- Now set the upgrade reference for CurrencyService
CurrencyService._upgradeService = UpgradeService

-- Initialize quest and mastery services
QuestService.init(DataService, CurrencyService)
MasteryService.init(DataService)

-- Set cross-references
UpgradeService.setQuestService(QuestService)
UpgradeService.setMasteryService(MasteryService)

PetService.init(DataService, CurrencyService, UpgradeService)
EggService.init(DataService, CurrencyService, PetService)
EggService.setQuestService(QuestService)

ZoneService.init(DataService, CurrencyService, PetService)
ZoneService.setQuestService(QuestService)
ZoneService.setMasteryService(MasteryService)

CampaignService.init(DataService, CurrencyService, PetService)

-- Start DataService auto-save loop
DataService.startAutoSave()

-- Bind to server shutdown to save all player data
DataService.bindToClose()

----------------------------------------------
-- Connect RemoteFunction handlers (server-authoritative validation)
----------------------------------------------

local function getRemoteFunction(name)
	return remotesFolder:FindFirstChild(name)
end

-- GetPlayerData (returns sanitized copy, not the cache reference)
getRemoteFunction("GetPlayerData").OnServerInvoke = function(player)
	if not player or not player:IsA("Player") then
		return nil
	end
	return DataService.getClientData(player)
end

-- HatchEgg (3 second cooldown)
getRemoteFunction("HatchEgg").OnServerInvoke = function(player, eggType)
	if not player or not player:IsA("Player") then
		return nil, "Invalid player"
	end
	if not canCall(player, "HatchEgg", 3) then
		return nil, "Please wait before hatching again"
	end
	if type(eggType) ~= "string" then
		return nil, "Invalid egg type parameter"
	end
	return EggService.purchaseAndHatch(player, eggType)
end

-- EquipPet (0.5 second cooldown)
getRemoteFunction("EquipPet").OnServerInvoke = function(player, petInstanceId)
	if not player or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if not canCall(player, "EquipPet", 0.5) then
		return false, "Please wait before equipping again"
	end
	if type(petInstanceId) ~= "string" then
		return false, "Invalid pet ID parameter"
	end
	return PetService.equipPet(player, petInstanceId)
end

-- UnequipPet (0.5 second cooldown)
getRemoteFunction("UnequipPet").OnServerInvoke = function(player, petInstanceId)
	if not player or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if not canCall(player, "UnequipPet", 0.5) then
		return false, "Please wait before unequipping again"
	end
	if type(petInstanceId) ~= "string" then
		return false, "Invalid pet ID parameter"
	end
	return PetService.unequipPet(player, petInstanceId)
end

-- DeletePet (1 second cooldown)
getRemoteFunction("DeletePet").OnServerInvoke = function(player, petInstanceId)
	if not player or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if not canCall(player, "DeletePet", 1) then
		return false, "Please wait before deleting again"
	end
	if type(petInstanceId) ~= "string" then
		return false, "Invalid pet ID parameter"
	end
	return PetService.deletePet(player, petInstanceId)
end

-- DeletePets (bulk delete, 1 second cooldown, max 100 pets)
getRemoteFunction("DeletePets").OnServerInvoke = function(player, petInstanceIds)
	if not player or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if not canCall(player, "DeletePets", 1) then
		return false, "Please wait before deleting again"
	end
	if type(petInstanceIds) ~= "table" then
		return false, "Invalid pet IDs parameter"
	end
	-- Bulk delete size limit
	if #petInstanceIds > 100 then
		return false, "Too many pets"
	end
	-- Validate each ID is a string
	for _, id in ipairs(petInstanceIds) do
		if type(id) ~= "string" then
			return false, "Invalid pet ID in list"
		end
	end
	return PetService.deletePets(player, petInstanceIds)
end

-- UnlockZone (2 second cooldown)
getRemoteFunction("UnlockZone").OnServerInvoke = function(player, zoneId)
	if not player or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if not canCall(player, "UnlockZone", 2) then
		return false, "Please wait before unlocking again"
	end
	if type(zoneId) ~= "number" then
		return false, "Invalid zone ID parameter"
	end
	return ZoneService.unlockZone(player, math.floor(zoneId))
end

-- PurchaseUpgrade (1 second cooldown)
getRemoteFunction("PurchaseUpgrade").OnServerInvoke = function(player, upgradeId)
	if not player or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if not canCall(player, "PurchaseUpgrade", 1) then
		return false, "Please wait before purchasing again"
	end
	if type(upgradeId) ~= "string" then
		return false, "Invalid upgrade ID parameter"
	end
	return UpgradeService.purchaseUpgrade(player, upgradeId)
end

-- GetQuestProgress
getRemoteFunction("GetQuestProgress").OnServerInvoke = function(player)
	if not player or not player:IsA("Player") then
		return {}
	end
	return QuestService.getQuestProgress(player)
end

-- PurchaseMasteryBuff (1 second cooldown)
getRemoteFunction("PurchaseMasteryBuff").OnServerInvoke = function(player, buffId)
	if not player or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if not canCall(player, "PurchaseMasteryBuff", 1) then
		return false, "Please wait before purchasing again"
	end
	if type(buffId) ~= "string" then
		return false, "Invalid buff ID parameter"
	end
	return MasteryService.purchaseBuff(player, buffId)
end

-- GetMasteryState
getRemoteFunction("GetMasteryState").OnServerInvoke = function(player)
	if not player or not player:IsA("Player") then
		return {}
	end
	return MasteryService.getMasteryState(player)
end

-- ConvertToGoldenPet (2 second cooldown)
getRemoteFunction("ConvertToGoldenPet").OnServerInvoke = function(player, petInstanceIds)
	if not player or not player:IsA("Player") then
		return nil, "Invalid player"
	end
	if not canCall(player, "ConvertToGoldenPet", 2) then
		return nil, "Please wait before converting again"
	end
	if type(petInstanceIds) ~= "table" then
		return nil, "Invalid pet IDs parameter (expected list)"
	end
	-- Validate each ID is a string
	for _, id in ipairs(petInstanceIds) do
		if type(id) ~= "string" then
			return nil, "Invalid pet ID in list"
		end
	end
	-- Limit to 7 pets max
	if #petInstanceIds < 1 or #petInstanceIds > 7 then
		return nil, "Must sacrifice between 1 and 7 pets"
	end
	local result, err = PetService.convertToGoldenPet(player, petInstanceIds)
	if result and result.success then
		-- Track quest progress for golden pet conversion
		QuestService.incrementStat(player, "goldenPetsConverted", 1)
	end
	return result, err
end

-- StartCampaignLevel (2 second cooldown)
getRemoteFunction("StartCampaignLevel").OnServerInvoke = function(player, levelNum)
	if not player or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if not canCall(player, "StartCampaignLevel", 2) then
		return false, "Please wait before starting again"
	end
	if type(levelNum) ~= "number" then
		return false, "Invalid level number parameter"
	end
	return CampaignService.startLevel(player, math.floor(levelNum))
end

-- DeployPetInCampaign (0.5 second cooldown)
getRemoteFunction("DeployPetInCampaign").OnServerInvoke = function(player, petInstanceId)
	if not player or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if not canCall(player, "DeployPetInCampaign", 0.5) then
		return false, "Please wait before deploying again"
	end
	if type(petInstanceId) ~= "string" then
		return false, "Invalid pet ID parameter"
	end
	return CampaignService.deployPet(player, petInstanceId)
end

-- AttackDestructible
getRemoteFunction("AttackDestructible").OnServerInvoke = function(player, destructibleId)
	if not player or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if type(destructibleId) ~= "string" then
		return false, "Invalid destructible ID parameter"
	end
	return ZoneService.attackDestructible(player, destructibleId)
end

-- ClickAttackDestructible (player tap/click damage - always 1 per click)
getRemoteFunction("ClickAttackDestructible").OnServerInvoke = function(player, destructibleId)
	if not player or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if type(destructibleId) ~= "string" then
		return false, "Invalid destructible ID parameter"
	end
	return ZoneService.clickAttackDestructible(player, destructibleId)
end

-- CritAttackDestructible (player clicked a crit circle - deals 2 damage if crit window active)
getRemoteFunction("CritAttackDestructible").OnServerInvoke = function(player, destructibleId)
	if not player or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if not canCall(player, "CritAttackDestructible", 0.2) then
		return false, "Please wait before crit attacking again"
	end
	if type(destructibleId) ~= "string" then
		return false, "Invalid destructible ID parameter"
	end
	return ZoneService.critAttackDestructible(player, destructibleId)
end

-- AssignPetTarget (client tells server which pet targets which destructible)
getRemoteFunction("AssignPetTarget").OnServerInvoke = function(player, petInstanceId, destructibleId)
	if not player or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if type(petInstanceId) ~= "string" then
		return false, "Invalid pet ID parameter"
	end
	-- destructibleId can be nil (clearing target) or string
	if destructibleId ~= nil and type(destructibleId) ~= "string" then
		return false, "Invalid destructible ID parameter"
	end
	return ZoneService.assignPetTarget(player, petInstanceId, destructibleId)
end

----------------------------------------------
-- Player Lifecycle
----------------------------------------------

-- Track session join times for playtime calculation
local _sessionJoinTimes = {}

Players.PlayerAdded:Connect(function(player)
	-- Load player data when they join
	DataService.loadPlayerData(player)

	-- Record join time for playtime tracking
	_sessionJoinTimes[player.UserId] = os.time()

	-- Create leaderstats folder for Roblox built-in leaderboard
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local data = DataService.getPlayerData(player)

	local levelStat = Instance.new("IntValue")
	levelStat.Name = "Level"
	levelStat.Value = data and data.level or 1
	levelStat.Parent = leaderstats

	local diamondsStat = Instance.new("IntValue")
	diamondsStat.Name = "Diamonds"
	diamondsStat.Value = data and data.diamonds or 0
	diamondsStat.Parent = leaderstats

	-- Check level-based quests on join (in case they already meet requirements)
	if data then
		QuestService.setStat(player, "reachLevel", data.level or 1)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	-- Accumulate playtime before saving
	local joinTime = _sessionJoinTimes[player.UserId]
	if joinTime then
		local sessionSeconds = os.time() - joinTime
		if sessionSeconds > 0 then
			QuestService.incrementStat(player, "playtime", sessionSeconds)
		end
		_sessionJoinTimes[player.UserId] = nil
	end

	-- Cleanup rate limits
	rateLimits[player.UserId] = nil

	-- Cleanup ZoneService player state (attack cooldowns, pet targets)
	ZoneService.onPlayerRemoving(player)

	-- Cleanup campaign battle if any
	CampaignService.onPlayerRemoving(player)
	-- Save and cleanup player data
	DataService.onPlayerRemoving(player)
end)

-- Handle players who joined before script loaded
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		DataService.loadPlayerData(player)
		_sessionJoinTimes[player.UserId] = os.time()

		-- Create leaderstats for already-connected players
		local leaderstats = player:FindFirstChild("leaderstats")
		if not leaderstats then
			leaderstats = Instance.new("Folder")
			leaderstats.Name = "leaderstats"
			leaderstats.Parent = player
		end

		local data = DataService.getPlayerData(player)

		local levelStat = leaderstats:FindFirstChild("Level")
		if not levelStat then
			levelStat = Instance.new("IntValue")
			levelStat.Name = "Level"
			levelStat.Parent = leaderstats
		end
		levelStat.Value = data and data.level or 1

		local diamondsStat = leaderstats:FindFirstChild("Diamonds")
		if not diamondsStat then
			diamondsStat = Instance.new("IntValue")
			diamondsStat.Name = "Diamonds"
			diamondsStat.Parent = leaderstats
		end
		diamondsStat.Value = data and data.diamonds or 0

		if data then
			QuestService.setStat(player, "reachLevel", data.level or 1)
		end
	end)
end

-- Helper: update leaderstats for a player from their current data
local function updateLeaderstats(player)
	local data = DataService.getPlayerData(player)
	if not data then return end
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end
	local levelStat = leaderstats:FindFirstChild("Level")
	if levelStat then
		levelStat.Value = data.level or 1
	end
	local diamondsStat = leaderstats:FindFirstChild("Diamonds")
	if diamondsStat then
		diamondsStat.Value = data.diamonds or 0
	end
end

-- Update leaderstats whenever currency or XP changes
-- Hook into existing remote events: listen for CurrencyUpdated and XPUpdated firing
local originalCurrencyUpdatedFire = nil
-- Use a periodic check (every 5 seconds) to keep leaderstats in sync
task.spawn(function()
	while true do
		task.wait(5)
		for _, player in ipairs(Players:GetPlayers()) do
			updateLeaderstats(player)
		end
	end
end)

-- Periodic playtime tracking: every 60 seconds, update playtime stats
-- This ensures quest progress is visible even during long sessions
task.spawn(function()
	while true do
		task.wait(60)
		for _, player in ipairs(Players:GetPlayers()) do
			local joinTime = _sessionJoinTimes[player.UserId]
			if joinTime then
				local sessionSeconds = os.time() - joinTime
				if sessionSeconds > 0 then
					-- Update the stat with total accumulated playtime
					local data = DataService.getPlayerData(player)
					if data and data.questStats then
						-- Calculate new total: stored + current session
						local storedPlaytime = data.questStats.playtime or 0
						-- We set the stat to stored + session so far
						-- But we must be careful not to double-count
						-- Instead, flush the session time into the stat and reset join time
						QuestService.incrementStat(player, "playtime", sessionSeconds)
						_sessionJoinTimes[player.UserId] = os.time()
					end
				end
			end
		end
	end
end)

print("[Battle Pets] Server initialized successfully!")
