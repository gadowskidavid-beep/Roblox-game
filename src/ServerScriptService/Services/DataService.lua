--[[
	DataService.lua - Conflict-safe player data persistence
	Uses versioned migrations, atomic session locks, retries, autosave heartbeats,
	and parallel shutdown saves. Studio falls back to memory-only data when API
	access is unavailable; production never overwrites a profile after load failure.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(game.ReplicatedStorage.Shared.Config)
local DataSchema = require(script.Parent.DataSchema)

local DataService = {}

local MAX_RETRIES = 3
local AUTOSAVE_INTERVAL = Config.AutoSaveInterval or 60
local SESSION_LOCK_TIMEOUT = Config.SessionLockTimeout or 180
local SHUTDOWN_TIMEOUT = 25
local SESSION_ID = game.JobId ~= "" and game.JobId or ("studio_" .. HttpService:GenerateGUID(false))

DataService._cache = {}
DataService._canSave = {}
DataService._saving = {}
DataService._useMemoryOnly = false

local dataStore = nil
local dsSuccess, dsResult = pcall(function()
	return DataStoreService:GetDataStore(Config.DataStoreName)
end)

if dsSuccess then
	dataStore = dsResult
else
	DataService._useMemoryOnly = true
	warn("[DataService] DataStore unavailable; using session-only data: " .. tostring(dsResult))
end

local function profileKey(userId)
	return "Player_" .. tostring(userId)
end

local function newSessionMetadata()
	return {
		id = SESSION_ID,
		placeId = game.PlaceId,
		updatedAt = os.time(),
	}
end

local function isForeignActiveSession(session)
	if type(session) ~= "table" or type(session.id) ~= "string" then
		return false
	end
	if session.id == SESSION_ID then
		return false
	end
	local updatedAt = type(session.updatedAt) == "number" and session.updatedAt or 0
	return os.time() - updatedAt < SESSION_LOCK_TIMEOUT
end

local function ownsStoredSession(storedData)
	return type(storedData) == "table"
		and type(storedData._session) == "table"
		and storedData._session.id == SESSION_ID
end

local function waitForCurrentSave(userId)
	local deadline = os.clock() + 10
	while DataService._saving[userId] and os.clock() < deadline do
		task.wait(0.05)
	end
	return not DataService._saving[userId]
end

local function useStudioFallback(player)
	if not RunService:IsStudio() then
		return nil
	end
	DataService._useMemoryOnly = true
	local data = DataSchema.getDefaultData()
	DataService._cache[player.UserId] = data
	DataService._canSave[player.UserId] = false
	warn("[DataService] Studio API access unavailable; switched to memory-only mode")
	return data
end

-- Atomically loads and locks a profile. A live lock from another server is never overwritten.
function DataService.loadPlayerData(player)
	if not player or not player:IsA("Player") then
		return nil, "Invalid player"
	end

	if DataService._cache[player.UserId] then
		return DataService._cache[player.UserId]
	end

	if DataService._useMemoryOnly then
		local data = DataSchema.getDefaultData()
		DataService._cache[player.UserId] = data
		DataService._canSave[player.UserId] = false
		return data
	end

	local key = profileKey(player.UserId)
	local loadedData = nil
	local lockConflict = nil
	local lastError = nil

	for attempt = 1, MAX_RETRIES do
		local success, result = pcall(function()
			return dataStore:UpdateAsync(key, function(storedData)
				local existingSession = type(storedData) == "table" and storedData._session or nil
				if isForeignActiveSession(existingSession) then
					lockConflict = existingSession
					return nil
				end

				local migrated = DataSchema.migrate(storedData)
				migrated._session = newSessionMetadata()
				return migrated
			end)
		end)

		if success and type(result) == "table" and result._session and result._session.id == SESSION_ID then
			loadedData = result
			break
		end
		if lockConflict then
			break
		end
		lastError = result
		if attempt < MAX_RETRIES then
			task.wait(2 ^ attempt)
		end
	end

	if loadedData then
		DataService._cache[player.UserId] = loadedData
		DataService._canSave[player.UserId] = true
		return loadedData
	end

	DataService._canSave[player.UserId] = false
	if lockConflict then
		local message = "Your data is still active on another server. Please wait a moment and rejoin."
		warn("[DataService] Refused concurrent session for " .. player.Name)
		return nil, message
	end

	local fallback = useStudioFallback(player)
	if fallback then
		return fallback
	end

	warn("[DataService] Failed to load " .. player.Name .. ": " .. tostring(lastError))
	return nil, "Your data could not be loaded safely. Please rejoin later."
end

-- Saves only while this server still owns the profile lock.
-- releaseLock is used on leave/shutdown so a new server can load immediately.
function DataService.savePlayerData(player, releaseLock)
	if not player or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if DataService._useMemoryOnly then
		return false, "Memory-only mode"
	end
	if not DataService._canSave[player.UserId] then
		return false, "Profile is not saveable"
	end
	if not waitForCurrentSave(player.UserId) then
		return false, "Save already in progress"
	end

	local data = DataService._cache[player.UserId]
	if not data then
		return false, "No cached data"
	end

	DataService._saving[player.UserId] = true
	local key = profileKey(player.UserId)
	local snapshot = DataSchema.cloneForPersistence(data)
	local sessionLost = false
	local lastError = nil
	local saved = false

	for attempt = 1, MAX_RETRIES do
		local success, result = pcall(function()
			return dataStore:UpdateAsync(key, function(storedData)
				if not ownsStoredSession(storedData) then
					sessionLost = true
					return nil
				end

				if releaseLock then
					snapshot._session = nil
				else
					snapshot._session = newSessionMetadata()
				end
				return snapshot
			end)
		end)

		if success and not sessionLost and type(result) == "table" then
			saved = true
			if not releaseLock then
				data._session = DataSchema.deepCopy(snapshot._session)
			end
			break
		end
		if sessionLost then
			break
		end
		lastError = result
		if attempt < MAX_RETRIES then
			task.wait(2 ^ attempt)
		end
	end

	DataService._saving[player.UserId] = nil

	if sessionLost then
		DataService._canSave[player.UserId] = false
		warn("[DataService] Session ownership lost for " .. player.Name .. "; refusing stale save")
		return false, "Session ownership lost"
	end
	if not saved then
		warn("[DataService] Failed to save " .. player.Name .. ": " .. tostring(lastError))
		return false, tostring(lastError)
	end
	return true
end

function DataService.getPlayerData(player)
	if not player or not player:IsA("Player") then
		return nil
	end
	return DataService._cache[player.UserId]
end

function DataService.getClientData(player)
	local data = DataService.getPlayerData(player)
	if not data then
		return nil
	end

	return {
		schemaVersion = data.schemaVersion,
		coins = data.coins,
		diamonds = data.diamonds,
		pets = DataSchema.deepCopy(data.pets),
		level = data.level,
		xp = data.xp,
		xpNeeded = (data.level or 1) * 100,
		equippedPets = DataSchema.deepCopy(data.equippedPets),
		unlockedZones = DataSchema.deepCopy(data.unlockedZones),
		upgrades = DataSchema.deepCopy(data.upgrades),
		upgradeTreePurchases = DataSchema.deepCopy(data.upgradeTreePurchases or {}),
		hatchPreferences = DataSchema.deepCopy(data.hatchPreferences or { preferredBatchCount = 1 }),
		questStats = DataSchema.deepCopy(data.questStats),
		campaignProgress = DataSchema.deepCopy(data.campaignProgress),
		masteryPoints = data.masteryPoints,
		masteryBuffs = DataSchema.deepCopy(data.masteryBuffs),
		discoveredPets = DataSchema.deepCopy(data.discoveredPets or {}),
		shopPurchases = DataSchema.deepCopy(data.shopPurchases or { extraEquipSlots = 0 }),
		potionInventory = DataSchema.deepCopy(data.potionInventory or {}),
		activeBuffs = DataSchema.deepCopy(data.activeBuffs or {}),
		potionUpgrades = DataSchema.deepCopy(data.potionUpgrades or {}),
	}
end

function DataService.onPlayerRemoving(player)
	DataService.savePlayerData(player, true)
	DataService._cache[player.UserId] = nil
	DataService._canSave[player.UserId] = nil
	DataService._saving[player.UserId] = nil
end

function DataService.startAutoSave()
	if DataService._useMemoryOnly then
		return
	end

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				if DataService._cache[player.UserId] and not DataService._saving[player.UserId] then
					task.spawn(DataService.savePlayerData, player, false)
				end
			end
		end
	end)
end

function DataService.bindToClose(beforeFinalSave)
	if DataService._useMemoryOnly then
		return
	end

	game:BindToClose(function()
		-- Transient economy owners must commit into cached profiles before any
		-- final save snapshots or releases those profiles.
		if type(beforeFinalSave) == "function" then
			local prepared, prepareResult = pcall(beforeFinalSave)
			if not prepared or prepareResult == false then
				warn("[DataService] Pre-save settlement did not complete for every player")
			end
		end

		local pending = 0
		for _, player in ipairs(Players:GetPlayers()) do
			if DataService._cache[player.UserId] then
				pending = pending + 1
				task.spawn(function()
					DataService.savePlayerData(player, true)
					pending = pending - 1
				end)
			end
		end

		local deadline = os.clock() + SHUTDOWN_TIMEOUT
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
