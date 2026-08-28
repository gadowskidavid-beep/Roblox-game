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
local PetEnchantMath = originalRequire("src/ReplicatedStorage/Shared/PetEnchantMath")
local PetDex = originalRequire("src/ReplicatedStorage/Shared/PetDex")

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

local testRemotes = nil
local ReplicatedStorage = {
	Shared = {
		Config = Config,
		BalanceConfig = BalanceConfig,
		PetData = PetData,
		PetHatchMath = PetHatchMath,
		PetVariantMath = PetVariantMath,
		PetVariantPresentation = PetVariantPresentation,
		PetEnchantMath = PetEnchantMath,
		PetDex = PetDex,
	},
}
function ReplicatedStorage:FindFirstChild(name)
	if name == "Remotes" then return testRemotes end
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
	if path == PetEnchantMath then return PetEnchantMath end
	if path == PetDex then return PetDex end
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
local upgradeShouldError = false
local shopShouldError = false

local admissionOpen = true
local dataService = {}
function dataService.getPlayerData()
	return profile
end
function dataService.isMutationAdmissionOpen()
	return admissionOpen
end
local currencyService = {}
function currencyService.removeCoins()
	return true
end
local upgradeService = {}
function upgradeService.getUpgradeBonus(_, upgradeName)
	if upgradeShouldError then error("injected upgrade failure") end
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
	if shopShouldError then error("injected shop failure") end
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

	it("neutralizes missing, throwing, and malformed damage providers", function()
		local pet = { petId = "Buddy", variant = "Normal", shiny = false }
		for _, malformed in ipairs({ "bad", math.huge, -math.huge, 0 / 0 }) do
			strongMultiplier = malformed
			shopDamageMultiplier = malformed
			expect(PetService.getPetDamage(pet, player)):toBe(1)
		end
		upgradeShouldError = true
		shopShouldError = true
		expect(PetService.getPetDamage(pet, player)):toBe(1)
		upgradeShouldError = false
		shopShouldError = false
		PetService._upgradeService = nil
		PetService._shopService = nil
		expect(PetService.getPetDamage(pet, player)):toBe(1)
		PetService._upgradeService = upgradeService
		PetService._shopService = shopService
		strongMultiplier = 0
		shopDamageMultiplier = 1
	end)

	it("always returns finite neutral values for malformed pets and lane inputs", function()
		expect(PetService.getPetDamage(nil, player)):toBe(0)
		expect(PetService.getPetDamage("forged", player)):toBe(0)
		expect(PetService.getPetDamage({ petId = "Buddy" }, nil)):toBe(0)
		local hostile = setmetatable({}, {
			__index = function() error("hostile pet index") end,
		})
		expect(PetService.getCampaignLaneSpeed(hostile)):toBe(0)
		expect(PetService.getCampaignLaneSpeed({ petId = 12 })):toBe(0)
	end)
end)

describe("PetService QOF-07 canonical single hatch", function()
	it("constructs all six canonical outcomes with truthful names and damage", function()
		questLuckMultiplier = 0
		masteryLuckMultiplier = 0
		shopLuckMultiplier = 1
		local cases = {
			{ 0.5, 0.5, "Normal", false, "Buddy", 1, "Buddy|Normal", "Buddy" },
			{ 0.5, 0, "Normal", true, "Shiny Buddy", 1.5, "Buddy|Normal|Shiny", "Shiny_Buddy" },
			{ 0.001, 0.5, "Golden", false, "Gold Buddy", 2, "Buddy|Golden", "Golden_Buddy" },
			{ 0.001, 0, "Golden", true, "Gold Shiny Buddy", 3, "Buddy|Golden|Shiny", "Shiny_Buddy" },
			{ 0, 0.5, "Rainbow", false, "Rainbow Buddy", 5, "Buddy|Rainbow", "Rainbow_Buddy" },
			{ 0, 0, "Rainbow", true, "Rainbow Shiny Buddy", 7.5, "Buddy|Rainbow|Shiny", "Shiny_Buddy" },
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
			expect(profile.discoveredPets[case[8]]):toBeTrue()
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

	it("uses six canonical keys while preserving four rolling compatibility keys", function()
		expect(PetService.getDiscoveryKey("Buddy", "Normal", false)):toBe("Buddy|Normal")
		expect(PetService.getDiscoveryKey("Buddy", "Normal", true)):toBe("Buddy|Normal|Shiny")
		expect(PetService.getDiscoveryKey("Buddy", "Golden", false)):toBe("Buddy|Golden")
		expect(PetService.getDiscoveryKey("Buddy", "Golden", true)):toBe("Buddy|Golden|Shiny")
		expect(PetService.getDiscoveryKey("Buddy", "Rainbow", false)):toBe("Buddy|Rainbow")
		expect(PetService.getDiscoveryKey("Buddy", "Rainbow", true)):toBe("Buddy|Rainbow|Shiny")
		expect(PetService.getLegacyDiscoveryKey("Buddy", "Normal", false)):toBe("Buddy")
		expect(PetService.getLegacyDiscoveryKey("Buddy", "Golden", false)):toBe("Golden_Buddy")
		expect(PetService.getLegacyDiscoveryKey("Buddy", "Rainbow", false)):toBe("Rainbow_Buddy")
		expect(PetService.getLegacyDiscoveryKey("Buddy", "Golden", true)):toBe("Shiny_Buddy")
		expect(PetService.getLegacyDiscoveryKey("Buddy", "Rainbow", true)):toBe("Shiny_Buddy")
		expect(PetService.getDiscoveryKey(nil, "Normal", false)):toBeNil()
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
		expect(profile.discoveredPets["Buddy|Normal"]):toBeNil()
		expect(prepared.pets[1].isNewDiscovery):toBeTrue()
		expect(prepared.pets[2].isNewDiscovery):toBeFalse()

		local committed, commitError = PetService.commitHatchBatch(player, prepared)
		expect(committed):toBeTrue()
		expect(commitError):toBeNil()
		expect(#profile.pets):toBe(2)
		expect(profile.discoveredPets.Buddy):toBeTrue()
		expect(profile.discoveredPets["Buddy|Normal"]):toBeTrue()

		expect(PetService.rollbackHatchBatch(prepared)):toBeTrue()
		expect(#profile.pets):toBe(0)
		expect(profile.discoveredPets.Buddy):toBeNil()
		expect(profile.discoveredPets["Buddy|Normal"]):toBeNil()
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


describe("PetService QOF-19 enchant runtime", function()
	it("applies Strong exactly once after canonical variant damage and before player buffs", function()
		strongMultiplier = 2
		shopDamageMultiplier = 3
		local pet = {
			petId = "Buddy", variant = "Normal", shiny = true, damage = 999999,
			enchantId = "StrongII", enchantStat = "damage", enchantMultiplier = 999,
		}
		-- 1.5 canonical * 1.25 StrongII = 1.875, floor(*2) = 3, floor(*3) = 9.
		expect(PetService.getPetDamage(pet, player)):toBe(9)
		strongMultiplier = 0
		shopDamageMultiplier = 1
	end)

	it("ignores Agile and forged enchant payloads for damage", function()
		strongMultiplier = 0
		shopDamageMultiplier = 1
		expect(PetService.getPetDamage({
			petId = "Buddy", variant = "Normal", shiny = false,
			enchantId = "AgileIII", enchantStat = "damage", enchantMultiplier = 999,
		}, player)):toBe(1)
		expect(PetService.getPetDamage({
			petId = "Buddy", variant = "Normal", shiny = false,
			enchantId = "Forged", enchantStat = "damage", enchantMultiplier = 999,
		}, player)):toBe(1)
	end)

	it("uses only PetData baseSpeed and Agile for campaign lane speed", function()
		expect(PetService.getCampaignLaneSpeed({ petId = "Buddy", enchantId = "AgileIII", speed = 999 })):toBe(13.5)
		expect(PetService.getCampaignLaneSpeed({ petId = "Buddy", enchantId = "StrongIII", speed = 999 })):toBe(10)
		expect(PetService.getCampaignLaneSpeed({ petId = "Unknown", enchantId = "AgileIII", speed = 999 })):toBe(0)
	end)
end)


describe("PetService defensive equip replication", function()
	it("sends a detached PetEquipped payload instead of the profile table", function()
		local capturedPayload = nil
		local equippedEvent = {}
		function equippedEvent:FireClient(_, payload)
			capturedPayload = payload
		end
		testRemotes = {
			FindFirstChild = function(_, name)
				if name == "PetEquipped" then return equippedEvent end
				return nil
			end,
		}
		local pet = {
			id = "equip-1", petId = "Buddy", name = "Buddy", rarity = "Common",
			variant = "Normal", shiny = false, favorite = false, equipped = false,
			metadata = { server = "private-copy-test" },
		}
		profile = {
			pets = { pet }, equippedPets = {}, discoveredPets = {}, shopPurchases = {},
		}
		local success, reason = PetService.equipPet(player, "equip-1")
		expect(success):toBeTrue()
		expect(reason):toBeNil()
		expect(capturedPayload == pet):toBeFalse()
		expect(capturedPayload.metadata == pet.metadata):toBeFalse()
		capturedPayload.name = "Forged"
		capturedPayload.metadata.server = "Forged"
		expect(pet.name):toBe("Buddy")
		expect(pet.metadata.server):toBe("private-copy-test")
		testRemotes = nil
	end)
end)



describe("PetService shared inventory mutation lease", function()
	it("closes admission through final-save while allowing only the existing owner to settle", function()
		profile = {
			pets = {}, equippedPets = {}, discoveredPets = {}, shopPurchases = {},
		}
		admissionOpen = true
		local existing = PetService.beginInventoryMutation(player, "existing-owner")
		expect(existing ~= nil):toBeTrue()
		admissionOpen = false
		expect(PetService.beginInventoryMutation(player, "late-remote")):toBeNil()
		expect(PetService.isInventoryMutationCurrent(player, existing)):toBeTrue()
		expect(PetService.endInventoryMutation(player, existing, false)):toBeTrue()
		expect(PetService.isInventoryMutationIdle(player)):toBeTrue()
		expect(PetService.beginInventoryMutation(player, "late-after-settle")):toBeNil()
		admissionOpen = true
	end)

	it("blocks Delete, Hatch, Equip, and Favorite while an Enchant restore owns the lease", function()
		local pet = {
			id = "leased-pet", petId = "Buddy", name = "Buddy", rarity = "Common",
			variant = "Normal", shiny = false, favorite = false, equipped = false,
		}
		profile = {
			coins = 1000,
			pets = { pet },
			equippedPets = {},
			discoveredPets = {},
			shopPurchases = {},
		}
		local lease = PetService.beginInventoryMutation(player, "EnchantingService.restore")
		expect(lease ~= nil):toBeTrue()
		local deleted, deleteError = PetService.deletePet(player, pet.id)
		expect(deleted):toBeFalse()
		expect(deleteError):toBe("Pet inventory mutation already in progress")
		local equipped, equipError = PetService.equipPet(player, pet.id)
		expect(equipped):toBeFalse()
		expect(equipError):toBe("Pet inventory mutation already in progress")
		local favorited, favoriteError = PetService.setPetFavorite(player, pet.id, true)
		expect(favorited):toBeFalse()
		expect(favoriteError):toBe("Pet inventory mutation already in progress")
		local hatched, hatchError = PetService.hatchEgg(player, "BasicEgg", true)
		expect(hatched):toBeNil()
		expect(hatchError):toBe("Pet inventory mutation already in progress")
		expect(#profile.pets):toBe(1)
		expect(pet.favorite):toBeFalse()
		expect(pet.equipped):toBeFalse()
		expect(PetService.endInventoryMutation(player, lease, false)):toBeTrue()
	end)

	it("allows normal CRUD paths and releases a fresh incarnation after each commit", function()
		local pet = {
			id = "normal-pet", petId = "Buddy", name = "Buddy", rarity = "Common",
			variant = "Normal", shiny = false, favorite = false, equipped = false,
		}
		profile = {
			pets = { pet }, equippedPets = {}, discoveredPets = {}, shopPurchases = {},
		}
		expect(PetService.equipPet(player, pet.id)):toBeTrue()
		expect(PetService.unequipPet(player, pet.id)):toBeTrue()
		expect(PetService.setPetFavorite(player, pet.id, true)):toBeTrue()
		expect(PetService.setPetFavorite(player, pet.id, false)):toBeTrue()
		expect(PetService.deletePets(player, { pet.id })):toBeTrue()
		expect(#profile.pets):toBe(0)
		expect(PetService._inventoryMutationLeases[player.UserId]):toBeNil()
	end)
end)
