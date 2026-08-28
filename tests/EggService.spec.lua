-- EggService.spec.lua - QOF-08 atomic paid batch transaction regressions.

local originalRequire = require
local Config = {
	EggCosts = {
		[1] = { Coins = 100 },
	},
}
local PetData = originalRequire("src/ReplicatedStorage/Shared/PetData")

local startEvents = {}
local resultEvents = {}
local startEvent = {}
function startEvent:FireClient(_, payload)
	table.insert(startEvents, {
		batchId = payload.batchId,
		eggType = payload.eggType,
		count = payload.count,
		totalCost = payload.totalCost,
	})
end
local resultEvent = {}
function resultEvent:FireClient(_, payload)
	local pets = {}
	for _, pet in ipairs(payload.pets or {}) do
		table.insert(pets, {
		id = pet.id,
		variant = pet.variant,
		shiny = pet.shiny,
		isNewDiscovery = pet.isNewDiscovery,
		})
	end
	table.insert(resultEvents, {
		batchId = payload.batchId,
		eggType = payload.eggType,
		count = payload.count,
		totalCost = payload.totalCost,
		pets = pets,
	})
end
local remotes = {}
function remotes:FindFirstChild(name)
	if name == "EggHatchStart" then return startEvent end
	if name == "EggHatchResult" then return resultEvent end
	return nil
end
local replicatedStorage = {
	Shared = { Config = Config, PetData = PetData },
}
function replicatedStorage:FindFirstChild(name)
	if name == "Remotes" then return remotes end
	return nil
end
local gameMock = { ReplicatedStorage = replicatedStorage }
function gameMock:GetService(name)
	if name == "ReplicatedStorage" then return replicatedStorage end
	error("Unexpected service: " .. tostring(name))
end
rawset(_G, "game", gameMock)

local function mockRequire(path)
	if path == Config then return Config end
	if path == PetData then return PetData end
	return originalRequire(path)
end
rawset(_G, "require", mockRequire)
local EggService = originalRequire("src/ServerScriptService/Services/EggService")
rawset(_G, "require", originalRequire)

local player = { Name = "Tester", UserId = 42 }
local profile = nil
local maximumBatchCount = 10
local spentCoins = 0
local refundedCoins = 0
local questHatches = 0
local inventoryReplications = 0
local rollbackCount = 0
local prepareError = nil
local prepareThrows = false
local commitError = nil
local commitThrows = false
local stationNear = true
local shinyCharges = 0
local shinyBoostCounts = {}
local shinyCommits = 0
local shinyRollbacks = 0

local dataService = {}
function dataService.getPlayerData()
	return profile
end

local currencyService = {}
function currencyService.spend(_, currency, amount)
	expect(currency):toBe("coins")
	if profile.coins < amount then
		return false
	end
	profile.coins = profile.coins - amount
	spentCoins = spentCoins + amount
	return true
end
function currencyService.creditRaw(_, currency, amount)
	expect(currency):toBe("coins")
	profile.coins = profile.coins + amount
	refundedCoins = refundedCoins + amount
	return true
end

local petService = {}
function petService.getMaxInventory()
	return profile.capacity
end
function petService.canAddPets(_, count)
	if profile.capacityBlocked or #profile.pets + count > profile.capacity then
		return false, "Pet inventory needs " .. tostring(count) .. " free slots"
	end
	return true
end
function petService.prepareHatchBatch(_, eggType, count, options)
	expect(eggType):toBe("BasicEgg")
	table.insert(shinyBoostCounts, type(options) == "table" and options.shinyBoostCount or 0)
	if prepareThrows then error("prepare exploded") end
	if prepareError then return nil, prepareError end
	local pets = {}
	for index = 1, count do
		table.insert(pets, {
			id = "pet-" .. tostring(index),
			petId = "Buddy",
			variant = index % 2 == 0 and "Golden" or "Normal",
			shiny = index == count,
			isNewDiscovery = index == 1,
		})
	end
	return {
		pets = pets,
		originalPetCount = #profile.pets,
		mutationStarted = false,
	}, nil
end
function petService.commitHatchBatch(_, prepared)
	if commitThrows then error("commit exploded") end
	if commitError then return false, commitError end
	prepared.mutationStarted = true
	for _, pet in ipairs(prepared.pets) do
		table.insert(profile.pets, pet)
	end
	return true
end
function petService.rollbackHatchBatch(prepared)
	rollbackCount = rollbackCount + 1
	while #profile.pets > prepared.originalPetCount do
		table.remove(profile.pets)
	end
	prepared.mutationStarted = false
	return true
end
function petService.replicateInventory()
	inventoryReplications = inventoryReplications + 1
end

local questService = {}
function questService.incrementStat(_, statName, amount)
	expect(statName):toBe("hatchEggs")
	questHatches = questHatches + amount
end
local upgradeTreeService = {}
function upgradeTreeService.getEntitlements()
	return { multiOpenCount = maximumBatchCount }
end

local potionService = {}
local pendingShiny = {}
function potionService.beginShinyChargeTransaction(_, count)
	local reserved = math.min(shinyCharges, count)
	if reserved <= 0 then return nil, 0 end
	local handle = {}
	pendingShiny[handle] = { old = shinyCharges }
	shinyCharges = shinyCharges - reserved
	return handle, reserved
end
function potionService.rollbackShinyChargeTransaction(handle)
	local pendingState = pendingShiny[handle]
	if not pendingState then return false end
	pendingShiny[handle] = nil
	shinyCharges = pendingState.old
	shinyRollbacks = shinyRollbacks + 1
	return true
end
function potionService.commitShinyChargeTransaction(handle)
	if not pendingShiny[handle] then return false end
	pendingShiny[handle] = nil
	shinyCommits = shinyCommits + 1
	return true
end

EggService.init(dataService, currencyService, petService, upgradeTreeService)
EggService.setPotionService(potionService)
EggService.setQuestService(questService)
EggService._stationValidator = function()
	return stationNear
end

local function resetState()
	profile = {
		coins = 10000,
		unlockedZones = { 1 },
		pets = {},
		capacity = 100,
		capacityBlocked = false,
		hatchPreferences = { preferredBatchCount = 1 },
	}
	maximumBatchCount = 10
	spentCoins = 0
	refundedCoins = 0
	questHatches = 0
	inventoryReplications = 0
	rollbackCount = 0
	prepareError = nil
	prepareThrows = false
	commitError = nil
	commitThrows = false
	stationNear = true
	shinyCharges = 0
	shinyBoostCounts = {}
	shinyCommits = 0
	shinyRollbacks = 0
	pendingShiny = {}
	startEvents = {}
	resultEvents = {}
	EggService._hatchLock[player.UserId] = nil
	EggService._transactionHook = nil
end

describe("EggService QOF-08 atomic batches", function()
	it("charges one total, commits all pets, emits one DTO, and advances quests by count", function()
		resetState()
		local result, err = EggService.purchaseAndHatch(player, "BasicEgg", 5, {
			bypassStation = false,
		})

		expect(err):toBeNil()
		expect(result.count):toBe(5)
		expect(result.totalCost):toBe(500)
		expect(spentCoins):toBe(500)
		expect(refundedCoins):toBe(0)
		expect(profile.coins):toBe(9500)
		expect(profile.hatchPreferences.preferredBatchCount):toBe(1)
		expect(#profile.pets):toBe(5)
		expect(#startEvents):toBe(1)
		expect(startEvents[1].count):toBe(5)
		expect(#resultEvents):toBe(1)
		expect(resultEvents[1].count):toBe(5)
		expect(#resultEvents[1].pets):toBe(5)
		expect(resultEvents[1].pets[1].isNewDiscovery):toBeTrue()
		expect(result.pets[1].isNewDiscovery):toBeNil()
		expect(inventoryReplications):toBe(1)
		expect(questHatches):toBe(5)
		expect(EggService._hatchLock[player.UserId]):toBeNil()
	end)

	it("keeps single hatch compatible and charges exactly one egg", function()
		resetState()
		maximumBatchCount = 1
		local result, err = EggService.purchaseAndHatch(player, "BasicEgg", 1, {
			bypassStation = false,
		})
		expect(err):toBeNil()
		expect(result.count):toBe(1)
		expect(spentCoins):toBe(100)
		expect(#profile.pets):toBe(1)
		expect(questHatches):toBe(1)
	end)

	it("accepts every whole transaction count through the entitlement cap", function()
		resetState()
		local result, err = EggService.purchaseAndHatch(player, "BasicEgg", 3, {
			bypassStation = false,
		})
		expect(err):toBeNil()
		expect(result.count):toBe(3)
		expect(spentCoins):toBe(300)
		expect(#profile.pets):toBe(3)
	end)

	it("rejects malformed and entitlement-locked transaction counts before mutation", function()
		for _, count in ipairs({ 0, 2.5 }) do
			resetState()
			local result, err = EggService.purchaseAndHatch(player, "BasicEgg", count, {
				bypassStation = false,
			})
			expect(result):toBeNil()
			expect(err):toBe("Invalid hatch count")
			expect(spentCoins):toBe(0)
			expect(#profile.pets):toBe(0)
		end

		resetState()
		maximumBatchCount = 2
		for _, count in ipairs({ 3, 5, 11 }) do
			local result, err = EggService.purchaseAndHatch(player, "BasicEgg", count, {
				bypassStation = false,
			})
			expect(result):toBeNil()
			expect(err):toBe("Multi-Open upgrade required")
		end
		expect(spentCoins):toBe(0)
	end)

	it("requires station proximity manually while allowing server auto-hatch to bypass it", function()
		resetState()
		stationNear = false
		local manualResult, manualError = EggService.purchaseAndHatch(player, "BasicEgg", 2, {
			bypassStation = false,
		})
		expect(manualResult):toBeNil()
		expect(manualError):toBe("Move closer to this egg station")
		expect(spentCoins):toBe(0)

		local autoResult, autoError = EggService.purchaseAndHatch(player, "BasicEgg", 2, {
			bypassStation = true,
		})
		expect(autoError):toBeNil()
		expect(autoResult.count):toBe(2)
		expect(spentCoins):toBe(200)
	end)

	it("preflights zone, total capacity, and total price without partial hatches", function()
		resetState()
		profile.unlockedZones = {}
		local zoneResult, zoneError = EggService.purchaseAndHatch(player, "BasicEgg", 5, true)
		expect(zoneResult):toBeNil()
		expect(zoneError):toBe("Zone not unlocked for this egg type")
		expect(spentCoins):toBe(0)

		resetState()
		profile.hatchPreferences.preferredBatchCount = 2
		profile.capacity = 4
		local capacityResult, capacityError = EggService.purchaseAndHatch(player, "BasicEgg", 5, true)
		expect(capacityResult):toBeNil()
		expect(capacityError):toBe("Pet inventory needs 5 free slots")
		expect(spentCoins):toBe(0)
		expect(profile.hatchPreferences.preferredBatchCount):toBe(2)

		resetState()
		profile.coins = 499
		local coinResult, coinError = EggService.purchaseAndHatch(player, "BasicEgg", 5, true)
		expect(coinResult):toBeNil()
		expect(coinError):toBe("Not enough coins for x5")
		expect(spentCoins):toBe(0)
		expect(#profile.pets):toBe(0)
	end)

	it("rolls back the exact total and every pet after injected transaction faults", function()
		for _, faultStage in ipairs({ "afterSpend", "afterInventory" }) do
			resetState()
			profile.hatchPreferences.preferredBatchCount = 2
			EggService._transactionHook = function(stage)
				if stage == faultStage then
					error("injected " .. stage)
				end
			end
			local result, err = EggService.purchaseAndHatch(player, "BasicEgg", 10, true)
			expect(result):toBeNil()
			expect(err):toBe("Hatch failed safely")
			expect(profile.coins):toBe(10000)
			expect(spentCoins):toBe(1000)
			expect(refundedCoins):toBe(1000)
			expect(#profile.pets):toBe(0)
			expect(#startEvents):toBe(0)
			expect(#resultEvents):toBe(0)
			expect(questHatches):toBe(0)
			expect(profile.hatchPreferences.preferredBatchCount):toBe(2)
			expect(EggService._hatchLock[player.UserId]):toBeNil()
		end
		EggService._transactionHook = nil
	end)

	it("persists a validated selection and reads it after a simulated rejoin", function()
		resetState()
		local selected, selectionError, state = EggService.setSelectedBatchCount(player, 5)
		expect(selected):toBeTrue()
		expect(selectionError):toBeNil()
		expect(state.selectedCount):toBe(5)
		expect(state.maximumCount):toBe(10)
		expect(profile.hatchPreferences.preferredBatchCount):toBe(5)

		-- A fresh service lifecycle has no session selection to restore. The profile
		-- remains the authority and therefore reproduces the saved preference.
		EggService.init(dataService, currencyService, petService, upgradeTreeService)
		expect(EggService.getSelectedBatchCount(player)):toBe(5)
	end)

	it("repairs saved preferences after entitlement loss to the highest allowed tier", function()
		resetState()
		profile.hatchPreferences.preferredBatchCount = 10
		maximumBatchCount = 5
		expect(EggService.getSelectedBatchCount(player)):toBe(5)
		expect(profile.hatchPreferences.preferredBatchCount):toBe(5)

		profile.hatchPreferences.preferredBatchCount = 5
		maximumBatchCount = 2
		local state = EggService.getBatchState(player)
		expect(state.selectedCount):toBe(2)
		expect(state.maximumCount):toBe(2)
		expect(profile.hatchPreferences.preferredBatchCount):toBe(2)

		profile.hatchPreferences.preferredBatchCount = 10
		maximumBatchCount = 1
		expect(EggService.getSelectedBatchCount(player)):toBe(1)
		expect(profile.hatchPreferences.preferredBatchCount):toBe(1)
	end)

	it("repairs invalid saved values to x1 and rejects locked sets without persisting them", function()
		resetState()
		profile.hatchPreferences.preferredBatchCount = 3
		expect(EggService.getSelectedBatchCount(player)):toBe(1)
		expect(profile.hatchPreferences.preferredBatchCount):toBe(1)

		maximumBatchCount = 2
		local selected, selectionError = EggService.setSelectedBatchCount(player, 5)
		expect(selected):toBeFalse()
		expect(selectionError):toBe("Multi-Open upgrade required")
		expect(profile.hatchPreferences.preferredBatchCount):toBe(1)
	end)

	it("revalidates entitlement without mutating preferences for explicit manual counts", function()
		resetState()
		profile.hatchPreferences.preferredBatchCount = 10
		maximumBatchCount = 5
		local result, err = EggService.purchaseAndHatch(player, "BasicEgg", 10, true)
		expect(result):toBeNil()
		expect(err):toBe("Multi-Open upgrade required")
		expect(spentCoins):toBe(0)
		expect(profile.hatchPreferences.preferredBatchCount):toBe(10)

		local autoResult, autoError = EggService.purchaseAndHatch(player, "BasicEgg", nil, true)
		expect(autoError):toBeNil()
		expect(autoResult.count):toBe(5)
		expect(profile.hatchPreferences.preferredBatchCount):toBe(5)
	end)

	it("quotes x1, x3, and feasible Max from fresh server resources", function()
		resetState()
		profile.capacity = 4
		profile.coins = 250
		profile.hatchPreferences.preferredBatchCount = 10
		local quote, quoteError = EggService.getHatchPurchaseOptions(player, "BasicEgg")
		expect(quoteError):toBeNil()
		expect(quote.unitCost):toBe(100)
		expect(quote.entitlementCap):toBe(10)
		expect(quote.freeSlots):toBe(4)
		expect(quote.feasibleMax):toBe(2)
		expect(quote.x1.available):toBeTrue()
		expect(quote.x3.available):toBeFalse()
		expect(quote.max.count):toBe(2)
		expect(profile.hatchPreferences.preferredBatchCount):toBe(10)

		profile.coins = 10000
		quote = EggService.getHatchPurchaseOptions(player, "BasicEgg")
		expect(quote.feasibleMax):toBe(4)
		expect(quote.x3.available):toBeTrue()

		stationNear = false
		local unavailable, proximityError = EggService.getHatchPurchaseOptions(player, "BasicEgg")
		expect(unavailable):toBeNil()
		expect(proximityError):toBe("Move closer to this egg station")
	end)

	it("strictly rejects malformed confirmation DTOs without mutation", function()
		local hostileIntents = {
			{},
			{ mode = "Fixed" },
			{ mode = "Fixed", count = "1" },
			{ mode = "Fixed", count = 2 },
			{ mode = "Fixed", count = 1, extra = true },
			{ mode = "Max", count = 10 },
			{ mode = "Unknown" },
		}
		for _, intent in ipairs(hostileIntents) do
			resetState()
			local result, err = EggService.purchaseFromIntent(player, "BasicEgg", intent)
			expect(result):toBeNil()
			expect(err):toBe("Invalid hatch intent")
			expect(spentCoins):toBe(0)
			expect(#profile.pets):toBe(0)
		end
		local result, err = EggService.purchaseFromIntent(player, "BasicEgg", "Max")
		expect(result):toBeNil()
		expect(err):toBe("Invalid hatch intent")
	end)

	it("enforces x3 entitlement/resources and never changes hatch preferences", function()
		resetState()
		profile.hatchPreferences.preferredBatchCount = 5
		maximumBatchCount = 2
		local lockedResult, lockedError = EggService.purchaseFromIntent(player, "BasicEgg", {
			mode = "Fixed",
			count = 3,
		})
		expect(lockedResult):toBeNil()
		expect(lockedError):toBe("x3 hatch option unavailable")
		expect(profile.hatchPreferences.preferredBatchCount):toBe(5)

		maximumBatchCount = 5
		local result, err = EggService.purchaseFromIntent(player, "BasicEgg", {
			mode = "Fixed",
			count = 3,
		})
		expect(err):toBeNil()
		expect(result.count):toBe(3)
		expect(result.totalCost):toBe(300)
		expect(#profile.pets):toBe(3)
		expect(profile.hatchPreferences.preferredBatchCount):toBe(5)
	end)

	it("serializes intent confirmation before resolving and committing Max", function()
		resetState()
		profile.capacity = 4
		profile.coins = 450
		local checkedLock = false
		EggService._transactionHook = function(stage)
			if stage ~= "afterPrepare" then return end
			expect(EggService._hatchLock[player.UserId]):toBeTrue()
			local concurrent, concurrentError = EggService.purchaseFromIntent(player, "BasicEgg", {
				mode = "Fixed",
				count = 1,
			})
			expect(concurrent):toBeNil()
			expect(concurrentError):toBe("Already hatching eggs")
			checkedLock = true
		end

		local result, err = EggService.purchaseFromIntent(player, "BasicEgg", { mode = "Max" })
		expect(err):toBeNil()
		expect(result.count):toBe(4)
		expect(checkedLock):toBeTrue()
		expect(EggService._hatchLock[player.UserId]):toBeNil()
	end)

	it("resolves variable Max at confirmation and preserves atomic rollback", function()
		resetState()
		profile.capacity = 7
		profile.coins = 450
		profile.hatchPreferences.preferredBatchCount = 10
		local result, err = EggService.purchaseFromIntent(player, "BasicEgg", { mode = "Max" })
		expect(err):toBeNil()
		expect(result.count):toBe(4)
		expect(result.totalCost):toBe(400)
		expect(profile.coins):toBe(50)
		expect(#profile.pets):toBe(4)
		expect(profile.hatchPreferences.preferredBatchCount):toBe(10)

		resetState()
		profile.capacity = 6
		profile.coins = 550
		EggService._transactionHook = function(stage)
			if stage == "afterInventory" then error("injected Max failure") end
		end
		local failed, failureError = EggService.purchaseFromIntent(player, "BasicEgg", { mode = "Max" })
		expect(failed):toBeNil()
		expect(failureError):toBe("Hatch failed safely")
		expect(spentCoins):toBe(500)
		expect(refundedCoins):toBe(500)
		expect(profile.coins):toBe(550)
		expect(#profile.pets):toBe(0)
	end)

	it("consumes Shiny charges only for successfully committed paid manual intent rolls", function()
		resetState()
		shinyCharges = 2
		local result, err = EggService.purchaseFromIntent(player, "BasicEgg", {
			mode = "Fixed",
			count = 3,
		})
		expect(err):toBeNil()
		expect(result.count):toBe(3)
		expect(shinyBoostCounts[1]):toBe(2)
		expect(shinyCharges):toBe(0)
		expect(shinyCommits):toBe(1)
		expect(shinyRollbacks):toBe(0)
	end)

	it("restores exact Shiny charges when a paid manual hatch rolls back", function()
		resetState()
		shinyCharges = 4
		EggService._transactionHook = function(stage)
			if stage == "afterInventory" then error("injected") end
		end
		local result, err = EggService.purchaseFromIntent(player, "BasicEgg", {
			mode = "Fixed",
			count = 3,
		})
		expect(result):toBeNil()
		expect(err):toBe("Hatch failed safely")
		expect(shinyBoostCounts[1]):toBe(3)
		expect(shinyCharges):toBe(4)
		expect(shinyCommits):toBe(0)
		expect(shinyRollbacks):toBe(1)
	end)

	it("does not consume Shiny charges for bypass or free hatches by default", function()
		resetState()
		shinyCharges = 5
		local bypassResult, bypassError = EggService.purchaseAndHatch(player, "BasicEgg", 2, {
			bypassStation = true,
		})
		expect(bypassError):toBeNil()
		expect(bypassResult.count):toBe(2)
		expect(shinyBoostCounts[1]):toBe(0)
		expect(shinyCharges):toBe(5)

		local freeResult, freeError = EggService.hatchFree(player, "BasicEgg")
		expect(freeError):toBeNil()
		expect(freeResult.count):toBe(1)
		expect(shinyBoostCounts[2]):toBe(0)
		expect(shinyCharges):toBe(5)
		expect(shinyCommits):toBe(0)
	end)

	it("cleans transient hatch locks without deleting the persistent preference", function()
		resetState()
		profile.hatchPreferences.preferredBatchCount = 5
		EggService._hatchLock[player.UserId] = true
		EggService.onPlayerRemoving(player)
		expect(EggService._hatchLock[player.UserId]):toBeNil()
		expect(profile.hatchPreferences.preferredBatchCount):toBe(5)
	end)
end)
