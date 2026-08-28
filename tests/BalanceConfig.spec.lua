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

	it("defines bounded dormant potion persistence", function()
		expect(BalanceConfig.Potions.Persistence.MaxInventoryPerPotion):toBe(999)
		expect(BalanceConfig.Potions.Persistence.MaxTimedBuffSeconds):toBe(2592000)
		expect(BalanceConfig.Potions.Upgrades.MaxShinyCharges):toBe(30)
	end)

	it("binds save-compatible QOF-07 IDs to canonical costs and highest-stage effects", function()
		expect(BalanceConfig.Hatch.EggQuality[1].id):toBe("Eggs I")
		expect(BalanceConfig.Hatch.EggQuality[1].cost):toEqual({ currency = "coins", amount = 5000 })
		expect(BalanceConfig.Hatch.EggQuality[2].id):toBe("Eggs II")
		expect(BalanceConfig.Hatch.EggQuality[2].rarityMultiplier):toBe(1.6)

		local expectedIds = {
			Golden = { "epicLuck1", "epicLuck2", "epicLuck3" },
			Rainbow = { "legendLuck1", "legendLuck2", "legendLuck3" },
			Shiny = { "rerollLuck1", "rerollLuck2", "rerollLuck3" },
		}
		for variant, ids in pairs(expectedIds) do
			local levels = BalanceConfig.Hatch.DirectVariantUpgrades[variant]
			for index, id in ipairs(ids) do
				expect(levels[index].id):toBe(id)
			end
			expect(levels[3].multiplier):toBe(2)
			expect(levels[1].cost.currency):toBe("diamonds")
		end
	end)

	it("activates QOF-12 movement and collection while future systems remain dormant", function()
		expect(BalanceConfig.Variants.RuntimeEnabled):toBeTrue()
		expect(BalanceConfig.Hatch.RuntimeEnabled):toBeTrue()
		expect(BalanceConfig.Hatch.EggQualityRuntimeEnabled):toBeTrue()
		expect(BalanceConfig.Hatch.MultiOpenRuntimeEnabled):toBeTrue()
		expect(BalanceConfig.Hatch.DirectVariantUpgradesRuntimeEnabled):toBeTrue()
		expect(BalanceConfig.Hatch.MultiOpen[1].requireIds):toEqual({ "Eggs II" })
		expect(BalanceConfig.Hatch.MultiOpen[2].requireIds):toEqual({ "Eggs III" })
		expect(BalanceConfig.Hatch.MultiOpen[3].requireIds):toEqual({ "Eggs IV" })
		expect(BalanceConfig.Machines.RuntimeEnabled):toBeFalse()
		expect(BalanceConfig.CoreUpgrades.RuntimeEnabled):toBeTrue()
		expect(BalanceConfig.CoreUpgrades.StorageRuntimeEnabled):toBeTrue()
		expect(BalanceConfig.CoreUpgrades.PetEquipSlotsRuntimeEnabled):toBeTrue()
		expect(BalanceConfig.CoreUpgrades.SpeedRuntimeEnabled):toBeTrue()
		expect(BalanceConfig.CoreUpgrades.MagnetRuntimeEnabled):toBeTrue()
		expect(BalanceConfig.CoreUpgrades.DoubleLuckRuntimeEnabled):toBeTrue()
		expect(BalanceConfig.Shop.AutoHatchRuntimeEnabled):toBeFalse()
		expect(BalanceConfig.Potions.RuntimeEnabled):toBeFalse()
		expect(BalanceConfig.Enchanting.RuntimeEnabled):toBeFalse()
	end)

	it("binds exact QOF-12 Movement and Magnet contracts", function()
		expect(BalanceConfig.CoreUpgrades.Movement):toEqual({
			BaseWalkSpeed = 16,
			MaxWalkSpeed = 128,
			ReconcileIntervalSeconds = 1,
		})
		expect(BalanceConfig.CoreUpgrades.PickupCollection):toEqual({
			BaseRadius = 8,
			MaxRadius = 32,
			PollIntervalSeconds = 0.2,
			LifetimeSeconds = 15,
			MaxPendingPerPlayer = 24,
		})

		local function project(levels)
			local result = {}
			for _, level in ipairs(levels) do
				table.insert(result, {
					id = level.id,
					requireIds = level.requireIds,
					multiplier = level.multiplier,
					cost = level.cost,
				})
			end
			return result
		end
		expect(project(BalanceConfig.CoreUpgrades.Speed)):toEqual({
			{ id = "coreSpeed1", requireIds = { "Eggs II" }, multiplier = 1.05, cost = { currency = "coins", amount = 5000 } },
			{ id = "coreSpeed2", requireIds = { "coreSpeed1" }, multiplier = 1.10, cost = { currency = "coins", amount = 25000 } },
			{ id = "coreSpeed3", requireIds = { "coreSpeed2" }, multiplier = 1.15, cost = { currency = "coins", amount = 100000 } },
			{ id = "coreSpeed4", requireIds = { "coreSpeed3" }, multiplier = 1.20, cost = { currency = "coins", amount = 300000 } },
		})
		expect(project(BalanceConfig.CoreUpgrades.Magnet)):toEqual({
			{ id = "coreMagnet1", requireIds = { "Eggs II" }, multiplier = 1.25, cost = { currency = "coins", amount = 10000 } },
			{ id = "coreMagnet2", requireIds = { "coreMagnet1" }, multiplier = 1.50, cost = { currency = "coins", amount = 50000 } },
			{ id = "coreMagnet3", requireIds = { "coreMagnet2" }, multiplier = 2.00, cost = { currency = "coins", amount = 200000 } },
		})
	end)

	it("binds exact QOF-11 Double Luck without reusing legacy Luck IDs", function()
		local doubleLuck = BalanceConfig.CoreUpgrades.DoubleLuck
		expect(doubleLuck.id):toBe("doubleLuck")
		expect(doubleLuck.name):toBe("Double Luck")
		expect(doubleLuck.requireIds):toEqual({ "Eggs II" })
		expect(doubleLuck.multiplier):toBe(2)
		expect(doubleLuck.cost):toEqual({ currency = "diamonds", amount = 5000 })
		expect(doubleLuck.id == "luck I"):toBeFalse()
	end)

	it("binds exact QOF-10 Storage and Pet Equip chains", function()
		local function project(levels)
			local result = {}
			for _, level in ipairs(levels) do
				table.insert(result, {
					id = level.id,
					name = level.name,
					requireIds = level.requireIds,
					bonusSlots = level.bonusSlots,
					cost = level.cost,
				})
			end
			return result
		end

		expect(project(BalanceConfig.CoreUpgrades.Storage)):toEqual({
			{ id = "playtime1", name = "Storage I", requireIds = { "Eggs II" }, bonusSlots = 25, cost = { currency = "diamonds", amount = 250 } },
			{ id = "playtime2", name = "Storage II", requireIds = { "playtime1" }, bonusSlots = 50, cost = { currency = "diamonds", amount = 750 } },
			{ id = "playtime3", name = "Storage III", requireIds = { "playtime2" }, bonusSlots = 75, cost = { currency = "diamonds", amount = 2000 } },
			{ id = "streak1", name = "Storage IV", requireIds = { "playtime3" }, bonusSlots = 100, cost = { currency = "diamonds", amount = 5000 } },
			{ id = "streak2", name = "Storage V", requireIds = { "streak1" }, bonusSlots = 125, cost = { currency = "diamonds", amount = 10000 } },
			{ id = "streak3", name = "Storage VI", requireIds = { "streak2" }, bonusSlots = 150, cost = { currency = "diamonds", amount = 20000 } },
		})
		expect(project(BalanceConfig.CoreUpgrades.PetEquipSlots)):toEqual({
			{ id = "friends1", name = "Pet Equip I", requireIds = { "Eggs II" }, bonusSlots = 1, cost = { currency = "diamonds", amount = 1000 } },
			{ id = "friends2", name = "Pet Equip II", requireIds = { "friends1" }, bonusSlots = 2, cost = { currency = "diamonds", amount = 2500 } },
			{ id = "friends3", name = "Pet Equip III", requireIds = { "friends2" }, bonusSlots = 3, cost = { currency = "diamonds", amount = 5000 } },
		})
	end)
end)
