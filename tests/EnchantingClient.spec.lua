-- EnchantingClient.spec.lua - QOF-19 pet-bound client/session and UX contracts.

local originalRequire = require
local EnchantingClientSession = originalRequire("src/ReplicatedStorage/Shared/EnchantingClientSession")
local EnchantingClientContract = originalRequire("src/ReplicatedStorage/Shared/EnchantingClientContract")

local function readSource(path)
	if not io or not io.open then return nil end
	local file = assert(io.open(path, "rb"))
	local source = file:read("*a")
	file:close()
	return source
end

local function contains(source, value)
	return source and string.find(source, value, 1, true) ~= nil
end

local function stateFor(petInstanceId, revision, enchantId)
	if enchantId == nil then enchantId = false end
	return {
		contractVersion = 1,
		stateRevision = revision,
		pet = {
			instanceId = petInstanceId,
			enchantId = enchantId,
		},
	}
end

local function canonicalState()
	return {
		contractVersion = 1,
		stateRevision = 0,
		runtimeEnabled = true,
		pet = { instanceId = "pet-a", enchantId = false },
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
		availability = { canRoll = true },
		isReroll = false,
	}
end

local function clone(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for key, child in pairs(value) do copy[clone(key)] = clone(child) end
	return copy
end

describe("QOF-19 enchanting client session ownership", function()
	it("binds selection and every operation to a stable pet ID generation", function()
		local session = EnchantingClientSession.new()
		expect(EnchantingClientSession.selectPet(session, "pet-a")):toBeTrue()
		local oldOperation = EnchantingClientSession.beginRequest(session, "GET_STATE")
		expect(oldOperation.petInstanceId):toBe("pet-a")
		expect(EnchantingClientSession.selectPet(session, "pet-b")):toBeTrue()
		expect(EnchantingClientSession.isCurrent(session, oldOperation)):toBeFalse()
		expect(EnchantingClientSession.finishRequest(session, oldOperation)):toBeFalse()
		expect(session.petInstanceId):toBe("pet-b")
	end)

	it("invalidates in-flight work on close and malformed replacement", function()
		local session = EnchantingClientSession.new()
		EnchantingClientSession.selectPet(session, "pet-a")
		local operation = EnchantingClientSession.beginRequest(session, "GET_STATE")
		EnchantingClientSession.close(session)
		expect(EnchantingClientSession.isCurrent(session, operation)):toBeFalse()
		expect(session.petInstanceId):toBeNil()
		expect(session.inFlight):toBeFalse()
		expect(EnchantingClientSession.selectPet(session, string.rep("x", 129))):toBeFalse()
		expect(session.petInstanceId):toBeNil()
	end)

	it("allows one request and builds ROLL concurrency expectations from accepted state", function()
		local session = EnchantingClientSession.new()
		EnchantingClientSession.selectPet(session, "pet-a")
		local getOperation = EnchantingClientSession.beginRequest(session, "GET_STATE")
		expect(EnchantingClientSession.beginRequest(session, "GET_STATE")):toBeNil()
		expect(EnchantingClientSession.acceptState(
			session, getOperation, stateFor("pet-a", 0, nil)
		)):toBeTrue()
		local rollOperation = EnchantingClientSession.beginRequest(session, "ROLL")
		expect(rollOperation.expectedStateRevision):toBe(0)
		expect(rollOperation.expectedEnchantId):toBeFalse()
		expect(EnchantingClientSession.beginRequest(session, "ROLL")):toBeNil()
	end)

	it("requires successful rolls to advance while accepting equal-revision semantic failures", function()
		local session = EnchantingClientSession.new()
		EnchantingClientSession.selectPet(session, "pet-a")
		local getOperation = EnchantingClientSession.beginRequest(session, "GET_STATE")
		expect(EnchantingClientSession.acceptState(
			session, getOperation, stateFor("pet-a", 2, "StrongI")
		)):toBeTrue()

		local failedRoll = EnchantingClientSession.beginRequest(session, "ROLL")
		expect(EnchantingClientSession.acceptState(
			session, failedRoll, stateFor("pet-a", 2, "StrongI"), false
		)):toBeTrue()

		local forgedSuccess = EnchantingClientSession.beginRequest(session, "ROLL")
		expect(EnchantingClientSession.acceptState(
			session, forgedSuccess, stateFor("pet-a", 2, "StrongI"), true
		)):toBeFalse()
		expect(EnchantingClientSession.finishRequest(session, forgedSuccess)):toBeTrue()

		local committedRoll = EnchantingClientSession.beginRequest(session, "ROLL")
		expect(EnchantingClientSession.acceptState(
			session, committedRoll, stateFor("pet-a", 3, "AgileI"), true
		)):toBeTrue()
	end)

	it("captures the exact current enchant for rerolls", function()
		local session = EnchantingClientSession.new()
		EnchantingClientSession.selectPet(session, "pet-a")
		local getOperation = EnchantingClientSession.beginRequest(session, "GET_STATE")
		expect(EnchantingClientSession.acceptState(
			session, getOperation, stateFor("pet-a", 7, "StrongII")
		)):toBeTrue()
		local rollOperation = EnchantingClientSession.beginRequest(session, "ROLL")
		expect(rollOperation.expectedStateRevision):toBe(7)
		expect(rollOperation.expectedEnchantId):toBe("StrongII")
	end)

	it("tracks monotone revisions independently for each pet", function()
		local session = EnchantingClientSession.new()
		EnchantingClientSession.selectPet(session, "pet-a")
		local petA = EnchantingClientSession.beginRequest(session, "GET_STATE")
		expect(EnchantingClientSession.acceptState(session, petA, stateFor("pet-a", 5))):toBeTrue()

		EnchantingClientSession.selectPet(session, "pet-b")
		local petB = EnchantingClientSession.beginRequest(session, "GET_STATE")
		expect(EnchantingClientSession.acceptState(session, petB, stateFor("pet-b", 1))):toBeTrue()

		EnchantingClientSession.selectPet(session, "pet-a")
		local stalePetA = EnchantingClientSession.beginRequest(session, "GET_STATE")
		expect(EnchantingClientSession.acceptState(
			session, stalePetA, stateFor("pet-a", 4)
		)):toBeFalse()
		expect(EnchantingClientSession.finishRequest(session, stalePetA)):toBeTrue()

		local equalPetA = EnchantingClientSession.beginRequest(session, "GET_STATE")
		expect(EnchantingClientSession.acceptState(
			session, equalPetA, stateFor("pet-a", 5)
		)):toBeTrue()
	end)

	it("rejects wrong-pet and malformed state without releasing ownership", function()
		local session = EnchantingClientSession.new()
		EnchantingClientSession.selectPet(session, "pet-a")
		local operation = EnchantingClientSession.beginRequest(session, "GET_STATE")
		expect(EnchantingClientSession.acceptState(
			session, operation, stateFor("pet-b", 0)
		)):toBeFalse()
		expect(session.inFlight):toBeTrue()
		expect(EnchantingClientSession.acceptState(session, operation, {
			contractVersion = 1,
			stateRevision = -1,
			pet = { instanceId = "pet-a", enchantId = false },
		})):toBeFalse()
		expect(EnchantingClientSession.acceptState(session, operation, {
			contractVersion = 1,
			stateRevision = 0,
			pet = { instanceId = "pet-a", enchantId = "UnknownEnchant" },
		})):toBeFalse()
		expect(EnchantingClientSession.finishRequest(session, operation)):toBeTrue()
	end)
end)

describe("QOF-19 exact client state DTO", function()
	it("accepts only the exact canonical V1 pool and economy", function()
		expect(EnchantingClientContract.validateState(canonicalState(), "pet-a")):toBeTrue()
		for _, price in ipairs({ 0, 501 }) do
			local state = canonicalState()
			state.economy.price = price
			expect(EnchantingClientContract.validateState(state, "pet-a")):toBeFalse()
		end
		local swapped = canonicalState()
		swapped.outcomes[1], swapped.outcomes[2] = swapped.outcomes[2], swapped.outcomes[1]
		expect(EnchantingClientContract.validateState(swapped, "pet-a")):toBeFalse()
		local altered = canonicalState()
		altered.outcomes[1].multiplier = 1.11
		expect(EnchantingClientContract.validateState(altered, "pet-a")):toBeFalse()
	end)

	it("rejects extra keys and metatables at every contract boundary", function()
		local locations = {
			function(state) state.extra = true end,
			function(state) state.pet.extra = true end,
			function(state) state.economy.extra = true end,
			function(state) state.availability.extra = true end,
			function(state) state.outcomes[1].extra = true end,
		}
		for _, mutate in ipairs(locations) do
			local state = canonicalState()
			mutate(state)
			expect(EnchantingClientContract.validateState(state, "pet-a")):toBeFalse()
		end
		for _, selectTable in ipairs({
			function(state) return state end,
			function(state) return state.pet end,
			function(state) return state.economy end,
			function(state) return state.availability end,
			function(state) return state.outcomes end,
			function(state) return state.outcomes[1] end,
		}) do
			local state = canonicalState()
			setmetatable(selectTable(state), {})
			expect(EnchantingClientContract.validateState(state, "pet-a")):toBeFalse()
		end
	end)
end)

describe("QOF-19 enchanting Main and inventory UX contracts", function()
	it("discovers the optional module and both remotes without waiting", function()
		local source = readSource("src/StarterPlayer/StarterPlayerScripts/Main.client.lua")
		if not source then return end
		expect(contains(source, 'Shared:FindFirstChild("EnchantingClientSession")')):toBeTrue()
		expect(contains(source, 'Remotes:FindFirstChild("GetEnchantingState")')):toBeTrue()
		expect(contains(source, 'Remotes:FindFirstChild("RollPetEnchant")')):toBeTrue()
		expect(contains(source, 'WaitForChild("EnchantingClientSession")')):toBeFalse()
		expect(contains(source, 'WaitForChild("GetEnchantingState")')):toBeFalse()
		expect(contains(source, 'WaitForChild("RollPetEnchant")')):toBeFalse()
		expect(contains(source, 'showEnchantingUnavailable("UNAVAILABLE")')):toBeTrue()
	end)

	it("constructs exact V1 GET_STATE and ROLL requests in async protected calls", function()
		local source = readSource("src/StarterPlayer/StarterPlayerScripts/Main.client.lua")
		if not source then return end
		expect(contains(source, 'action = "GET_STATE"')):toBeTrue()
		expect(contains(source, 'action = "ROLL"')):toBeTrue()
		expect(contains(source, "expectedStateRevision = operation.expectedStateRevision")):toBeTrue()
		expect(contains(source, "expectedEnchantId = operation.expectedEnchantId")):toBeTrue()
		expect(contains(source, "GetEnchantingState:InvokeServer({")):toBeTrue()
		expect(contains(source, "RollPetEnchant:InvokeServer({")):toBeTrue()
		expect(contains(source, "task.spawn(function()")):toBeTrue()
		expect(contains(source, "local invoked, success, reason, state = pcall(function()")):toBeTrue()
	end)

	it("validates the exact canonical DTO and session ownership before UI apply", function()
		local source = readSource("src/StarterPlayer/StarterPlayerScripts/Main.client.lua")
		if not source then return end
		expect(contains(source, 'Shared:FindFirstChild("EnchantingClientContract")')):toBeTrue()
		expect(contains(source, "EnchantingClientContract.validateState(state, petInstanceId)")):toBeTrue()
		expect(contains(source, "local validResultTuple = type(success) == \"boolean\"")):toBeTrue()
		expect(contains(source, "success == false and ENCHANTING_REASON_CODES[reason] == true")):toBeTrue()
		expect(contains(source, "requestEnchantingState(operation.petInstanceId, true)")):toBeTrue()
		local validateAt = string.find(source, "validEnchantingState(state, operation.petInstanceId)", 1, true)
		local acceptAt = string.find(source, "EnchantingClientSession.acceptState(", 1, true)
		local applyAt = string.find(source, "uiController:applyEnchantingState(state", 1, true)
		expect(validateAt ~= nil and acceptAt ~= nil and applyAt ~= nil):toBeTrue()
		expect(validateAt < applyAt):toBeTrue()
		expect(acceptAt < applyAt):toBeTrue()
	end)

	it("renders server cost and six outcomes with stable-ID lifecycle closure", function()
		local source = readSource("src/StarterPlayer/StarterPlayerScripts/UIController.lua")
		if not source then return end
		expect(contains(source, 'detailsBtn.Name = "PetDetailsBtn"')):toBeTrue()
		expect(contains(source, 'enchantName = enchantId == false and "None"')):toBeTrue()
		expect(contains(source, 'tostring(state.economy.price) .. " Diamonds"')):toBeTrue()
		expect(contains(source, "for _, outcome in ipairs(state.outcomes) do")):toBeTrue()
		expect(contains(source, 'string.format("%s  •  %d%%  •  %s ×%.2f"')):toBeTrue()
		expect(contains(source, "Reroll replaces this one enchant slot. The old enchant cannot be kept.")):toBeTrue()
		expect(contains(source, "local detailPet = self:_findInventoryPet(self._petDetailPetId)")):toBeTrue()
		expect(contains(source, "elseif state.availability.reason then")):toBeTrue()
		expect(contains(source, "self:_requestEnchantingClose()")):toBeTrue()
		expect(contains(source, "function UIController:openMachineSelection(machineId)")):toBeTrue()
	end)

	it("states every machine enchant and economy consequence clearly", function()
		local source = readSource("src/StarterPlayer/StarterPlayerScripts/UIController.lua")
		if not source then return end
		expect(contains(source, "Input pets and their enchants are always consumed.")):toBeTrue()
		expect(contains(source, "Diamonds are also spent on a normal failure.")):toBeTrue()
		expect(contains(source, "A successful output starts with no enchant.")):toBeTrue()
	end)
end)
