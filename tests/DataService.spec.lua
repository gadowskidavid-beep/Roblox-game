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
local playersService = {}
function playersService:GetPlayers()
	return {}
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
	it("projects hatchPreferences as a deep copy without private session state", function()
		local profile = {
			schemaVersion = 7,
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
			potionInventory = {},
			activeBuffs = {},
			potionUpgrades = {},
			_session = { id = "private" },
		}
		DataService._cache[player.UserId] = profile

		local projected = DataService.getClientData(player)
		expect(projected.hatchPreferences):toEqual({ preferredBatchCount = 5 })
		expect(projected._session):toBeNil()
		projected.hatchPreferences.preferredBatchCount = 1
		expect(profile.hatchPreferences.preferredBatchCount):toBe(5)
	end)
end)
