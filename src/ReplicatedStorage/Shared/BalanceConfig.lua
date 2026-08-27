--[[
	BalanceConfig.lua - Single source of truth for Battle Pets economy and progression values.

	Sections marked RuntimeEnabled = false define approved future QOF balance, but are not
	consumed by gameplay until their data migration and server-authoritative service exist.
	Legacy values preserve current behavior while systems are migrated incrementally.
]]

local BalanceConfig = {
	Version = 1,

	Currencies = {
		Coins = "coins",
		Diamonds = "diamonds",
	},

	Limits = {
		PetInventoryBase = 100,
		PetInventoryAbsolute = 250,
		ExtraEquipSlots = 5,
		EquippedPetsBase = 3,
		EquippedPetsAbsolute = 12,
		AutoHatchInterval = 3,
		DestructibleReplicationDistance = 300,
	},

	World = {
		RarityWeights = {
			Common = 60,
			Uncommon = 25,
			Rare = 10,
			Epic = 4,
			Legendary = 1,
		},
		EggCoinCostsByZone = {
			[1] = 100,
			[2] = 500,
			[3] = 2000,
			[4] = 5000,
			[5] = 15000,
			[6] = 40000,
			[7] = 100000,
			[8] = 300000,
		},
		ZoneGateCoinCosts = {
			[1] = 0,
			[2] = 500,
			[3] = 2000,
			[4] = 5000,
			[5] = 15000,
			[6] = 40000,
			[7] = 100000,
			[8] = 300000,
		},
		Campaign = {
			EnergyRegenRate = 1,
			MaxEnergy = 100,
			BaseHealth = 500,
			EnemyBaseHealth = 500,
			PetDeployCosts = {
				Common = 10,
				Uncommon = 20,
				Rare = 35,
				Epic = 45,
				Legendary = 50,
			},
		},
	},

	-- Approved target model. Activated with the V6 pet migration in QOF-03/QOF-04.
	Variants = {
		RuntimeEnabled = false,
		Base = {
			Normal = { displayName = "Normal", damageMultiplier = 1 },
			Golden = { displayName = "Gold", damageMultiplier = 2 },
			Rainbow = { displayName = "Rainbow", damageMultiplier = 5 },
		},
		Shiny = {
			baseChance = 0.0001,
			damageMultiplier = 1.5,
			displayName = "Shiny",
		},
	},

	-- Approved target hatch model. Current hatch behavior remains under Legacy.Hatch
	-- until the variant migration and atomic batch flow are implemented.
	Hatch = {
		RuntimeEnabled = false,
		BaseChances = {
			Golden = 0.01,
			Rainbow = 0.001,
			Shiny = 0.0001,
		},
		LuckCaps = {
			SpeciesMultiplier = 10,
			GoldenChance = 0.05,
			RainbowChance = 0.005,
			ShinyChance = 0.001,
		},
		EggQuality = {
			{ id = "Eggs I", cost = { currency = "coins", amount = 5000 }, rarityMultiplier = 1.25 },
			{ id = "Eggs II", cost = { currency = "coins", amount = 50000 }, rarityMultiplier = 1.60 },
		},
		MultiOpen = {
			{ id = "Eggs III", cost = { currency = "diamonds", amount = 500 }, eggCount = 2 },
			{ id = "Eggs IV", cost = { currency = "diamonds", amount = 2500 }, eggCount = 5 },
			{ id = "Eggs V", cost = { currency = "diamonds", amount = 10000 }, eggCount = 10 },
		},
		DirectVariantUpgrades = {
			Golden = {
				{ multiplier = 1.25, cost = { currency = "diamonds", amount = 500 } },
				{ multiplier = 1.50, cost = { currency = "diamonds", amount = 1500 } },
				{ multiplier = 2.00, cost = { currency = "diamonds", amount = 5000 } },
			},
			Rainbow = {
				{ multiplier = 1.25, cost = { currency = "diamonds", amount = 1500 } },
				{ multiplier = 1.50, cost = { currency = "diamonds", amount = 5000 } },
				{ multiplier = 2.00, cost = { currency = "diamonds", amount = 15000 } },
			},
			Shiny = {
				{ multiplier = 1.25, cost = { currency = "diamonds", amount = 5000 } },
				{ multiplier = 1.50, cost = { currency = "diamonds", amount = 15000 } },
				{ multiplier = 2.00, cost = { currency = "diamonds", amount = 50000 } },
			},
		},
	},

	Machines = {
		RuntimeEnabled = false,
		MinInputs = 1,
		MaxInputs = 7,
		SuccessChanceByInput = {
			[1] = 0.13,
			[2] = 0.26,
			[3] = 0.39,
			[4] = 0.50,
			[5] = 0.63,
			[6] = 0.88,
			[7] = 1.00,
		},
		Gold = {
			id = "GoldMachine",
			zoneId = 3,
			inputVariant = "Normal",
			outputVariant = "Golden",
			cost = { currency = "diamonds", amount = 750 },
		},
		Rainbow = {
			id = "RainbowMachine",
			zoneId = 6,
			inputVariant = "Golden",
			outputVariant = "Rainbow",
			cost = { currency = "diamonds", amount = 2500 },
		},
	},

	CoreUpgrades = {
		RuntimeEnabled = false,
		Speed = {
			{ multiplier = 1.05, cost = { currency = "coins", amount = 5000 } },
			{ multiplier = 1.10, cost = { currency = "coins", amount = 25000 } },
			{ multiplier = 1.15, cost = { currency = "coins", amount = 100000 } },
			{ multiplier = 1.20, cost = { currency = "coins", amount = 300000 } },
		},
		Storage = {
			{ bonusSlots = 25, cost = { currency = "diamonds", amount = 250 } },
			{ bonusSlots = 50, cost = { currency = "diamonds", amount = 750 } },
			{ bonusSlots = 75, cost = { currency = "diamonds", amount = 2000 } },
			{ bonusSlots = 100, cost = { currency = "diamonds", amount = 5000 } },
			{ bonusSlots = 125, cost = { currency = "diamonds", amount = 10000 } },
			{ bonusSlots = 150, cost = { currency = "diamonds", amount = 20000 } },
		},
		Magnet = {
			{ multiplier = 1.25, cost = { currency = "coins", amount = 10000 } },
			{ multiplier = 1.50, cost = { currency = "coins", amount = 50000 } },
			{ multiplier = 2.00, cost = { currency = "coins", amount = 200000 } },
		},
		DoubleLuck = {
			multiplier = 2,
			cost = { currency = "diamonds", amount = 5000 },
		},
		PetEquipSlots = {
			{ bonusSlots = 1, cost = { currency = "diamonds", amount = 1000 } },
			{ bonusSlots = 2, cost = { currency = "diamonds", amount = 2500 } },
			{ bonusSlots = 3, cost = { currency = "diamonds", amount = 5000 } },
		},
	},

	Potions = {
		RuntimeEnabled = false,
		Persistence = {
			MaxInventoryPerPotion = 999,
			MaxTimedBuffSeconds = 30 * 24 * 60 * 60,
		},
		Catalog = {
			LuckPotion = {
				cost = { currency = "diamonds", amount = 100 },
				buffType = "luck",
				multiplier = 2,
				durationSeconds = 600,
			},
			MegaLuckPotion = {
				cost = { currency = "diamonds", amount = 350 },
				buffType = "luck",
				multiplier = 5,
				durationSeconds = 300,
			},
			SpeedPotion = {
				cost = { currency = "diamonds", amount = 50 },
				buffType = "speed",
				multiplier = 2,
				durationSeconds = 300,
			},
			CoinPotion = {
				cost = { currency = "diamonds", amount = 125 },
				buffType = "coins",
				multiplier = 2,
				durationSeconds = 600,
			},
			ShinyPotion = {
				cost = { currency = "diamonds", amount = 1000 },
				buffType = "shinyChance",
				multiplier = 10,
				hatchCharges = 3,
			},
		},
		Upgrades = {
			BaseSlots = 2,
			MaxSlots = 5,
			PotionSlots = {
				{ slots = 3, cost = { currency = "diamonds", amount = 500 } },
				{ slots = 4, cost = { currency = "diamonds", amount = 1500 } },
				{ slots = 5, cost = { currency = "diamonds", amount = 4000 } },
			},
			Duration = {
				{ multiplier = 1.25, cost = { currency = "diamonds", amount = 750 } },
				{ multiplier = 1.50, cost = { currency = "diamonds", amount = 2000 } },
				{ multiplier = 1.75, cost = { currency = "diamonds", amount = 5000 } },
				{ multiplier = 2.00, cost = { currency = "diamonds", amount = 10000 } },
			},
			AutoDrink = {
				cost = { currency = "diamonds", amount = 7500 },
			},
			MaxShinyCharges = 30,
		},
	},

	Enchanting = {
		RuntimeEnabled = false,
		RollCost = { currency = "diamonds", amount = 500 },
		MaxSlotsPerPet = 1,
		Pool = {
			{ id = "StrongI", weight = 35, stat = "damage", multiplier = 1.10 },
			{ id = "StrongII", weight = 15, stat = "damage", multiplier = 1.25 },
			{ id = "StrongIII", weight = 5, stat = "damage", multiplier = 1.50 },
			{ id = "AgileI", weight = 30, stat = "speed", multiplier = 1.10 },
			{ id = "AgileII", weight = 12, stat = "speed", multiplier = 1.20 },
			{ id = "AgileIII", weight = 3, stat = "speed", multiplier = 1.35 },
		},
	},

	-- Values below remain active until their owning systems are migrated.
	Legacy = {
		Hatch = {
			ShinyChance = 0.01,
			RainbowChance = 0.001,
		},
		GoldenConversion = {
			MinInputs = 1,
			MaxInputs = 7,
			SuccessChanceByInput = {
				[1] = 0.13,
				[2] = 0.26,
				[3] = 0.39,
				[4] = 0.50,
				[5] = 0.63,
				[6] = 0.88,
				[7] = 1.00,
			},
		},
		Shop = {
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
		},
		UpgradeTreeRequirements = {
			["exit"] = { currency = "coins", amount = 0 },
			["Eggs I"] = { currency = "coins", amount = 15 },
			["Eggs II"] = { currency = "coins", amount = 2500 },
			["Eggs III"] = { currency = "coins", amount = 5000000 },
			["Eggs IV"] = { currency = "coins", amount = 1002000000 },
			["Eggs V"] = { currency = "coins", amount = 1555000000000 },
			["eggSpeed I"] = { currency = "coins", amount = 500 },
			["eggSpeed II"] = { currency = "coins", amount = 10000 },
			["eggSpeed III"] = { currency = "coins", amount = 500000 },
			["luck I"] = { currency = "coins", amount = 100 },
			["luck II"] = { currency = "coins", amount = 5000 },
			["luck III"] = { currency = "coins", amount = 250000 },
			["luck IV"] = { currency = "coins", amount = 10000000 },
			["coins I"] = { currency = "coins", amount = 50 },
			["coins II"] = { currency = "coins", amount = 2000 },
			["coins III"] = { currency = "coins", amount = 100000 },
			["coins IV"] = { currency = "coins", amount = 5000000 },
			["coins V"] = { currency = "coins", amount = 500000000 },
			["playerPortal"] = { currency = "coins", amount = 0 },
			["luckPortal"] = { currency = "coins", amount = 0 },
			["coinPortal"] = { currency = "coins", amount = 0 },
			["playerBack"] = { currency = "coins", amount = 0 },
			["friends1"] = { currency = "coins", amount = 1000 },
			["friends2"] = { currency = "coins", amount = 25000 },
			["friends3"] = { currency = "coins", amount = 500000 },
			["playtime1"] = { currency = "coins", amount = 500 },
			["playtime2"] = { currency = "coins", amount = 15000 },
			["playtime3"] = { currency = "coins", amount = 250000 },
			["streak1"] = { currency = "coins", amount = 750 },
			["streak2"] = { currency = "coins", amount = 20000 },
			["streak3"] = { currency = "coins", amount = 400000 },
			["vip1"] = { currency = "coins", amount = 5000 },
			["vip2"] = { currency = "coins", amount = 100000 },
			["vip3"] = { currency = "coins", amount = 2000000 },
			["luckBack"] = { currency = "coins", amount = 0 },
			["epicLuck1"] = { currency = "coins", amount = 50000 },
			["epicLuck2"] = { currency = "coins", amount = 500000 },
			["epicLuck3"] = { currency = "coins", amount = 5000000 },
			["legendLuck1"] = { currency = "coins", amount = 200000 },
			["legendLuck2"] = { currency = "coins", amount = 2000000 },
			["legendLuck3"] = { currency = "coins", amount = 20000000 },
			["rerollLuck1"] = { currency = "coins", amount = 100000 },
			["rerollLuck2"] = { currency = "coins", amount = 1000000 },
			["rerollLuck3"] = { currency = "coins", amount = 50000000 },
			["coinBack"] = { currency = "coins", amount = 0 },
			["coinMult1"] = { currency = "coins", amount = 1000000 },
			["coinMult2"] = { currency = "coins", amount = 10000000 },
			["coinMult3"] = { currency = "coins", amount = 100000000 },
			["coinMult4"] = { currency = "coins", amount = 1000000000 },
			["coinPassive1"] = { currency = "coins", amount = 500000 },
			["coinPassive2"] = { currency = "coins", amount = 5000000 },
			["coinPassive3"] = { currency = "coins", amount = 50000000 },
			["coinPassive4"] = { currency = "coins", amount = 500000000 },
			["coinBonus1"] = { currency = "coins", amount = 750000 },
			["coinBonus2"] = { currency = "coins", amount = 7500000 },
			["coinBonus3"] = { currency = "coins", amount = 75000000 },
		},
	},
}

local VALID_CURRENCIES = {
	coins = true,
	diamonds = true,
}

local function isFiniteNumber(value)
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
end

local function validateCost(cost, context)
	assert(type(cost) == "table", context .. " cost must be a table")
	assert(VALID_CURRENCIES[cost.currency] == true, context .. " has an unknown currency")
	assert(isFiniteNumber(cost.amount) and cost.amount >= 0, context .. " has an invalid amount")
end

local function validateIncreasingCosts(levels, context)
	local previous = -1
	for index, level in ipairs(levels) do
		validateCost(level.cost, context .. " level " .. tostring(index))
		assert(level.cost.amount > previous, context .. " costs must increase")
		previous = level.cost.amount
	end
end

function BalanceConfig.Validate()
	local futureSections = {
		Variants = BalanceConfig.Variants,
		Hatch = BalanceConfig.Hatch,
		Machines = BalanceConfig.Machines,
		CoreUpgrades = BalanceConfig.CoreUpgrades,
		Potions = BalanceConfig.Potions,
		Enchanting = BalanceConfig.Enchanting,
	}
	for name, section in pairs(futureSections) do
		assert(section.RuntimeEnabled == false, name .. " must remain disabled until its owning QOF")
	end

	for name, value in pairs(BalanceConfig.Limits) do
		assert(isFiniteNumber(value) and value > 0, name .. " limit must be positive")
	end
	assert(BalanceConfig.Limits.PetInventoryBase <= BalanceConfig.Limits.PetInventoryAbsolute, "pet inventory limits are inverted")
	assert(BalanceConfig.Limits.EquippedPetsBase <= BalanceConfig.Limits.EquippedPetsAbsolute, "equipped pet limits are inverted")

	local rarityWeight = 0
	for name, weight in pairs(BalanceConfig.World.RarityWeights) do
		assert(isFiniteNumber(weight) and weight > 0, name .. " rarity weight must be positive")
		rarityWeight = rarityWeight + weight
	end
	assert(rarityWeight == 100, "rarity weights must sum to 100")

	local zoneCount = 0
	for zoneId = 1, 8 do
		local eggCost = BalanceConfig.World.EggCoinCostsByZone[zoneId]
		local gateCost = BalanceConfig.World.ZoneGateCoinCosts[zoneId]
		assert(isFiniteNumber(eggCost) and eggCost >= 0, "zone " .. tostring(zoneId) .. " egg cost is invalid")
		assert(isFiniteNumber(gateCost) and gateCost >= 0, "zone " .. tostring(zoneId) .. " gate cost is invalid")
		zoneCount = zoneCount + 1
	end
	assert(zoneCount == 8, "world must define exactly eight zones")
	for zoneId in pairs(BalanceConfig.World.EggCoinCostsByZone) do
		assert(type(zoneId) == "number" and zoneId >= 1 and zoneId <= zoneCount, "egg cost contains an unknown zone")
	end
	for zoneId in pairs(BalanceConfig.World.ZoneGateCoinCosts) do
		assert(type(zoneId) == "number" and zoneId >= 1 and zoneId <= zoneCount, "gate cost contains an unknown zone")
	end

	local campaign = BalanceConfig.World.Campaign
	assert(isFiniteNumber(campaign.EnergyRegenRate) and campaign.EnergyRegenRate > 0, "campaign energy regen is invalid")
	assert(isFiniteNumber(campaign.MaxEnergy) and campaign.MaxEnergy > 0, "campaign max energy is invalid")
	assert(isFiniteNumber(campaign.BaseHealth) and campaign.BaseHealth > 0, "campaign base health is invalid")
	assert(isFiniteNumber(campaign.EnemyBaseHealth) and campaign.EnemyBaseHealth > 0, "campaign enemy health is invalid")
	for rarity, cost in pairs(campaign.PetDeployCosts) do
		assert(BalanceConfig.World.RarityWeights[rarity] ~= nil, "unknown campaign deploy rarity")
		assert(isFiniteNumber(cost) and cost >= 0 and cost <= campaign.MaxEnergy, rarity .. " deploy cost is invalid")
	end

	local chances = BalanceConfig.Hatch.BaseChances
	for name, chance in pairs(chances) do
		assert(isFiniteNumber(chance) and chance >= 0 and chance <= 1, name .. " hatch chance is invalid")
	end
	assert(chances.Golden + chances.Rainbow <= 1, "base variant chances exceed 100%")

	assert(BalanceConfig.Variants.Base.Normal.damageMultiplier == 1, "Normal multiplier must be x1")
	assert(BalanceConfig.Variants.Base.Golden.damageMultiplier == 2, "Gold multiplier must be x2")
	assert(BalanceConfig.Variants.Base.Rainbow.damageMultiplier == 5, "Rainbow multiplier must be x5")
	assert(BalanceConfig.Variants.Shiny.damageMultiplier == 1.5, "Shiny multiplier must be x1.5")

	local expectedCounts = { 2, 5, 10 }
	for index, level in ipairs(BalanceConfig.Hatch.MultiOpen) do
		assert(level.eggCount == expectedCounts[index], "Multi-Open counts must be 2/5/10")
		validateCost(level.cost, "Multi-Open " .. tostring(index))
	end
	assert(#BalanceConfig.Hatch.MultiOpen == #expectedCounts, "Multi-Open must have exactly three levels")

	validateIncreasingCosts(BalanceConfig.Hatch.EggQuality, "Egg Quality")
	for variant, levels in pairs(BalanceConfig.Hatch.DirectVariantUpgrades) do
		validateIncreasingCosts(levels, variant .. " hatch chance")
		local previousMultiplier = 0
		for _, level in ipairs(levels) do
			assert(isFiniteNumber(level.multiplier) and level.multiplier > previousMultiplier, variant .. " multipliers must increase")
			previousMultiplier = level.multiplier
		end
	end

	local function validateMachineCurve(machine, context)
		assert(machine.MinInputs >= 1 and machine.MaxInputs >= machine.MinInputs, context .. " input limits are invalid")
		local previousChance = -1
		for count = machine.MinInputs, machine.MaxInputs do
			local chance = machine.SuccessChanceByInput[count]
			assert(isFiniteNumber(chance) and chance > previousChance and chance <= 1, context .. " chances must increase")
			previousChance = chance
		end
		assert(previousChance == 1, context .. " maximum inputs must guarantee success")
	end
	validateMachineCurve(BalanceConfig.Machines, "target machine")
	validateMachineCurve(BalanceConfig.Legacy.GoldenConversion, "legacy Golden conversion")
	validateCost(BalanceConfig.Machines.Gold.cost, "Gold Machine")
	validateCost(BalanceConfig.Machines.Rainbow.cost, "Rainbow Machine")

	validateIncreasingCosts(BalanceConfig.CoreUpgrades.Speed, "Speed")
	validateIncreasingCosts(BalanceConfig.CoreUpgrades.Storage, "Storage")
	validateIncreasingCosts(BalanceConfig.CoreUpgrades.Magnet, "Magnet")
	validateIncreasingCosts(BalanceConfig.CoreUpgrades.PetEquipSlots, "Pet Equip Slots")
	validateCost(BalanceConfig.CoreUpgrades.DoubleLuck.cost, "Double Luck")
	validateIncreasingCosts(BalanceConfig.Potions.Upgrades.PotionSlots, "Potion Slots")
	validateIncreasingCosts(BalanceConfig.Potions.Upgrades.Duration, "Potion Duration")
	validateCost(BalanceConfig.Potions.Upgrades.AutoDrink.cost, "Auto-Drink")

	local potionPersistence = BalanceConfig.Potions.Persistence
	assert(
		isFiniteNumber(potionPersistence.MaxInventoryPerPotion)
			and potionPersistence.MaxInventoryPerPotion > 0
			and potionPersistence.MaxInventoryPerPotion % 1 == 0,
		"potion inventory cap is invalid"
	)
	assert(
		isFiniteNumber(potionPersistence.MaxTimedBuffSeconds)
			and potionPersistence.MaxTimedBuffSeconds > 0
			and potionPersistence.MaxTimedBuffSeconds % 1 == 0,
		"timed buff persistence cap is invalid"
	)
	assert(
		isFiniteNumber(BalanceConfig.Potions.Upgrades.MaxShinyCharges)
			and BalanceConfig.Potions.Upgrades.MaxShinyCharges > 0
			and BalanceConfig.Potions.Upgrades.MaxShinyCharges % 1 == 0,
		"Shiny charge cap is invalid"
	)

	for potionId, potion in pairs(BalanceConfig.Potions.Catalog) do
		validateCost(potion.cost, potionId)
		assert(isFiniteNumber(potion.multiplier) and potion.multiplier > 0, potionId .. " multiplier is invalid")
		if potion.durationSeconds ~= nil then
			assert(isFiniteNumber(potion.durationSeconds) and potion.durationSeconds > 0, potionId .. " duration is invalid")
		end
		if potion.hatchCharges ~= nil then
			assert(potion.hatchCharges > 0 and potion.hatchCharges % 1 == 0, potionId .. " charges are invalid")
		end
	end

	validateCost(BalanceConfig.Enchanting.RollCost, "Enchanting")
	local enchantWeight = 0
	for _, enchant in ipairs(BalanceConfig.Enchanting.Pool) do
		assert(enchant.weight > 0, enchant.id .. " weight must be positive")
		enchantWeight = enchantWeight + enchant.weight
	end
	assert(enchantWeight == 100, "enchant weights must sum to 100")

	local legacyHatch = BalanceConfig.Legacy.Hatch
	assert(isFiniteNumber(legacyHatch.ShinyChance) and legacyHatch.ShinyChance >= 0 and legacyHatch.ShinyChance <= 1, "legacy Shiny chance is invalid")
	assert(isFiniteNumber(legacyHatch.RainbowChance) and legacyHatch.RainbowChance >= 0 and legacyHatch.RainbowChance <= 1, "legacy Rainbow chance is invalid")
	assert(legacyHatch.ShinyChance + legacyHatch.RainbowChance <= 1, "legacy hatch chances exceed 100%")

	for itemId, item in pairs(BalanceConfig.Legacy.Shop) do
		validateCost({ currency = item.currency, amount = item.cost }, "legacy shop " .. itemId)
		assert(isFiniteNumber(item.multiplier) and item.multiplier > 0, itemId .. " multiplier is invalid")
		assert(isFiniteNumber(item.duration) and item.duration >= 0, itemId .. " duration is invalid")
		if item.maxPurchases ~= nil then
			assert(item.maxPurchases > 0 and item.maxPurchases % 1 == 0, itemId .. " max purchases is invalid")
		end
	end

	local treeCount = 0
	for upgradeId, requirement in pairs(BalanceConfig.Legacy.UpgradeTreeRequirements) do
		validateCost(requirement, "legacy tree " .. upgradeId)
		treeCount = treeCount + 1
	end
	assert(treeCount == 56, "legacy upgrade tree must contain exactly 56 nodes")

	return true
end

BalanceConfig.Validate()

return BalanceConfig
