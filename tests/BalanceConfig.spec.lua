-- BalanceConfig.spec.lua - Structural regression tests for QOF-02 balance data.

local BalanceConfig = require("src/ReplicatedStorage/Shared/BalanceConfig")

describe("BalanceConfig validation", function()
	it("passes its complete structural validator", function()
		expect(BalanceConfig.Validate()):toBeTrue()
	end)

	it("keeps approved variant chances and multipliers exact", function()
		expect(BalanceConfig.Hatch.BaseChances.Golden):toBe(0.01)
		expect(BalanceConfig.Hatch.BaseChances.Rainbow):toBe(0.001)
		expect(BalanceConfig.Hatch.BaseChances.Shiny):toBe(0.0001)
		expect(BalanceConfig.Variants.Base.Golden.damageMultiplier):toBe(2)
		expect(BalanceConfig.Variants.Base.Rainbow.damageMultiplier):toBe(5)
		expect(BalanceConfig.Variants.Shiny.damageMultiplier):toBe(1.5)
	end)

	it("uses the approved machine prices and seven-pet guarantee", function()
		expect(BalanceConfig.Machines.Gold.cost.amount):toBe(750)
		expect(BalanceConfig.Machines.Rainbow.cost.amount):toBe(2500)
		expect(BalanceConfig.Machines.SuccessChanceByInput):toEqual({
			[1] = 0.13,
			[2] = 0.26,
			[3] = 0.39,
			[4] = 0.50,
			[5] = 0.63,
			[6] = 0.88,
			[7] = 1,
		})
		expect(BalanceConfig.Legacy.GoldenConversion.SuccessChanceByInput):toEqual({
			[1] = 0.13,
			[2] = 0.26,
			[3] = 0.39,
			[4] = 0.50,
			[5] = 0.63,
			[6] = 0.88,
			[7] = 1,
		})
	end)

	it("defines Multi-Open as 2, 5, and 10 eggs", function()
		expect(BalanceConfig.Hatch.MultiOpen[1].eggCount):toBe(2)
		expect(BalanceConfig.Hatch.MultiOpen[2].eggCount):toBe(5)
		expect(BalanceConfig.Hatch.MultiOpen[3].eggCount):toBe(10)
	end)

	it("preserves all 56 current tree requirements during migration", function()
		local expected = {
			exit = 0,
			["Eggs I"] = 15, ["Eggs II"] = 2500, ["Eggs III"] = 5000000,
			["Eggs IV"] = 1002000000, ["Eggs V"] = 1555000000000,
			["eggSpeed I"] = 500, ["eggSpeed II"] = 10000, ["eggSpeed III"] = 500000,
			["luck I"] = 100, ["luck II"] = 5000, ["luck III"] = 250000, ["luck IV"] = 10000000,
			["coins I"] = 50, ["coins II"] = 2000, ["coins III"] = 100000,
			["coins IV"] = 5000000, ["coins V"] = 500000000,
			playerPortal = 0, luckPortal = 0, coinPortal = 0, playerBack = 0,
			friends1 = 1000, friends2 = 25000, friends3 = 500000,
			playtime1 = 500, playtime2 = 15000, playtime3 = 250000,
			streak1 = 750, streak2 = 20000, streak3 = 400000,
			vip1 = 5000, vip2 = 100000, vip3 = 2000000,
			luckBack = 0,
			epicLuck1 = 50000, epicLuck2 = 500000, epicLuck3 = 5000000,
			legendLuck1 = 200000, legendLuck2 = 2000000, legendLuck3 = 20000000,
			rerollLuck1 = 100000, rerollLuck2 = 1000000, rerollLuck3 = 50000000,
			coinBack = 0,
			coinMult1 = 1000000, coinMult2 = 10000000, coinMult3 = 100000000, coinMult4 = 1000000000,
			coinPassive1 = 500000, coinPassive2 = 5000000,
			coinPassive3 = 50000000, coinPassive4 = 500000000,
			coinBonus1 = 750000, coinBonus2 = 7500000, coinBonus3 = 75000000,
		}
		local actual = {}
		for upgradeId, requirement in pairs(BalanceConfig.Legacy.UpgradeTreeRequirements) do
			expect(requirement.currency):toBe("coins")
			actual[upgradeId] = requirement.amount
		end
		expect(actual):toEqual(expected)
	end)

	it("preserves current hatch and shop compatibility values", function()
		expect(BalanceConfig.Legacy.Hatch):toEqual({ ShinyChance = 0.01, RainbowChance = 0.001 })
		expect(BalanceConfig.Legacy.Shop):toEqual({
			LuckyPotion = { cost = 100, currency = "diamonds", multiplier = 2, duration = 300 },
			SpeedPotion = { cost = 50, currency = "diamonds", multiplier = 2, duration = 300 },
			PowerPotion = { cost = 150, currency = "diamonds", multiplier = 2, duration = 300 },
			CoinPotion = { cost = 125, currency = "diamonds", multiplier = 2, duration = 300 },
			AutoHatch = { cost = 500, currency = "diamonds", multiplier = 1, duration = 600 },
			ExtraEquipSlot = {
				cost = 1000,
				currency = "diamonds",
				multiplier = 1,
				duration = 0,
				maxPurchases = 5,
			},
		})
	end)

	it("keeps target systems disabled until their owning QOF activates them", function()
		expect(BalanceConfig.Variants.RuntimeEnabled):toBeFalse()
		expect(BalanceConfig.Hatch.RuntimeEnabled):toBeFalse()
		expect(BalanceConfig.Machines.RuntimeEnabled):toBeFalse()
		expect(BalanceConfig.CoreUpgrades.RuntimeEnabled):toBeFalse()
		expect(BalanceConfig.Potions.RuntimeEnabled):toBeFalse()
		expect(BalanceConfig.Enchanting.RuntimeEnabled):toBeFalse()
	end)
end)
