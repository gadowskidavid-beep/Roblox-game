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


describe("DataService fail-closed shutdown settlement", function()
	it("skips final profile saves when pre-save settlement is unresolved", function()
		local originalTask = rawget(_G, "task")
		local originalWarn = rawget(_G, "warn")
		local originalBindToClose = gameMock.BindToClose
		local originalSavePlayerData = DataService.savePlayerData
		local originalUseMemoryOnly = DataService._useMemoryOnly
		local originalPasses = DataService._shutdownMaxPasses
		local originalCache = DataService._cache[player.UserId]
		local originalPlayers = {}
		for index, existingPlayer in ipairs(currentPlayers) do
			originalPlayers[index] = existingPlayer
		end
		local closeCallback = nil
		local saveCalls = 0
		local ok, testError = pcall(function()
			for index = #currentPlayers, 1, -1 do currentPlayers[index] = nil end
			currentPlayers[1] = player
			DataService._cache[player.UserId] = originalCache or {}
			DataService._useMemoryOnly = false
			DataService._shutdownMaxPasses = 2
			gameMock.BindToClose = function(_, callback) closeCallback = callback end
			DataService.savePlayerData = function()
				saveCalls = saveCalls + 1
				return true
			end
			rawset(_G, "warn", function() end)
			rawset(_G, "task", {
				spawn = function(callback, ...) return callback(...) end,
				wait = function() end,
			})
			DataService.bindToClose(function() return false end)
			expect(type(closeCallback)):toBe("function")
			closeCallback()
			expect(saveCalls):toBe(0)
		end)
		rawset(_G, "task", originalTask)
		rawset(_G, "warn", originalWarn)
		gameMock.BindToClose = originalBindToClose
		DataService.savePlayerData = originalSavePlayerData
		DataService._useMemoryOnly = originalUseMemoryOnly
		DataService._shutdownMaxPasses = originalPasses
		DataService._cache[player.UserId] = originalCache
		DataService._pendingProfiles[player.UserId] = nil
		DataService._profilePlayers[player.UserId] = nil
		DataService._mutationAdmissionClosed[player.UserId] = nil
		for index = #currentPlayers, 1, -1 do currentPlayers[index] = nil end
		for index, existingPlayer in ipairs(originalPlayers) do currentPlayers[index] = existingPlayer end
		if not ok then error(testError, 0) end
	end)
end)



local function lifecyclePlayer(userId, name)
	local value = { UserId = userId, Name = name or ("Player" .. tostring(userId)) }
	function value:IsA(className) return className == "Player" end
	return value
end

describe("DataService retrying profile lifecycle", function()
	it("retries a transient leave settlement and performs exactly one releasing save", function()
		local departing = lifecyclePlayer(101, "Transient")
		local originalTask = rawget(_G, "task")
		local originalSave = DataService.savePlayerData
		local spawnedWorker = nil
		local settleCalls = 0
		local saveCalls = 0
		DataService._cache[101] = { marker = "held" }
		DataService._canSave[101] = true
		DataService._profilePlayers[101] = departing
		rawset(_G, "task", {
			spawn = function(callback) spawnedWorker = callback end,
			wait = function() end,
		})
		DataService.savePlayerData = function(candidate, releaseLock)
			expect(candidate):toBe(departing)
			expect(releaseLock):toBeTrue()
			saveCalls = saveCalls + 1
			return true
		end
		local first = DataService.onPlayerRemoving(departing, function()
			settleCalls = settleCalls + 1
			return settleCalls >= 2
		end)
		expect(first):toBeFalse()
		expect(type(spawnedWorker)):toBe("function")
		expect(saveCalls):toBe(0)
		expect(DataService.processPendingProfile(101)):toBeTrue()
		expect(settleCalls):toBe(2)
		expect(saveCalls):toBe(1)
		expect(DataService._cache[101]):toBeNil()
		expect(DataService.processPendingProfile(101)):toBeTrue()
		expect(saveCalls):toBe(1)
		DataService.savePlayerData = originalSave
		rawset(_G, "task", originalTask)
	end)

	it("retains a permanent failure and refuses a new Player instance for the same user", function()
		local departing = lifecyclePlayer(102, "Old")
		local rejoin = lifecyclePlayer(102, "New")
		local originalTask = rawget(_G, "task")
		local originalSave = DataService.savePlayerData
		local originalRetries = DataService._rejoinRetryAttempts
		local saveCalls = 0
		DataService._cache[102] = { marker = "old-player-only" }
		DataService._canSave[102] = true
		DataService._profilePlayers[102] = departing
		rawset(_G, "task", { spawn = function() end, wait = function() end })
		DataService.savePlayerData = function()
			saveCalls = saveCalls + 1
			return true
		end
		DataService._rejoinRetryAttempts = 2
		expect(DataService.onPlayerRemoving(departing, function() return false end)):toBeFalse()
		local loaded, loadError = DataService.loadPlayerData(rejoin)
		expect(loaded):toBeNil()
		expect(string.find(loadError, "still settling", 1, true) ~= nil):toBeTrue()
		expect(DataService.getPlayerData(rejoin)):toBeNil()
		expect(DataService.getPlayerData(departing).marker):toBe("old-player-only")
		expect(saveCalls):toBe(0)
		DataService._pendingProfiles[102] = nil
		DataService._cache[102] = nil
		DataService._canSave[102] = nil
		DataService._profilePlayers[102] = nil
		DataService.savePlayerData = originalSave
		DataService._rejoinRetryAttempts = originalRetries
		rawset(_G, "task", originalTask)
	end)

	it("retries an executing owner at shutdown while saving an independent profile immediately", function()
		local firstPlayer = lifecyclePlayer(103, "Executing")
		local secondPlayer = lifecyclePlayer(104, "Independent")
		local originalTask = rawget(_G, "task")
		local originalBind = gameMock.BindToClose
		local originalSave = DataService.savePlayerData
		local originalPasses = DataService._shutdownMaxPasses
		local closeCallback = nil
		local settleCalls = { [103] = 0, [104] = 0 }
		local saves = {}
		for _, candidate in ipairs({ firstPlayer, secondPlayer }) do
			DataService._cache[candidate.UserId] = { marker = candidate.Name }
			DataService._canSave[candidate.UserId] = true
			DataService._profilePlayers[candidate.UserId] = candidate
		end
		for index = #currentPlayers, 1, -1 do currentPlayers[index] = nil end
		currentPlayers[1] = firstPlayer
		currentPlayers[2] = secondPlayer
		gameMock.BindToClose = function(_, callback) closeCallback = callback end
		rawset(_G, "task", { spawn = function(callback, ...) return callback(...) end, wait = function() end })
		DataService.savePlayerData = function(candidate, releaseLock)
			expect(releaseLock):toBeTrue()
			saves[candidate.UserId] = (saves[candidate.UserId] or 0) + 1
			return true
		end
		DataService._shutdownMaxPasses = 3
		DataService.bindToClose({
			beginShutdown = function() return true end,
			settlePlayer = function(candidate)
				settleCalls[candidate.UserId] = settleCalls[candidate.UserId] + 1
				return candidate.UserId ~= 103 or settleCalls[103] >= 2
			end,
		})
		closeCallback()
		expect(settleCalls[103]):toBe(2)
		expect(settleCalls[104]):toBe(1)
		expect(saves[103]):toBe(1)
		expect(saves[104]):toBe(1)
		DataService.savePlayerData = originalSave
		DataService._shutdownMaxPasses = originalPasses
		gameMock.BindToClose = originalBind
		rawset(_G, "task", originalTask)
		for index = #currentPlayers, 1, -1 do currentPlayers[index] = nil end
	end)

	it("uses the full shutdown deadline while isolating immediate and permanent profiles", function()
		local delayed = lifecyclePlayer(106, "Delayed")
		local immediate = lifecyclePlayer(107, "Immediate")
		local permanent = lifecyclePlayer(108, "Permanent")
		local originalTask = rawget(_G, "task")
		local originalWarn = rawget(_G, "warn")
		local originalBind = gameMock.BindToClose
		local originalSave = DataService.savePlayerData
		local originalPasses = DataService._shutdownMaxPasses
		local originalClock = DataService._clock
		local originalTimeout = DataService._shutdownTimeout
		local closeCallback = nil
		local now = 0
		local workers = {}
		local saves = {}

		for _, candidate in ipairs({ delayed, immediate, permanent }) do
			DataService._cache[candidate.UserId] = { marker = candidate.Name }
			DataService._canSave[candidate.UserId] = true
			DataService._profilePlayers[candidate.UserId] = candidate
		end
		for index = #currentPlayers, 1, -1 do currentPlayers[index] = nil end
		currentPlayers[1] = delayed
		currentPlayers[2] = immediate
		currentPlayers[3] = permanent
		DataService._clock = function() return now end
		DataService._shutdownTimeout = 25
		DataService._shutdownMaxPasses = nil
		gameMock.BindToClose = function(_, callback) closeCallback = callback end
		rawset(_G, "warn", function() end)
		rawset(_G, "task", {
			spawn = function(callback, ...)
				local arguments = { ... }
				table.insert(workers, coroutine.create(function()
					callback(table.unpack(arguments))
				end))
			end,
			wait = function(duration)
				local _, isMain = coroutine.running()
				if not isMain then return coroutine.yield() end
				now = now + (duration or 0)
				for index = #workers, 1, -1 do
					local worker = workers[index]
					local resumed, workerError = coroutine.resume(worker)
					if not resumed then error(workerError, 0) end
					if coroutine.status(worker) == "dead" then
						table.remove(workers, index)
					end
				end
			end,
		})
		DataService.savePlayerData = function(candidate, releaseLock)
			expect(releaseLock):toBeTrue()
			saves[candidate.UserId] = now
			return true
		end

		DataService.bindToClose({
			beginShutdown = function() return true end,
			settlePlayer = function(candidate)
				if candidate == delayed then return now >= 12 end
				return candidate == immediate
			end,
		})
		closeCallback()

		expect(saves[107] <= 0.1):toBeTrue()
		expect(saves[106] >= 12 and saves[106] < 25):toBeTrue()
		expect(saves[108]):toBeNil()
		expect(DataService._cache[108] ~= nil):toBeTrue()
		expect(DataService._pendingProfiles[108] ~= nil):toBeTrue()
		expect(now >= 25):toBeTrue()

		DataService.savePlayerData = originalSave
		DataService._shutdownMaxPasses = originalPasses
		DataService._shutdownTimeout = originalTimeout
		DataService._clock = originalClock
		gameMock.BindToClose = originalBind
		rawset(_G, "warn", originalWarn)
		rawset(_G, "task", originalTask)
		for _, userId in ipairs({ 106, 107, 108 }) do
			DataService._cache[userId] = nil
			DataService._canSave[userId] = nil
			DataService._profilePlayers[userId] = nil
			DataService._pendingProfiles[userId] = nil
			DataService._departureWorkers[userId] = nil
			DataService._mutationAdmissionClosed[userId] = nil
		end
		for index = #currentPlayers, 1, -1 do currentPlayers[index] = nil end
	end)

	it("settles and releases a departed pending profile during shutdown", function()
		local departing = lifecyclePlayer(105, "Departed")
		local originalTask = rawget(_G, "task")
		local originalBind = gameMock.BindToClose
		local originalSave = DataService.savePlayerData
		local closeCallback = nil
		local allowSettlement = false
		local saveCalls = 0
		DataService._cache[105] = { marker = "departed-cache" }
		DataService._canSave[105] = true
		DataService._profilePlayers[105] = departing
		for index = #currentPlayers, 1, -1 do currentPlayers[index] = nil end
		rawset(_G, "task", { spawn = function() end, wait = function() end })
		DataService.savePlayerData = function(candidate, releaseLock)
			expect(candidate):toBe(departing)
			expect(releaseLock):toBeTrue()
			saveCalls = saveCalls + 1
			return true
		end
		expect(DataService.onPlayerRemoving(departing, function()
			return allowSettlement
		end)):toBeFalse()
		allowSettlement = true
		-- Leave retry worker was intentionally suppressed; shutdown workers execute.
		rawset(_G, "task", {
			spawn = function(callback, ...) return callback(...) end,
			wait = function() end,
		})
		gameMock.BindToClose = function(_, callback) closeCallback = callback end
		DataService.bindToClose({ beginShutdown = function() return true end })
		closeCallback()
		expect(saveCalls):toBe(1)
		expect(DataService._cache[105]):toBeNil()
		expect(DataService._pendingProfiles[105]):toBeNil()
		DataService.savePlayerData = originalSave
		gameMock.BindToClose = originalBind
		rawset(_G, "task", originalTask)
	end)
end)
