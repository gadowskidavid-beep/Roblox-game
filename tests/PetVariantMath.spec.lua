-- PetVariantMath.spec.lua - Canonical QOF-04 pet damage tests.

local originalRequire = require
local BalanceConfig = originalRequire("src/ReplicatedStorage/Shared/BalanceConfig")
local PetData = originalRequire("src/ReplicatedStorage/Shared/PetData")
local SharedMock = {
	BalanceConfig = BalanceConfig,
	PetData = PetData,
}
rawset(_G, "script", { Parent = SharedMock })

local function mockRequire(path)
	if path == BalanceConfig then return BalanceConfig end
	if path == PetData then return PetData end
	return originalRequire(path)
end
rawset(_G, "require", mockRequire)
local PetVariantMath = originalRequire("src/ReplicatedStorage/Shared/PetVariantMath")
rawset(_G, "require", originalRequire)

describe("PetVariantMath canonical damage", function()
	it("calculates all six base variant and Shiny combinations", function()
		expect(PetVariantMath.getBaseDamage("Splash", "Normal", false)):toBe(3)
		expect(PetVariantMath.getBaseDamage("Splash", "Normal", true)):toBe(4.5)
		expect(PetVariantMath.getBaseDamage("Splash", "Golden", false)):toBe(6)
		expect(PetVariantMath.getBaseDamage("Splash", "Golden", true)):toBe(9)
		expect(PetVariantMath.getBaseDamage("Splash", "Rainbow", false)):toBe(15)
		expect(PetVariantMath.getBaseDamage("Splash", "Rainbow", true)):toBe(22.5)
	end)

	it("normalizes invalid base variants without trusting their value", function()
		expect(PetVariantMath.normalizeBaseVariant("Mythic")):toBe("Normal")
		expect(PetVariantMath.normalizeBaseVariant(nil)):toBe("Normal")
		expect(PetVariantMath.getBaseDamage("Buddy", "Mythic", true)):toBe(1.5)
	end)

	it("returns zero for unknown species and invalid base damage", function()
		expect(PetVariantMath.getBaseDamage("MissingPet", "Rainbow", true)):toBe(0)
		expect(PetVariantMath.getDamageFromBase(math.huge, "Normal", false)):toBe(0)
		expect(PetVariantMath.getDamageFromBase(-1, "Normal", false)):toBe(0)
	end)

	it("replaces a forged compatibility mirror", function()
		local pet = { petId = "Buddy", variant = "Golden", shiny = true, damage = 999999 }
		expect(PetVariantMath.refreshDamageMirror(pet)):toBe(3)
		expect(pet.damage):toBe(3)
	end)
end)
