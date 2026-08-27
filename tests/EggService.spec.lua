-- EggService.spec.lua - Paid QOF-06 single-egg orchestration regressions.

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
function startEvent:FireClient(player, eggType)
	table.insert(startEvents, { player = player, eggType = eggType })
end
local resultEvent = {}
function resultEvent:FireClient(player, pet)
	table.insert(resultEvents, {
		player = player,
		variant = pet.variant,
		shiny = pet.shiny,
		isNewDiscovery = pet.isNewDiscovery,
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
rawset(_G, "task", { wait = function() end })

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
local removedCoins = 0
local refundedCoins = 0
local hatchResult = nil
local hatchError = nil
local questHatches = 0

local dataService = {}
function dataService.getPlayerData()
	return profile
end
local currencyService = {}
function currencyService.removeCoins(_, amount)
	removedCoins = removedCoins + amount
	return true
end
function currencyService.addCoins(_, amount)
	refundedCoins = refundedCoins + amount
end
local petService = {}
function petService.canAddPet()
	if profile.capacityBlocked then
		return false, "Pet inventory full"
	end
	return true
end
function petService.hatchEgg(_, eggType, skipCostDeduction)
	expect(eggType):toBe("BasicEgg")
	expect(skipCostDeduction):toBeTrue()
	return hatchResult, hatchError
end
local questService = {}
function questService.incrementStat(_, statName, amount)
	expect(statName):toBe("hatchEggs")
	questHatches = questHatches + amount
end

EggService.init(dataService, currencyService, petService)
EggService.setQuestService(questService)

local function resetState()
	profile = { unlockedZones = { 1 }, capacityBlocked = false }
	removedCoins = 0
	refundedCoins = 0
	hatchResult = {
		id = "pet-1",
		petId = "Buddy",
		variant = "Golden",
		shiny = true,
		isNewDiscovery = true,
	}
	hatchError = nil
	questHatches = 0
	startEvents = {}
	resultEvents = {}
	EggService._hatchLock[player.UserId] = nil
end

describe("EggService paid QOF-06 single hatch", function()
	it("charges once, emits the canonical result, advances quests, and releases its lock", function()
		resetState()
		local pet, err = EggService.purchaseAndHatch(player, "BasicEgg")
		local expectedCost = Config.EggCosts[1].Coins

		expect(err):toBeNil()
		expect(pet):toBe(hatchResult)
		expect(removedCoins):toBe(expectedCost)
		expect(refundedCoins):toBe(0)
		expect(#startEvents):toBe(1)
		expect(startEvents[1].eggType):toBe("BasicEgg")
		expect(#resultEvents):toBe(1)
		expect(resultEvents[1].variant):toBe("Golden")
		expect(resultEvents[1].shiny):toBeTrue()
		expect(resultEvents[1].isNewDiscovery):toBeTrue()
		expect(hatchResult.isNewDiscovery):toBeNil()
		expect(questHatches):toBe(1)
		expect(EggService._hatchLock[player.UserId]):toBeNil()
	end)

	it("refunds exactly once and suppresses result and quest events when construction fails", function()
		resetState()
		hatchResult = nil
		hatchError = "Invalid pet in pool"
		local pet, err = EggService.purchaseAndHatch(player, "BasicEgg")
		local expectedCost = Config.EggCosts[1].Coins

		expect(pet):toBeNil()
		expect(err):toBe("Invalid pet in pool")
		expect(removedCoins):toBe(expectedCost)
		expect(refundedCoins):toBe(expectedCost)
		expect(#startEvents):toBe(1)
		expect(#resultEvents):toBe(0)
		expect(questHatches):toBe(0)
		expect(EggService._hatchLock[player.UserId]):toBeNil()
	end)

	it("rejects locked zones and full inventories before charging", function()
		resetState()
		profile.unlockedZones = {}
		local zonePet, zoneError = EggService.purchaseAndHatch(player, "BasicEgg")
		expect(zonePet):toBeNil()
		expect(zoneError):toBe("Zone not unlocked for this egg type")
		expect(removedCoins):toBe(0)

		resetState()
		profile.capacityBlocked = true
		local capacityPet, capacityError = EggService.purchaseAndHatch(player, "BasicEgg")
		expect(capacityPet):toBeNil()
		expect(capacityError):toBe("Pet inventory full")
		expect(removedCoins):toBe(0)
		expect(#startEvents):toBe(0)
		expect(#resultEvents):toBe(0)
	end)
end)
