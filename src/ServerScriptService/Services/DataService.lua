--[[
	DataService.lua - Conflict-safe player data persistence.
	Profiles remain bound to the exact Player instance that acquired them. Leave
	settlement is queued and retried before one releasing save; shutdown retries
	owners per profile so one unresolved user never suppresses unrelated saves.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(game.ReplicatedStorage.Shared.Config)
local ProgressionMath = require(game.ReplicatedStorage.Shared.ProgressionMath)
local DataSchema = require(script.Parent.DataSchema)
local ProfileTransactionService = require(script.Parent.ProfileTransactionService)

local DataService = {}

local MAX_RETRIES = 3
local AUTOSAVE_INTERVAL = Config.AutoSaveInterval or 60
local SESSION_LOCK_TIMEOUT = Config.SessionLockTimeout or 180
local SHUTDOWN_TIMEOUT = 25
local SESSION_ID = game.JobId ~= "" and game.JobId or ("studio_" .. HttpService:GenerateGUID(false))

DataService._cache = {}
DataService._canSave = {}
DataService._saving = {}
DataService._profilePlayers = {}
DataService._pendingProfiles = {}
DataService._departureWorkers = {}
DataService._mutationAdmissionClosed = {}
DataService._useMemoryOnly = false
DataService._departureRetryAttempts = 20
DataService._rejoinRetryAttempts = 20
DataService._shutdownMaxPasses = nil -- test-only seam; production retries to the deadline
DataService._shutdownTimeout = SHUTDOWN_TIMEOUT
DataService._clock = os.clock -- deterministic test seam for the shared shutdown deadline

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
	if type(session) ~= "table" or type(session.id) ~= "string" then return false end
	if session.id == SESSION_ID then return false end
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

local function clearProfile(userId)
	ProfileTransactionService.clearProfile(userId)
	DataService._cache[userId] = nil
	DataService._canSave[userId] = nil
	DataService._saving[userId] = nil
	DataService._profilePlayers[userId] = nil
	DataService._pendingProfiles[userId] = nil
	DataService._departureWorkers[userId] = nil
	DataService._mutationAdmissionClosed[userId] = nil
end

local function useStudioFallback(player)
	if not RunService:IsStudio() then return nil end
	DataService._useMemoryOnly = true
	local data = DataSchema.getDefaultData()
	DataService._cache[player.UserId] = data
	DataService._canSave[player.UserId] = false
	DataService._profilePlayers[player.UserId] = player
	warn("[DataService] Studio API access unavailable; switched to memory-only mode")
	return data
end

-- Atomically loads and locks a profile. A retained cache is never transferred to
-- a different Player instance: its pending old owner gets bounded retries first.
function DataService.loadPlayerData(player)
	if not player or not player:IsA("Player") then return nil, "Invalid player" end
	local userId = player.UserId
	local cached = DataService._cache[userId]
	if cached then
		local owner = DataService._profilePlayers[userId]
		if (owner == nil or owner == player) and DataService._pendingProfiles[userId] == nil then
			DataService._profilePlayers[userId] = player
			return cached
		end
		for _ = 1, DataService._rejoinRetryAttempts do
			if not DataService._cache[userId] then break end
			if DataService._pendingProfiles[userId] then
				DataService.processPendingProfile(userId)
			end
			if DataService._cache[userId] then task.wait(0.1) end
		end
		if DataService._cache[userId] then
			return nil, "Your previous session is still settling safely. Please rejoin shortly."
		end
	end

	if DataService._useMemoryOnly then
		local data = DataSchema.getDefaultData()
		DataService._cache[userId] = data
		DataService._canSave[userId] = false
		DataService._profilePlayers[userId] = player
		return data
	end

	local key = profileKey(userId)
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
		if success and type(result) == "table" and result._session
			and result._session.id == SESSION_ID then
			loadedData = result
			break
		end
		if lockConflict then break end
		lastError = result
		if attempt < MAX_RETRIES then task.wait(2 ^ attempt) end
	end

	if loadedData then
		DataService._cache[userId] = loadedData
		DataService._canSave[userId] = true
		DataService._profilePlayers[userId] = player
		return loadedData
	end
	DataService._canSave[userId] = false
	if lockConflict then
		warn("[DataService] Refused concurrent session for " .. player.Name)
		return nil, "Your data is still active on another server. Please wait a moment and rejoin."
	end
	local fallback = useStudioFallback(player)
	if fallback then return fallback end
	warn("[DataService] Failed to load " .. player.Name .. ": " .. tostring(lastError))
	return nil, "Your data could not be loaded safely. Please rejoin later."
end

-- Saves only while this server still owns the profile lock.
function DataService.savePlayerData(player, releaseLock)
	if not player or not player:IsA("Player") then return false, "Invalid player" end
	if DataService._useMemoryOnly then return false, "Memory-only mode" end
	if not DataService._canSave[player.UserId] then return false, "Profile is not saveable" end
	if not waitForCurrentSave(player.UserId) then return false, "Save already in progress" end
	local data = DataService._cache[player.UserId]
	if not data then return false, "No cached data" end

	DataService._saving[player.UserId] = true
	-- The save flag closes the opposite side of the begin/save race: a new owner
	-- cannot start after this point, and an existing owner blocks before cloning.
	if ProfileTransactionService.hasPending(player) then
		DataService._saving[player.UserId] = nil
		return false, "Profile transaction pending"
	end
	if not releaseLock and DataService._pendingProfiles[player.UserId] ~= nil then
		DataService._saving[player.UserId] = nil
		return false, "Profile departure pending"
	end
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
				if releaseLock then snapshot._session = nil else snapshot._session = newSessionMetadata() end
				return snapshot
			end)
		end)
		if success and not sessionLost and type(result) == "table" then
			saved = true
			if not releaseLock then data._session = DataSchema.deepCopy(snapshot._session) end
			break
		end
		if sessionLost then break end
		lastError = result
		if attempt < MAX_RETRIES then task.wait(2 ^ attempt) end
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

function DataService.isProfileSaveInProgress(player)
	return player ~= nil and DataService._saving[player.UserId] == true
end

function DataService.closeMutationAdmission(player)
	if not player or not player:IsA("Player") then return false end
	local userId = player.UserId
	local owner = DataService._profilePlayers[userId]
	if owner ~= nil and owner ~= player then return false end
	if DataService._cache[userId] == nil then return false end
	DataService._profilePlayers[userId] = owner or player
	DataService._mutationAdmissionClosed[userId] = player
	return ProfileTransactionService.closeAdmission(player)
end

function DataService.isMutationAdmissionOpen(player)
	if not player or not player:IsA("Player") then return false end
	local userId = player.UserId
	local owner = DataService._profilePlayers[userId]
	return DataService._cache[userId] ~= nil
		and (owner == nil or owner == player)
		and DataService._mutationAdmissionClosed[userId] == nil
		and ProfileTransactionService.isAdmissionOpen(player)
		and DataService._pendingProfiles[userId] == nil
end

function DataService.getPlayerData(player)
	if not player or not player:IsA("Player") then return nil end
	local owner = DataService._profilePlayers[player.UserId]
	if owner ~= nil and owner ~= player then return nil end
	return DataService._cache[player.UserId]
end

function DataService.getClientData(player)
	local data = DataService.getPlayerData(player)
	if not data then return nil end
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
		upgrades = ProgressionMath.normalizeQuestLevels(data.upgrades),
		upgradeTreePurchases = DataSchema.deepCopy(data.upgradeTreePurchases or {}),
		hatchPreferences = DataSchema.deepCopy(data.hatchPreferences or { preferredBatchCount = 1 }),
		autoHatchExpiresAt = data.autoHatchExpiresAt or 0,
		questStats = DataSchema.deepCopy(data.questStats),
		campaignProgress = DataSchema.deepCopy(data.campaignProgress),
		masteryPoints = data.masteryPoints,
		masteryBuffs = ProgressionMath.normalizeMasteryLevels(data.masteryBuffs),
		discoveredPets = DataSchema.deepCopy(data.discoveredPets or {}),
		shopPurchases = DataSchema.deepCopy(data.shopPurchases or { extraEquipSlots = 0 }),
		potionInventory = DataSchema.deepCopy(data.potionInventory or {}),
		activeBuffs = DataSchema.deepCopy(data.activeBuffs or {}),
		potionUpgrades = DataSchema.deepCopy(data.potionUpgrades or {}),
		autoDrinkSelection = DataSchema.deepCopy(data.autoDrinkSelection or {}),
	}
end

local function attemptPendingRecord(record)
	if record.completed then return true end
	if record.settling then return false end
	record.settling = true
	if not record.settled then
		local ok, settled = pcall(record.settle, record.player)
		local profileSettled = ok and settled == true
			and ProfileTransactionService.settlePlayer(record.player)
		if not profileSettled then
			record.attempts = record.attempts + 1
			record.lastError = ok and "Settlement unresolved" or tostring(settled)
			record.settling = false
			return false
		end
		record.settled = true
	end

	local saved = true
	local saveError = nil
	if not DataService._useMemoryOnly then
		saved, saveError = DataService.savePlayerData(record.player, true)
	end
	if saved then
		record.completed = true
		record.settling = false
		clearProfile(record.userId)
		return true
	end
	record.attempts = record.attempts + 1
	record.lastError = saveError
	record.settling = false
	return false
end

function DataService.processPendingProfile(userId)
	local record = DataService._pendingProfiles[userId]
	if not record then return DataService._cache[userId] == nil end
	return attemptPendingRecord(record)
end

local function scheduleDepartureRetries(userId)
	if DataService._departureWorkers[userId] then return end
	DataService._departureWorkers[userId] = true
	task.spawn(function()
		for _ = 1, DataService._departureRetryAttempts do
			if not DataService._pendingProfiles[userId] then break end
			task.wait(0.25)
			if DataService.processPendingProfile(userId) then break end
		end
		DataService._departureWorkers[userId] = nil
	end)
end

-- Registers one profile owner. Settlement and the releasing save are retried;
-- cache/Player identity remain held until both have succeeded exactly once.
function DataService.onPlayerRemoving(player, settleCallback)
	if not player or not player:IsA("Player") then return false end
	local userId = player.UserId
	if not DataService.closeMutationAdmission(player) then return false end
	local existing = DataService._pendingProfiles[userId]
	if existing then
		if existing.player ~= player then return false end
		return DataService.processPendingProfile(userId)
	end
	DataService._profilePlayers[userId] = DataService._profilePlayers[userId] or player
	DataService._pendingProfiles[userId] = {
		userId = userId,
		player = player,
		settle = type(settleCallback) == "function" and settleCallback or function() return true end,
		settled = false,
		settling = false,
		completed = false,
		attempts = 0,
	}
	local completed = DataService.processPendingProfile(userId)
	if not completed then scheduleDepartureRetries(userId) end
	return completed
end

function DataService.startAutoSave()
	if DataService._useMemoryOnly then return end
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				if DataService._cache[player.UserId]
					and not DataService._pendingProfiles[player.UserId]
					and not ProfileTransactionService.hasPending(player)
					and not DataService._saving[player.UserId] then
					task.spawn(DataService.savePlayerData, player, false)
				end
			end
		end
	end)
end

-- lifecycle may be a compatibility function(player), or a table containing
-- beginShutdown() and settlePlayer(player). Each cached profile (including a
-- departed retained owner) is retried independently until the shared deadline.
function DataService.bindToClose(lifecycle)
	if DataService._useMemoryOnly then return end
	game:BindToClose(function()
		-- Close the central mutation boundary for every profile before any owner is
		-- observed as settled or any releasing snapshot can be taken.
		for userId in pairs(DataService._cache) do
			local profilePlayer = DataService._profilePlayers[userId]
			if not profilePlayer then
				for _, candidate in ipairs(Players:GetPlayers()) do
					if candidate.UserId == userId then profilePlayer = candidate break end
				end
			end
			if profilePlayer then DataService.closeMutationAdmission(profilePlayer) end
		end

		local beginShutdown = type(lifecycle) == "table" and lifecycle.beginShutdown or nil
		local settlePlayer = type(lifecycle) == "table" and lifecycle.settlePlayer
			or (type(lifecycle) == "function" and lifecycle or function() return true end)
		if type(beginShutdown) == "function" then
			local ok, result = pcall(beginShutdown)
			if not ok or result == false then
				warn("[DataService] Shutdown admission gate could not be confirmed; profiles remain fail-closed")
				return
			end
		end

		for userId in pairs(DataService._cache) do
			if not DataService._pendingProfiles[userId] then
				local profilePlayer = DataService._profilePlayers[userId]
				if not profilePlayer then
					for _, candidate in ipairs(Players:GetPlayers()) do
						if candidate.UserId == userId then profilePlayer = candidate break end
					end
				end
				if profilePlayer then
					DataService._pendingProfiles[userId] = {
						userId = userId,
						player = profilePlayer,
						settle = settlePlayer,
						settled = false,
						settling = false,
						completed = false,
						attempts = 0,
					}
				end
			end
		end

		local deadline = DataService._clock() + DataService._shutdownTimeout
		local pendingWorkers = 0
		local userIds = {}
		for userId in pairs(DataService._pendingProfiles) do table.insert(userIds, userId) end
		for _, userId in ipairs(userIds) do
			pendingWorkers = pendingWorkers + 1
			task.spawn(function()
				local pass = 0
				while DataService._clock() < deadline
					and (DataService._shutdownMaxPasses == nil
						or pass < DataService._shutdownMaxPasses) do
					pass = pass + 1
					if DataService.processPendingProfile(userId) then break end
					task.wait(0.1)
				end
				pendingWorkers = pendingWorkers - 1
			end)
		end
		while pendingWorkers > 0 and DataService._clock() < deadline do task.wait(0.05) end
		for userId, record in pairs(DataService._pendingProfiles) do
			warn("[DataService] Shutdown left profile " .. tostring(userId)
				.. " held fail-closed: " .. tostring(record.lastError or "settlement deadline"))
		end
	end)
end

-- DataService owns the profile incarnation; initialize the central transaction
-- registry only after every admission/save callback above has been defined.
ProfileTransactionService.init(DataService)

return DataService
