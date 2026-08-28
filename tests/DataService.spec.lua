-- DataService.spec.lua - Focused QOF-09 client projection contract.

local originalRequire = require
local Config = {
	AutoSaveInterval = 60,
	SessionLockTimeout = 180,
	DataStoreName = "TestStore",
}
local DataSchema = {}
function DataSchema.deepCopy(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for key, child in pairs(value) do
		copy[DataSchema.deepCopy(key)] = DataSchema.deepCopy(child)
	end
	return copy
end

local dataStoreService = {}
function dataStoreService:GetDataStore()
	return {}
end
local httpService = {}
function httpService:GenerateGUID()
	return "test-guid"
end
local currentPlayers = {}
local playersService = {}
function playersService:GetPlayers()
	return currentPlayers
end
local runService = {}
function runService:IsStudio()
	return false
end

local SharedMock = { Config = Config }
local ServicesMock = { DataSchema = DataSchema }
local gameMock = {
	JobId = "test-job",
	PlaceId = 1,
	ReplicatedStorage = { Shared = SharedMock },
}
function gameMock:GetService(name)
	if name == "DataStoreService" then return dataStoreService end
	if name == "HttpService" then return httpService end
	if name == "Players" then return playersService end
	if name == "RunService" then return runService end
	error("Unexpected service: " .. tostring(name))
end
rawset(_G, "game", gameMock)
rawset(_G, "script", { Parent = ServicesMock })

local function mockRequire(path)
	if path == Config then return Config end
	if path == DataSchema then return DataSchema end
	return originalRequire(path)
end
rawset(_G, "require", mockRequire)
local DataService = originalRequire("src/ServerScriptService/Services/DataService")
rawset(_G, "require", originalRequire)

local player = { UserId = 42 }
function player:IsA(className)
	return className == "Player"
end

describe("DataService QOF-09 client projection", function()
	it("projects hatch and potion state as deep copies without private session state", function()
		local profile = {
			schemaVersion = 8,
			coins = 10,
			diamonds = 2,
			pets = {},
			level = 1,
			xp = 0,
			equippedPets = {},
			unlockedZones = { 1 },
			upgrades = {},
			upgradeTreePurchases = {},
			hatchPreferences = { preferredBatchCount = 5 },
			questStats = {},
			campaignProgress = {},
			masteryPoints = 0,
			masteryBuffs = {},
			discoveredPets = {},
			shopPurchases = {},
			potionInventory = { LuckPotion = 4 },
			activeBuffs = { luck = { sources = { LuckPotion = { expiresAt = 1500 } } } },
			potionBuffSources = { LuckPotion = { expiresAt = 1500 } },
			potionUpgrades = { slots = 3, durationLevel = 1, autoDrink = false },
			autoDrinkSelection = { LuckPotion = true },
			_session = { id = "private" },
		}
		DataService._cache[player.UserId] = profile

		local projected = DataService.getClientData(player)
		expect(projected.hatchPreferences):toEqual({ preferredBatchCount = 5 })
		expect(projected.potionInventory):toEqual({ LuckPotion = 4 })
		expect(projected.activeBuffs):toEqual({ luck = { sources = { LuckPotion = { expiresAt = 1500 } } } })
		expect(projected.potionUpgrades):toEqual({ slots = 3, durationLevel = 1, autoDrink = false })
		expect(projected.autoDrinkSelection):toEqual({ LuckPotion = true })
		expect(projected.potionBuffSources):toBeNil()
		expect(projected._session):toBeNil()
		projected.hatchPreferences.preferredBatchCount = 1
		projected.potionInventory.LuckPotion = 1
		projected.activeBuffs.luck.sources.LuckPotion.expiresAt = 1
		projected.potionUpgrades.slots = 5
		projected.autoDrinkSelection.LuckPotion = nil
		expect(profile.hatchPreferences.preferredBatchCount):toBe(5)
		expect(profile.potionInventory.LuckPotion):toBe(4)
		expect(profile.activeBuffs.luck.sources.LuckPotion.expiresAt):toBe(1500)
		expect(profile.potionUpgrades.slots):toBe(3)
		expect(profile.autoDrinkSelection.LuckPotion):toBeTrue()
	end)
end)

describe("DataService shutdown persistence", function()
	it("runs the pre-save hook before the final releasing save", function()
		local originalTask = rawget(_G, "task")
		local originalBindToClose = gameMock.BindToClose
		local originalSavePlayerData = DataService.savePlayerData
		local originalUseMemoryOnly = DataService._useMemoryOnly
		local originalCache = DataService._cache[player.UserId]
		local originalPlayers = {}
		for index, existingPlayer in ipairs(currentPlayers) do
			originalPlayers[index] = existingPlayer
		end

		local closeCallback = nil
		local events = {}
		local savedPlayer = nil
		local releasedLock = nil

		local ok, testError = pcall(function()
			for index = #currentPlayers, 1, -1 do
				currentPlayers[index] = nil
			end
			currentPlayers[1] = player
			DataService._cache[player.UserId] = originalCache or {}
			DataService._useMemoryOnly = false

			gameMock.BindToClose = function(_, callback)
				closeCallback = callback
			end
			DataService.savePlayerData = function(candidate, releaseLock)
				table.insert(events, "savePlayerData")
				savedPlayer = candidate
				releasedLock = releaseLock
				return true
			end
			rawset(_G, "task", {
				spawn = function(callback, ...)
					return callback(...)
				end,
				wait = function() end,
			})

			DataService.bindToClose(function()
				table.insert(events, "beforeFinalSave")
				return true
			end)
			expect(type(closeCallback)):toBe("function")

			closeCallback()

			expect(events):toEqual({ "beforeFinalSave", "savePlayerData" })
			expect(savedPlayer):toBe(player)
			expect(releasedLock):toBeTrue()
		end)

		rawset(_G, "task", originalTask)
		gameMock.BindToClose = originalBindToClose
		DataService.savePlayerData = originalSavePlayerData
		DataService._useMemoryOnly = originalUseMemoryOnly
		DataService._cache[player.UserId] = originalCache
		for index = #currentPlayers, 1, -1 do
			currentPlayers[index] = nil
		end
		for index, existingPlayer in ipairs(originalPlayers) do
			currentPlayers[index] = existingPlayer
		end

		if not ok then
			error(testError, 0)
		end
	end)
end)
