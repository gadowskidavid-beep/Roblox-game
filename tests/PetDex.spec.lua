-- PetDex.spec.lua - QOF-20 pure six-state collection contract tests.

local originalRequire = require
local PetData = originalRequire("src/ReplicatedStorage/Shared/PetData")
local Parent = { PetData = PetData }
rawset(_G, "script", { Parent = Parent })
rawset(_G, "require", function(path)
	if path == PetData then return PetData end
	return originalRequire(path)
end)
local PetDex = originalRequire("src/ReplicatedStorage/Shared/PetDex")
rawset(_G, "require", originalRequire)

local EXPECTED_STATES = {
	{ id = "Normal", baseVariant = "Normal", shiny = false },
	{ id = "NormalShiny", baseVariant = "Normal", shiny = true },
	{ id = "Golden", baseVariant = "Golden", shiny = false },
	{ id = "GoldenShiny", baseVariant = "Golden", shiny = true },
	{ id = "Rainbow", baseVariant = "Rainbow", shiny = false },
	{ id = "RainbowShiny", baseVariant = "Rainbow", shiny = true },
}

describe("PetDex QOF-20 six-state contract", function()
	it("returns six ordered defensive states and the exact 96-card total", function()
		local first = PetDex.getStates()
		local second = PetDex.getStates()
		expect(first):toEqual(EXPECTED_STATES)
		expect(PetDex.getTotalStateCount()):toBe(96)
		first[1].baseVariant = "Forged"
		expect(second):toEqual(EXPECTED_STATES)
		expect(PetDex.getStates()):toEqual(EXPECTED_STATES)
	end)

	it("builds all exact canonical and rolling compatibility keys", function()
		expect(PetDex.getCanonicalKey("Buddy", "Normal", false)):toBe("Buddy|Normal")
		expect(PetDex.getCanonicalKey("Buddy", "Normal", true)):toBe("Buddy|Normal|Shiny")
		expect(PetDex.getCanonicalKey("Buddy", "Golden", false)):toBe("Buddy|Golden")
		expect(PetDex.getCanonicalKey("Buddy", "Golden", true)):toBe("Buddy|Golden|Shiny")
		expect(PetDex.getCanonicalKey("Buddy", "Rainbow", false)):toBe("Buddy|Rainbow")
		expect(PetDex.getCanonicalKey("Buddy", "Rainbow", true)):toBe("Buddy|Rainbow|Shiny")
		expect(PetDex.getWriteKeys("Buddy", "Golden", true))
			:toEqual({ "Buddy|Golden|Shiny", "Shiny_Buddy" })
		expect(PetDex.getCanonicalKey("Unknown", "Normal", false)):toBeNil()
		expect(PetDex.getCanonicalKey("Buddy", "Shiny", false)):toBeNil()
		expect(PetDex.getCanonicalKey("Buddy", "Normal", nil)):toBeNil()
	end)

	it("migrates legacy progress conservatively without gifting combined Shinies", function()
		local projected = PetDex.projectDiscovery({
			Buddy = true,
			Golden_Buddy = true,
			Rainbow_Buddy = true,
			Shiny_Buddy = true,
			Unknown = true,
			["Buddy|Rainbow|Shiny"] = false,
		})
		expect(projected.Buddy):toBeTrue()
		expect(projected["Buddy|Normal"]):toBeTrue()
		expect(projected["Buddy|Golden"]):toBeTrue()
		expect(projected["Buddy|Rainbow"]):toBeTrue()
		expect(projected["Buddy|Normal|Shiny"]):toBeTrue()
		expect(projected["Buddy|Golden|Shiny"]):toBeNil()
		expect(projected["Buddy|Rainbow|Shiny"]):toBeNil()
		expect(projected.Unknown):toBeNil()

		local exactGoldShiny = PetDex.projectDiscovery({
			Shiny_Buddy = true,
			["Buddy|Golden|Shiny"] = true,
		})
		expect(exactGoldShiny["Buddy|Golden|Shiny"]):toBeTrue()
		expect(exactGoldShiny["Buddy|Normal|Shiny"]):toBeNil()
	end)

	it("backfills exact owned states and retains required legacy mirrors", function()
		local normalized = PetDex.normalizeDiscovery({}, {
			{ petId = "Buddy", variant = "Golden", shiny = true },
			{ petId = "Whiskers", variant = "Rainbow", shiny = false },
		})
		expect(normalized["Buddy|Golden|Shiny"]):toBeTrue()
		expect(normalized.Shiny_Buddy):toBeTrue()
		expect(normalized["Whiskers|Rainbow"]):toBeTrue()
		expect(normalized.Rainbow_Whiskers):toBeTrue()
		expect(normalized["Buddy|Normal|Shiny"]):toBeNil()
	end)

	it("records confirmed pets idempotently and rejects hostile boundaries", function()
		local discovery = {}
		expect(PetDex.recordPet(discovery, {
			petId = "Buddy", variant = "Rainbow", shiny = true,
		})):toBeTrue()
		expect(PetDex.recordPet(discovery, {
			petId = "Buddy", variant = "Rainbow", shiny = true,
		})):toBeFalse()
		expect(discovery["Buddy|Rainbow|Shiny"]):toBeTrue()
		expect(discovery.Shiny_Buddy):toBeTrue()
		expect(PetDex.projectDiscovery(setmetatable({}, {}))):toBeNil()
		expect(PetDex.recordPet({}, setmetatable({}, {}))):toBeFalse()
	end)
end)
