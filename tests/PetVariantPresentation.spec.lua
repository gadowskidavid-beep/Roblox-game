-- PetVariantPresentation.spec.lua - Pure QOF-05 presentation tests.

local originalRequire = require
local PetData = originalRequire("src/ReplicatedStorage/Shared/PetData")
local SharedMock = { PetData = PetData }
rawset(_G, "script", { Parent = SharedMock })

local function mockRequire(path)
	if path == PetData then return PetData end
	return originalRequire(path)
end
rawset(_G, "require", mockRequire)
local Presentation = originalRequire("src/ReplicatedStorage/Shared/PetVariantPresentation")
rawset(_G, "require", originalRequire)

describe("PetVariantPresentation canonical labels", function()
	it("resolves all six base variant and Shiny combinations", function()
		local cases = {
			{ pet = { petId = "Buddy", variant = "Normal", shiny = false }, label = "Normal", name = "Buddy", key = "Normal:Standard" },
			{ pet = { petId = "Buddy", variant = "Normal", shiny = true }, label = "Normal Shiny", name = "Shiny Buddy", key = "Normal:Shiny" },
			{ pet = { petId = "Buddy", variant = "Golden", shiny = false }, label = "Gold", name = "Gold Buddy", key = "Golden:Standard" },
			{ pet = { petId = "Buddy", variant = "Golden", shiny = true }, label = "Gold Shiny", name = "Gold Shiny Buddy", key = "Golden:Shiny" },
			{ pet = { petId = "Buddy", variant = "Rainbow", shiny = false }, label = "Rainbow", name = "Rainbow Buddy", key = "Rainbow:Standard" },
			{ pet = { petId = "Buddy", variant = "Rainbow", shiny = true }, label = "Rainbow Shiny", name = "Rainbow Shiny Buddy", key = "Rainbow:Shiny" },
		}

		for _, case in ipairs(cases) do
			local result = Presentation.resolve(case.pet)
			expect(result.variantLabel):toBe(case.label)
			expect(result.displayPetName):toBe(case.name)
			expect(result.visualKey):toBe(case.key)
		end
	end)

	it("supports legacy golden and Shiny representations", function()
		local golden = Presentation.resolve({ petId = "Splash", golden = true })
		expect(golden.baseVariant):toBe("Golden")
		expect(golden.variantLabel):toBe("Gold")

		local shiny = Presentation.resolve({ petId = "Splash", variant = "Shiny" })
		expect(shiny.baseVariant):toBe("Normal")
		expect(shiny.isShiny):toBeTrue()
		expect(shiny.variantLabel):toBe("Normal Shiny")
	end)

	it("normalizes missing and invalid state safely", function()
		local missing = Presentation.resolve(nil)
		expect(missing.baseVariant):toBe("Normal")
		expect(missing.isShiny):toBeFalse()
		expect(missing.variantLabel):toBe("Normal")
		expect(missing.displayPetName):toBe("Pet")

		local invalid = Presentation.resolve({ petId = "Buddy", variant = "Mythic", shiny = "yes" })
		expect(invalid.baseVariant):toBe("Normal")
		expect(invalid.isShiny):toBeFalse()
	end)

	it("uses canonical species names with a safe unknown-species fallback", function()
		expect(Presentation.resolve({ petId = "Buddy", name = "Forged" }).petName):toBe("Buddy")
		expect(Presentation.resolve({ petId = "Unknown", name = "Fallback" }).petName):toBe("Fallback")
		expect(Presentation.resolve({ petId = "Unknown" }).petName):toBe("Unknown")
	end)

	it("keeps the four-category compatibility projection", function()
		expect(Presentation.resolve({ variant = "Normal", shiny = true }).legacyCategory):toBe("Shiny")
		expect(Presentation.resolve({ variant = "Golden", shiny = true }).legacyCategory):toBe("Shiny")
		expect(Presentation.resolve({ variant = "Rainbow", shiny = false }).legacyCategory):toBe("Rainbow")
	end)

	it("does not mutate input tables", function()
		local pet = { petId = "Buddy", variant = "Golden", shiny = true, nested = { value = 4 } }
		local before = { petId = "Buddy", variant = "Golden", shiny = true, nested = { value = 4 } }
		Presentation.resolve(pet)
		expect(pet):toEqual(before)
	end)
end)
