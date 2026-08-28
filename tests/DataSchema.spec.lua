--[[
	DataSchema.spec.lua - Unit tests for DataSchema module.
	Uses the minimal describe/it/expect runner from run_tests.lua.

	These tests are pure Luau (no Roblox API). We provide a mock for game.ReplicatedStorage
	and require DataSchema directly.
]]

-- Mock Roblox shared dependencies while loading production modules.
local originalRequire = require
local Config = {
	MaxExtraEquipSlots = 5,
	MaxPetInventoryBase = 100,
	MaxPetInventoryAbsolute = 250,
	MaxEquippedPetsAbsolute = 12,
}
local BalanceConfig = originalRequire("src/ReplicatedStorage/Shared/BalanceConfig")
local PetData = originalRequire("src/ReplicatedStorage/Shared/PetData")
local SharedMock = {
	Config = Config,
	BalanceConfig = BalanceConfig,
	PetData = PetData,
}
local ReplicatedStorageMock = { Shared = SharedMock }
rawset(_G, "game", { ReplicatedStorage = ReplicatedStorageMock })
rawset(_G, "script", { Parent = SharedMock })

local function mockRequire(path)
	if path == Config then return Config end
	if path == BalanceConfig then return BalanceConfig end
	if path == PetData then return PetData end
	if path == SharedMock.PetVariantMath then return SharedMock.PetVariantMath end
	return originalRequire(path)
end
rawset(_G, "require", mockRequire)

-- math.clamp may not exist in standard Lua; provide a polyfill
if not math.clamp then
	math.clamp = function(value, min, max)
		if value < min then return min end
		if value > max then return max end
		return value
	end
end

local PetVariantMath = originalRequire("src/ReplicatedStorage/Shared/PetVariantMath")
SharedMock.PetVariantMath = PetVariantMath
local DataSchema = originalRequire("src/ServerScriptService/Services/DataSchema")

-- Restore require
rawset(_G, "require", originalRequire)

-- Begin tests

describe("DataSchema.getDefaultData", function()
	it("returns a table with schemaVersion equal to DataSchema.VERSION", function()
		local data = DataSchema.getDefaultData()
		expect(data.schemaVersion):toBe(DataSchema.VERSION)
	end)

	it("has coins = 0, diamonds = 0, xp = 0, level = 1", function()
		local data = DataSchema.getDefaultData()
		expect(data.coins):toBe(0)
		expect(data.diamonds):toBe(0)
		expect(data.xp):toBe(0)
		expect(data.level):toBe(1)
	end)

	it("has a starter pet in the pets array", function()
		local data = DataSchema.getDefaultData()
		expect(#data.pets):toBe(1)
		expect(data.pets[1].petId):toBe("Buddy")
		expect(data.pets[1].rarity):toBe("Common")
		expect(data.pets[1].variant):toBe("Normal")
		expect(data.pets[1].shiny):toBeFalse()
	end)

	it("creates empty future potion state with bounded defaults", function()
		local data = DataSchema.getDefaultData()
		expect(data.potionInventory):toEqual({})
		expect(data.activeBuffs):toEqual({})
		expect(data.potionUpgrades):toEqual({ slots = 2, durationLevel = 0, autoDrink = false })
	end)

	it("has unlockedZones containing zone 1", function()
		local data = DataSchema.getDefaultData()
		expect(data.unlockedZones):toContain(1)
		expect(#data.unlockedZones):toBe(1)
	end)

	it("has equippedPets containing the starter pet id", function()
		local data = DataSchema.getDefaultData()
		expect(data.equippedPets):toContain("starter_pet_1")
	end)

	it("has shopPurchases.extraEquipSlots = 0", function()
		local data = DataSchema.getDefaultData()
		expect(data.shopPurchases.extraEquipSlots):toBe(0)
	end)

	it("has questStats with all expected fields at 0", function()
		local data = DataSchema.getDefaultData()
		expect(data.questStats.destroyDestructibles):toBe(0)
		expect(data.questStats.hatchEggs):toBe(0)
		expect(data.questStats.earnCoins):toBe(0)
		expect(data.questStats.playtime):toBe(0)
		expect(data.questStats.reachLevel):toBe(0)
		expect(data.questStats.goldenPetsConverted):toBe(0)
	end)
end)

describe("DataSchema.migrate", function()
	it("returns default data when called with nil", function()
		local data = DataSchema.migrate(nil)
		local defaults = DataSchema.getDefaultData()
		expect(data.schemaVersion):toBe(DataSchema.VERSION)
		expect(data.coins):toBe(defaults.coins)
		expect(data.level):toBe(defaults.level)
	end)

	it("returns default data when called with an empty table", function()
		local data = DataSchema.migrate({})
		expect(data.schemaVersion):toBe(DataSchema.VERSION)
		expect(data.coins):toBe(0)
		expect(data.level):toBe(1)
		expect(#data.unlockedZones >= 1):toBeTrue()
	end)

	it("preserves existing valid data while merging defaults", function()
		local raw = { coins = 500, diamonds = 10, level = 5 }
		local data = DataSchema.migrate(raw)
		expect(data.coins):toBe(500)
		expect(data.diamonds):toBe(10)
		expect(data.level):toBe(5)
		-- Should still have default fields merged in
		expect(data.masteryPoints):toBe(0)
	end)

	it("clamps negative coins to 0", function()
		local raw = { coins = -100 }
		local data = DataSchema.migrate(raw)
		expect(data.coins):toBe(0)
	end)
end)

describe("normalizePets (via migrate)", function()
	it("removes duplicate pets by id", function()
		local raw = {
			pets = {
				{ id = "pet_1", petId = "Dog", name = "Dog", rarity = "Common", damage = 5, variant = "Normal", equipped = true },
				{ id = "pet_1", petId = "Dog", name = "Dog", rarity = "Common", damage = 5, variant = "Normal", equipped = true },
				{ id = "pet_2", petId = "Cat", name = "Cat", rarity = "Rare", damage = 10, variant = "Normal", equipped = false },
			},
			equippedPets = { "pet_1" },
		}
		local data = DataSchema.migrate(raw)
		-- Should only have 2 unique pets
		expect(#data.pets):toBe(2)
	end)

	it("repairs equippedPets when pet.equipped flag diverges from equippedPets list", function()
		local raw = {
			pets = {
				{ id = "pet_1", petId = "Dog", name = "Dog", rarity = "Common", damage = 5, variant = "Normal", equipped = true },
				{ id = "pet_2", petId = "Cat", name = "Cat", rarity = "Rare", damage = 10, variant = "Normal", equipped = true },
			},
			equippedPets = { "pet_1" },  -- Only pet_1 is listed, but pet_2 has equipped = true
		}
		local data = DataSchema.migrate(raw)
		-- pet_2 should now be in equippedPets since its flag was true
		local found = false
		for _, id in ipairs(data.equippedPets) do
			if id == "pet_2" then found = true end
		end
		expect(found):toBeTrue()
	end)

	it("removes invalid pet entries (missing id or non-table)", function()
		local raw = {
			pets = {
				"not_a_table",
				{ petId = "Dog", name = "Dog", rarity = "Common", damage = 5 }, -- missing id
				{ id = "", petId = "Cat", name = "Cat", rarity = "Rare", damage = 3 }, -- empty id
				{ id = "valid_1", petId = "Phoenix", name = "Phoenix", rarity = "Legendary", damage = 20, variant = "Normal", equipped = false },
			},
			equippedPets = {},
		}
		local data = DataSchema.migrate(raw)
		expect(#data.pets):toBe(1)
		expect(data.pets[1].id):toBe("valid_1")
	end)
end)

describe("normalizeNumberArray (via unlockedZones)", function()
	it("sorts and deduplicates zone numbers", function()
		local raw = {
			unlockedZones = { 3, 1, 3, 2, 1 },
		}
		local data = DataSchema.migrate(raw)
		expect(data.unlockedZones[1]):toBe(1)
		expect(data.unlockedZones[2]):toBe(2)
		expect(data.unlockedZones[3]):toBe(3)
		expect(#data.unlockedZones):toBe(3)
	end)

	it("always includes required zone 1 even if missing from input", function()
		local raw = {
			unlockedZones = { 3, 5 },
		}
		local data = DataSchema.migrate(raw)
		expect(data.unlockedZones):toContain(1)
	end)

	it("filters out values outside valid range (1-8)", function()
		local raw = {
			unlockedZones = { 0, 1, 9, 100, 4 },
		}
		local data = DataSchema.migrate(raw)
		-- Only 1 and 4 should remain
		expect(#data.unlockedZones):toBe(2)
		expect(data.unlockedZones):toContain(1)
		expect(data.unlockedZones):toContain(4)
	end)

	it("handles non-number entries gracefully", function()
		local raw = {
			unlockedZones = { "hello", true, 2, nil, 5 },
		}
		local data = DataSchema.migrate(raw)
		expect(data.unlockedZones):toContain(1)  -- required
		expect(data.unlockedZones):toContain(2)
	end)
end)

describe("extraEquipSlots capping", function()
	it("caps extraEquipSlots to Config.MaxExtraEquipSlots", function()
		local raw = {
			shopPurchases = { extraEquipSlots = 99 },
		}
		local data = DataSchema.migrate(raw)
		expect(data.shopPurchases.extraEquipSlots):toBeLessThanOrEqual(Config.MaxExtraEquipSlots)
		expect(data.shopPurchases.extraEquipSlots):toBe(Config.MaxExtraEquipSlots)
	end)

	it("allows values within the valid range", function()
		local raw = {
			shopPurchases = { extraEquipSlots = 3 },
		}
		local data = DataSchema.migrate(raw)
		expect(data.shopPurchases.extraEquipSlots):toBe(3)
	end)

	it("clamps negative extraEquipSlots to 0", function()
		local raw = {
			shopPurchases = { extraEquipSlots = -5 },
		}
		local data = DataSchema.migrate(raw)
		expect(data.shopPurchases.extraEquipSlots):toBe(0)
	end)
end)

describe("DataSchema.deepCopy", function()
	it("creates an independent copy of a nested table", function()
		local original = { a = 1, b = { c = 2, d = { 3, 4, 5 } } }
		local copy = DataSchema.deepCopy(original)
		copy.b.c = 99
		expect(original.b.c):toBe(2)
	end)

	it("copies primitive values as-is", function()
		expect(DataSchema.deepCopy(42)):toBe(42)
		expect(DataSchema.deepCopy("hello")):toBe("hello")
		expect(DataSchema.deepCopy(true)):toBe(true)
	end)
end)


describe("V6 pet migration", function()
	it("maps every V5 variant into base variant plus independent shiny", function()
		local data = DataSchema.migrate({
			schemaVersion = 5,
			pets = {
				{ id = "normal", petId = "Buddy", name = "Buddy", damage = 999, variant = "Normal" },
				{ id = "gold", petId = "Buddy", name = "Golden Buddy", damage = 999, variant = "Golden" },
				{ id = "goldMirror", petId = "Buddy", name = "Golden Buddy", damage = 999, variant = "Rainbow", golden = true },
				{ id = "rainbow", petId = "Buddy", name = "Rainbow Buddy", damage = 999, variant = "Rainbow" },
				{ id = "shiny", petId = "Buddy", name = "Shiny Buddy", damage = 999, variant = "Shiny" },
				{ id = "invalid", petId = "Buddy", name = "Buddy", damage = 999, variant = "Mythic", shiny = true },
			},
			equippedPets = {},
		}, 1000)

		expect(data.schemaVersion):toBe(6)
		expect(data.pets[1].variant):toBe("Normal")
		expect(data.pets[1].shiny):toBeFalse()
		expect(data.pets[1].damage):toBe(1)
		expect(data.pets[2].variant):toBe("Golden")
		expect(data.pets[2].golden):toBeTrue()
		expect(data.pets[2].damage):toBe(2)
		expect(data.pets[3].variant):toBe("Golden")
		expect(data.pets[3].shiny):toBeFalse()
		expect(data.pets[3].damage):toBe(2)
		expect(data.pets[4].variant):toBe("Rainbow")
		expect(data.pets[4].damage):toBe(5)
		expect(data.pets[5].variant):toBe("Normal")
		expect(data.pets[5].shiny):toBeTrue()
		expect(data.pets[5].damage):toBe(1.5)
		expect(data.pets[6].variant):toBe("Normal")
		expect(data.pets[6].shiny):toBeTrue()
		expect(data.pets[6].damage):toBe(1.5)
	end)

	it("recalculates V6 combined variant damage from canonical identity", function()
		local data = DataSchema.migrate({
			schemaVersion = 6,
			pets = {
				{
					id = "rainbowShiny",
					petId = "Splash",
					name = "Rainbow Shiny Splash",
					damage = 75,
					variant = "Rainbow",
					shiny = true,
					favorite = true,
					equipped = true,
				},
			},
			equippedPets = { "rainbowShiny" },
		}, 1000)
		local pet = data.pets[1]
		expect(pet.variant):toBe("Rainbow")
		expect(pet.shiny):toBeTrue()
		expect(pet.damage):toBe(22.5)
		expect(pet.favorite):toBeTrue()
		expect(pet.equipped):toBeTrue()
	end)
end)

describe("V6 potion persistence normalization", function()
	it("whitelists inventory, removes expired buffs, and caps charge state", function()
		local data = DataSchema.migrate({
			potionInventory = {
				LuckPotion = 4.9,
				ShinyPotion = 2,
				UnknownPotion = 999,
				SpeedPotion = -3,
			},
			activeBuffs = {
				luck = 1200.9,
				speed = 999,
				coins = "later",
				shinyChance = { charges = 99 },
				unknown = 9000,
			},
			potionUpgrades = {
				slots = 99,
				durationLevel = 99,
				autoDrink = 1,
			},
		}, 1000)

		expect(data.potionInventory):toEqual({ LuckPotion = 4, ShinyPotion = 2 })
		expect(data.activeBuffs):toEqual({
			luck = 1200,
			shinyChance = { charges = 30 },
		})
		expect(data.potionUpgrades):toEqual({ slots = 5, durationLevel = 4, autoDrink = false })
	end)

	it("restores safe potion upgrade defaults from malformed values", function()
		local data = DataSchema.migrate({
			potionInventory = "invalid",
			activeBuffs = "invalid",
			potionUpgrades = {
				slots = -4,
				durationLevel = -2,
				autoDrink = true,
			},
		}, 1000)
		expect(data.potionInventory):toEqual({})
		expect(data.activeBuffs):toEqual({})
		expect(data.potionUpgrades):toEqual({ slots = 2, durationLevel = 0, autoDrink = true })
	end)
end)

describe("V6 compatibility guarantees", function()
	it("preserves discovery and upgrade tree purchases while removing malformed entries", function()
		local data = DataSchema.migrate({
			discoveredPets = {
				Dog = true,
				Golden_Dog = true,
				Shiny_Dog = true,
				Rainbow_Dog = true,
				Ignored = false,
				[12] = true,
			},
			upgradeTreePurchases = {
				["Eggs I"] = true,
				["luck I"] = true,
				Ignored = false,
			},
		}, 1000)
		expect(data.discoveredPets):toEqual({
			Dog = true,
			Golden_Dog = true,
			Shiny_Dog = true,
			Rainbow_Dog = true,
		})
		expect(data.upgradeTreePurchases):toEqual({ ["Eggs I"] = true, ["luck I"] = true })
	end)

	it("is idempotent for migrated V6 profiles", function()
		local once = DataSchema.migrate({
			schemaVersion = 5,
			pets = {
				{ id = "shiny", petId = "Dog", name = "Shiny Dog", damage = 15, variant = "Shiny" },
			},
			equippedPets = {},
			potionInventory = { LuckPotion = 2 },
			activeBuffs = { luck = 1500, shinyChance = { charges = 3 } },
			upgradeTreePurchases = { ["Eggs I"] = true },
		}, 1000)
		local twice = DataSchema.migrate(once, 1000)
		expect(twice):toEqual(once)
	end)

	it("cloneForPersistence deep-copies and removes expired or transient state", function()
		local live = DataSchema.migrate({
			activeBuffs = { luck = 1500 },
			potionInventory = { LuckPotion = 2 },
			xpNeeded = 999,
		}, 1000)
		local snapshot = DataSchema.cloneForPersistence(live, 1600)
		expect(snapshot.activeBuffs):toEqual({})
		expect(snapshot.xpNeeded):toBeNil()
		expect(snapshot.potionInventory):toEqual({ LuckPotion = 2 })
		snapshot.potionInventory.LuckPotion = 1
		expect(live.potionInventory.LuckPotion):toBe(2)
	end)
end)


describe("V6 rolling-server and magnitude safety", function()
	it("restores canonical Shiny after a rolling QOF-03 floor and save", function()
		local v6 = DataSchema.migrate({
			schemaVersion = 5,
			pets = {
				{ id = "shiny", petId = "Buddy", name = "Shiny Buddy", damage = 15, variant = "Shiny" },
			},
			equippedPets = {},
		}, 1000)

		-- QOF-03 retains the independent flag but floors the mirror and stamps V6.
		-- QOF-04 must recover canonical damage after all old servers are drained.
		local rollingQof03Save = DataSchema.deepCopy(v6)
		rollingQof03Save.pets[1].damage = math.floor(rollingQof03Save.pets[1].damage)
		rollingQof03Save.schemaVersion = 6
		local reloaded = DataSchema.migrate(rollingQof03Save, 1000)
		expect(reloaded.pets[1].variant):toBe("Normal")
		expect(reloaded.pets[1].shiny):toBeTrue()
		expect(reloaded.pets[1].damage):toBe(1.5)
	end)

	it("caps huge finite potion quantities and timed expiries", function()
		local data = DataSchema.migrate({
			potionInventory = { LuckPotion = 1e300 },
			activeBuffs = { luck = 1e300 },
		}, 1000)
		expect(data.potionInventory.LuckPotion):toBe(999)
		expect(data.activeBuffs.luck):toBe(2593000)
	end)

	it("drops non-finite potion quantities and timed expiries", function()
		local data = DataSchema.migrate({
			potionInventory = { LuckPotion = math.huge, CoinPotion = 0 / 0 },
			activeBuffs = { luck = math.huge, coins = 0 / 0 },
		}, 1000)
		expect(data.potionInventory):toEqual({})
		expect(data.activeBuffs):toEqual({})
	end)
end)
