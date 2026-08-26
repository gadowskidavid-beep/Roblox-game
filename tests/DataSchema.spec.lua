--[[
	DataSchema.spec.lua - Unit tests for DataSchema module.
	Uses the minimal describe/it/expect runner from run_tests.lua.

	These tests are pure Luau (no Roblox API). We provide a mock for game.ReplicatedStorage
	and require DataSchema directly.
]]

-- Mock game.ReplicatedStorage.Shared.Config
local Config = {
	MaxExtraEquipSlots = 5,
	MaxPetInventoryBase = 100,
	MaxPetInventoryAbsolute = 250,
	MaxEquippedPetsAbsolute = 12,
}

-- Patch the global `game` to provide Config when DataSchema requires it
local SharedMock = {}
SharedMock.Config = Config

local ReplicatedStorageMock = { Shared = SharedMock }

-- Create a mock game tree that supports indexing
local gameMock = { ReplicatedStorage = ReplicatedStorageMock }
rawset(_G, "game", gameMock)

-- Override require to intercept the Config dependency
local originalRequire = require
local function mockRequire(path)
	-- When DataSchema does require(game.ReplicatedStorage.Shared.Config),
	-- the path argument will be our Config table (since the mock returns it).
	-- In that case, just return Config itself.
	if path == Config then
		return Config
	end
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

-- Now load DataSchema
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
