local originalRequire = require
local BalanceConfig = originalRequire("src/ReplicatedStorage/Shared/BalanceConfig")
local SharedMock = { BalanceConfig = BalanceConfig }
rawset(_G, "script", { Parent = SharedMock })
rawset(_G, "require", function(path)
	if path == BalanceConfig then return BalanceConfig end
	return originalRequire(path)
end)
local PetEnchantMath = originalRequire("src/ReplicatedStorage/Shared/PetEnchantMath")
SharedMock.PetEnchantMath = PetEnchantMath

local ReplicatedStorage = { Shared = SharedMock }
local gameMock = { ReplicatedStorage = ReplicatedStorage }
function gameMock:GetService(name)
	if name == "ReplicatedStorage" then return ReplicatedStorage end
	error("Unexpected service: " .. tostring(name))
end
rawset(_G, "game", gameMock)
rawset(_G, "require", function(path)
	if path == BalanceConfig then return BalanceConfig end
	if path == PetEnchantMath then return PetEnchantMath end
	return originalRequire(path)
end)
local EnchantingService = originalRequire("src/ServerScriptService/Services/EnchantingService")
rawset(_G, "require", originalRequire)

local player = { UserId = 1901, Name = "EnchantTester" }
local profile
local pending
local beginCalls
local commitCalls
local rollbackCalls
local currencyEvents
local inventoryEvents
local rngCalls
local nextRoll
local commitMode
local rollbackMode
local inventoryShouldError
local inventoryLease
local inventoryLeaseEnds
local profileLookupShouldError
local breakProfileAfterReplication

local dataService = {}
function dataService.getPlayerData()
	if profileLookupShouldError then error("injected profile lookup failure") end
	return profile
end

local currencyService = {}
function currencyService.beginSpendTransaction(_, currency, amount)
	table.insert(beginCalls, { currency = currency, amount = amount })
	if not profile or type(profile[currency]) ~= "number" or profile[currency] < amount then
		return nil
	end
	local transaction = {}
	pending[transaction] = { profile = profile, currency = currency, amount = amount }
	profile[currency] = profile[currency] - amount
	return transaction
end
function currencyService.commitSpendTransaction(transaction)
	commitCalls = commitCalls + 1
	local entry = pending[transaction]
	if not entry then return false end
	if commitMode == "error" then error("injected commit error") end
	if commitMode == "false" then return false end
	pending[transaction] = nil
	currencyEvents = currencyEvents + 1
	return true
end
function currencyService.rollbackSpendTransaction(transaction)
	rollbackCalls = rollbackCalls + 1
	local entry = pending[transaction]
	if not entry then return false end
	if rollbackMode == "error" then error("injected rollback error") end
	if rollbackMode == "false" then return false end
	pending[transaction] = nil
	entry.profile[entry.currency] = entry.profile[entry.currency] + entry.amount
	return true
end

local petService = {}
function petService.replicateInventory()
	if inventoryShouldError then error("injected inventory event failure") end
	inventoryEvents = inventoryEvents + 1
	if breakProfileAfterReplication then profileLookupShouldError = true end
end
function petService.beginInventoryMutation(receivedPlayer)
	if inventoryLease ~= nil then return nil end
	inventoryLease = { player = receivedPlayer }
	return inventoryLease
end
function petService.isInventoryMutationCurrent(receivedPlayer, lease)
	return inventoryLease == lease and lease.player == receivedPlayer
end
function petService.endInventoryMutation(receivedPlayer, lease, mutated)
	if not petService.isInventoryMutationCurrent(receivedPlayer, lease) then return false end
	table.insert(inventoryLeaseEnds, mutated == true)
	inventoryLease = nil
	return true
end

local function makePet(enchantId)
	local pet = { id = "pet-1", petId = "Buddy", damage = 1 }
	if enchantId then pet.enchantId = enchantId end
	return pet
end

local function reset(enchantId, diamonds)
	profile = { diamonds = diamonds == nil and 2000 or diamonds, pets = { makePet(enchantId) } }
	pending = {}
	beginCalls = {}
	commitCalls = 0
	rollbackCalls = 0
	currencyEvents = 0
	inventoryEvents = 0
	rngCalls = 0
	nextRoll = 1
	commitMode = "success"
	rollbackMode = "success"
	inventoryShouldError = false
	inventoryLease = nil
	inventoryLeaseEnds = {}
	profileLookupShouldError = false
	breakProfileAfterReplication = false
	EnchantingService.init(dataService, currencyService, petService)
	EnchantingService.setRandomSource(function(minimum, maximum)
		expect(minimum):toBe(1)
		expect(maximum):toBe(100)
		rngCalls = rngCalls + 1
		return nextRoll
	end)
end

local function getRequest(id)
	return { contractVersion = 1, action = "GET_STATE", petInstanceId = id or "pet-1" }
end

local function rollRequest(revision, enchantId, id)
	return {
		contractVersion = 1,
		action = "ROLL",
		petInstanceId = id or "pet-1",
		expectedStateRevision = revision or 0,
		expectedEnchantId = enchantId or false,
	}
end

local function roll(revision, enchantId)
	return EnchantingService.roll(player, rollRequest(revision, enchantId))
end

describe("EnchantingService QOF-19 Contract V1 state", function()
	it("accepts only exact plain GET_STATE and ROLL requests", function()
		reset()
		local ok, reason = EnchantingService.getStateFromRequest(player, getRequest())
		expect(ok):toBeTrue()
		expect(reason):toBeNil()

		local invalid = {
			{ contractVersion = 2, action = "GET_STATE", petInstanceId = "pet-1" },
			{ contractVersion = 1, action = "GET_STATE", petInstanceId = "pet-1", extra = true },
			{ contractVersion = 1, action = "ROLL", petInstanceId = "pet-1", expectedStateRevision = -1, expectedEnchantId = false },
			{ contractVersion = 1, action = "ROLL", petInstanceId = "pet-1", expectedStateRevision = 0.5, expectedEnchantId = false },
			{ contractVersion = 1, action = "ROLL", petInstanceId = "pet-1", expectedStateRevision = 0, expectedEnchantId = "Unknown" },
			{ contractVersion = 1, action = "ROLL", petInstanceId = "pet-1", expectedStateRevision = 0 },
		}
		for _, request in ipairs(invalid) do
			local success, failure = EnchantingService.roll(player, request)
			expect(success):toBeFalse()
			expect(failure):toBe("INVALID_REQUEST")
		end

		local metamethodCalls = 0
		local hostile = setmetatable({}, {
			__pairs = function() metamethodCalls = metamethodCalls + 1; error("hostile") end,
			__index = function() metamethodCalls = metamethodCalls + 1; error("hostile") end,
		})
		local success, failure = EnchantingService.roll(player, hostile)
		expect(success):toBeFalse()
		expect(failure):toBe("INVALID_REQUEST")
		expect(metamethodCalls):toBe(0)
	end)

	it("returns an exact fresh deep DTO with canonical economy, slot, pool, and availability", function()
		reset("AgileII")
		local success, reason, state = EnchantingService.getStateFromRequest(player, getRequest())
		expect(success):toBeTrue()
		expect(reason):toBeNil()
		expect(state):toEqual({
			contractVersion = 1,
			stateRevision = 0,
			runtimeEnabled = true,
			pet = { instanceId = "pet-1", enchantId = "AgileII" },
			economy = { currency = "diamonds", price = 500 },
			maxSlotsPerPet = 1,
			outcomes = {
				{ id = "StrongI", weight = 35, stat = "damage", multiplier = 1.10 },
				{ id = "StrongII", weight = 15, stat = "damage", multiplier = 1.25 },
				{ id = "StrongIII", weight = 5, stat = "damage", multiplier = 1.50 },
				{ id = "AgileI", weight = 30, stat = "speed", multiplier = 1.10 },
				{ id = "AgileII", weight = 12, stat = "speed", multiplier = 1.20 },
				{ id = "AgileIII", weight = 3, stat = "speed", multiplier = 1.35 },
			},
			availability = { canRoll = true, reason = nil },
			isReroll = true,
		})
		state.pet.enchantId = "Forged"
		state.economy.price = 1
		state.outcomes[1].weight = 100
		state.availability.canRoll = false
		local _, _, fresh = EnchantingService.getStateFromRequest(player, getRequest())
		expect(fresh.pet.enchantId):toBe("AgileII")
		expect(fresh.economy.price):toBe(500)
		expect(fresh.outcomes[1].weight):toBe(35)
		expect(fresh.availability.canRoll):toBeTrue()
	end)

	it("returns safe unavailable DTOs for missing pets and insufficient balance", function()
		reset(nil, 499)
		local _, _, poor = EnchantingService.getStateFromRequest(player, getRequest())
		expect(poor.pet.enchantId):toBeFalse()
		expect(poor.availability):toEqual({ canRoll = false, reason = "INSUFFICIENT_BALANCE" })
		local _, _, missing = EnchantingService.getStateFromRequest(player, getRequest("missing"))
		expect(missing.pet):toEqual({ instanceId = "missing", enchantId = false })
		expect(missing.availability):toEqual({ canRoll = false, reason = "PET_NOT_FOUND" })
	end)
end)

describe("EnchantingService QOF-19 weighted roll and concurrency", function()
	it("maps every exact 1..100 weighted boundary in ipairs order", function()
		local cases = {
			{ 1, "StrongI" }, { 35, "StrongI" },
			{ 36, "StrongII" }, { 50, "StrongII" },
			{ 51, "StrongIII" }, { 55, "StrongIII" },
			{ 56, "AgileI" }, { 85, "AgileI" },
			{ 86, "AgileII" }, { 97, "AgileII" },
			{ 98, "AgileIII" }, { 100, "AgileIII" },
		}
		for _, case in ipairs(cases) do
			reset()
			nextRoll = case[1]
			local success, reason, state = roll()
			expect(success):toBeTrue()
			expect(reason):toBeNil()
			expect(profile.pets[1].enchantId):toBe(case[2])
			expect(state.pet.enchantId):toBe(case[2])
			expect(state.stateRevision):toBe(1)
			expect(profile.diamonds):toBe(1500)
			expect(beginCalls[1]):toEqual({ currency = "diamonds", amount = 500 })
			expect(currencyEvents):toBe(1)
			expect(inventoryEvents):toBe(1)
		end
	end)

	it("rejects missing, stale revision, and stale enchant before RNG or debit", function()
		reset("StrongI")
		local success, reason = EnchantingService.roll(player, rollRequest(0, false, "missing"))
		expect(success):toBeFalse()
		expect(reason):toBe("PET_NOT_FOUND")
		success, reason = roll(1, "StrongI")
		expect(success):toBeFalse()
		expect(reason):toBe("STALE_STATE")
		success, reason = roll(0, "AgileI")
		expect(success):toBeFalse()
		expect(reason):toBe("STALE_STATE")
		expect(rngCalls):toBe(0)
		expect(#beginCalls):toBe(0)
		expect(profile.diamonds):toBe(2000)
	end)

	it("rejects insufficient balance before RNG and exact silent transaction work", function()
		reset(nil, 499)
		local success, reason = roll()
		expect(success):toBeFalse()
		expect(reason):toBe("INSUFFICIENT_BALANCE")
		expect(rngCalls):toBe(0)
		expect(commitCalls):toBe(0)
		expect(rollbackCalls):toBe(0)
		expect(currencyEvents):toBe(0)
		expect(inventoryEvents):toBe(0)
	end)

	it("holds a per-player lock, rejects reentrancy, and allows a charged same-ID reroll", function()
		reset("StrongI")
		nextRoll = 1
		local nestedSuccess = true
		local nestedReason
		EnchantingService.setTransactionHook(function(stage)
			if stage == "afterSpend" then
				nestedSuccess, nestedReason = roll(0, "StrongI")
				expect(currencyEvents):toBe(0)
				expect(inventoryEvents):toBe(0)
			end
		end)
		local success, reason, state = roll(0, "StrongI")
		expect(success):toBeTrue()
		expect(reason):toBeNil()
		expect(nestedSuccess):toBeFalse()
		expect(nestedReason):toBe("BUSY")
		expect(state.pet.enchantId):toBe("StrongI")
		expect(state.isReroll):toBeTrue()
		expect(profile.diamonds):toBe(1500)
		expect(EnchantingService._playerLocks[player.UserId]):toBeNil()
	end)

	it("rejects work while another service owns the shared inventory lease", function()
		reset()
		local externalLease = petService.beginInventoryMutation(player)
		local success, reason = roll()
		expect(success):toBeFalse()
		expect(reason):toBe("BUSY")
		expect(#beginCalls):toBe(0)
		expect(rngCalls):toBe(0)
		expect(profile.diamonds):toBe(2000)
		expect(petService.endInventoryMutation(player, externalLease, false)):toBeTrue()
	end)

	it("rejects same-ID replacement ABA after a state snapshot", function()
		reset()
		local _, _, state = EnchantingService.getStateFromRequest(player, getRequest())
		expect(state.stateRevision):toBe(0)
		profile.pets[1] = makePet()
		local success, reason = roll(state.stateRevision, nil)
		expect(success):toBeFalse()
		expect(reason):toBe("STALE_STATE")
		expect(#beginCalls):toBe(0)
		expect(profile.diamonds):toBe(2000)
	end)
end)

describe("EnchantingService QOF-19 rollback and lifecycle", function()
	it("restores exact absent/present enchant state and debit at every precommit fault stage", function()
		for _, oldEnchantId in ipairs({ false, "AgileII" }) do
			for _, faultStage in ipairs({ "afterSpend", "afterRoll", "afterMutation", "beforeCommit" }) do
				local initialId = nil
				if oldEnchantId ~= false then initialId = oldEnchantId end
				reset(initialId)
				EnchantingService.setTransactionHook(function(stage)
					if stage == faultStage then error("injected " .. stage) end
				end)
				local success, reason = roll(0, initialId)
				expect(success):toBeFalse()
				expect(reason):toBe("TECHNICAL_FAILURE")
				expect(profile.diamonds):toBe(2000)
				expect(rawget(profile.pets[1], "enchantId")):toBe(initialId)
				expect(currencyEvents):toBe(0)
				expect(inventoryEvents):toBe(0)
				expect(EnchantingService._playerLocks[player.UserId]):toBeNil()
			end
		end
	end)

	it("revalidates profile, pets table, pet ref/index, old enchant, and revision before mutation", function()
		local mutators = {
			function() profile = { diamonds = 1500, pets = { makePet() } } end,
			function() profile.pets = { profile.pets[1] } end,
			function() profile.pets[1] = makePet() end,
			function() profile.pets[1].enchantId = "AgileI" end,
			function() EnchantingService._revisions[player.UserId] = { ["pet-1"] = 1 } end,
		}
		for _, mutate in ipairs(mutators) do
			reset()
			local chargedProfile = profile
			EnchantingService.setTransactionHook(function(stage)
				if stage == "afterRoll" then mutate() end
			end)
			local success, reason = roll()
			expect(success):toBeFalse()
			expect(reason):toBe("STALE_STATE")
			expect(chargedProfile.diamonds):toBe(2000)
			expect(currencyEvents):toBe(0)
			expect(inventoryEvents):toBe(0)
		end
	end)

	it("restores both pet and exact debit when currency commit fails or throws", function()
		for _, mode in ipairs({ "false", "error" }) do
			reset("StrongII")
			commitMode = mode
			nextRoll = 100
			local success, reason = roll(0, "StrongII")
			expect(success):toBeFalse()
			expect(reason):toBe("TECHNICAL_FAILURE")
			expect(profile.pets[1].enchantId):toBe("StrongII")
			expect(profile.diamonds):toBe(2000)
			expect(rollbackCalls):toBe(1)
			expect(currencyEvents):toBe(0)
		end
	end)

	it("reports ROLLBACK_FAILED if either pet or currency restoration fails", function()
		reset()
		rollbackMode = "false"
		EnchantingService.setRandomSource(function() return 0 / 0 end)
		local success, reason = roll()
		expect(success):toBeFalse()
		expect(reason):toBe("ROLLBACK_FAILED")
		expect(profile.diamonds):toBe(1500)

		reset("StrongI")
		EnchantingService.setTransactionHook(function(stage)
			if stage == "afterMutation" then
				profile.pets[1].enchantId = "AgileIII"
				error("injected concurrent pet overwrite")
			end
		end)
		success, reason = roll(0, "StrongI")
		expect(success):toBeFalse()
		expect(reason):toBe("ROLLBACK_FAILED")
		expect(profile.pets[1].enchantId):toBe("AgileIII")
		expect(profile.diamonds):toBe(2000)
	end)

	it("does not roll back committed economy when inventory notification throws", function()
		reset()
		inventoryShouldError = true
		nextRoll = 98
		local success, reason, state = roll()
		expect(success):toBeTrue()
		expect(reason):toBeNil()
		expect(profile.diamonds):toBe(1500)
		expect(profile.pets[1].enchantId):toBe("AgileIII")
		expect(state.stateRevision):toBe(1)
		expect(currencyEvents):toBe(1)
		expect(rollbackCalls):toBe(0)
	end)

	it("keeps a paid commit successful when post-commit state refresh fails", function()
		reset()
		breakProfileAfterReplication = true
		local success, reason, state = roll()
		expect(success):toBeTrue()
		expect(reason):toBeNil()
		expect(state):toBeNil()
		expect(profile.diamonds):toBe(1500)
		expect(profile.pets[1].enchantId):toBe("StrongI")
		expect(commitCalls):toBe(1)
		expect(rollbackCalls):toBe(0)
		profileLookupShouldError = false
	end)

	it("retains failed restore handles and settles them retryably during cleanup", function()
		reset()
		rollbackMode = "false"
		EnchantingService.setRandomSource(function() return 0 / 0 end)
		local success, reason = roll()
		expect(success):toBeFalse()
		expect(reason):toBe("ROLLBACK_FAILED")
		expect(profile.diamonds):toBe(1500)
		expect(EnchantingService._activeTransactions[player.UserId] ~= nil):toBeTrue()
		expect(EnchantingService._playerLocks[player.UserId]):toBeTrue()
		expect(inventoryLease ~= nil):toBeTrue()

		expect(EnchantingService.cleanup(player)):toBeFalse()
		expect(profile.diamonds):toBe(1500)
		expect(EnchantingService._activeTransactions[player.UserId] ~= nil):toBeTrue()

		rollbackMode = "success"
		expect(EnchantingService.cleanup(player)):toBeTrue()
		expect(profile.diamonds):toBe(2000)
		expect(EnchantingService._activeTransactions[player.UserId]):toBeNil()
		expect(EnchantingService._playerLocks[player.UserId]):toBeNil()
		expect(inventoryLease):toBeNil()
		expect(EnchantingService.cleanup(player)):toBeTrue()
	end)

	it("does not settle or release a transaction that is still executing", function()
		reset()
		EnchantingService._playerLocks[player.UserId] = true
		EnchantingService._activeTransactions[player.UserId] = {
			player = player,
			executing = true,
			inventoryLease = petService.beginInventoryMutation(player),
		}
		expect(EnchantingService.cleanup(player)):toBeFalse()
		expect(EnchantingService._playerLocks[player.UserId]):toBeTrue()
		expect(inventoryLease ~= nil):toBeTrue()
	end)

	it("settles retryable transactions before shutdown and rejects new rolls", function()
		reset()
		rollbackMode = "false"
		EnchantingService.setRandomSource(function() return 0 / 0 end)
		local success, reason = roll()
		expect(success):toBeFalse()
		expect(reason):toBe("ROLLBACK_FAILED")
		rollbackMode = "success"
		expect(EnchantingService.prepareForShutdown()):toBeTrue()
		expect(profile.diamonds):toBe(2000)
		success, reason = roll()
		expect(success):toBeFalse()
		expect(reason):toBe("SERVICE_UNAVAILABLE")
	end)
end)


describe("QOF-19 server remote wiring", function()
	it("creates, rate-limits, initializes, and cleans both enchanting remotes", function()
		if not io or not io.open then return end
		local file = assert(io.open("src/ServerScriptService/Main.server.lua", "rb"))
		local source = file:read("*a")
		file:close()
		expect(string.find(source, '"GetEnchantingState"', 1, true) ~= nil):toBeTrue()
		expect(string.find(source, '"RollPetEnchant"', 1, true) ~= nil):toBeTrue()
		expect(string.find(source, 'EnchantingService.init(DataService, CurrencyService, PetService)', 1, true) ~= nil):toBeTrue()
		expect(string.find(source, 'getRemoteFunction("GetEnchantingState").OnServerInvoke', 1, true) ~= nil):toBeTrue()
		expect(string.find(source, 'canCall(player, "GetEnchantingState"', 1, true) ~= nil):toBeTrue()
		expect(string.find(source, 'canCallBurst(player, "GetEnchantingState"', 1, true) ~= nil):toBeTrue()
		expect(string.find(source, 'getRemoteFunction("RollPetEnchant").OnServerInvoke', 1, true) ~= nil):toBeTrue()
		expect(string.find(source, 'canCall(player, "RollPetEnchant"', 1, true) ~= nil):toBeTrue()
		expect(string.find(source, 'canCallBurst(player, "RollPetEnchant"', 1, true) ~= nil):toBeTrue()
		local releaseAt = assert(string.find(source, "DataService.onPlayerRemoving(player, function()", 1, true))
		local eggCleanupAt = assert(string.find(source, "EggService.onPlayerRemoving(player)", releaseAt, true))
		local machineCleanupAt = assert(string.find(source, "MachineService.onPlayerRemoving(player)", eggCleanupAt, true))
		local cleanupAt = assert(string.find(source, "EnchantingService.onPlayerRemoving(player)", machineCleanupAt, true))
		expect(releaseAt < eggCleanupAt):toBeTrue()
		expect(eggCleanupAt < machineCleanupAt):toBeTrue()
		expect(machineCleanupAt < cleanupAt):toBeTrue()
		expect(string.find(source, "EggService.beginShutdown()", 1, true) ~= nil):toBeTrue()
		expect(string.find(source, "MachineService.beginShutdown()", 1, true) ~= nil):toBeTrue()
		expect(string.find(source, "EnchantingService.beginShutdown()", 1, true) ~= nil):toBeTrue()
		expect(string.find(source, "Profile settlement queued for retry", 1, true) ~= nil):toBeTrue()
	end)
end)
