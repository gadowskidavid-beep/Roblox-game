--[[
	DataService.lua - Player data persistence service
	Handles save/load with DataStoreService, caching, and auto-save.
	Falls back to memory-only (session) storage when DataStore is unavailable
	(e.g. unpublished places or Studio testing).
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(game.ReplicatedStorage.Shared.Config)

local DataService = {}

-- In-memory cache of player data
DataService._cache = {}

-- Track whether a player's data loaded successfully (prevents overwriting real saves with defaults)
DataService._canSave = {}

-- Flag: if true, DataStore is unavailable and we operate in memory-only mode
DataService._useMemoryOnly = false

-- DataStore reference (may be nil if unavailable)
local dataStore = nil

-- Attempt to acquire DataStore handle safely
local dsSuccess, dsResult = pcall(function()
	return DataStoreService:GetDataStore(Config.DataStoreName)
end)

if dsSuccess then
	dataStore = dsResult
else
	DataService._useMemoryOnly = true
	warn("[DataService] DataStore unavailable - running in memory-only mode (session data will not persist). Reason: " .. tostring(dsResult))
end

-- Default player data schema
local function getDefaultData()
	local starterPet = {
		id = "starter_pet_1",
		petId = "Buddy",
		name = "Buddy",
		rarity = "Common",
		damage = 5,
		equipped = true,
	}

	return {
		coins = 0,
		diamonds = 0,
		xp = 0,
		level = 1,
		pets = { starterPet },
		unlockedZones = {1},
		campaignProgress = {},
		upgrades = {},
		equippedPets = { "starter_pet_1" },
	}
end

-- Deep copy a table
local function deepCopy(original)
	local copy = {}
	for key, value in pairs(original) do
		if type(value) == "table" then
			copy[key] = deepCopy(value)
		else
			copy[key] = value
		end
	end
	return copy
end

-- Load player data from DataStore with retry logic
function DataService.loadPlayerData(player)
	if not player or not player:IsA("Player") then
		return nil
	end

	-- Memory-only mode: just give defaults immediately
	if DataService._useMemoryOnly then
		DataService._cache[player.UserId] = getDefaultData()
		DataService._canSave[player.UserId] = false
		return DataService._cache[player.UserId]
	end

	local key = "Player_" .. tostring(player.UserId)
	local MAX_RETRIES = 3
	local success, data = false, nil

	for attempt = 1, MAX_RETRIES do
		success, data = pcall(function()
			return dataStore:GetAsync(key)
		end)
		if success then
			break
		end
		if attempt < MAX_RETRIES then
			task.wait(2 ^ attempt) -- Exponential backoff: 2s, 4s
		end
	end

	if success and data then
		-- Merge with defaults (handles new fields added after save)
		local defaults = getDefaultData()
		for field, defaultValue in pairs(defaults) do
			if data[field] == nil then
				data[field] = defaultValue
			end
		end
		DataService._cache[player.UserId] = data
		DataService._canSave[player.UserId] = true
	elseif success and not data then
		-- No existing save, new player - safe to save defaults
		DataService._cache[player.UserId] = getDefaultData()
		DataService._canSave[player.UserId] = true
	else
		-- Load failed after all retries - use defaults but do NOT allow saving
		DataService._cache[player.UserId] = getDefaultData()
		DataService._canSave[player.UserId] = false
		warn("[DataService] Failed to load data for " .. player.Name .. " after " .. MAX_RETRIES .. " retries: " .. tostring(data))
	end

	return DataService._cache[player.UserId]
end

-- Save player data to DataStore
function DataService.savePlayerData(player)
	if not player or not player:IsA("Player") then
		return false
	end

	-- Guard: skip save in memory-only mode
	if DataService._useMemoryOnly then
		return false
	end

	-- Guard: do not save if initial load failed (prevents overwriting real data with defaults)
	if not DataService._canSave[player.UserId] then
		warn("[DataService] Skipping save for " .. player.Name .. " - initial load failed")
		return false
	end

	local data = DataService._cache[player.UserId]
	if not data then
		return false
	end

	local key = "Player_" .. tostring(player.UserId)
	local success, err = pcall(function()
		dataStore:SetAsync(key, data)
	end)

	if not success then
		warn("[DataService] Failed to save data for " .. player.Name .. ": " .. tostring(err))
	end

	return success
end

-- Get cached player data (does not hit DataStore)
function DataService.getPlayerData(player)
	if not player or not player:IsA("Player") then
		return nil
	end
	return DataService._cache[player.UserId]
end

-- Called when player leaves - save and cleanup
function DataService.onPlayerRemoving(player)
	DataService.savePlayerData(player)
	DataService._cache[player.UserId] = nil
	DataService._canSave[player.UserId] = nil
end

-- Periodic auto-save for all online players (every 60 seconds)
function DataService.startAutoSave()
	-- No need to auto-save in memory-only mode
	if DataService._useMemoryOnly then
		return
	end

	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in ipairs(Players:GetPlayers()) do
				if DataService._cache[player.UserId] then
					DataService.savePlayerData(player)
				end
			end
		end
	end)
end

-- Bind to server shutdown: save all players before the server exits
function DataService.bindToClose()
	-- No need to bind in memory-only mode
	if DataService._useMemoryOnly then
		return
	end

	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			if DataService._cache[player.UserId] then
				DataService.savePlayerData(player)
			end
		end
	end)
end

return DataService
