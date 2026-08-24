--[[
	DataService.lua - Player data persistence service
	Handles save/load with DataStoreService, caching, and auto-save.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(game.ReplicatedStorage.Shared.Config)

local DataService = {}

-- In-memory cache of player data
DataService._cache = {}

-- DataStore reference
local dataStore = DataStoreService:GetDataStore(Config.DataStoreName)

-- Default player data schema
local function getDefaultData()
	return {
		coins = 0,
		diamonds = 0,
		xp = 0,
		level = 1,
		pets = {},
		unlockedZones = {1},
		campaignProgress = {},
		upgrades = {},
		equippedPets = {},
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

-- Load player data from DataStore
function DataService.loadPlayerData(player)
	if not player or not player:IsA("Player") then
		return nil
	end

	local key = "Player_" .. tostring(player.UserId)
	local success, data = pcall(function()
		return dataStore:GetAsync(key)
	end)

	if success and data then
		-- Merge with defaults (handles new fields added after save)
		local defaults = getDefaultData()
		for field, defaultValue in pairs(defaults) do
			if data[field] == nil then
				data[field] = defaultValue
			end
		end
		DataService._cache[player.UserId] = data
	else
		-- Use defaults if load fails or no data exists
		DataService._cache[player.UserId] = getDefaultData()
		if not success then
			warn("[DataService] Failed to load data for " .. player.Name .. ": " .. tostring(data))
		end
	end

	return DataService._cache[player.UserId]
end

-- Save player data to DataStore
function DataService.savePlayerData(player)
	if not player or not player:IsA("Player") then
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
end

-- Periodic auto-save for all online players (every 60 seconds)
function DataService.startAutoSave()
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

return DataService
