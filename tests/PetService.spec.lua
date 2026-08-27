-- PetService.spec.lua - QOF-06 server-authoritative hatch and damage tests.

local originalRequire = require
local BalanceConfig = originalRequire("src/ReplicatedStorage/Shared/BalanceConfig")
local PetData = originalRequire("src/ReplicatedStorage/Shared/PetData")
local SharedMock = {
	BalanceConfig = BalanceConfig,
	PetData = PetData,
}
rawset(_G, "script", { Parent = SharedMock })

local function bootstrapRequire(path)
	if path == BalanceConfig then return BalanceConfig end
	if path == PetData then return PetData end
	return originalRequire(path)
end
rawset(_G, "require", bootstrapRequire)
local PetHatchMath = originalRequire("src/ReplicatedStorage/Shared/PetHatchMath")
local PetVariantMath = originalRequire("src/ReplicatedStorage/Shared/PetVariantMath")
local PetVariantPresentation = originalRequire("src/ReplicatedStorage/Shared/PetVariantPresentation")

local Config = {
	MaxPetInventoryBase = 100,
	MaxPetInventoryAbsolute = 250,
	MaxEquippedPetsBase = 4,
	MaxEquippedPetsAbsolute = 12,
	MaxExtraEquipSlots = 5,
	RAINBOW_CHANCE = BalanceConfig.Legacy.Hatch.RainbowChance,
	SHINY_CHANCE = BalanceConfig.Legacy.Hatch.ShinyChance,
	EggCosts = {
		[1] = { Coins = 100 },
	},
}

local guidCounter = 0
local HttpService = {}
function HttpService:GenerateGUID()
	guidCounter = guidCounter + 1
	return "test-guid-" .. tostring(guidCounter)
end

local ReplicatedStorage = {
	Shared = {
		Config = Config,
		BalanceConfig = BalanceConfig,
		PetData = PetData,
		PetHatchMath = PetHatchMath,
		PetVariantMath = PetVariantMath,
		PetVariantPresentation = PetVariantPresentation,
	},
}
function ReplicatedStorage:FindFirstChild()
	return nil
end

local gameMock = { ReplicatedStorage = ReplicatedStorage }
function gameMock:GetService(name)
	if name == "HttpService" then return HttpService end
	if name == "ReplicatedStorage" then return ReplicatedStorage end
	error("Unexpected service: " .. tostring(name))
end
rawset(_G, "game", gameMock)

local function mockRequire(path)
	if path == Config then return Config end
	if path == BalanceConfig then return BalanceConfig end
	if path == PetData then return PetData end
	if path == PetHatchMath then return PetHatchMath end
	if path == PetVariantMath then return PetVariantMath end
	if path == PetVariantPresentation then return PetVariantPresentation end
	return originalRequire(path)
end
rawset(_G, "require", mockRequire)
local PetService = originalRequire("src/ServerScriptService/Services/PetService")
rawset(_G, "require", originalRequire)

local profile = nil
local strongMultiplier = 0
local questLuckMultiplier = 0
local masteryLuckMultiplier = 0
local shopDamageMultiplier = 1
local shopLuckMultiplier = 1

local dataService = {}
function dataService.getPlayerData()
	return profile
end
local currencyService = {}
function currencyService.removeCoins()
	return true
end
local upgradeService = {}
function upgradeService.getUpgradeBonus(_, upgradeName)
	if upgradeName == "StrongPets" then return strongMultiplier end
	if upgradeName == "LuckyEggs" then return questLuckMultiplier end
	return 0
end
local masteryService = {}
function masteryService.getBuffBonus(_, buffType)
	if buffType == "BetterLuck" then return masteryLuckMultiplier end
	return 0
end
local shopService = {}
function shopService.getShopMultiplier(_, buffType)
	if buffType == "damage" then return shopDamageMultiplier end
	if buffType == "luck" then return shopLuckMultiplier end
	return 1
end

local player = { Name = "Tester", UserId = 1 }
PetService.init(dataService, currencyService, upgradeService)
PetService.setMasteryService(masteryService)
PetService.setShopService(shopService)

local function freshProfile()
	profile = { pets = {}, equippedPets = {}, discoveredPets = {}, shopPurchases = {} }
end

local function hatchWithRolls(baseVariantRoll, shinyRoll)
	freshProfile()
	local rolls = { 0, baseVariantRoll, shinyRoll }
	local rollIndex = 0
	local originalRandom = math.random
	math.random = function()
		rollIndex = rollIndex + 1
		return rolls[rollIndex]
	end
	local pet, hatchError = PetService.hatchEgg(player, "BasicEgg", true)
	math.random = originalRandom
	return pet, hatchError
end

describe("PetService canonical combat damage", function()
	it("ignores a forged damage mirror", function()
		strongMultiplier = 0
		shopDamageMultiplier = 1
		local pet = { petId = "Buddy", variant = "Normal", shiny = true, damage = 999999 }
		expect(PetService.getPetDamage(pet, player)):toBe(1.5)
	end)

	it("applies StrongPets and shop damage once after canonical damage", function()
		strongMultiplier = 2
		shopDamageMultiplier = 3
		local pet = { petId = "Buddy", variant = "Normal", shiny = true, damage = 999999 }
		expect(PetService.getPetDamage(pet, player)):toBe(9)
		strongMultiplier = 0
		shopDamageMultiplier = 1
	end)

	it("gives unknown species zero damage even with a forged mirror", function()
		local pet = { petId = "Unknown", variant = "Rainbow", shiny = true, damage = 999999 }
		expect(PetService.getPetDamage(pet, player)):toBe(0)
	end)
end)

describe("PetService QOF-06 canonical single hatch", function()
	it("constructs all six canonical outcomes with truthful names and damage", function()
		questLuckMultiplier = 0
		masteryLuckMultiplier = 0
		shopLuckMultiplier = 1
		local cases = {
			{ 0.5, 0.5, "Normal", false, "Buddy", 1, "Buddy" },
			{ 0.5, 0, "Normal", true, "Shiny Buddy", 1.5, "Shiny_Buddy" },
			{ 0.001, 0.5, "Golden", false, "Gold Buddy", 2, "Golden_Buddy" },
			{ 0.001, 0, "Golden", true, "Gold Shiny Buddy", 3, "Shiny_Buddy" },
			{ 0, 0.5, "Rainbow", false, "Rainbow Buddy", 5, "Rainbow_Buddy" },
			{ 0, 0, "Rainbow", true, "Rainbow Shiny Buddy", 7.5, "Shiny_Buddy" },
		}

		for _, case in ipairs(cases) do
			local pet, hatchError = hatchWithRolls(case[1], case[2])
			expect(hatchError):toBeNil()
			expect(pet.petId):toBe("Buddy")
			expect(pet.variant):toBe(case[3])
			expect(pet.shiny):toBe(case[4])
			expect(pet.name):toBe(case[5])
			expect(pet.damage):toBe(case[6])
			expect(pet.golden):toBe(case[3] == "Golden")
			expect(profile.discoveredPets[case[7]]):toBeTrue()
		end
	end)

	it("composes all active luck sources and enforces approved caps", function()
		questLuckMultiplier = 2
		masteryLuckMultiplier = 3
		shopLuckMultiplier = 2
		expect(PetService.getHatchLuckMultiplier(player)):toBe(10)

		local pet, hatchError = hatchWithRolls(0.004, 0.0009)
		expect(hatchError):toBeNil()
		expect(pet.variant):toBe("Rainbow")
		expect(pet.shiny):toBeTrue()
		expect(pet.damage):toBe(7.5)

		questLuckMultiplier = 0
		masteryLuckMultiplier = 0
		shopLuckMultiplier = 1
	end)

	it("keeps legacy discovery categories for combined Shiny outcomes", function()
		expect(PetService.getLegacyDiscoveryKey("Buddy", "Normal", false)):toBe("Buddy")
		expect(PetService.getLegacyDiscoveryKey("Buddy", "Golden", false)):toBe("Golden_Buddy")
		expect(PetService.getLegacyDiscoveryKey("Buddy", "Rainbow", false)):toBe("Rainbow_Buddy")
		expect(PetService.getLegacyDiscoveryKey("Buddy", "Golden", true)):toBe("Shiny_Buddy")
		expect(PetService.getLegacyDiscoveryKey("Buddy", "Rainbow", true)):toBe("Shiny_Buddy")
		expect(PetService.getLegacyDiscoveryKey(nil, "Normal", false)):toBeNil()
	end)
end)

describe("PetService legacy Golden conversion regression", function()
	it("creates canonical Golden damage and preserves conversion behavior", function()
		profile = {
			pets = {
				{
					id = "normal-1",
					petId = "Buddy",
					name = "Buddy",
					variant = "Normal",
					shiny = false,
					golden = false,
					favorite = false,
					equipped = false,
					damage = 999999,
				},
			},
			equippedPets = {},
			discoveredPets = {},
		}
		local originalRandom = math.random
		math.random = function() return 0 end
		local result, conversionError = PetService.convertToGoldenPet(player, { "normal-1" })
		math.random = originalRandom

		expect(conversionError):toBeNil()
		expect(result.success):toBeTrue()
		expect(result.goldenPet.variant):toBe("Golden")
		expect(result.goldenPet.shiny):toBeFalse()
		expect(result.goldenPet.damage):toBe(2)
		expect(#profile.pets):toBe(1)
	end)

	it("protects canonical Shiny pets from legacy Golden conversion", function()
		profile = {
			pets = {
				{
					id = "shiny-1",
					petId = "Buddy",
					name = "Shiny Buddy",
					variant = "Normal",
					shiny = true,
					golden = false,
					favorite = false,
					equipped = false,
					damage = 1.5,
				},
			},
			equippedPets = {},
			discoveredPets = {},
		}
		local result, conversionError = PetService.convertToGoldenPet(player, { "shiny-1" })
		expect(result):toBeNil()
		expect(conversionError):toBe("Shiny pets cannot be sacrificed")
		expect(#profile.pets):toBe(1)
	end)
end)
