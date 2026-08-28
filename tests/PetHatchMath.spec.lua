-- PetHatchMath.spec.lua - QOF-07 canonical hatch probability and entitlement tests.

local originalRequire = require
local BalanceConfig = originalRequire("src/ReplicatedStorage/Shared/BalanceConfig")
local SharedMock = { BalanceConfig = BalanceConfig }
rawset(_G, "script", { Parent = SharedMock })

local function mockRequire(path)
	if path == BalanceConfig then return BalanceConfig end
	return originalRequire(path)
end
rawset(_G, "require", mockRequire)
local PetHatchMath = originalRequire("src/ReplicatedStorage/Shared/PetHatchMath")
rawset(_G, "require", originalRequire)

describe("PetHatchMath canonical direct outcomes", function()
	it("produces all six base-variant and independent Shiny combinations", function()
		local cases = {
			{ baseRoll = 0.5, shinyRoll = 0.5, variant = "Normal", shiny = false },
			{ baseRoll = 0.5, shinyRoll = 0, variant = "Normal", shiny = true },
			{ baseRoll = 0.001, shinyRoll = 0.5, variant = "Golden", shiny = false },
			{ baseRoll = 0.001, shinyRoll = 0, variant = "Golden", shiny = true },
			{ baseRoll = 0, shinyRoll = 0.5, variant = "Rainbow", shiny = false },
			{ baseRoll = 0, shinyRoll = 0, variant = "Rainbow", shiny = true },
		}
		for _, case in ipairs(cases) do
			local variant, shiny = PetHatchMath.rollOutcome(case.baseRoll, case.shinyRoll, 1)
			expect(variant):toBe(case.variant)
			expect(shiny):toBe(case.shiny)
		end
	end)

	it("uses exact categorical boundaries without overlapping Gold and Rainbow", function()
		local beforeRainbow = PetHatchMath.rollOutcome(0.000999999, 1, 1)
		local atRainbowBoundary = PetHatchMath.rollOutcome(0.001, 1, 1)
		local beforeNormal = PetHatchMath.rollOutcome(0.010999999, 1, 1)
		local atNormalBoundary = PetHatchMath.rollOutcome(0.011, 1, 1)
		expect(beforeRainbow):toBe("Rainbow")
		expect(atRainbowBoundary):toBe("Golden")
		expect(beforeNormal):toBe("Golden")
		expect(atNormalBoundary):toBe("Normal")
	end)

	it("keeps Shiny independent and honors its exact boundary", function()
		local variantA, shinyBefore = PetHatchMath.rollOutcome(0, 0.000099999, 1)
		local variantB, shinyAt = PetHatchMath.rollOutcome(0, 0.0001, 1)
		expect(variantA):toBe("Rainbow")
		expect(variantB):toBe("Rainbow")
		expect(shinyBefore):toBeTrue()
		expect(shinyAt):toBeFalse()
	end)

	it("separates Egg Quality from per-variant direct entitlement multipliers", function()
		expect(PetHatchMath.getSpeciesMultiplier(2, 1.6)):toBe(3.2)
		local generalOnly = PetHatchMath.getEffectiveChances(2)
		local upgraded = PetHatchMath.getEffectiveChances(2, {
			Golden = 2,
			Rainbow = 1.5,
			Shiny = 1.25,
		})
		expect(generalOnly.Golden):toBe(0.02)
		expect(generalOnly.Rainbow):toBe(0.002)
		expect(generalOnly.Shiny):toBe(0.0002)
		expect(upgraded.Golden):toBe(0.04)
		expect(upgraded.Rainbow):toBe(0.003)
		expect(upgraded.Shiny):toBe(0.00025)
	end)

	it("applies every cap after general Luck and direct entitlements compose", function()
		local combined = PetHatchMath.combineLuckMultipliers(2, 3, 2)
		local chances = PetHatchMath.getEffectiveChances(combined, {
			Golden = 2,
			Rainbow = 2,
			Shiny = 2,
		})
		expect(combined):toBe(10)
		expect(PetHatchMath.getSpeciesMultiplier(999, 1.6)):toBe(10)
		expect(chances.Golden):toBe(0.05)
		expect(chances.Rainbow):toBe(0.005)
		expect(chances.Shiny):toBe(0.001)
	end)

	it("treats missing, malformed, and sub-neutral multipliers safely", function()
		expect(PetHatchMath.combineLuckMultipliers(nil, 0, -1, 0 / 0)):toBe(1)
		expect(PetHatchMath.getSpeciesMultiplier(math.huge)):toBe(1)
		local variant, shiny = PetHatchMath.rollOutcome(-1, math.huge, "forged")
		expect(variant):toBe("Normal")
		expect(shiny):toBeFalse()
	end)
end)
