-- HatchCinematicPolicy.spec.lua - Pure QOF-09 classification and timing tests.

local Policy = require("src/ReplicatedStorage/Shared/HatchCinematicPolicy")

describe("HatchCinematicPolicy classification", function()
	it("applies Shiny, Rainbow, Golden, Legendary, Epic, Rare priority", function()
		expect(Policy.classifyPet({ rarity = "Legendary", variant = "Normal", shiny = true })):toBe("Shiny")
		expect(Policy.classifyPet({ rarity = "Legendary", variant = "Rainbow" })):toBe("Rainbow")
		expect(Policy.classifyPet({ rarity = "Legendary", variant = "Golden" })):toBe("Golden")
		expect(Policy.classifyPet({ rarity = "Legendary", variant = "Normal" })):toBe("Legendary")
		expect(Policy.classifyPet({ rarity = "Epic", variant = "Normal" })):toBe("Epic")
		expect(Policy.classifyPet({ rarity = "Rare", variant = "Normal" })):toBe("Rare")
	end)

	it("keeps normal Common and Uncommon results non-rare", function()
		expect(Policy.classifyPet({ rarity = "Common", variant = "Normal" })):toBe("Normal")
		expect(Policy.classifyPet({ rarity = "Uncommon", variant = "Normal" })):toBe("Normal")
		expect(Policy.classifyPet(nil)):toBe("Normal")
		expect(Policy.classifyPet("invalid")):toBe("Normal")
	end)

	it("supports rolling legacy Golden and Shiny mirrors", function()
		expect(Policy.classifyPet({ rarity = "Common", golden = true })):toBe("Golden")
		expect(Policy.classifyPet({ rarity = "Common", variant = "Shiny" })):toBe("Shiny")
	end)
end)

describe("HatchCinematicPolicy hero selection", function()
	it("chooses the highest classification and keeps the first equal result", function()
		local pets = {
			{ rarity = "Rare", variant = "Normal" },
			{ rarity = "Legendary", variant = "Normal" },
			{ rarity = "Legendary", variant = "Normal" },
			{ rarity = "Epic", variant = "Rainbow" },
		}
		expect(Policy.chooseHero(pets)):toBe(4)

		pets[4] = { rarity = "Rare", variant = "Normal" }
		expect(Policy.chooseHero(pets)):toBe(2)
	end)

	it("keeps the first Shiny when classifications tie", function()
		local pets = {
			{ rarity = "Legendary", variant = "Normal", shiny = true },
			{ rarity = "Common", variant = "Golden", shiny = true },
			{ rarity = "Common", variant = "Rainbow", shiny = true },
			{ rarity = "Common", variant = "Rainbow", shiny = true },
		}
		expect(Policy.chooseHero(pets)):toBe(1)
	end)

	it("designates the first result as hero for a normal non-empty batch", function()
		expect(Policy.chooseHero({
			{ rarity = "Common", variant = "Normal" },
			{ rarity = "Uncommon", variant = "Normal" },
		})):toBe(1)
		expect(Policy.chooseHero(nil)):toBeNil()
		expect(Policy.chooseHero({})):toBeNil()
	end)
end)

describe("HatchCinematicPolicy plans", function()
	it("builds deterministic entry metadata without mutating pets", function()
		local pets = {
			{ rarity = "Common", variant = "Normal" },
			{ rarity = "Epic", variant = "Normal" },
			{ rarity = "Rare", variant = "Golden" },
		}
		local before = {
			{ rarity = "Common", variant = "Normal" },
			{ rarity = "Epic", variant = "Normal" },
			{ rarity = "Rare", variant = "Golden" },
		}
		local plan = Policy.buildPlan(pets)
		expect(plan.heroIndex):toBe(3)
		expect(plan.hasRare):toBe(true)
		expect(plan.count):toBe(3)
		expect(plan.entries):toHaveLength(3)
		expect(plan.entries[1]):toEqual({ delay = 0, isHero = false, classification = "Normal" })
		expect(plan.entries[2]):toEqual({ delay = 0.12, isHero = false, classification = "Epic" })
		expect(plan.entries[3]):toEqual({ delay = 0.24, isHero = true, classification = "Golden" })
		expect(pets):toEqual(before)
	end)

	it("uses one designated hero but standard timing for a normal batch", function()
		local plan = Policy.buildPlan({
			{ rarity = "Common", variant = "Normal" },
			{ rarity = "Uncommon", variant = "Normal" },
		})
		expect(plan.heroIndex):toBe(1)
		expect(plan.hasRare):toBe(false)
		expect(plan.entries[1].isHero):toBe(true)
		expect(plan.entries[2].isHero):toBe(false)
		expect(plan.totalDuration):toBe(
			Policy.TIMINGS.IntroDuration
				+ Policy.TIMINGS.PopStagger
				+ Policy.TIMINGS.PopDuration
				+ Policy.TIMINGS.StandardHoldDuration
				+ Policy.TIMINGS.OutroDuration
		)
	end)

	it("keeps an x10 plan within the fixed three-second budget", function()
		local pets = {}
		for index = 1, 10 do
			pets[index] = {
				rarity = index == 10 and "Legendary" or "Common",
				variant = "Normal",
			}
		end
		local plan = Policy.buildPlan(pets)
		expect(Policy.TIMINGS.PopStagger):toBe(0.12)
		expect(plan.count):toBe(10)
		expect(plan.entries[10].delay):toBe(Policy.TIMINGS.PopStagger * 9)
		expect(plan.totalDuration):toBeLessThanOrEqual(3)
		expect(plan.totalDuration):toBeLessThanOrEqual(Policy.TIMINGS.MaxTotalDuration)
	end)

	it("caps hostile oversized lists and safely handles empty input", function()
		local pets = {}
		for index = 1, 12 do
			pets[index] = { rarity = "Rare", variant = "Normal" }
		end
		expect(Policy.buildPlan(pets).count):toBe(10)
		expect(Policy.buildPlan(nil)):toEqual({
			heroIndex = nil,
			hasRare = false,
			count = 0,
			entries = {},
			totalDuration = 0,
		})
	end)
end)
