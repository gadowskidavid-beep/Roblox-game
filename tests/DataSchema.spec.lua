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
local CampaignData = originalRequire("src/ReplicatedStorage/Shared/CampaignData")
local QuestData = originalRequire("src/ReplicatedStorage/Shared/QuestData")
local MasteryData = originalRequire("src/ReplicatedStorage/Shared/MasteryData")
local SharedMock = {
	Config = Config,
	BalanceConfig = BalanceConfig,
	PetData = PetData,
	CampaignData = CampaignData,
	QuestData = QuestData,
	MasteryData = MasteryData,
}
local ReplicatedStorageMock = { Shared = SharedMock }
rawset(_G, "game", { ReplicatedStorage = ReplicatedStorageMock })
rawset(_G, "script", { Parent = SharedMock })

local function mockRequire(path)
	if path == Config then return Config end
	if path == BalanceConfig then return BalanceConfig end
	if path == PetData then return PetData end
	if path == CampaignData then return CampaignData end
	if path == QuestData then return QuestData end
	if path == MasteryData then return MasteryData end
	if path == SharedMock.ProgressionMath then return SharedMock.ProgressionMath end
	if path == SharedMock.PetVariantMath then return SharedMock.PetVariantMath end
	if path == SharedMock.PetEnchantMath then return SharedMock.PetEnchantMath end
	if path == SharedMock.PetDex then return SharedMock.PetDex end
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
local PetEnchantMath = originalRequire("src/ReplicatedStorage/Shared/PetEnchantMath")
SharedMock.PetEnchantMath = PetEnchantMath
local PetDex = originalRequire("src/ReplicatedStorage/Shared/PetDex")
SharedMock.PetDex = PetDex
local ProgressionMath = originalRequire("src/ReplicatedStorage/Shared/ProgressionMath")
SharedMock.ProgressionMath = ProgressionMath
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

	it("creates empty persistent potion inventory and active state", function()
		local data = DataSchema.getDefaultData()
		expect(data.potionInventory):toEqual({})
		expect(data.activeBuffs):toEqual({})
		expect(data.potionBuffSources):toEqual({})
		expect(data.potionUpgrades):toEqual({ slots = 2, durationLevel = 0, autoDrink = false })
	end)

	it("defaults the persistent hatch preference to x1 and paid expiry to inactive", function()
		local first = DataSchema.getDefaultData()
		local second = DataSchema.getDefaultData()
		expect(first.hatchPreferences):toEqual({ preferredBatchCount = 1 })
		expect(first.autoHatchExpiresAt):toBe(0)
		first.hatchPreferences.preferredBatchCount = 10
		expect(second.hatchPreferences.preferredBatchCount):toBe(1)
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

		expect(data.schemaVersion):toBe(DataSchema.VERSION)
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
			luck = {
				sources = {
					LuckPotion = { expiresAt = 1200 },
				},
			},
			shinyChance = { charges = 30 },
		})
		expect(data.potionUpgrades):toEqual({ slots = 5, durationLevel = 4, autoDrink = false })
		expect(data.autoDrinkSelection):toEqual({})
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

	it("preserves exactly 999 and clamps 1000 independently per potion", function()
		local atCap = DataSchema.migrate({
			potionInventory = { LuckPotion = 999, SpeedPotion = 1000 },
		}, 1000)
		expect(atCap.potionInventory):toEqual({ LuckPotion = 999, SpeedPotion = 999 })
	end)

	it("round-trips canonical inventory through migration and persistence at schema V8", function()
		local migrated = DataSchema.migrate({
			schemaVersion = 7,
			potionInventory = {
				LuckPotion = 7,
				MegaLuckPotion = 3,
				LuckyPotion = 9,
				PowerPotion = 9,
			},
		}, 1000)
		local snapshot = DataSchema.cloneForPersistence(migrated, 1000)
		local reloaded = DataSchema.migrate(snapshot, 1000)
		expect(reloaded.schemaVersion):toBe(DataSchema.VERSION)
		expect(reloaded.potionInventory):toEqual({ LuckPotion = 7, MegaLuckPotion = 3 })
		snapshot.potionInventory.LuckPotion = 1
		expect(migrated.potionInventory.LuckPotion):toBe(7)
	end)
end)

describe("V6 compatibility guarantees", function()
	it("preserves discovery and upgrade tree purchases while removing malformed entries", function()
		local data = DataSchema.migrate({
			pets = {},
			equippedPets = {},
			discoveredPets = {
				Buddy = true,
				Golden_Buddy = true,
				Shiny_Buddy = true,
				Rainbow_Buddy = true,
				Ignored = false,
				[12] = true,
			},
			upgradeTreePurchases = {
				["Eggs I"] = true,
				["Eggs III"] = true,
				["Eggs V"] = true,
				["luck I"] = true,
				Ignored = false,
			},
		}, 1000)
		expect(data.discoveredPets):toEqual({
			Buddy = true,
			Golden_Buddy = true,
			Shiny_Buddy = true,
			Rainbow_Buddy = true,
			["Buddy|Normal"] = true,
			["Buddy|Golden"] = true,
			["Buddy|Normal|Shiny"] = true,
			["Buddy|Rainbow"] = true,
		})
		expect(data.upgradeTreePurchases):toEqual({
			["Eggs I"] = true,
			["Eggs III"] = true,
			["Eggs V"] = true,
			["luck I"] = true,
		})
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
		expect(data.activeBuffs.luck):toEqual({
			sources = {
				LuckPotion = { expiresAt = 2593000 },
			},
		})
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


describe("V7 persistent hatch preferences", function()
	it("migrates V6 profiles without a preference to the x1 default", function()
		local data = DataSchema.migrate({ schemaVersion = 6, coins = 250 }, 1000)
		expect(data.schemaVersion):toBe(DataSchema.VERSION)
		expect(data.hatchPreferences):toEqual({ preferredBatchCount = 1 })
		expect(data.coins):toBe(250)
	end)

	it("preserves only the fixed x1, x2, x5, and x10 tiers", function()
		for _, count in ipairs({ 1, 2, 5, 10 }) do
			local data = DataSchema.migrate({
				hatchPreferences = { preferredBatchCount = count },
			}, 1000)
			expect(data.hatchPreferences.preferredBatchCount):toBe(count)
		end

		for _, invalid in ipairs({ 0, 3, 2.5, "5", true, math.huge, -math.huge }) do
			local data = DataSchema.migrate({
				hatchPreferences = { preferredBatchCount = invalid },
			}, 1000)
			expect(data.hatchPreferences.preferredBatchCount):toBe(1)
		end
		expect(DataSchema.migrate({ hatchPreferences = "invalid" }, 1000).hatchPreferences)
			:toEqual({ preferredBatchCount = 1 })
		expect(DataSchema.migrate({
			hatchPreferences = { preferredBatchCount = 0 / 0 },
		}, 1000).hatchPreferences.preferredBatchCount):toBe(1)
	end)

	it("keeps migration and persistence cloning idempotent and independent", function()
		local once = DataSchema.migrate({
			schemaVersion = 6,
			hatchPreferences = { preferredBatchCount = 5 },
		}, 1000)
		local twice = DataSchema.migrate(once, 1000)
		local snapshot = DataSchema.cloneForPersistence(twice, 1000)
		expect(twice):toEqual(once)
		expect(snapshot):toEqual(twice)
		snapshot.hatchPreferences.preferredBatchCount = 1
		expect(twice.hatchPreferences.preferredBatchCount):toBe(5)
	end)
end)


local function simulateQof13PotionSave(profile, currentTime)
	local saved = DataSchema.deepCopy(profile)
	local downgradedBuffs = {}
	for buffType, state in pairs(saved.activeBuffs or {}) do
		-- QOF-13 accepts timed state only as one numeric expiry. Structured V8
		-- sources are therefore dropped, while its known charge shape survives.
		if type(state) == "number" and state > currentTime then
			downgradedBuffs[buffType] = math.floor(state)
		elseif buffType == "shinyChance" and type(state) == "table"
			and type(state.charges) == "number" and state.charges > 0 then
			downgradedBuffs[buffType] = { charges = math.min(30, math.floor(state.charges)) }
		end
	end
	saved.activeBuffs = downgradedBuffs
	saved.schemaVersion = 7
	return saved
end

describe("V8 structured potion sources and Auto-Drink selection", function()
	it("preserves independent Luck and Mega Luck timers under one buff type", function()
		local data = DataSchema.migrate({
			schemaVersion = 8,
			activeBuffs = {
				luck = {
					sources = {
						LuckPotion = { expiresAt = 1600 },
						MegaLuckPotion = { expiresAt = 1300 },
						SpeedPotion = { expiresAt = 1800 },
					},
				},
			},
		}, 1000)
		expect(data.activeBuffs):toEqual({
			luck = {
				sources = {
					LuckPotion = { expiresAt = 1600 },
					MegaLuckPotion = { expiresAt = 1300 },
				},
			},
		})
	end)

	it("migrates legacy numeric timers conservatively and removes expired sources", function()
		local data = DataSchema.migrate({
			schemaVersion = 7,
			activeBuffs = { luck = 1400, speed = 999, coins = 1700 },
		}, 1000)
		expect(data.activeBuffs):toEqual({
			luck = { sources = { LuckPotion = { expiresAt = 1400 } } },
			coins = { sources = { CoinPotion = { expiresAt = 1700 } } },
		})
	end)

	it("recovers every timed source after a realistic QOF-13 wipe and schema downgrade", function()
		local v8 = DataSchema.migrate({
			schemaVersion = 8,
			activeBuffs = {
				luck = {
					sources = {
						LuckPotion = { expiresAt = 1600 },
						MegaLuckPotion = { expiresAt = 1e300 },
					},
				},
				speed = { sources = { SpeedPotion = { expiresAt = 1700 } } },
				coins = { sources = { CoinPotion = { expiresAt = 1800 } } },
			},
		}, 1000)
		local cap = 1000 + BalanceConfig.Potions.Persistence.MaxTimedBuffSeconds
		expect(v8.potionBuffSources):toEqual({
			LuckPotion = { expiresAt = 1600 },
			MegaLuckPotion = { expiresAt = cap },
			SpeedPotion = { expiresAt = 1700 },
			CoinPotion = { expiresAt = 1800 },
		})

		local rollingQof13Save = simulateQof13PotionSave(
			DataSchema.cloneForPersistence(v8, 1000),
			1000
		)
		expect(rollingQof13Save.schemaVersion):toBe(7)
		expect(rollingQof13Save.activeBuffs):toEqual({})
		expect(rollingQof13Save.potionBuffSources):toEqual(v8.potionBuffSources)

		local recovered = DataSchema.migrate(rollingQof13Save, 1000)
		expect(recovered.schemaVersion):toBe(DataSchema.VERSION)
		expect(recovered.activeBuffs):toEqual({
			luck = { sources = {
				LuckPotion = { expiresAt = 1600 },
				MegaLuckPotion = { expiresAt = cap },
			} },
			speed = { sources = { SpeedPotion = { expiresAt = 1700 } } },
			coins = { sources = { CoinPotion = { expiresAt = 1800 } } },
		})
		-- Luck and Mega Luck remain source identities under one runtime buff slot;
		-- the compatibility mirror is never a second activeBuffs collection.
		expect(recovered.activeBuffs.luck.sources.LuckPotion.expiresAt):toBe(1600)
		expect(recovered.activeBuffs.luck.sources.MegaLuckPotion.expiresAt):toBe(cap)
	end)

	it("filters, merges, caps, and resynchronizes the rolling source mirror", function()
		local data = DataSchema.migrate({
			schemaVersion = 7,
			activeBuffs = { luck = 1400 },
			potionBuffSources = {
				LuckPotion = { expiresAt = 1300 },
				MegaLuckPotion = { expiresAt = 1500 },
				SpeedPotion = { expiresAt = 999 },
				CoinPotion = { expiresAt = 1e300 },
				ShinyPotion = { expiresAt = 1900 },
				UnknownPotion = { expiresAt = 1900 },
			},
		}, 1000)
		local cap = 1000 + BalanceConfig.Potions.Persistence.MaxTimedBuffSeconds
		expect(data.activeBuffs):toEqual({
			luck = { sources = {
				LuckPotion = { expiresAt = 1400 },
				MegaLuckPotion = { expiresAt = 1500 },
			} },
			coins = { sources = { CoinPotion = { expiresAt = cap } } },
		})
		expect(data.potionBuffSources):toEqual({
			LuckPotion = { expiresAt = 1400 },
			MegaLuckPotion = { expiresAt = 1500 },
			CoinPotion = { expiresAt = cap },
		})

		data.activeBuffs.luck.sources.LuckPotion.expiresAt = 1700
		local snapshot = DataSchema.cloneForPersistence(data, 1000)
		expect(snapshot.potionBuffSources.LuckPotion.expiresAt):toBe(1700)
		snapshot.potionBuffSources.LuckPotion.expiresAt = 1800
		expect(data.potionBuffSources.LuckPotion.expiresAt):toBe(1400)
	end)

	it("whitelists explicit selections and never selects Shiny by default", function()
		local defaults = DataSchema.getDefaultData()
		expect(defaults.autoDrinkSelection):toEqual({})
		local data = DataSchema.migrate({
			autoDrinkSelection = {
				LuckPotion = true,
				ShinyPotion = false,
				UnknownPotion = true,
				SpeedPotion = 1,
			},
		}, 1000)
		expect(data.autoDrinkSelection):toEqual({ LuckPotion = true })
		expect(data.autoDrinkSelection.ShinyPotion):toBeNil()
	end)
end)



describe("V9 paid Auto-Hatch absolute expiry", function()
	it("preserves only a canonical integer expiry in the exact live window", function()
		for _, expiresAt in ipairs({ 1001, 1300, 1600 }) do
			local data = DataSchema.migrate({ autoHatchExpiresAt = expiresAt }, 1000)
			expect(data.schemaVersion):toBe(DataSchema.VERSION)
			expect(data.autoHatchExpiresAt):toBe(expiresAt)
		end
	end)

	it("fails closed for expired, fractional, corrupt, non-finite, and absurdly distant values", function()
		for _, expiresAt in ipairs({ -1, 0, 999, 1000, 1000.1, 1300.5, 1600.9, 1601, 1e300, math.huge, -math.huge, "1600", true }) do
			local data = DataSchema.migrate({ autoHatchExpiresAt = expiresAt }, 1000)
			expect(data.autoHatchExpiresAt):toBe(0)
		end
		expect(DataSchema.migrate({ autoHatchExpiresAt = 0 / 0 }, 1000).autoHatchExpiresAt):toBe(0)
	end)

	it("counts offline wall time and clears access at the exact expiry", function()
		local saved = DataSchema.cloneForPersistence(DataSchema.migrate({
			autoHatchExpiresAt = 1500,
			hatchPreferences = { preferredBatchCount = 10 },
		}, 1000), 1200)
		expect(saved.autoHatchExpiresAt):toBe(1500)
		expect(saved.hatchPreferences.preferredBatchCount):toBe(10)
		expect(DataSchema.migrate(saved, 1499).autoHatchExpiresAt):toBe(1500)
		expect(DataSchema.migrate(saved, 1500).autoHatchExpiresAt):toBe(0)
	end)
end)


describe("DataSchema V10 pet enchant persistence", function()
	it("migrates ordinary V9 pets without inventing an enchant", function()
		local data = DataSchema.migrate({
			schemaVersion = 9,
			pets = {
				{ id = "plain", petId = "Buddy", variant = "Normal", damage = 999 },
			},
			equippedPets = {},
		}, 1000)
		expect(data.schemaVersion):toBe(DataSchema.VERSION)
		expect(data.pets[1].enchantId):toBeNil()
		expect(data.pets[1].damage):toBe(1)
	end)

	it("preserves only a valid rolling enchantId and strips forged derived fields", function()
		local valid = DataSchema.migrate({
			schemaVersion = 9,
			pets = {
				{
					id = "enchanted", petId = "Buddy", variant = "Golden", damage = 999,
					enchantId = "StrongII", enchant = "StrongIII",
					enchantData = { stat = "damage", multiplier = 999 },
					enchants = { "StrongIII" }, enchantStat = "damage", enchantMultiplier = 999,
				},
			},
			equippedPets = {},
		}, 1000)
		local pet = valid.pets[1]
		expect(pet.enchantId):toBe("StrongII")
		expect(pet.enchant):toBeNil()
		expect(pet.enchantData):toBeNil()
		expect(pet.enchants):toBeNil()
		expect(pet.enchantStat):toBeNil()
		expect(pet.enchantMultiplier):toBeNil()
		-- The compatibility mirror remains canonical base damage, never enchanted damage.
		expect(pet.damage):toBe(2)
	end)

	it("removes empty, wrong-type, and unknown enchant IDs", function()
		local invalidValues = { "", "Unknown", "strongi", 12, true, { id = "StrongI" } }
		for index, invalid in ipairs(invalidValues) do
			local data = DataSchema.migrate({
				pets = { { id = "pet-" .. tostring(index), petId = "Buddy", enchantId = invalid } },
				equippedPets = {},
			}, 1000)
			expect(data.pets[1].enchantId):toBeNil()
		end
	end)

	it("is idempotent across normalize, persistence clone, and reload", function()
		local once = DataSchema.migrate({
			schemaVersion = 9,
			pets = {
				{ id = "one", petId = "Buddy", enchantId = "AgileIII", enchantMultiplier = 50 },
				{ id = "two", petId = "Dog", enchantId = "forged", enchant = "StrongI" },
			},
			equippedPets = {},
		}, 1000)
		local twice = DataSchema.migrate(once, 1000)
		local snapshot = DataSchema.cloneForPersistence(twice, 1000)
		local reloaded = DataSchema.migrate(snapshot, 1000)
		expect(twice):toEqual(once)
		expect(snapshot):toEqual(once)
		expect(reloaded):toEqual(once)
	end)
end)


describe("DataSchema V11 six-state Pet Dex migration", function()
	it("backfills the starter as an exact Normal discovery for new profiles", function()
		local data = DataSchema.migrate(nil, 1000)
		expect(data.schemaVersion):toBe(12)
		expect(data.discoveredPets.Buddy):toBeTrue()
		expect(data.discoveredPets["Buddy|Normal"]):toBeTrue()
		expect(data.discoveredPets["Buddy|Normal|Shiny"]):toBeNil()
	end)

	it("maps four legacy categories conservatively into canonical states", function()
		local data = DataSchema.migrate({
			schemaVersion = 10,
			pets = {},
			equippedPets = {},
			discoveredPets = {
				Buddy = true,
				Golden_Buddy = true,
				Rainbow_Buddy = true,
				Shiny_Buddy = true,
				forged = true,
				["Buddy|Golden|Shiny"] = false,
			},
		}, 1000)
		expect(data.discoveredPets.Buddy):toBeTrue()
		expect(data.discoveredPets.Golden_Buddy):toBeTrue()
		expect(data.discoveredPets.Rainbow_Buddy):toBeTrue()
		expect(data.discoveredPets.Shiny_Buddy):toBeTrue()
		expect(data.discoveredPets["Buddy|Normal"]):toBeTrue()
		expect(data.discoveredPets["Buddy|Golden"]):toBeTrue()
		expect(data.discoveredPets["Buddy|Rainbow"]):toBeTrue()
		expect(data.discoveredPets["Buddy|Normal|Shiny"]):toBeTrue()
		expect(data.discoveredPets["Buddy|Golden|Shiny"]):toBeNil()
		expect(data.discoveredPets.forged):toBeNil()
	end)

	it("backfills exact owned combined states without inventing another Shiny", function()
		local data = DataSchema.migrate({
			schemaVersion = 10,
			pets = {
				{ id = "gold-shiny", petId = "Buddy", variant = "Golden", shiny = true },
				{ id = "rainbow", petId = "Whiskers", variant = "Rainbow", shiny = false },
			},
			equippedPets = {},
			discoveredPets = {},
		}, 1000)
		expect(data.discoveredPets["Buddy|Golden|Shiny"]):toBeTrue()
		expect(data.discoveredPets.Shiny_Buddy):toBeTrue()
		expect(data.discoveredPets["Buddy|Normal|Shiny"]):toBeNil()
		expect(data.discoveredPets["Whiskers|Rainbow"]):toBeTrue()
		expect(data.discoveredPets.Rainbow_Whiskers):toBeTrue()
	end)

	it("keeps canonical progress through a rolling V10 stamp and remains idempotent", function()
		local once = DataSchema.migrate({
			schemaVersion = 10,
			pets = {},
			equippedPets = {},
			discoveredPets = {
				Shiny_Buddy = true,
				["Buddy|Rainbow|Shiny"] = true,
			},
		}, 1000)
		expect(once.discoveredPets["Buddy|Rainbow|Shiny"]):toBeTrue()
		expect(once.discoveredPets["Buddy|Normal|Shiny"]):toBeNil()
		local rolling = DataSchema.deepCopy(once)
		rolling.schemaVersion = 10
		local twice = DataSchema.migrate(rolling, 1000)
		local snapshot = DataSchema.cloneForPersistence(twice, 1000)
		expect(twice):toEqual(once)
		expect(snapshot):toEqual(once)
		snapshot.discoveredPets["Buddy|Rainbow|Shiny"] = nil
		expect(once.discoveredPets["Buddy|Rainbow|Shiny"]):toBeTrue()
	end)
end)



describe("DataSchema V12 hostile progression normalization", function()
	it("keeps only known finite integer quest and mastery levels within canonical maxima", function()
		local data = DataSchema.migrate({
			schemaVersion = 11,
			upgrades = {
				StrongPets = 3,
				GoldenPetsChance = 1,
				FasterPets = 4,
				LuckyEggs = -1,
				EggMaster = 1.5,
				Sprinting = "2",
				CoinCollector = math.huge,
				Dedication = -math.huge,
				Veteran = 0 / 0,
				Rising = {},
				Legend = function() end,
				UnknownQuest = 1,
			},
			masteryBuffs = {
				MoreCoins = 10,
				LongerBuffs = 5,
				MoreDiamonds = 11,
				BetterLuck = -1,
				XPBoost = 1.5,
				FasterRunning = "2",
				MorePetSlots = math.huge,
				BiggerRange = -math.huge,
				QuickHatch = 0 / 0,
				DropMagnet = {},
				DoubleJump = function() end,
				UnknownMastery = 1,
			},
		}, 1000)

		expect(data.schemaVersion):toBe(12)
		expect(data.upgrades):toEqual({ StrongPets = 3, GoldenPetsChance = 1 })
		expect(data.masteryBuffs):toEqual({ MoreCoins = 10, LongerBuffs = 5 })
	end)

	it("normalizes sparse arrays by sorted positive integer keys and keeps first valid duplicates", function()
		local data = DataSchema.migrate({
			pets = {
				[7] = { id = "pet-c", petId = "Buddy", variant = "Rainbow", shiny = true },
				[2] = { id = "pet-a", petId = "Buddy", variant = "Normal", equipped = false },
				[5] = { id = "pet-a", petId = "Dog", variant = "Golden", equipped = true },
				[4] = "invalid",
				ignored = { id = "string-key", petId = "Dog" },
			},
			equippedPets = {
				[8] = "pet-c",
				[3] = "pet-a",
				[5] = "pet-a",
				ignored = "pet-c",
			},
			unlockedZones = { [9] = 7, [2] = 3, [4] = 3, [6] = 2.5, ignored = 8 },
			campaignProgress = { [10] = 48, [1] = 4, [6] = 4, [3] = 12, [5] = math.huge },
		}, 1000)

		expect(#data.pets):toBe(2)
		expect(data.pets[1].id):toBe("pet-a")
		expect(data.pets[1].petId):toBe("Buddy")
		expect(data.pets[2].id):toBe("pet-c")
		expect(data.pets[2].variant):toBe("Rainbow")
		expect(data.pets[2].shiny):toBeTrue()
		expect(data.equippedPets):toEqual({ "pet-a", "pet-c" })
		expect(data.unlockedZones):toEqual({ 1, 3, 7 })
		expect(data.campaignProgress):toEqual({ 4, 12, 48 })
	end)

	it("reapplies V12 normalization during persistence cloning without mutating live data", function()
		local live = DataSchema.migrate({
			upgrades = { StrongPets = 2 },
			masteryBuffs = { MoreCoins = 4 },
		}, 1000)
		live.upgrades.StrongPets = 999
		live.upgrades.UnknownQuest = 1
		live.masteryBuffs.MoreCoins = "10"
		live.masteryBuffs.UnknownMastery = 1

		local snapshot = DataSchema.cloneForPersistence(live, 1000)
		expect(snapshot.upgrades):toEqual({})
		expect(snapshot.masteryBuffs):toEqual({})
		expect(live.upgrades.StrongPets):toBe(999)
		expect(live.masteryBuffs.MoreCoins):toBe("10")
		expect(DataSchema.migrate(snapshot, 1000)):toEqual(snapshot)
	end)

	it("preserves valid V5, V6, V10, and V11 profile semantics through V12", function()
		local fixtures = {
			{
				schemaVersion = 5,
				pets = { { id = "v5", petId = "Buddy", variant = "Shiny" } },
				equippedPets = {},
			},
			{
				schemaVersion = 6,
				pets = { { id = "v6", petId = "Buddy", variant = "Rainbow", shiny = true } },
				equippedPets = {},
			},
			{
				schemaVersion = 10,
				pets = { { id = "v10", petId = "Buddy", variant = "Golden", shiny = true, enchantId = "StrongIII" } },
				equippedPets = {},
			},
			{
				schemaVersion = 11,
				pets = { { id = "v11", petId = "Buddy", variant = "Rainbow", shiny = true, enchantId = "AgileII" } },
				equippedPets = {},
				discoveredPets = { ["Buddy|Rainbow|Shiny"] = true },
			},
		}

		for _, fixture in ipairs(fixtures) do
			fixture.upgrades = { StrongPets = 3 }
			fixture.masteryBuffs = { MoreCoins = 10 }
			local once = DataSchema.migrate(fixture, 1000)
			local twice = DataSchema.migrate(once, 1000)
			expect(once.schemaVersion):toBe(12)
			expect(once.upgrades.StrongPets):toBe(3)
			expect(once.masteryBuffs.MoreCoins):toBe(10)
			expect(once.pets[1].shiny):toBeTrue()
			expect(twice):toEqual(once)
		end

		local enchanted = DataSchema.migrate(fixtures[3], 1000)
		expect(enchanted.pets[1].enchantId):toBe("StrongIII")
		expect(enchanted.discoveredPets["Buddy|Golden|Shiny"]):toBeTrue()
		local dex = DataSchema.migrate(fixtures[4], 1000)
		expect(dex.pets[1].enchantId):toBe("AgileII")
		expect(dex.discoveredPets["Buddy|Rainbow|Shiny"]):toBeTrue()
	end)
end)



describe("DataSchema V12 campaign boss claim normalization", function()
	it("keeps only exact true claims for canonical SpecialEgg levels", function()
		local values = { false, "claimed", {}, function() end, 1, 0 / 0 }
		for _, hostile in ipairs(values) do
			local data = DataSchema.migrate({
				campaignBossRewards = {
					["6"] = hostile,
					["12"] = true,
					["5"] = true,
					["999"] = true,
					[6] = true,
				},
			}, 1000)
			expect(data.campaignBossRewards):toEqual({ ["12"] = true })
			expect(DataSchema.migrate(data, 1000)):toEqual(data)
		end
	end)
end)
