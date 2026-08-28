-- PetService.spec.lua - QOF-07 server-authoritative hatch and damage tests.

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
local treeEggQualityMultiplier = 1
local treeGeneralLuckMultiplier = 1
local treeDirectVariantMultipliers = { Golden = 1, Rainbow = 1, Shiny = 1 }
local questStorageBonus = 0
local questFriendshipBonus = 0
local masteryPetSlotsBonus = 0
local treeStorageBonus = 0
local treeEquipBonus = 0

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
	if upgradeName == "ExtraSlots" then return questStorageBonus end
	if upgradeName == "Friendship" then return questFriendshipBonus end
	return 0
end
local masteryService = {}
function masteryService.getBuffBonus(_, buffType)
	if buffType == "BetterLuck" then return masteryLuckMultiplier end
	if buffType == "MorePetSlots" then return masteryPetSlotsBonus end
	return 0
end
local shopService = {}
function shopService.getShopMultiplier(_, buffType)
	if buffType == "damage" then return shopDamageMultiplier end
	if buffType == "luck" then return shopLuckMultiplier end
	return 1
end
local upgradeTreeService = {}
function upgradeTreeService.getEntitlements()
	return {
		eggQualityMultiplier = treeEggQualityMultiplier,
		generalLuckMultiplier = treeGeneralLuckMultiplier,
		directVariantMultipliers = treeDirectVariantMultipliers,
		storageBonusSlots = treeStorageBonus,
		petEquipBonusSlots = treeEquipBonus,
	}
end

local player = { Name = "Tester", UserId = 1 }
PetService.init(dataService, currencyService, upgradeService)
PetService.setMasteryService(masteryService)
PetService.setShopService(shopService)
PetService.setUpgradeTreeService(upgradeTreeService)

local function freshProfile()
	profile = { pets = {}, equippedPets = {}, discoveredPets = {}, shopPurchases = {} }
end

local function hatchWithRolls(baseVariantRoll, shinyRoll, speciesRoll)
	freshProfile()
	local rolls = { speciesRoll or 0, baseVariantRoll, shinyRoll }
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

describe("PetService QOF-07 canonical single hatch", function()
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

	it("composes QOF-11 Double Luck with every existing server-owned source", function()
		questLuckMultiplier = 2
		masteryLuckMultiplier = 1
		shopLuckMultiplier = 1
		treeGeneralLuckMultiplier = 2
		expect(PetService.getHatchLuckMultiplier(player)):toBe(4)

		questLuckMultiplier = 0
		masteryLuckMultiplier = 0
		shopLuckMultiplier = 1
		treeGeneralLuckMultiplier = 1
	end)

	it("neutralizes malformed or sub-neutral tree Luck", function()
		questLuckMultiplier = 2
		masteryLuckMultiplier = 1
		shopLuckMultiplier = 1
		for _, malformed in ipairs({ "forged", 0, -1, math.huge, 0 / 0 }) do
			treeGeneralLuckMultiplier = malformed
			expect(PetService.getHatchLuckMultiplier(player)):toBe(2)
		end

		questLuckMultiplier = 0
		masteryLuckMultiplier = 0
		shopLuckMultiplier = 1
		treeGeneralLuckMultiplier = 1
	end)

	it("composes all active luck sources and enforces approved caps", function()
		questLuckMultiplier = 2
		masteryLuckMultiplier = 3
		shopLuckMultiplier = 2
		treeGeneralLuckMultiplier = 2
		expect(PetService.getHatchLuckMultiplier(player)):toBe(10)

		local pet, hatchError = hatchWithRolls(0.004, 0.0009)
		expect(hatchError):toBeNil()
		expect(pet.variant):toBe("Rainbow")
		expect(pet.shiny):toBeTrue()
		expect(pet.damage):toBe(7.5)

		questLuckMultiplier = 0
		masteryLuckMultiplier = 0
		shopLuckMultiplier = 1
		treeGeneralLuckMultiplier = 1
	end)

	it("keeps Egg Quality species-only and direct upgrades variant-specific", function()
		questLuckMultiplier = 0
		masteryLuckMultiplier = 0
		shopLuckMultiplier = 1
		treeEggQualityMultiplier = 1.6
		treeDirectVariantMultipliers = { Golden = 2, Rainbow = 2, Shiny = 2 }

		local pet, hatchError = hatchWithRolls(0.0015, 0.00015, 0.66)
		expect(hatchError):toBeNil()
		expect(pet.petId):toBe("Whiskers")
		expect(pet.variant):toBe("Rainbow")
		expect(pet.shiny):toBeTrue()
		expect(pet.damage):toBe(60)

		treeEggQualityMultiplier = 1
		treeDirectVariantMultipliers = { Golden = 1, Rainbow = 1, Shiny = 1 }
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



describe("PetService QOF-10 capacities", function()
	it("combines quest and contiguous tree Storage and clamps to 100..250", function()
		freshProfile()
		questStorageBonus = 20
		treeStorageBonus = 75
		expect(PetService.getMaxInventory(player)):toBe(195)

		questStorageBonus = 20
		treeStorageBonus = 150
		expect(PetService.getMaxInventory(player)):toBe(250)

		questStorageBonus = 0 / 0
		treeStorageBonus = "forged"
		expect(PetService.getMaxInventory(player)):toBe(100)
		questStorageBonus = 0
		treeStorageBonus = 0
	end)

	it("combines Friendship, MorePetSlots mastery, legacy shop, and tree Equip", function()
		freshProfile()
		questFriendshipBonus = 1
		masteryPetSlotsBonus = 2
		profile.shopPurchases.extraEquipSlots = 2
		treeEquipBonus = 1
		expect(PetService.getMaxEquipped(player)):toBe(9)

		questFriendshipBonus = 3
		masteryPetSlotsBonus = 5
		profile.shopPurchases.extraEquipSlots = 999
		treeEquipBonus = 3
		expect(PetService.getMaxEquipped(player)):toBe(12)

		questFriendshipBonus = math.huge
		masteryPetSlotsBonus = "bad"
		profile.shopPurchases.extraEquipSlots = -5
		treeEquipBonus = 0 / 0
		expect(PetService.getMaxEquipped(player)):toBe(3)
		questFriendshipBonus = 0
		masteryPetSlotsBonus = 0
		treeEquipBonus = 0
	end)

	it("does not truncate an existing over-cap inventory", function()
		freshProfile()
		for index = 1, 251 do
			table.insert(profile.pets, { id = "existing-" .. tostring(index) })
		end
		questStorageBonus = 20
		treeStorageBonus = 150
		expect(PetService.getMaxInventory(player)):toBe(250)
		local allowed = PetService.canAddPets(player, 1)
		expect(allowed):toBeFalse()
		expect(#profile.pets):toBe(251)
		questStorageBonus = 0
		treeStorageBonus = 0
	end)
end)

describe("PetService QOF-08 prepared batch boundary", function()
	it("prepares without mutation, commits all results once, and can restore the exact snapshot", function()
		freshProfile()
		local originalRandom = math.random
		math.random = function() return 0.5 end
		local prepared, prepareError = PetService.prepareHatchBatch(player, "BasicEgg", 2)
		math.random = originalRandom

		expect(prepareError):toBeNil()
		expect(#prepared.pets):toBe(2)
		expect(#profile.pets):toBe(0)
		expect(profile.discoveredPets.Buddy):toBeNil()
		expect(prepared.pets[1].isNewDiscovery):toBeTrue()
		expect(prepared.pets[2].isNewDiscovery):toBeFalse()

		local committed, commitError = PetService.commitHatchBatch(player, prepared)
		expect(committed):toBeTrue()
		expect(commitError):toBeNil()
		expect(#profile.pets):toBe(2)
		expect(profile.discoveredPets.Buddy):toBeTrue()

		expect(PetService.rollbackHatchBatch(prepared)):toBeTrue()
		expect(#profile.pets):toBe(0)
		expect(profile.discoveredPets.Buddy):toBeNil()
	end)

	it("boosts exactly the first reserved Shiny rolls without changing other variants", function()
		freshProfile()
		questLuckMultiplier = 0
		masteryLuckMultiplier = 0
		shopLuckMultiplier = 1
		treeGeneralLuckMultiplier = 1
		treeDirectVariantMultipliers = { Golden = 1, Rainbow = 1, Shiny = 1 }
		local rolls = {
			0, 0.5, 0.0005,
			0, 0.5, 0.0005,
			0, 0.5, 0.0005,
		}
		local index = 0
		local originalRandom = math.random
		math.random = function()
			index = index + 1
			return rolls[index]
		end
		local prepared, prepareError = PetService.prepareHatchBatch(player, "BasicEgg", 3, {
			shinyBoostCount = 2,
		})
		math.random = originalRandom
		expect(prepareError):toBeNil()
		expect(prepared.pets[1].variant):toBe("Normal")
		expect(prepared.pets[1].shiny):toBeTrue()
		expect(prepared.pets[2].shiny):toBeTrue()
		expect(prepared.pets[3].shiny):toBeFalse()
		expect(#profile.pets):toBe(0)
	end)

	it("rejects a whole batch when total capacity is unavailable", function()
		freshProfile()
		for index = 1, 99 do
			table.insert(profile.pets, { id = "existing-" .. tostring(index) })
		end
		local prepared, prepareError = PetService.prepareHatchBatch(player, "BasicEgg", 2)
		expect(prepared):toBeNil()
		expect(prepareError):toBe("Pet inventory needs 2 free slots (100 max)")
		expect(#profile.pets):toBe(99)
	end)
end)
