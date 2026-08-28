--[[
	AutoHatchService.lua - QOF-18 paid, station-bound Auto-Hatch authority.
	Persistent state is limited to an absolute os.time() expiry and EggService's
	batch preference. Targets, generations, revisions, pause state and in-flight
	work are server-session-only and never resume remotely after rejoin.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BalanceConfig = require(game.ReplicatedStorage.Shared.BalanceConfig)

local AutoHatchService = {}

local DEFINITION = BalanceConfig.Shop.AutoHatch
local CONTRACT_VERSION = 1
local AVAILABLE_COUNTS = { 1, 2, 5, 10 }

AutoHatchService._dataService = nil
AutoHatchService._currencyService = nil
AutoHatchService._eggService = nil
AutoHatchService._stationAuthority = nil
AutoHatchService._sessions = {}
AutoHatchService._purchaseLocks = {}
AutoHatchService._revisions = {}
AutoHatchService._generations = {}
AutoHatchService._rejoinRequired = {}
AutoHatchService._stoppedReasons = {}
AutoHatchService._actionFeedback = {}
AutoHatchService._started = false
AutoHatchService._nextGlobalTickAt = nil
AutoHatchService._transactionHook = nil
AutoHatchService._now = os.time
AutoHatchService._spawn = task.spawn
AutoHatchService._schedulerSpawn = task.spawn

local function isFiniteNumber(value)
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
end

local function deepCopy(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for key, child in pairs(value) do
		copy[deepCopy(key)] = deepCopy(child)
	end
	return copy
end

local function userIdFor(player)
	return player and player.UserId
end

local function isPlayer(player)
	return player ~= nil
		and player.UserId ~= nil
		and type(player.IsA) == "function"
		and player:IsA("Player")
end

local function getData(player)
	if type(AutoHatchService._dataService) ~= "table"
		or type(AutoHatchService._dataService.getPlayerData) ~= "function" then
		return nil
	end
	return AutoHatchService._dataService.getPlayerData(player)
end

local function dependenciesReady()
	local dataService = AutoHatchService._dataService
	local currencyService = AutoHatchService._currencyService
	local eggService = AutoHatchService._eggService
	local authority = AutoHatchService._stationAuthority
	return BalanceConfig.Shop.AutoHatchRuntimeEnabled == true
		and DEFINITION.RuntimeEnabled == true
		and type(dataService) == "table"
		and type(dataService.getPlayerData) == "function"
		and type(currencyService) == "table"
		and type(currencyService.beginSpendTransaction) == "function"
		and type(currencyService.setSpendSettler) == "function"
		and type(currencyService.commitSpendTransaction) == "function"
		and type(currencyService.rollbackSpendTransaction) == "function"
		and type(eggService) == "table"
		and type(eggService.getBatchState) == "function"
		and type(eggService.setSelectedBatchCount) == "function"
		and type(eggService.purchaseAndHatch) == "function"
		and type(authority) == "table"
		and type(authority.validateSelection) == "function"
end

local function runtimeAvailable()
	return AutoHatchService._started == true and dependenciesReady()
end

local function readLiveExpiry(data, now, shouldNormalize)
	if type(data) ~= "table" then return 0 end
	local value = data.autoHatchExpiresAt
	if not isFiniteNumber(value) or value % 1 ~= 0
		or value <= now or value > now + DEFINITION.durationSeconds then
		if shouldNormalize then data.autoHatchExpiresAt = 0 end
		return 0
	end
	if shouldNormalize then data.autoHatchExpiresAt = value end
	return value
end

local function normalizeLiveExpiry(data, now)
	return readLiveExpiry(data, now, true)
end

local function nextGeneration(userId)
	local generation = (AutoHatchService._generations[userId] or 0) + 1
	AutoHatchService._generations[userId] = generation
	return generation
end

local function bumpRevision(userId)
	local revision = (AutoHatchService._revisions[userId] or 0) + 1
	AutoHatchService._revisions[userId] = revision
	return revision
end

local function currentRevision(userId)
	return AutoHatchService._revisions[userId] or 0
end

local function exactRequest(request, action, allowedFields, expectedCount)
	if type(request) ~= "table" or getmetatable(request) ~= nil then return false end
	local count = 0
	for key in pairs(request) do
		if allowedFields[key] ~= true then return false end
		count = count + 1
	end
	return count == expectedCount
		and request.contractVersion == CONTRACT_VERSION
		and request.action == action
end

local function validIdentifier(value, maximum)
	return type(value) == "string" and #value > 0 and #value <= maximum
end

local function requestIsGet(request)
	return exactRequest(request, "GET_STATE", { contractVersion = true, action = true }, 2)
end

local function requestIsPurchase(request)
	return exactRequest(request, "PURCHASE", { contractVersion = true, action = true }, 2)
end

local function requestIsSetBatch(request)
	return exactRequest(request, "SET_BATCH", {
		contractVersion = true,
		action = true,
		selectedCount = true,
	}, 3) and isFiniteNumber(request.selectedCount) and request.selectedCount % 1 == 0
end

local function requestIsStart(request)
	return exactRequest(request, "START", {
		contractVersion = true,
		action = true,
		stationId = true,
		stationToken = true,
	}, 4)
		and validIdentifier(request.stationId, 64)
		and validIdentifier(request.stationToken, 128)
end

local function requestIsStop(request)
	return exactRequest(request, "STOP", { contractVersion = true, action = true }, 2)
end

local function getBatchState(player)
	if type(AutoHatchService._eggService) ~= "table"
		or type(AutoHatchService._eggService.getBatchState) ~= "function" then
		return { selectedCount = 1, maximumCount = 1, availableCounts = deepCopy(AVAILABLE_COUNTS) }
	end
	local state = AutoHatchService._eggService.getBatchState(player)
	return {
		selectedCount = type(state) == "table" and state.selectedCount or 1,
		maximumCount = type(state) == "table" and state.maximumCount or 1,
		availableCounts = deepCopy(AVAILABLE_COUNTS),
	}
end

local function buildState(player, shouldNormalizeExpiry)
	local now = math.floor(AutoHatchService._now())
	local data = getData(player)
	local expiresAt = readLiveExpiry(data, now, shouldNormalizeExpiry)
	local userId = userIdFor(player)
	local session = userId and AutoHatchService._sessions[userId] or nil
	local batchState = getBatchState(player)
	local active = expiresAt > now
	local status = "STOPPED"
	local pauseReason = nil
	local generation = userId and (AutoHatchService._generations[userId] or 0) or 0
	local station = nil
	local nextHatchAt = nil
	local inFlight = false
	if session then
		status = session.status
		pauseReason = session.pauseReason
		generation = session.generation
		station = deepCopy(session.station)
		nextHatchAt = session.nextHatchAt
		inFlight = session.inFlight == true
	elseif active and userId and AutoHatchService._rejoinRequired[userId] then
		pauseReason = "REJOIN_REQUIRES_STATION"
	elseif userId then
		pauseReason = AutoHatchService._stoppedReasons[userId]
	end

	return {
		contractVersion = CONTRACT_VERSION,
		stateRevision = userId and currentRevision(userId) or 0,
		serverTime = now,
		runtimeEnabled = runtimeAvailable(),
		economy = {
			currency = DEFINITION.cost.currency,
			price = DEFINITION.cost.amount,
			durationSeconds = DEFINITION.durationSeconds,
			intervalSeconds = DEFINITION.intervalSeconds,
		},
		expiresAt = expiresAt,
		remainingSeconds = math.max(0, expiresAt - now),
		selectedCount = batchState.selectedCount,
		maximumCount = batchState.maximumCount,
		availableCounts = batchState.availableCounts,
		generation = generation,
		status = status,
		station = station,
		nextHatchAt = nextHatchAt,
		pauseReason = pauseReason,
		actionFeedback = userId and deepCopy(AutoHatchService._actionFeedback[userId]) or nil,
		inFlight = inFlight,
	}
end

function AutoHatchService.getState(player)
	return buildState(player, true)
end

local function fireStateUpdated(player, state)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local event = remotes and remotes:FindFirstChild("AutoHatchStateUpdated")
	if event then
		pcall(function()
			event:FireClient(player, deepCopy(state))
		end)
	end
end

local function publish(player)
	local userId = userIdFor(player)
	if userId then
		AutoHatchService._actionFeedback[userId] = nil
		bumpRevision(userId)
	end
	local state = AutoHatchService.getState(player)
	fireStateUpdated(player, state)
	return deepCopy(state)
end

local function rejectedStartState(player, request, reason)
	local userId = userIdFor(player)
	if userId then
		AutoHatchService._actionFeedback[userId] = {
			action = "START",
			reason = reason,
			stationId = type(request) == "table" and request.stationId or nil,
		}
		bumpRevision(userId)
	end
	local state = AutoHatchService.getState(player)
	-- Rejections are canonical state updates: GET_STATE and the action response
	-- expose identical bytes for this revision regardless of arrival order.
	fireStateUpdated(player, state)
	return deepCopy(state)
end

local function invokeTransactionHook(stage, context)
	if type(AutoHatchService._transactionHook) == "function" then
		AutoHatchService._transactionHook(stage, context)
	end
end

function AutoHatchService.init(dataService, currencyService, eggService, stationAuthority)
	AutoHatchService._dataService = dataService
	AutoHatchService._currencyService = currencyService
	AutoHatchService._eggService = eggService
	AutoHatchService._stationAuthority = stationAuthority
end

function AutoHatchService.getStateFromRequest(player, request)
	if not isPlayer(player) or not requestIsGet(request) then
		return false, "INVALID_REQUEST", AutoHatchService.getState(player)
	end
	return true, nil, AutoHatchService.getState(player)
end

function AutoHatchService.rejectStart(player, request, reason)
	if not isPlayer(player) or not requestIsStart(request)
		or type(reason) ~= "string" or reason == "" then
		return false, "INVALID_REQUEST", AutoHatchService.getState(player)
	end
	return false, reason, rejectedStartState(player, request, reason)
end

function AutoHatchService.purchase(player, request)
	if not isPlayer(player) or not requestIsPurchase(request) then
		return false, "INVALID_REQUEST", AutoHatchService.getState(player)
	end
	if not runtimeAvailable() then
		return false, "RUNTIME_UNAVAILABLE", AutoHatchService.getState(player)
	end
	local userId = player.UserId
	if AutoHatchService._purchaseLocks[userId] then
		return false, "PURCHASE_IN_FLIGHT", AutoHatchService.getState(player)
	end
	AutoHatchService._purchaseLocks[userId] = true

	local success = false
	local reason = "TECHNICAL_ERROR"
	local state = nil
	local callOk = pcall(function()
		local data = getData(player)
		if type(data) ~= "table" then reason = "NO_PROFILE" return end
		local now = math.floor(AutoHatchService._now())
		local currentExpiry = data.autoHatchExpiresAt
		if isFiniteNumber(currentExpiry)
			and currentExpiry % 1 == 0
			and currentExpiry > now
			and currentExpiry <= now + DEFINITION.durationSeconds then
			reason = "ACCESS_ALREADY_ACTIVE"
			return
		end

		local currencyTransaction = AutoHatchService._currencyService.beginSpendTransaction(
			player,
			DEFINITION.cost.currency,
			DEFINITION.cost.amount,
			"AutoHatchService.purchase"
		)
		if type(currencyTransaction) ~= "table" then reason = "INSUFFICIENT_DIAMONDS" return end

		local context = {
			player = player,
			data = data,
			oldExpiry = currentExpiry,
			newExpiry = now + DEFINITION.durationSeconds,
			currencyTransaction = currencyTransaction,
			expiryMutationStarted = false,
			expiryRestored = false,
			oldRejoinRequired = AutoHatchService._rejoinRequired[userId],
			oldStoppedReason = AutoHatchService._stoppedReasons[userId],
			oldActionFeedback = AutoHatchService._actionFeedback[userId],
			oldRevision = AutoHatchService._revisions[userId],
			transientMutationStarted = false,
			transientRestored = false,
			committed = false,
		}
		local function settleTransaction()
			if context.committed then return true end
			if context.expiryMutationStarted then
				local liveExpiry = context.data.autoHatchExpiresAt
				if not context.expiryRestored then
					if liveExpiry == context.newExpiry then
						context.data.autoHatchExpiresAt = context.oldExpiry
					elseif liveExpiry ~= context.oldExpiry then
						return false
					end
					context.expiryRestored = true
				elseif liveExpiry ~= context.oldExpiry then
					return false
				end
			end
			if context.transientMutationStarted then
				local expectedRevision = (context.oldRevision or 0) + 1
				if not context.transientRestored then
					local stillProjected = AutoHatchService._rejoinRequired[userId] == false
						and AutoHatchService._stoppedReasons[userId] == nil
						and AutoHatchService._actionFeedback[userId] == nil
						and AutoHatchService._revisions[userId] == expectedRevision
					local alreadyRestored = AutoHatchService._rejoinRequired[userId] == context.oldRejoinRequired
						and AutoHatchService._stoppedReasons[userId] == context.oldStoppedReason
						and AutoHatchService._actionFeedback[userId] == context.oldActionFeedback
						and AutoHatchService._revisions[userId] == context.oldRevision
					if stillProjected then
						AutoHatchService._rejoinRequired[userId] = context.oldRejoinRequired
						AutoHatchService._stoppedReasons[userId] = context.oldStoppedReason
						AutoHatchService._actionFeedback[userId] = context.oldActionFeedback
						AutoHatchService._revisions[userId] = context.oldRevision
					elseif not alreadyRestored then
						return false
					end
					context.transientRestored = true
				elseif AutoHatchService._rejoinRequired[userId] ~= context.oldRejoinRequired
					or AutoHatchService._stoppedReasons[userId] ~= context.oldStoppedReason
					or AutoHatchService._actionFeedback[userId] ~= context.oldActionFeedback
					or AutoHatchService._revisions[userId] ~= context.oldRevision then
					return false
				end
			end
			if context.currencyTransaction == nil then return true end
			local rollbackCallOk, rolledBack = pcall(
				AutoHatchService._currencyService.rollbackSpendTransaction,
				context.currencyTransaction
			)
			if not rollbackCallOk or rolledBack ~= true then return false end
			context.currencyTransaction = nil
			return true
		end

		local settlerCallOk, settlerRegistered = pcall(
			AutoHatchService._currencyService.setSpendSettler,
			currencyTransaction,
			settleTransaction
		)
		if not settlerCallOk or settlerRegistered ~= true then
			local rollbackCallOk, rolledBack = pcall(settleTransaction)
			if not rollbackCallOk or rolledBack ~= true then
				reason = "ROLLBACK_FAILED"
			end
			return
		end

		local transactionOk = pcall(function()
			invokeTransactionHook("afterSpend", context)
			context.expiryMutationStarted = true
			data.autoHatchExpiresAt = context.newExpiry
			invokeTransactionHook("afterMutation", context)
			context.transientMutationStarted = true
			AutoHatchService._rejoinRequired[userId] = false
			AutoHatchService._stoppedReasons[userId] = nil
			AutoHatchService._actionFeedback[userId] = nil
			AutoHatchService._revisions[userId] = (context.oldRevision or 0) + 1
			-- Build and retain the full authoritative DTO before the point of no
			-- return. If best-effort post-commit publication fails, this remains a
			-- successful paid response rather than inviting a duplicate retry.
			state = AutoHatchService.getState(player)
			if AutoHatchService._currencyService.commitSpendTransaction(currencyTransaction) ~= true then
				error("currency commit failed")
			end
			context.committed = true
			context.currencyTransaction = nil
		end)
		if not transactionOk then
			state = nil
			local rollbackCallOk, rolledBack = pcall(settleTransaction)
			if not rollbackCallOk or rolledBack ~= true then
				reason = "ROLLBACK_FAILED"
			end
			return
		end

		-- Currency commit is the economic point of no return. The authoritative
		-- response and revision already exist; post-commit replication is
		-- best-effort and cannot change the paid result into a retryable failure.
		success = true
		reason = nil
		pcall(fireStateUpdated, player, state)
	end)
	AutoHatchService._purchaseLocks[userId] = nil
	if state == nil then
		local stateCallOk, fallbackState = pcall(buildState, player, false)
		if stateCallOk then state = fallbackState end
	end
	if not callOk then
		if success then return true, nil, state end
		return false, "TECHNICAL_ERROR", state
	end
	return success, reason, state
end

function AutoHatchService.setBatch(player, request)
	if not isPlayer(player) or not requestIsSetBatch(request) then
		return false, "INVALID_REQUEST", AutoHatchService.getState(player)
	end
	if not runtimeAvailable() then
		return false, "RUNTIME_UNAVAILABLE", AutoHatchService.getState(player)
	end
	local selected, message = AutoHatchService._eggService.setSelectedBatchCount(
		player, request.selectedCount
	)
	if not selected then
		local reason = message == "Multi-Open upgrade required" and "BATCH_NOT_ENTITLED"
			or "INVALID_BATCH"
		return false, reason, AutoHatchService.getState(player)
	end
	return true, nil, publish(player)
end

local function nextRegularTick(now)
	local candidate = AutoHatchService._nextGlobalTickAt
	if not isFiniteNumber(candidate) or candidate <= now then
		candidate = now + DEFINITION.intervalSeconds
	end
	return math.floor(candidate)
end

function AutoHatchService.startSession(player, request)
	if not isPlayer(player) or not requestIsStart(request) then
		return false, "INVALID_REQUEST", AutoHatchService.getState(player)
	end
	if not runtimeAvailable() then
		return false, "RUNTIME_UNAVAILABLE", rejectedStartState(player, request, "RUNTIME_UNAVAILABLE")
	end
	local now = math.floor(AutoHatchService._now())
	local data = getData(player)
	if normalizeLiveExpiry(data, now) <= now then
		return false, "ACCESS_REQUIRED", rejectedStartState(player, request, "ACCESS_REQUIRED")
	end
	local authority = AutoHatchService._stationAuthority
	local station, stationError = authority.validateSelection(
		player, request.stationId, request.stationToken, nil, nil, true
	)
	if type(station) ~= "table" then
		local reason = stationError or "STATION_INVALID"
		return false, reason, rejectedStartState(player, request, reason)
	end
	local userId = player.UserId
	local generation = nextGeneration(userId)
	local batchState = getBatchState(player)
	local pauseReason = nil
	local status = "RUNNING"
	if batchState.selectedCount > batchState.maximumCount then
		status = "PAUSED"
		pauseReason = "BATCH_NOT_ENTITLED"
	end
	AutoHatchService._rejoinRequired[userId] = false
	AutoHatchService._stoppedReasons[userId] = nil
	AutoHatchService._sessions[userId] = {
		player = player,
		generation = generation,
		stationToken = request.stationToken,
		station = deepCopy(station),
		status = status,
		pauseReason = pauseReason,
		nextHatchAt = nextRegularTick(now),
		inFlight = false,
	}
	return true, nil, publish(player)
end

function AutoHatchService.stopSession(player, request)
	if not isPlayer(player) or not requestIsStop(request) then
		return false, "INVALID_REQUEST", AutoHatchService.getState(player)
	end
	local userId = player.UserId
	nextGeneration(userId)
	AutoHatchService._sessions[userId] = nil
	AutoHatchService._rejoinRequired[userId] = false
	AutoHatchService._stoppedReasons[userId] = nil
	return true, nil, publish(player)
end

local function reasonForHatchError(message)
	local text = tostring(message or "")
	if string.find(text, "Not enough coins", 1, true) then return "INSUFFICIENT_COINS" end
	if string.find(text, "inventory", 1, true) or string.find(text, "Inventory", 1, true) then
		return "INVENTORY_FULL"
	end
	if text == "Already hatching eggs" then return "HATCH_LOCKED" end
	if text == "Multi-Open upgrade required" then return "BATCH_NOT_ENTITLED" end
	if string.find(text, "Zone", 1, true) then return "ZONE_LOCKED" end
	return "TECHNICAL_ERROR"
end

local function finishBatch(player, generation, result, hatchError, callOk)
	local userId = player.UserId
	local session = AutoHatchService._sessions[userId]
	if not session or session.generation ~= generation then return end
	session.inFlight = false
	local now = math.floor(AutoHatchService._now())
	if normalizeLiveExpiry(getData(player), now) <= now then
		nextGeneration(userId)
		AutoHatchService._sessions[userId] = nil
		AutoHatchService._stoppedReasons[userId] = "ACCESS_EXPIRED"
		publish(player)
		return
	end
	if callOk and type(result) == "table" then
		session.status = "RUNNING"
		session.pauseReason = nil
	else
		session.status = "PAUSED"
		session.pauseReason = callOk and reasonForHatchError(hatchError) or "TECHNICAL_ERROR"
	end
	publish(player)
end

local function processPlayerTick(session, now)
	local player = session.player
	local userId = player and player.UserId
	if not userId or AutoHatchService._sessions[userId] ~= session then return end
	if session.inFlight or now < session.nextHatchAt then return end
	local data = getData(player)
	local expiresAt = normalizeLiveExpiry(data, now)
	if now >= expiresAt then
		nextGeneration(userId)
		AutoHatchService._sessions[userId] = nil
		AutoHatchService._rejoinRequired[userId] = false
		AutoHatchService._stoppedReasons[userId] = "ACCESS_EXPIRED"
		publish(player)
		return
	end

	-- One regular tick is consumed regardless of outcome. No missed interval is
	-- queued and a stalled callback can never trigger catch-up work.
	session.nextHatchAt = now + DEFINITION.intervalSeconds
	local station, stationError = AutoHatchService._stationAuthority.validateSelection(
		player,
		session.station.stationId,
		session.stationToken,
		session.station.eggType,
		session.station.zone,
		false
	)
	if type(station) ~= "table" then
		session.status = "PAUSED"
		session.pauseReason = stationError or "STATION_INVALID"
		publish(player)
		return
	end
	local batchState = getBatchState(player)
	if batchState.selectedCount > batchState.maximumCount then
		session.status = "PAUSED"
		session.pauseReason = "BATCH_NOT_ENTITLED"
		publish(player)
		return
	end

	local generation = session.generation
	session.inFlight = true
	session.status = "RUNNING"
	session.pauseReason = nil
	publish(player)
	AutoHatchService._spawn(function()
		local callOk, result, hatchError = pcall(function()
			return AutoHatchService._eggService.purchaseAndHatch(
				player,
				station.eggType,
				batchState.selectedCount,
				{
					bypassStation = true,
					consumeShinyCharges = false,
					autoHatch = true,
				}
			)
		end)
		finishBatch(player, generation, result, hatchError, callOk)
	end)
end

function AutoHatchService._processTick(now)
	now = math.floor(isFiniteNumber(now) and now or AutoHatchService._now())
	AutoHatchService._nextGlobalTickAt = now + DEFINITION.intervalSeconds
	for _, session in pairs(AutoHatchService._sessions) do
		processPlayerTick(session, now)
	end
end

local function disableRuntimeAfterSchedulerFailure()
	local wasStarted = AutoHatchService._started == true
	AutoHatchService._started = false
	AutoHatchService._nextGlobalTickAt = nil
	if not wasStarted then return end

	local recipients = {}
	for _, session in pairs(AutoHatchService._sessions) do
		local player = session and session.player
		if isPlayer(player) then recipients[player.UserId] = player end
	end
	if type(Players) == "table" or type(Players) == "userdata" then
		local getPlayersOk, connectedPlayers = pcall(function()
			return Players:GetPlayers()
		end)
		if getPlayersOk and type(connectedPlayers) == "table" then
			for _, player in ipairs(connectedPlayers) do
				if isPlayer(player) then recipients[player.UserId] = player end
			end
		end
	end
	for _, player in pairs(recipients) do
		pcall(function()
			publish(player)
		end)
	end
end

local function runSchedulerLoop()
	local loopOk = pcall(function()
		while AutoHatchService._started do
			task.wait(DEFINITION.intervalSeconds)
			if not AutoHatchService._started then break end
			AutoHatchService._processTick(AutoHatchService._now())
		end
	end)
	if not loopOk then
		disableRuntimeAfterSchedulerFailure()
	end
end

function AutoHatchService.start()
	if AutoHatchService._started or not dependenciesReady()
		or type(AutoHatchService._schedulerSpawn) ~= "function" then
		return false
	end
	AutoHatchService._started = true
	AutoHatchService._nextGlobalTickAt = math.floor(AutoHatchService._now()) + DEFINITION.intervalSeconds
	local spawnOk, spawnResult = pcall(AutoHatchService._schedulerSpawn, runSchedulerLoop)
	if not spawnOk or spawnResult == false or AutoHatchService._started ~= true then
		disableRuntimeAfterSchedulerFailure()
		return false
	end
	return true
end

function AutoHatchService.onPlayerAdded(player)
	if not isPlayer(player) then return end
	local userId = player.UserId
	nextGeneration(userId)
	AutoHatchService._sessions[userId] = nil
	local now = math.floor(AutoHatchService._now())
	local expiresAt = normalizeLiveExpiry(getData(player), now)
	AutoHatchService._rejoinRequired[userId] = expiresAt > now
	AutoHatchService._stoppedReasons[userId] = nil
	publish(player)
end

function AutoHatchService.onPlayerRemoving(player)
	if not player or player.UserId == nil then return end
	local userId = player.UserId
	nextGeneration(userId)
	AutoHatchService._sessions[userId] = nil
	AutoHatchService._purchaseLocks[userId] = nil
	AutoHatchService._rejoinRequired[userId] = nil
	AutoHatchService._stoppedReasons[userId] = nil
	AutoHatchService._actionFeedback[userId] = nil
	normalizeLiveExpiry(getData(player), math.floor(AutoHatchService._now()))
end

function AutoHatchService.prepareForShutdown()
	AutoHatchService._started = false
	AutoHatchService._nextGlobalTickAt = nil
	for userId, session in pairs(AutoHatchService._sessions) do
		nextGeneration(userId)
		AutoHatchService._sessions[userId] = nil
		if session.player then
			normalizeLiveExpiry(getData(session.player), math.floor(AutoHatchService._now()))
		end
	end
	return true
end

function AutoHatchService._validateRequestForTests(kind, request)
	if kind == "get" then return requestIsGet(request) end
	if kind == "purchase" then return requestIsPurchase(request) end
	if kind == "setBatch" then return requestIsSetBatch(request) end
	if kind == "start" then return requestIsStart(request) end
	if kind == "stop" then return requestIsStop(request) end
	return false
end

return AutoHatchService
