local originalRequire = require
local BalanceConfig = originalRequire("src/ReplicatedStorage/Shared/BalanceConfig")

local updates = {}
local updateEvent = {}
function updateEvent:FireClient(_, state)
	table.insert(updates, state)
end
local remotes = {}
function remotes:FindFirstChild(name)
	if name == "AutoHatchStateUpdated" then return updateEvent end
	return nil
end
local replicatedStorage = { Shared = { BalanceConfig = BalanceConfig } }
function replicatedStorage:FindFirstChild(name)
	if name == "Remotes" then return remotes end
	return nil
end
local players = {}
local gameMock = { ReplicatedStorage = replicatedStorage }
function gameMock:GetService(name)
	if name == "Players" then return players end
	if name == "ReplicatedStorage" then return replicatedStorage end
	error("Unexpected service " .. tostring(name))
end
rawset(_G, "game", gameMock)
rawset(_G, "task", {
	spawn = function(callback) callback() end,
	wait = function() end,
})
rawset(_G, "require", function(path)
	if path == BalanceConfig then return BalanceConfig end
	return originalRequire(path)
end)
local AutoHatchService = originalRequire("src/ServerScriptService/Services/AutoHatchService")
rawset(_G, "require", originalRequire)

local player = { UserId = 1801, Name = "AutoTester" }
function player:IsA(className) return className == "Player" end
function players:GetPlayers() return { player } end
local now = 1000
local profile = nil
local pendingCurrency = {}
local commits = 0
local rollbacks = 0
local hatchCalls = {}
local hatchError = nil
local maximumCount = 10
local stationAllowed = true
local stationReason = "STATION_INVALID"
local spawnQueue = {}
local schedulerCallback = nil

local dataService = {}
function dataService.getPlayerData() return profile end

local currencyService = {}
function currencyService.beginSpendTransaction(_, currency, amount)
	expect(currency):toBe("diamonds")
	expect(amount):toBe(500)
	if profile.diamonds < amount then return nil end
	profile.diamonds = profile.diamonds - amount
	local handle = {}
	pendingCurrency[handle] = amount
	return handle
end
function currencyService.commitSpendTransaction(handle)
	if not pendingCurrency[handle] then return false end
	pendingCurrency[handle] = nil
	commits = commits + 1
	return true
end
function currencyService.rollbackSpendTransaction(handle)
	local amount = pendingCurrency[handle]
	if not amount then return false end
	pendingCurrency[handle] = nil
	profile.diamonds = profile.diamonds + amount
	rollbacks = rollbacks + 1
	return true
end

local eggService = {}
function eggService.getBatchState()
	return {
		selectedCount = profile.hatchPreferences.preferredBatchCount,
		maximumCount = maximumCount,
		availableCounts = { 1, 2, 5, 10 },
	}
end
function eggService.setSelectedBatchCount(_, count)
	if count ~= 1 and count ~= 2 and count ~= 5 and count ~= 10 then
		return false, "Invalid hatch count"
	end
	if count > maximumCount then return false, "Multi-Open upgrade required" end
	profile.hatchPreferences.preferredBatchCount = count
	return true
end
function eggService.purchaseAndHatch(_, eggType, count, options)
	table.insert(hatchCalls, { eggType = eggType, count = count, options = options })
	if hatchError then return nil, hatchError end
	return { batchId = "auto:" .. tostring(#hatchCalls), eggType = eggType, count = count, pets = {} }
end

local stationAuthority = {}
function stationAuthority.validateSelection(_, stationId, token, expectedEggType, expectedZone, requireProximity)
	if not stationAllowed then return nil, stationReason end
	if stationId ~= "EggStation-1-BasicEgg" or token ~= "station-guid" then
		return nil, "STATION_INVALID"
	end
	if expectedEggType ~= nil and expectedEggType ~= "BasicEgg" then return nil, "STATION_INVALID" end
	if expectedZone ~= nil and expectedZone ~= 1 then return nil, "STATION_INVALID" end
	return { stationId = stationId, eggType = "BasicEgg", zone = 1 }
end

local function resetState()
	now = 1000
	profile = {
		diamonds = 1000,
		autoHatchExpiresAt = 0,
		hatchPreferences = { preferredBatchCount = 1 },
	}
	pendingCurrency = {}
	commits = 0
	rollbacks = 0
	hatchCalls = {}
	hatchError = nil
	maximumCount = 10
	stationAllowed = true
	stationReason = "STATION_INVALID"
	spawnQueue = {}
	schedulerCallback = nil
	updates = {}
	AutoHatchService._sessions = {}
	AutoHatchService._purchaseLocks = {}
	AutoHatchService._revisions = {}
	AutoHatchService._generations = {}
	AutoHatchService._rejoinRequired = {}
	AutoHatchService._stoppedReasons = {}
	AutoHatchService._actionFeedback = {}
	AutoHatchService._started = false
	AutoHatchService._nextGlobalTickAt = 1003
	AutoHatchService._transactionHook = nil
	AutoHatchService._now = function() return now end
	AutoHatchService._spawn = function(callback) callback() end
	AutoHatchService._schedulerSpawn = function(callback)
		schedulerCallback = callback
		return true
	end
	AutoHatchService.init(dataService, currencyService, eggService, stationAuthority)
	expect(AutoHatchService.start()):toBeTrue()
	expect(schedulerCallback ~= nil):toBeTrue()
end

local function purchaseRequest()
	return { contractVersion = 1, action = "PURCHASE" }
end
local function startRequest()
	return {
		contractVersion = 1,
		action = "START",
		stationId = "EggStation-1-BasicEgg",
		stationToken = "station-guid",
	}
end
local function stopRequest()
	return { contractVersion = 1, action = "STOP" }
end
local function grantAccess(expiry)
	profile.autoHatchExpiresAt = expiry or (now + 600)
end

describe("AutoHatchService QOF-18 strict contract and purchase", function()
	it("accepts only exact versioned request shapes", function()
		resetState()
		expect(AutoHatchService._validateRequestForTests("purchase", purchaseRequest())):toBeTrue()
		expect(AutoHatchService._validateRequestForTests("get", { contractVersion = 1, action = "GET_STATE" })):toBeTrue()
		expect(AutoHatchService._validateRequestForTests("setBatch", {
			contractVersion = 1, action = "SET_BATCH", selectedCount = 5,
		})):toBeTrue()
		expect(AutoHatchService._validateRequestForTests("start", startRequest())):toBeTrue()
		expect(AutoHatchService._validateRequestForTests("stop", stopRequest())):toBeTrue()
		for _, hostile in ipairs({
			{},
			{ contractVersion = 2, action = "PURCHASE" },
			{ contractVersion = 1, action = "PURCHASE", extra = true },
		}) do
			expect(AutoHatchService._validateRequestForTests("purchase", hostile)):toBeFalse()
		end
	end)

	it("purchases exactly 600 seconds for 500 Diamonds and rejects active stacking", function()
		resetState()
		local success, reason, state = AutoHatchService.purchase(player, purchaseRequest())
		expect(success):toBeTrue()
		expect(reason):toBeNil()
		expect(profile.diamonds):toBe(500)
		expect(profile.autoHatchExpiresAt):toBe(1600)
		expect(commits):toBe(1)
		expect(state.economy.price):toBe(500)
		expect(state.economy.durationSeconds):toBe(600)
		expect(state.remainingSeconds):toBe(600)

		local again, activeReason = AutoHatchService.purchase(player, purchaseRequest())
		expect(again):toBeFalse()
		expect(activeReason):toBe("ACCESS_ALREADY_ACTIVE")
		expect(profile.diamonds):toBe(500)
		expect(profile.autoHatchExpiresAt):toBe(1600)
	end)

	it("fails closed for insufficient funds and rolls back exact state on technical faults", function()
		resetState()
		profile.diamonds = 499
		local success, reason = AutoHatchService.purchase(player, purchaseRequest())
		expect(success):toBeFalse()
		expect(reason):toBe("INSUFFICIENT_DIAMONDS")
		expect(profile.autoHatchExpiresAt):toBe(0)

		resetState()
		AutoHatchService._transactionHook = function(stage)
			if stage == "afterMutation" then error("injected") end
		end
		success, reason = AutoHatchService.purchase(player, purchaseRequest())
		expect(success):toBeFalse()
		expect(reason):toBe("TECHNICAL_ERROR")
		expect(profile.diamonds):toBe(1000)
		expect(profile.autoHatchExpiresAt):toBe(0)
		expect(rollbacks):toBe(1)
		expect(commits):toBe(0)
	end)

	it("fails closed for fractional live expiries instead of repairing paid time", function()
		resetState()
		profile.autoHatchExpiresAt = 1600.9
		local state = AutoHatchService.getState(player)
		expect(profile.autoHatchExpiresAt):toBe(0)
		expect(state.expiresAt):toBe(0)
		expect(state.remainingSeconds):toBe(0)
	end)

	it("reports runtime availability only after complete dependencies and scheduler startup", function()
		resetState()
		expect(AutoHatchService.getState(player).runtimeEnabled):toBeTrue()

		AutoHatchService.prepareForShutdown()
		AutoHatchService.init(dataService, currencyService, eggService, {})
		expect(AutoHatchService.start()):toBeFalse()
		expect(AutoHatchService.getState(player).runtimeEnabled):toBeFalse()
		local diamondsBefore = profile.diamonds
		local expiryBefore = profile.autoHatchExpiresAt
		local purchased, purchaseReason = AutoHatchService.purchase(player, purchaseRequest())
		expect(purchased):toBeFalse()
		expect(purchaseReason):toBe("RUNTIME_UNAVAILABLE")
		expect(profile.diamonds):toBe(diamondsBefore)
		expect(profile.autoHatchExpiresAt):toBe(expiryBefore)
		expect(next(pendingCurrency)):toBeNil()
		local started, startReason, unavailableState = AutoHatchService.startSession(player, startRequest())
		expect(started):toBeFalse()
		expect(startReason):toBe("RUNTIME_UNAVAILABLE")
		expect(unavailableState.runtimeEnabled):toBeFalse()
		expect(unavailableState.actionFeedback.reason):toBe("RUNTIME_UNAVAILABLE")

		AutoHatchService.init(dataService, currencyService, eggService, stationAuthority)
		AutoHatchService._schedulerSpawn = function() error("scheduler unavailable") end
		expect(AutoHatchService.start()):toBeFalse()
		expect(AutoHatchService._started):toBeFalse()
		expect(AutoHatchService.getState(player).runtimeEnabled):toBeFalse()
		purchased, purchaseReason = AutoHatchService.purchase(player, purchaseRequest())
		expect(purchased):toBeFalse()
		expect(purchaseReason):toBe("RUNTIME_UNAVAILABLE")
		expect(profile.diamonds):toBe(diamondsBefore)
	end)

	it("fails closed and republishes unavailable state if the running scheduler crashes", function()
		resetState()
		expect(AutoHatchService.getState(player).runtimeEnabled):toBeTrue()
		local previousWait = task.wait
		task.wait = function() error("injected scheduler crash") end
		schedulerCallback()
		task.wait = previousWait
		expect(AutoHatchService._started):toBeFalse()
		expect(AutoHatchService._nextGlobalTickAt):toBeNil()
		expect(AutoHatchService.getState(player).runtimeEnabled):toBeFalse()
		expect(#updates > 0):toBeTrue()
		expect(updates[#updates].runtimeEnabled):toBeFalse()
		local purchased, reason = AutoHatchService.purchase(player, purchaseRequest())
		expect(purchased):toBeFalse()
		expect(reason):toBe("RUNTIME_UNAVAILABLE")
	end)

	it("publishes rate-limited starts through the same canonical feedback revision", function()
		resetState()
		local beforeRevision = AutoHatchService.getState(player).stateRevision
		local success, reason, state = AutoHatchService.rejectStart(
			player, startRequest(), "RATE_LIMITED"
		)
		expect(success):toBeFalse()
		expect(reason):toBe("RATE_LIMITED")
		expect(state.stateRevision > beforeRevision):toBeTrue()
		expect(state.actionFeedback):toEqual({
			action = "START",
			reason = "RATE_LIMITED",
			stationId = "EggStation-1-BasicEgg",
		})
		local concurrentGet = AutoHatchService.getState(player)
		expect(concurrentGet.stateRevision):toBe(state.stateRevision)
		expect(concurrentGet.actionFeedback):toEqual(state.actionFeedback)
		expect(updates[#updates].actionFeedback):toEqual(state.actionFeedback)
	end)

	it("returns monotone full DTOs with independent nested copies", function()
		resetState()
		grantAccess()
		AutoHatchService.onPlayerAdded(player)
		local first = AutoHatchService.getState(player)
		expect(first.pauseReason):toBe("REJOIN_REQUIRES_STATION")
		expect(first.status):toBe("STOPPED")
		expect(first.contractVersion):toBe(1)
		expect(first.stateRevision > 0):toBeTrue()
		first.economy.price = 1
		first.availableCounts[1] = 99
		local second = AutoHatchService.getState(player)
		expect(second.economy.price):toBe(500)
		expect(second.availableCounts[1]):toBe(1)
		expect(second.stateRevision):toBe(first.stateRevision)
	end)
end)

describe("AutoHatchService QOF-18 station session and scheduler", function()
	it("returns revisioned authoritative start failures without changing the session", function()
		resetState()
		local beforeRevision = AutoHatchService.getState(player).stateRevision
		local success, reason, state = AutoHatchService.startSession(player, startRequest())
		expect(success):toBeFalse()
		expect(reason):toBe("ACCESS_REQUIRED")
		expect(state.stateRevision > beforeRevision):toBeTrue()
		expect(state.actionFeedback):toEqual({
			action = "START",
			reason = "ACCESS_REQUIRED",
			stationId = "EggStation-1-BasicEgg",
		})
		expect(AutoHatchService.getState(player).actionFeedback):toEqual({
			action = "START",
			reason = "ACCESS_REQUIRED",
			stationId = "EggStation-1-BasicEgg",
		})
		expect(AutoHatchService.getState(player).stateRevision):toBe(state.stateRevision)

		grantAccess()
		stationAllowed = false
		for _, stableReason in ipairs({
			"TOO_FAR", "ZONE_LOCKED", "STATION_INVALID", "CHARACTER_UNAVAILABLE",
		}) do
			stationReason = stableReason
			success, reason, state = AutoHatchService.startSession(player, startRequest())
			expect(success):toBeFalse()
			expect(reason):toBe(stableReason)
			expect(state.actionFeedback.reason):toBe(stableReason)
			expect(state.status):toBe("STOPPED")
			local concurrentGet = AutoHatchService.getState(player)
			expect(concurrentGet.stateRevision):toBe(state.stateRevision)
			expect(concurrentGet.actionFeedback):toEqual(state.actionFeedback)
		end
		stationAllowed = true
		success, reason, state = AutoHatchService.startSession(player, startRequest())
		expect(success):toBeTrue()
		expect(state.actionFeedback):toBeNil()
	end)

	it("starts only at an exact nearby station and waits for the next regular tick", function()
		resetState()
		grantAccess()
		profile.hatchPreferences.preferredBatchCount = 5
		local success, reason, state = AutoHatchService.startSession(player, startRequest())
		expect(success):toBeTrue()
		expect(reason):toBeNil()
		expect(state.station):toEqual({ stationId = "EggStation-1-BasicEgg", eggType = "BasicEgg", zone = 1 })
		expect(state.nextHatchAt):toBe(1003)
		AutoHatchService._processTick(1002)
		expect(#hatchCalls):toBe(0)
		AutoHatchService._processTick(1003)
		expect(#hatchCalls):toBe(1)
		expect(hatchCalls[1].count):toBe(5)
		expect(hatchCalls[1].options.bypassStation):toBeTrue()
		expect(hatchCalls[1].options.consumeShinyCharges):toBeFalse()
	end)

	it("allows at most one in-flight batch and creates no backlog or catch-up", function()
		resetState()
		grantAccess()
		AutoHatchService._spawn = function(callback) table.insert(spawnQueue, callback) end
		AutoHatchService.startSession(player, startRequest())
		AutoHatchService._processTick(1003)
		expect(#spawnQueue):toBe(1)
		expect(AutoHatchService.getState(player).inFlight):toBeTrue()
		AutoHatchService._processTick(1006)
		AutoHatchService._processTick(1012)
		expect(#spawnQueue):toBe(1)
		spawnQueue[1]()
		expect(#hatchCalls):toBe(1)
		AutoHatchService._processTick(1013)
		expect(#spawnQueue):toBe(2)
		-- A large stall still schedules just one batch for that observed tick.
		spawnQueue[2]()
		AutoHatchService._processTick(1100)
		expect(#spawnQueue):toBe(3)
	end)

	it("invalidates old callbacks on stop and target generation changes", function()
		resetState()
		grantAccess()
		AutoHatchService._spawn = function(callback) table.insert(spawnQueue, callback) end
		AutoHatchService.startSession(player, startRequest())
		local generation = AutoHatchService.getState(player).generation
		AutoHatchService._processTick(1003)
		local stopped = AutoHatchService.stopSession(player, stopRequest())
		expect(stopped):toBeTrue()
		expect(AutoHatchService.getState(player).generation > generation):toBeTrue()
		expect(AutoHatchService.getState(player).station):toBeNil()
		-- Already atomically admitted work may commit, but cannot revive the session.
		spawnQueue[1]()
		expect(#hatchCalls):toBe(1)
		expect(AutoHatchService.getState(player).status):toBe("STOPPED")
	end)

	it("starts no new batch at expiry and cleans expired persistent state", function()
		resetState()
		grantAccess(1003)
		AutoHatchService.startSession(player, startRequest())
		AutoHatchService._processTick(1003)
		expect(#hatchCalls):toBe(0)
		expect(profile.autoHatchExpiresAt):toBe(0)
		expect(AutoHatchService.getState(player).remainingSeconds):toBe(0)
	end)

	it("pauses stable reasons and retries only on later regular ticks", function()
		resetState()
		grantAccess()
		profile.hatchPreferences.preferredBatchCount = 10
		maximumCount = 5
		local started, _, state = AutoHatchService.startSession(player, startRequest())
		expect(started):toBeTrue()
		expect(state.pauseReason):toBe("BATCH_NOT_ENTITLED")
		expect(profile.hatchPreferences.preferredBatchCount):toBe(10)
		AutoHatchService._processTick(1003)
		expect(#hatchCalls):toBe(0)

		maximumCount = 10
		hatchError = "Not enough coins for x10"
		AutoHatchService._processTick(1006)
		expect(#hatchCalls):toBe(1)
		expect(AutoHatchService.getState(player).pauseReason):toBe("INSUFFICIENT_COINS")
		hatchError = nil
		AutoHatchService._processTick(1009)
		expect(#hatchCalls):toBe(2)
		expect(AutoHatchService.getState(player).pauseReason):toBeNil()
	end)

	it("revalidates station identity every tick while bypassing only distance", function()
		resetState()
		grantAccess()
		AutoHatchService.startSession(player, startRequest())
		stationAllowed = false
		stationReason = "STATION_INVALID"
		AutoHatchService._processTick(1003)
		expect(#hatchCalls):toBe(0)
		expect(AutoHatchService.getState(player).pauseReason):toBe("STATION_INVALID")
		stationAllowed = true
		AutoHatchService._processTick(1006)
		expect(#hatchCalls):toBe(1)
	end)

	it("leave clears transient work before cleanup while preserving remaining absolute access", function()
		resetState()
		grantAccess()
		AutoHatchService.startSession(player, startRequest())
		AutoHatchService.onPlayerRemoving(player)
		expect(AutoHatchService._sessions[player.UserId]):toBeNil()
		expect(profile.autoHatchExpiresAt):toBe(1600)
		AutoHatchService.onPlayerAdded(player)
		local state = AutoHatchService.getState(player)
		expect(state.status):toBe("STOPPED")
		expect(state.pauseReason):toBe("REJOIN_REQUIRES_STATION")
		expect(state.station):toBeNil()
	end)
end)
