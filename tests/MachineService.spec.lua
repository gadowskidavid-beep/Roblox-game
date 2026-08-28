-- MachineService.spec.lua - Focused QOF-16 Gold-only runtime tests.

local originalRequire = require
local BalanceConfig = originalRequire("src/ReplicatedStorage/Shared/BalanceConfig")
local PetData = originalRequire("src/ReplicatedStorage/Shared/PetData")

local Config = {
	MaxPetInventoryBase = 100,
	MaxPetInventoryAbsolute = 250,
	MaxEquippedPetsBase = 3,
	MaxEquippedPetsAbsolute = 12,
	EggCosts = { [1] = { Coins = 100 } },
}

local guidCounter = 0
local HttpService = {}
function HttpService:GenerateGUID()
	guidCounter = guidCounter + 1
	return "machine-guid-" .. tostring(guidCounter)
end

local inventoryEvents = 0
local inventoryEvent = {}
function inventoryEvent:FireClient()
	inventoryEvents = inventoryEvents + 1
end
local remotes = {}
function remotes:FindFirstChild(name)
	if name == "PetInventoryUpdated" then return inventoryEvent end
	return nil
end
local ReplicatedStorage = {
	Shared = {
		Config = Config,
		BalanceConfig = BalanceConfig,
		PetData = PetData,
	},
}
function ReplicatedStorage:FindFirstChild(name)
	if name == "Remotes" then return remotes end
	return nil
end

local gameMock = { ReplicatedStorage = ReplicatedStorage }
function gameMock:GetService(name)
	if name == "ReplicatedStorage" then return ReplicatedStorage end
	if name == "HttpService" then return HttpService end
	error("Unexpected service: " .. tostring(name))
end
rawset(_G, "game", gameMock)

local sharedMock = { BalanceConfig = BalanceConfig, PetData = PetData }
rawset(_G, "script", { Parent = sharedMock })
local function sharedRequire(path)
	if path == BalanceConfig then return BalanceConfig end
	if path == PetData then return PetData end
	return originalRequire(path)
end
rawset(_G, "require", sharedRequire)
local PetHatchMath = originalRequire("src/ReplicatedStorage/Shared/PetHatchMath")
local PetVariantMath = originalRequire("src/ReplicatedStorage/Shared/PetVariantMath")
local PetVariantPresentation = originalRequire("src/ReplicatedStorage/Shared/PetVariantPresentation")
ReplicatedStorage.Shared.PetHatchMath = PetHatchMath
ReplicatedStorage.Shared.PetVariantMath = PetVariantMath
ReplicatedStorage.Shared.PetVariantPresentation = PetVariantPresentation

local function serviceRequire(path)
	if path == Config then return Config end
	if path == BalanceConfig then return BalanceConfig end
	if path == PetData then return PetData end
	if path == PetHatchMath then return PetHatchMath end
	if path == PetVariantMath then return PetVariantMath end
	if path == PetVariantPresentation then return PetVariantPresentation end
	return originalRequire(path)
end
rawset(_G, "require", serviceRequire)
local PetService = originalRequire("src/ServerScriptService/Services/PetService")
local MachineService = originalRequire("src/ServerScriptService/Services/MachineService")
rawset(_G, "require", originalRequire)

-- PetService may already be cached by its earlier spec with that spec's private
-- ReplicatedStorage mock. Count the public replication boundary directly here.
local inventoryShouldError = false
PetService.replicateInventory = function()
	if inventoryShouldError then error("injected inventory notification failure") end
	inventoryEvents = inventoryEvents + 1
end

local player = { Name = "MachineTester", UserId = 501 }
local profile = nil
local pendingTransactions = {}
local currencyEvents = 0
local rollbackCalls = 0
local commitMode = "success"
local rollbackMode = "success"
local questShouldError = false
local questCalls = {}

local dataService = {}
function dataService.getPlayerData()
	return profile
end

local currencyService = {}
function currencyService.beginSpendTransaction(_, currency, amount)
	if not profile or type(profile[currency]) ~= "number" or profile[currency] < amount then
		return nil
	end
	local transaction = {}
	pendingTransactions[transaction] = {
		profile = profile,
		currency = currency,
		amount = amount,
	}
	profile[currency] = profile[currency] - amount
	return transaction
end
function currencyService.commitSpendTransaction(transaction)
	local pending = pendingTransactions[transaction]
	if not pending then return false end
	if commitMode == "error" then error("injected currency commit failure") end
	if commitMode == "false" then return false end
	pendingTransactions[transaction] = nil
	currencyEvents = currencyEvents + 1
	return true
end
function currencyService.rollbackSpendTransaction(transaction)
	local pending = pendingTransactions[transaction]
	if not pending then return false end
	if rollbackMode == "error" then error("injected currency rollback failure") end
	if rollbackMode == "false" then return false end
	pendingTransactions[transaction] = nil
	pending.profile[pending.currency] = pending.profile[pending.currency] + pending.amount
	rollbackCalls = rollbackCalls + 1
	return true
end

local upgradeService = {}
function upgradeService.getUpgradeBonus()
	return 0
end
local questService = {}
function questService.incrementStat(_, statType, amount)
	if questShouldError then error("injected quest notification failure") end
	table.insert(questCalls, { statType = statType, amount = amount })
	profile.questStats[statType] = (profile.questStats[statType] or 0) + amount
end

local function makePet(id, petId, variant, shiny)
	local presentation = PetVariantPresentation.resolve({ petId = petId, variant = variant, shiny = shiny })
	return {
		id = id,
		petId = petId,
		name = presentation.displayPetName,
		rarity = PetData.Pets[petId].rarity,
		damage = PetVariantMath.getBaseDamage(petId, variant, shiny),
		variant = variant,
		shiny = shiny == true,
		golden = variant == "Golden",
		favorite = false,
		equipped = false,
	}
end

local ACTIVATION_TOKEN = "server-gold-machine-token"

local function resetState(pets, zones)
	profile = {
		coins = 0,
		diamonds = 10000,
		pets = pets or { makePet("pet-1", "Buddy", "Normal", false) },
		equippedPets = {},
		discoveredPets = {},
		unlockedZones = zones or { 1, 2, 3, 4, 5, 6 },
		questStats = { goldenPetsConverted = 0 },
	}
	pendingTransactions = {}
	currencyEvents = 0
	inventoryEvents = 0
	rollbackCalls = 0
	commitMode = "success"
	rollbackMode = "success"
	inventoryShouldError = false
	questShouldError = false
	questCalls = {}
	PetService.init(dataService, currencyService, upgradeService)
	MachineService.init(dataService, currencyService, PetService)
	MachineService.setQuestService(questService)
	MachineService.setActivationValidator(function(_, machineId, activationToken)
		return machineId == "GoldMachine" and activationToken == ACTIVATION_TOKEN
	end)
	MachineService.setRandomSource(function()
		return 0
	end)
end

local function attempt(machineId, ids)
	return MachineService.attemptConversion(player, machineId, ACTIVATION_TOKEN, ids)
end

local function idsFor(count)
	local pets = {}
	local ids = {}
	for index = 1, count do
		local id = "pet-" .. tostring(index)
		pets[index] = makePet(id, "Buddy", "Normal", index == count)
		ids[index] = id
	end
	return pets, ids
end

describe("MachineService QOF-16 definitions and strict admission", function()
	it("keeps canonical economics exact while enabling only Gold", function()
		expect(BalanceConfig.Machines.RuntimeEnabled):toBeTrue()
		expect(BalanceConfig.Machines.Gold):toEqual({
			RuntimeEnabled = true,
			id = "GoldMachine", zoneId = 3, inputVariant = "Normal", outputVariant = "Golden",
			cost = { currency = "diamonds", amount = 750 },
		})
		expect(BalanceConfig.Machines.Rainbow):toEqual({
			RuntimeEnabled = false,
			id = "RainbowMachine", zoneId = 6, inputVariant = "Golden", outputVariant = "Rainbow",
			cost = { currency = "diamonds", amount = 2500 },
		})
		expect(BalanceConfig.Machines.SuccessChanceByInput):toEqual({
			[1] = 0.13, [2] = 0.26, [3] = 0.39, [4] = 0.50,
			[5] = 0.63, [6] = 0.88, [7] = 1.00,
		})
	end)

	it("honors the global kill switch and fails closed without a validator", function()
		resetState()
		local originalGate = BalanceConfig.Machines.RuntimeEnabled
		BalanceConfig.Machines.RuntimeEnabled = false
		local result, message = MachineService.attemptConversion(
			player,
			"GoldMachine",
			ACTIVATION_TOKEN,
			{ "pet-1" }
		)
		BalanceConfig.Machines.RuntimeEnabled = originalGate
		expect(result):toBeNil()
		expect(message):toBe("Machines are not available")
		expect(profile.diamonds):toBe(10000)

		MachineService.setActivationValidator(nil)
		result, message = attempt("GoldMachine", { "pet-1" })
		expect(result):toBeNil()
		expect(message):toBe("Machine activation unavailable")
		expect(profile.diamonds):toBe(10000)
	end)

	it("requires a bounded server activation token before world validation", function()
		resetState()
		local validatorCalls = 0
		MachineService.setActivationValidator(function()
			validatorCalls = validatorCalls + 1
			return true
		end)
		for _, invalidToken in ipairs({ "", string.rep("x", 129) }) do
			local result, message = MachineService.attemptConversion(
				player,
				"GoldMachine",
				invalidToken,
				{ "pet-1" }
			)
			expect(result):toBeNil()
			expect(message):toBe("Invalid machine activation")
		end
		local result, message = MachineService.attemptConversion(player, "GoldMachine", nil, { "pet-1" })
		expect(result):toBeNil()
		expect(message):toBe("Invalid machine activation")
		expect(validatorCalls):toBe(0)
		expect(profile.diamonds):toBe(10000)
	end)

	it("rejects unknown machines, locked zones, denied activation, and invalid players", function()
		resetState(nil, { 1, 2 })
		expect(attempt("UnknownMachine", { "pet-1" })):toBeNil()
		local result, message = attempt("GoldMachine", { "pet-1" })
		expect(result):toBeNil()
		expect(message):toBe("Machine zone is locked")
		MachineService.setActivationValidator(function() return false, "too far" end)
		profile.unlockedZones = { 1, 2, 3 }
		result, message = attempt("GoldMachine", { "pet-1" })
		expect(result):toBeNil()
		expect(message):toBe("too far")
		local oldUserId = player.UserId
		player.UserId = 1.5
		result = attempt("GoldMachine", { "pet-1" })
		player.UserId = oldUserId
		expect(result):toBeNil()
		expect(profile.diamonds):toBe(10000)
	end)

	it("rejects non-dense, extra-keyed, empty, oversized, malformed, and duplicate ID lists", function()
		resetState()
		local invalidLists = {
			{},
			{ [2] = "pet-1" },
			{ [1] = "pet-1", extra = "pet-2" },
			{ "pet-1", "pet-1" },
			{ 12 },
			{ "" },
			{ "1", "2", "3", "4", "5", "6", "7", "8" },
		}
		for _, invalid in ipairs(invalidLists) do
			local result = attempt("GoldMachine", invalid)
			expect(result):toBeNil()
		end
		expect(profile.diamonds):toBe(10000)
		expect(#profile.pets):toBe(1)
	end)

	it("rejects stale ownership, mixed species, wrong variants, favorites, and both equipped representations", function()
		local cases = {
			function() return { "missing" } end,
			function() profile.pets[2] = makePet("pet-2", "Whiskers", "Normal", false); return { "pet-1", "pet-2" } end,
			function() profile.pets[1] = makePet("pet-1", "Buddy", "Golden", false); return { "pet-1" } end,
			function() profile.pets[1].favorite = true; return { "pet-1" } end,
			function() profile.pets[1].equipped = true; return { "pet-1" } end,
			function() profile.equippedPets = { "pet-1" }; return { "pet-1" } end,
		}
		for _, arrange in ipairs(cases) do
			resetState()
			local result = attempt("GoldMachine", arrange())
			expect(result):toBeNil()
			expect(profile.diamonds):toBe(10000)
		end
	end)
end)

describe("MachineService QOF-16 chance and business outcomes", function()
	it("uses every exact chance boundary and guarantees seven inputs", function()
		for count, chance in ipairs(BalanceConfig.Machines.SuccessChanceByInput) do
			local pets, ids = idsFor(count)
			resetState(pets)
			MachineService.setRandomSource(function() return chance end)
			local result = attempt("GoldMachine", ids)
			expect(result.success):toBeTrue()
			expect(result.chance):toBe(chance)

			if count < 7 then
				pets, ids = idsFor(count)
				resetState(pets)
				MachineService.setRandomSource(function() return chance + 0.000001 end)
				result = attempt("GoldMachine", ids)
				expect(result.success):toBeFalse()
			end
		end
	end)

	it("consumes exact inputs and Gold price on an ordinary failed roll", function()
		local pets, ids = idsFor(3)
		resetState(pets)
		MachineService.setRandomSource(function() return 1 end)
		local result, message = attempt("GoldMachine", ids)
		expect(message):toBeNil()
		expect(result.success):toBeFalse()
		expect(profile.diamonds):toBe(9250)
		expect(#profile.pets):toBe(0)
		expect(profile.discoveredPets):toEqual({})
		expect(currencyEvents):toBe(1)
		expect(inventoryEvents):toBe(1)
		expect(#questCalls):toBe(0)
	end)

	it("creates one canonical Shiny Gold result and increments the quest only post-commit", function()
		local pets, ids = idsFor(2)
		resetState(pets)
		local result = attempt("GoldMachine", ids)
		expect(result.success):toBeTrue()
		expect(profile.diamonds):toBe(9250)
		expect(#profile.pets):toBe(1)
		local output = profile.pets[1]
		expect(output):toBe(result.outputPet)
		expect(output.petId):toBe("Buddy")
		expect(output.variant):toBe("Golden")
		expect(output.shiny):toBeTrue()
		expect(output.golden):toBeTrue()
		expect(output.name):toBe("Gold Shiny Buddy")
		expect(output.damage):toBe(3)
		expect(output.isNewDiscovery):toBeNil()
		expect(profile.discoveredPets.Shiny_Buddy):toBeTrue()
		expect(result.isNewDiscovery):toBeTrue()
		expect(questCalls):toEqual({ { statType = "goldenPetsConverted", amount = 1 } })
		expect(profile.questStats.goldenPetsConverted):toBe(1)
		expect(currencyEvents):toBe(1)
		expect(inventoryEvents):toBe(1)
	end)

	it("rejects dormant Rainbow before profile, validator, pet, RNG, currency, or quest work", function()
		resetState({
			makePet("gold-1", "Buddy", "Golden", false),
			makePet("gold-2", "Buddy", "Golden", true),
		})
		local calls = { profile = 0, validator = 0, pet = 0, rng = 0, currency = 0 }
		local originalGetPlayerData = dataService.getPlayerData
		local originalPrepare = PetService.prepareVariantConversion
		local originalBeginSpend = currencyService.beginSpendTransaction
		dataService.getPlayerData = function(...)
			calls.profile = calls.profile + 1
			return originalGetPlayerData(...)
		end
		PetService.prepareVariantConversion = function(...)
			calls.pet = calls.pet + 1
			return originalPrepare(...)
		end
		currencyService.beginSpendTransaction = function(...)
			calls.currency = calls.currency + 1
			return originalBeginSpend(...)
		end
		MachineService.setActivationValidator(function()
			calls.validator = calls.validator + 1
			return true
		end)
		MachineService.setRandomSource(function()
			calls.rng = calls.rng + 1
			return 0
		end)

		local result, message = attempt("RainbowMachine", { "gold-1", "gold-2" })
		dataService.getPlayerData = originalGetPlayerData
		PetService.prepareVariantConversion = originalPrepare
		currencyService.beginSpendTransaction = originalBeginSpend

		expect(result):toBeNil()
		expect(message):toBe("Machine is not available")
		expect(calls):toEqual({ profile = 0, validator = 0, pet = 0, rng = 0, currency = 0 })
		expect(profile.diamonds):toBe(10000)
		expect(#profile.pets):toBe(2)
		expect(#questCalls):toBe(0)
	end)

	it("uses projected capacity after consumption instead of requiring a free slot first", function()
		local pets = {}
		for index = 1, 100 do
			pets[index] = makePet("pet-" .. tostring(index), "Buddy", "Normal", false)
		end
		resetState(pets)
		local result = attempt("GoldMachine", { "pet-1" })
		expect(result.success):toBeTrue()
		expect(#profile.pets):toBe(100)
	end)

	it("rejects insufficient diamonds without rolling, mutation, or replication", function()
		resetState()
		profile.diamonds = 749
		local rolls = 0
		MachineService.setRandomSource(function() rolls = rolls + 1; return 0 end)
		local result = attempt("GoldMachine", { "pet-1" })
		expect(result):toBeNil()
		expect(profile.diamonds):toBe(749)
		expect(#profile.pets):toBe(1)
		expect(rolls):toBe(0)
		expect(currencyEvents):toBe(0)
		expect(inventoryEvents):toBe(0)
	end)
end)

describe("MachineService QOF-16 rollback and lock semantics", function()
	it("restores exact currency, ordered inventory identity, and discovery shape after spend faults", function()
		resetState({ makePet("a", "Buddy", "Normal", false), makePet("b", "Buddy", "Normal", false) })
		profile.discoveredPets = nil
		local inventory = profile.pets
		local first = inventory[1]
		local second = inventory[2]
		MachineService.setTransactionHook(function(stage)
			if stage == "afterSpend" then error("injected after spend") end
		end)
		local result, message = attempt("GoldMachine", { "a" })
		expect(result):toBeNil()
		expect(message):toBe("Conversion failed safely")
		expect(profile.diamonds):toBe(10000)
		expect(profile.pets):toBe(inventory)
		expect(profile.pets[1]):toBe(first)
		expect(profile.pets[2]):toBe(second)
		expect(profile.discoveredPets):toBeNil()
		expect(rollbackCalls):toBe(1)
		expect(currencyEvents):toBe(0)
		expect(inventoryEvents):toBe(0)
		expect(#questCalls):toBe(0)
	end)

	it("restores exact table identities, order, and discovery content after pet mutation faults", function()
		resetState({
			makePet("keep-1", "Buddy", "Normal", false),
			makePet("remove", "Buddy", "Normal", true),
			makePet("keep-2", "Buddy", "Normal", false),
		})
		local inventory = profile.pets
		local discovery = { Buddy = true, custom = "preserve" }
		profile.discoveredPets = discovery
		local original = { inventory[1], inventory[2], inventory[3] }
		MachineService.setTransactionHook(function(stage)
			if stage == "afterPetMutation" then error("injected after mutation") end
		end)
		local result = attempt("GoldMachine", { "remove" })
		expect(result):toBeNil()
		expect(profile.diamonds):toBe(10000)
		expect(profile.pets):toBe(inventory)
		expect(profile.pets[1]):toBe(original[1])
		expect(profile.pets[2]):toBe(original[2])
		expect(profile.pets[3]):toBe(original[3])
		expect(profile.discoveredPets):toBe(discovery)
		expect(profile.discoveredPets):toEqual({ Buddy = true, custom = "preserve" })
		expect(currencyEvents):toBe(0)
		expect(inventoryEvents):toBe(0)
		expect(#questCalls):toBe(0)
	end)

	it("treats invalid RNG as technical failure and restores the silent debit", function()
		resetState()
		MachineService.setRandomSource(function() return 0 / 0 end)
		local result = attempt("GoldMachine", { "pet-1" })
		expect(result):toBeNil()
		expect(profile.diamonds):toBe(10000)
		expect(#profile.pets):toBe(1)
		expect(rollbackCalls):toBe(1)
		expect(currencyEvents):toBe(0)
	end)

	it("rolls back pet and currency state when currency commit fails or throws", function()
		for _, mode in ipairs({ "false", "error" }) do
			resetState()
			local inventory = profile.pets
			local originalPet = inventory[1]
			commitMode = mode
			local result, message = attempt("GoldMachine", { "pet-1" })
			expect(result):toBeNil()
			expect(message):toBe("Conversion failed safely")
			expect(profile.diamonds):toBe(10000)
			expect(profile.pets):toBe(inventory)
			expect(profile.pets[1]):toBe(originalPet)
			expect(profile.discoveredPets):toEqual({})
			expect(rollbackCalls):toBe(1)
			expect(currencyEvents):toBe(0)
			expect(inventoryEvents):toBe(0)
			expect(MachineService._playerLocks[player.UserId]):toBeNil()
		end
	end)

	it("reports failed restorations instead of claiming rollback safety", function()
		for _, mode in ipairs({ "false", "error" }) do
			resetState()
			rollbackMode = mode
			MachineService.setTransactionHook(function(stage)
				if stage == "beforeCommit" then error("injected before commit") end
			end)
			local result, message = attempt("GoldMachine", { "pet-1" })
			expect(result):toBeNil()
			expect(message):toBe("Conversion rollback failed")
			expect(profile.diamonds):toBe(9250)
			expect(#profile.pets):toBe(1)
			expect(profile.pets[1].id):toBe("pet-1")
			expect(currencyEvents):toBe(0)
			expect(inventoryEvents):toBe(0)
			expect(MachineService._playerLocks[player.UserId]):toBeNil()
		end
	end)

	it("keeps committed economics successful when protected notifications throw", function()
		resetState()
		inventoryShouldError = true
		questShouldError = true
		local result, message = attempt("GoldMachine", { "pet-1" })
		expect(message):toBeNil()
		expect(result.success):toBeTrue()
		expect(profile.diamonds):toBe(9250)
		expect(#profile.pets):toBe(1)
		expect(profile.pets[1].variant):toBe("Golden")
		expect(currencyEvents):toBe(1)
		expect(inventoryEvents):toBe(0)
		expect(#questCalls):toBe(0)
		expect(MachineService._playerLocks[player.UserId]):toBeNil()
	end)

	it("rejects reentrant work under the per-player lock and cleanup releases stale locks", function()
		resetState()
		local nestedResult = true
		local nestedMessage = nil
		MachineService.setTransactionHook(function(stage)
			if stage == "afterSpend" then
				nestedResult, nestedMessage = MachineService.attemptConversion(
					player,
					"GoldMachine",
					ACTIVATION_TOKEN,
					{ "pet-1" }
				)
			end
		end)
		local result = attempt("GoldMachine", { "pet-1" })
		expect(result.success):toBeTrue()
		expect(nestedResult):toBeNil()
		expect(nestedMessage):toBe("Machine conversion already in progress")
		MachineService._playerLocks[player.UserId] = true
		MachineService.cleanup(player)
		expect(MachineService._playerLocks[player.UserId]):toBeNil()
	end)
end)

describe("QOF-16 server source contracts", function()
	it("wires only UseMachine with strict limits and post-init world authority", function()
		if not io or not io.open then return end
		local mainFile = assert(io.open("src/ServerScriptService/Main.server.lua", "rb"))
		local mainSource = mainFile:read("*a")
		mainFile:close()
		local machineFile = assert(io.open("src/ServerScriptService/Services/MachineService.lua", "rb"))
		local machineSource = machineFile:read("*a")
		machineFile:close()
		local zoneFile = assert(io.open("src/ServerScriptService/Services/ZoneService.lua", "rb"))
		local zoneSource = zoneFile:read("*a")
		zoneFile:close()

		expect(string.find(mainSource, '"UseMachine"', 1, true) ~= nil):toBeTrue()
		expect(string.find(mainSource, 'getRemoteFunction("UseMachine").OnServerInvoke', 1, true) ~= nil):toBeTrue()
		expect(string.find(mainSource, 'canCall(player, "UseMachine"', 1, true) ~= nil):toBeTrue()
		expect(string.find(mainSource, 'canCallBurst(player, "UseMachine"', 1, true) ~= nil):toBeTrue()
		expect(string.find(mainSource, "return MachineService.attemptConversion", 1, true) ~= nil):toBeTrue()
		expect(string.find(mainSource, "MachineService.setActivationValidator(activationValidatorOrError)", 1, true) ~= nil):toBeTrue()
		expect(string.find(mainSource, "ConvertToGoldenPet", 1, true) == nil):toBeTrue()
		expect(string.find(mainSource, "PetService.convertToGoldenPet", 1, true) == nil):toBeTrue()
		expect(string.find(mainSource, "goldenPetsConverted", 1, true) == nil):toBeTrue()
		expect(string.find(machineSource, '"goldenPetsConverted"', 1, true) ~= nil):toBeTrue()

		expect(string.find(zoneSource, "local machineRegistry = {}", 1, true) ~= nil):toBeTrue()
		expect(string.find(zoneSource, "GenerateGUID(false)", 1, true) ~= nil):toBeTrue()
		expect(string.find(zoneSource, 'Instance.new("Model")', 1, true) ~= nil):toBeTrue()
		expect(string.find(zoneSource, 'anchor.Name = "Anchor"', 1, true) ~= nil):toBeTrue()
		expect(string.find(zoneSource, 'Instance.new("ProximityPrompt")', 1, true) ~= nil):toBeTrue()
		expect(string.find(zoneSource, "local function validateMachineActivation", 1, true) ~= nil):toBeTrue()
		expect(string.find(zoneSource, "return validateMachineActivation", 1, true) ~= nil):toBeTrue()
		expect(string.find(zoneSource, 'BalanceConfig.Machines.Gold', 1, true) ~= nil):toBeTrue()
		expect(string.find(zoneSource, 'BalanceConfig.Machines.Rainbow', 1, true) == nil):toBeTrue()
	end)
end)



describe("MachineService QOF-16 adversarial transaction boundaries", function()
	it("isolates transaction economics from canonical mutation during activation", function()
		resetState()
		local gold = BalanceConfig.Machines.Gold
		local originalId = gold.id
		local originalZoneId = gold.zoneId
		local originalInputVariant = gold.inputVariant
		local originalOutputVariant = gold.outputVariant
		local originalCost = gold.cost
		MachineService.setActivationValidator(function(_, machineId, activationToken)
			expect(machineId):toBe("GoldMachine")
			expect(activationToken):toBe(ACTIVATION_TOKEN)
			gold.id = "ForgedMachine"
			gold.zoneId = 999
			gold.inputVariant = "Golden"
			gold.outputVariant = "Rainbow"
			gold.cost = { currency = "coins", amount = 1 }
			return true
		end)
		local result, message = attempt("GoldMachine", { "pet-1" })
		gold.id = originalId
		gold.zoneId = originalZoneId
		gold.inputVariant = originalInputVariant
		gold.outputVariant = originalOutputVariant
		gold.cost = originalCost
		expect(message):toBeNil()
		expect(result.machineId):toBe("GoldMachine")
		expect(result.cost):toBe(750)
		expect(result.currency):toBe("diamonds")
		expect(profile.diamonds):toBe(9250)
		expect(gold.id):toBe("GoldMachine")
		expect(gold.zoneId):toBe(3)
		expect(gold.inputVariant):toBe("Normal")
		expect(gold.outputVariant):toBe("Golden")
		expect(gold.cost):toBe(originalCost)
		expect(gold.cost.amount):toBe(750)
	end)

	it("rejects hostile metatables before invoking any ID-list metamethod", function()
		resetState()
		local metamethodCalls = 0
		local hostile = setmetatable({ "pet-1" }, {
			__len = function() metamethodCalls = metamethodCalls + 1; error("hostile __len") end,
			__pairs = function() metamethodCalls = metamethodCalls + 1; error("hostile __pairs") end,
			__index = function() metamethodCalls = metamethodCalls + 1; error("hostile __index") end,
		})
		local callOk, result, message = pcall(function()
			return attempt("GoldMachine", hostile)
		end)
		expect(callOk):toBeTrue()
		expect(result):toBeNil()
		expect(message):toBe("Pet IDs must be a plain dense list")
		expect(metamethodCalls):toBe(0)
		expect(profile.diamonds):toBe(10000)
		expect(#profile.pets):toBe(1)

		local directOk, prepared, prepareError = pcall(function()
			return PetService.prepareVariantConversion(player, hostile, "Normal", "Golden")
		end)
		expect(directOk):toBeTrue()
		expect(prepared):toBeNil()
		expect(prepareError):toBe("Pet IDs must be a plain dense list")
		expect(metamethodCalls):toBe(0)
	end)

	it("rejects discovery content divergence without clobbering new progress", function()
		resetState()
		local inventory = profile.pets
		local originalPet = inventory[1]
		MachineService.setTransactionHook(function(stage)
			if stage == "afterSpend" then
				profile.discoveredPets.External = true
			end
		end)
		local result, message = attempt("GoldMachine", { "pet-1" })
		expect(result):toBeNil()
		expect(message):toBe("Discovery changed during conversion")
		expect(profile.diamonds):toBe(10000)
		expect(profile.pets):toBe(inventory)
		expect(profile.pets[1]):toBe(originalPet)
		expect(profile.discoveredPets.External):toBeTrue()
		expect(rollbackCalls):toBe(1)
		expect(currencyEvents):toBe(0)
		expect(inventoryEvents):toBe(0)
	end)

	it("rejects discovery identity divergence and preserves the replacement", function()
		resetState()
		local replacement = { External = true }
		MachineService.setTransactionHook(function(stage)
			if stage == "afterSpend" then
				profile.discoveredPets = replacement
			end
		end)
		local result, message = attempt("GoldMachine", { "pet-1" })
		expect(result):toBeNil()
		expect(message):toBe("Discovery changed during conversion")
		expect(profile.diamonds):toBe(10000)
		expect(profile.discoveredPets):toBe(replacement)
		expect(profile.discoveredPets.External):toBeTrue()
		expect(#profile.pets):toBe(1)
	end)

	it("rolls back only its discovery key and remains idempotent", function()
		resetState()
		local inventory = profile.pets
		local originalPet = inventory[1]
		local discovery = profile.discoveredPets
		local capturedPrepared = nil
		MachineService.setTransactionHook(function(stage, context)
			if stage == "afterPetMutation" then
				capturedPrepared = context.prepared
				profile.discoveredPets.External = true
				error("injected concurrent discovery progress")
			end
		end)
		local result, message = attempt("GoldMachine", { "pet-1" })
		expect(result):toBeNil()
		expect(message):toBe("Conversion failed safely")
		expect(profile.diamonds):toBe(10000)
		expect(profile.pets):toBe(inventory)
		expect(profile.pets[1]):toBe(originalPet)
		expect(profile.discoveredPets):toBe(discovery)
		expect(profile.discoveredPets.External):toBeTrue()
		expect(profile.discoveredPets[capturedPrepared.discoveryKey]):toBeNil()
		expect(rollbackCalls):toBe(1)

		local secondRollback = PetService.rollbackVariantConversion(capturedPrepared)
		expect(secondRollback):toBeTrue()
		expect(profile.diamonds):toBe(10000)
		expect(profile.pets):toBe(inventory)
		expect(profile.pets[1]):toBe(originalPet)
		expect(profile.discoveredPets):toBe(discovery)
		expect(profile.discoveredPets.External):toBeTrue()
		expect(rollbackCalls):toBe(1)
	end)

	it("never replaces discovery progress installed after pet mutation", function()
		resetState()
		local replacement = { External = true }
		MachineService.setTransactionHook(function(stage)
			if stage == "afterPetMutation" then
				profile.discoveredPets = replacement
				error("injected discovery replacement")
			end
		end)
		local result, message = attempt("GoldMachine", { "pet-1" })
		expect(result):toBeNil()
		expect(message):toBe("Conversion failed safely")
		expect(profile.diamonds):toBe(10000)
		expect(profile.discoveredPets):toBe(replacement)
		expect(profile.discoveredPets.External):toBeTrue()
		expect(#profile.pets):toBe(1)
		expect(profile.pets[1].id):toBe("pet-1")
	end)
end)
