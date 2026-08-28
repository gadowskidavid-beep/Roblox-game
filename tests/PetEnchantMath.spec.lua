local originalRequire = require
local BalanceConfig = originalRequire("src/ReplicatedStorage/Shared/BalanceConfig")
local SharedMock = { BalanceConfig = BalanceConfig }
rawset(_G, "script", { Parent = SharedMock })
rawset(_G, "require", function(path)
	if path == BalanceConfig then return BalanceConfig end
	return originalRequire(path)
end)
local PetEnchantMath = originalRequire("src/ReplicatedStorage/Shared/PetEnchantMath")
rawset(_G, "require", originalRequire)

describe("PetEnchantMath QOF-19 canonical whitelist", function()
	it("normalizes only the six exact canonical IDs", function()
		for _, definition in ipairs(BalanceConfig.Enchanting.Pool) do
			expect(PetEnchantMath.normalizeEnchantId(definition.id)):toBe(definition.id)
		end
		for _, invalid in ipairs({ "", "StrongIV", "strongi", " AgileI", 1, true }) do
			expect(PetEnchantMath.normalizeEnchantId(invalid)):toBeNil()
		end
	end)

	it("returns fresh defensive definition and public-pool copies", function()
		local definition = PetEnchantMath.getDefinition("StrongI")
		definition.id = "Forged"
		definition.multiplier = 999
		expect(PetEnchantMath.getDefinition("StrongI")):toEqual({
			id = "StrongI", weight = 35, stat = "damage", multiplier = 1.10,
		})

		local first = PetEnchantMath.getPublicPool()
		local second = PetEnchantMath.getPublicPool()
		first[1].id = "Forged"
		table.remove(first, 2)
		expect(#second):toBe(6)
		expect(second[1].id):toBe("StrongI")
		expect(PetEnchantMath.getPublicPool()[1].multiplier):toBe(1.10)
	end)

	it("applies Strong only to damage and Agile only to campaign speed", function()
		expect(PetEnchantMath.getDamageMultiplier({ enchantId = "StrongII" })):toBe(1.25)
		expect(PetEnchantMath.getCampaignSpeedMultiplier({ enchantId = "StrongII" })):toBe(1)
		expect(PetEnchantMath.getDamageMultiplier({ enchantId = "AgileIII" })):toBe(1)
		expect(PetEnchantMath.getCampaignSpeedMultiplier({ enchantId = "AgileIII" })):toBe(1.35)
	end)

	it("ignores forged pet-side stat and multiplier payloads", function()
		local forged = {
			enchantId = "Unknown",
			enchant = "StrongIII",
			enchantData = { id = "StrongIII", stat = "damage", multiplier = 999 },
			enchantStat = "damage",
			enchantMultiplier = 999,
		}
		expect(PetEnchantMath.getDamageMultiplier(forged)):toBe(1)
		expect(PetEnchantMath.getCampaignSpeedMultiplier(forged)):toBe(1)
	end)
end)
