-- PetService.spec.lua - QOF-04 server-authoritative damage and constructor tests.

local originalRequire = require
local BalanceConfig = originalRequire("src/ReplicatedStorage/Shared/BalanceConfig")
local PetData = originalRequire("src/ReplicatedStorage/Shared/PetData")
local PetVariantMath = originalRequire("src/ReplicatedStorage/Shared/PetVariantMath")

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
		PetVariantMath = PetVariantMath,
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
	if path == PetVariantMath then return PetVariantMath end
	return originalRequire(path)
end
rawset(_G, "require", mockRequire)
local PetService = originalRequire("src/ServerScriptService/Services/PetService")
rawset(_G, "require", originalRequire)

local profile = nil
local strongMultiplier = 0
local shopDamageMultiplier = 1
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
	return 0
end
local shopService = {}
function shopService.getShopMultiplier(_, buffType)
	if buffType == "damage" then return shopDamageMultiplier end
	return 1
end

local player = { Name = "Tester", UserId = 1 }
PetService.init(dataService, currencyService, upgradeService)
PetService.setShopService(shopService)

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

describe("PetService QOF-04 constructors", function()
	it("keeps the legacy Shiny hatch roll but emits canonical x1.5 damage", function()
		profile = { pets = {}, equippedPets = {}, discoveredPets = {}, shopPurchases = {} }
		strongMultiplier = 0
		shopDamageMultiplier = 1
		PetService.setMasteryService(nil)
		PetService.setShopService(nil)

		local rolls = { 0, 1, 0 }
		local rollIndex = 0
		local originalRandom = math.random
		math.random = function()
			rollIndex = rollIndex + 1
			return rolls[rollIndex]
		end
		local pet, hatchError = PetService.hatchEgg(player, "BasicEgg", true)
		math.random = originalRandom
		PetService.setShopService(shopService)

		expect(hatchError):toBeNil()
		expect(pet.petId):toBe("Buddy")
		expect(pet.variant):toBe("Normal")
		expect(pet.shiny):toBeTrue()
		expect(pet.damage):toBe(1.5)
		expect(profile.discoveredPets.Shiny_Buddy):toBeTrue()
	end)

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
