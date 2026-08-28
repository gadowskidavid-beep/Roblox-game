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
		RuntimeEnabled = true,
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

	-- Canonical hatch model. QOF-08 adds atomic, server-authoritative Multi-Open
	-- to the QOF-06/07 outcome and entitlement foundations.
	Hatch = {
		-- This top-level gate owns only the direct single-egg outcome model.
		-- Deferred subfeatures keep explicit gates so their balance data stays dormant.
		RuntimeEnabled = true,
		EggQualityRuntimeEnabled = true,
		MultiOpenRuntimeEnabled = true,
		DirectVariantUpgradesRuntimeEnabled = true,
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
			{
				id = "Eggs I",
				name = "Egg Quality I",
				description = "Improves non-Common species weights by x1.25.",
				requireIds = {},
				cost = { currency = "coins", amount = 5000 },
				rarityMultiplier = 1.25,
			},
			{
				id = "Eggs II",
				name = "Egg Quality II",
				description = "Improves non-Common species weights by x1.60 total.",
				requireIds = { "Eggs I" },
				cost = { currency = "coins", amount = 50000 },
				rarityMultiplier = 1.60,
			},
		},
		MultiOpen = {
			{
				id = "Eggs III",
				name = "Multi-Open I",
				description = "Unlocks atomic x2 egg hatching.",
				requireIds = { "Eggs II" },
				cost = { currency = "diamonds", amount = 500 },
				eggCount = 2,
			},
			{
				id = "Eggs IV",
				name = "Multi-Open II",
				description = "Unlocks atomic x5 egg hatching.",
				requireIds = { "Eggs III" },
				cost = { currency = "diamonds", amount = 2500 },
				eggCount = 5,
			},
			{
				id = "Eggs V",
				name = "Multi-Open III",
				description = "Unlocks atomic x10 egg hatching.",
				requireIds = { "Eggs IV" },
				cost = { currency = "diamonds", amount = 10000 },
				eggCount = 10,
			},
		},
		-- QOF-07 intentionally reuses three legacy save-compatible chains. Each
		-- branch applies only its highest contiguous purchased level.
		DirectVariantUpgrades = {
			Golden = {
				{
					id = "epicLuck1",
					name = "Gold Chance I",
					description = "Multiplies direct Gold hatch chance by x1.25.",
					requireIds = {},
					multiplier = 1.25,
					cost = { currency = "diamonds", amount = 500 },
				},
				{
					id = "epicLuck2",
					name = "Gold Chance II",
					description = "Multiplies direct Gold hatch chance by x1.50 total.",
					requireIds = { "epicLuck1" },
					multiplier = 1.50,
					cost = { currency = "diamonds", amount = 1500 },
				},
				{
					id = "epicLuck3",
					name = "Gold Chance III",
					description = "Multiplies direct Gold hatch chance by x2 total.",
					requireIds = { "epicLuck2" },
					multiplier = 2.00,
					cost = { currency = "diamonds", amount = 5000 },
				},
			},
			Rainbow = {
				{
					id = "legendLuck1",
					name = "Rainbow Chance I",
					description = "Multiplies direct Rainbow hatch chance by x1.25.",
					requireIds = {},
					multiplier = 1.25,
					cost = { currency = "diamonds", amount = 1500 },
				},
				{
					id = "legendLuck2",
					name = "Rainbow Chance II",
					description = "Multiplies direct Rainbow hatch chance by x1.50 total.",
					requireIds = { "legendLuck1" },
					multiplier = 1.50,
					cost = { currency = "diamonds", amount = 5000 },
				},
				{
					id = "legendLuck3",
					name = "Rainbow Chance III",
					description = "Multiplies direct Rainbow hatch chance by x2 total.",
					requireIds = { "legendLuck2" },
					multiplier = 2.00,
					cost = { currency = "diamonds", amount = 15000 },
				},
			},
			Shiny = {
				{
					id = "rerollLuck1",
					name = "Shiny Chance I",
					description = "Multiplies independent Shiny chance by x1.25.",
					requireIds = {},
					multiplier = 1.25,
					cost = { currency = "diamonds", amount = 5000 },
				},
				{
					id = "rerollLuck2",
					name = "Shiny Chance II",
					description = "Multiplies independent Shiny chance by x1.50 total.",
					requireIds = { "rerollLuck1" },
					multiplier = 1.50,
					cost = { currency = "diamonds", amount = 15000 },
				},
				{
					id = "rerollLuck3",
					name = "Shiny Chance III",
					description = "Multiplies independent Shiny chance by x2 total.",
					requireIds = { "rerollLuck2" },
					multiplier = 2.00,
					cost = { currency = "diamonds", amount = 50000 },
				},
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
		-- QOF-12 activates server-owned Movement Speed and Magnet branches on top
		-- of the QOF-10 capacity and QOF-11 Double Luck entitlements. Every branch
		-- retains an independent runtime gate to prevent accidental activation.
		RuntimeEnabled = true,
		SpeedRuntimeEnabled = true,
		StorageRuntimeEnabled = true,
		MagnetRuntimeEnabled = true,
		DoubleLuckRuntimeEnabled = true,
		PetEquipSlotsRuntimeEnabled = true,
		Movement = {
			BaseWalkSpeed = 16,
			MaxWalkSpeed = 128,
			ReconcileIntervalSeconds = 1,
		},
		PickupCollection = {
			BaseRadius = 8,
			MaxRadius = 32,
			PollIntervalSeconds = 0.2,
			LifetimeSeconds = 15,
			MaxPendingPerPlayer = 24,
		},
		Speed = {
			{
				id = "coreSpeed1",
				name = "Movement Speed I",
				description = "Increases tree movement speed to x1.05 total.",
				requireIds = { "Eggs II" },
				multiplier = 1.05,
				cost = { currency = "coins", amount = 5000 },
			},
			{
				id = "coreSpeed2",
				name = "Movement Speed II",
				description = "Increases tree movement speed to x1.10 total.",
				requireIds = { "coreSpeed1" },
				multiplier = 1.10,
				cost = { currency = "coins", amount = 25000 },
			},
			{
				id = "coreSpeed3",
				name = "Movement Speed III",
				description = "Increases tree movement speed to x1.15 total.",
				requireIds = { "coreSpeed2" },
				multiplier = 1.15,
				cost = { currency = "coins", amount = 100000 },
			},
			{
				id = "coreSpeed4",
				name = "Movement Speed IV",
				description = "Increases tree movement speed to x1.20 total.",
				requireIds = { "coreSpeed3" },
				multiplier = 1.20,
				cost = { currency = "coins", amount = 300000 },
			},
		},
		Storage = {
			{
				id = "playtime1",
				name = "Storage I",
				description = "Increases pet inventory capacity by 25 slots.",
				requireIds = { "Eggs II" },
				bonusSlots = 25,
				cost = { currency = "diamonds", amount = 250 },
			},
			{
				id = "playtime2",
				name = "Storage II",
				description = "Increases pet inventory capacity by 50 slots total.",
				requireIds = { "playtime1" },
				bonusSlots = 50,
				cost = { currency = "diamonds", amount = 750 },
			},
			{
				id = "playtime3",
				name = "Storage III",
				description = "Increases pet inventory capacity by 75 slots total.",
				requireIds = { "playtime2" },
				bonusSlots = 75,
				cost = { currency = "diamonds", amount = 2000 },
			},
			{
				id = "streak1",
				name = "Storage IV",
				description = "Increases pet inventory capacity by 100 slots total.",
				requireIds = { "playtime3" },
				bonusSlots = 100,
				cost = { currency = "diamonds", amount = 5000 },
			},
			{
				id = "streak2",
				name = "Storage V",
				description = "Increases pet inventory capacity by 125 slots total.",
				requireIds = { "streak1" },
				bonusSlots = 125,
				cost = { currency = "diamonds", amount = 10000 },
			},
			{
				id = "streak3",
				name = "Storage VI",
				description = "Increases pet inventory capacity by 150 slots total.",
				requireIds = { "streak2" },
				bonusSlots = 150,
				cost = { currency = "diamonds", amount = 20000 },
			},
		},
		Magnet = {
			{
				id = "coreMagnet1",
				name = "Magnet I",
				description = "Increases tree pickup radius to x1.25 total.",
				requireIds = { "Eggs II" },
				multiplier = 1.25,
				cost = { currency = "coins", amount = 10000 },
			},
			{
				id = "coreMagnet2",
				name = "Magnet II",
				description = "Increases tree pickup radius to x1.50 total.",
				requireIds = { "coreMagnet1" },
				multiplier = 1.50,
				cost = { currency = "coins", amount = 50000 },
			},
			{
				id = "coreMagnet3",
				name = "Magnet III",
				description = "Increases tree pickup radius to x2 total.",
				requireIds = { "coreMagnet2" },
				multiplier = 2.00,
				cost = { currency = "coins", amount = 200000 },
			},
		},
		DoubleLuck = {
			id = "doubleLuck",
			name = "Double Luck",
			description = "Doubles general hatch luck, subject to existing chance caps.",
			requireIds = { "Eggs II" },
			multiplier = 2,
			cost = { currency = "diamonds", amount = 5000 },
		},
		PetEquipSlots = {
			{
				id = "friends1",
				name = "Pet Equip I",
				description = "Increases maximum equipped pets by 1.",
				requireIds = { "Eggs II" },
				bonusSlots = 1,
				cost = { currency = "diamonds", amount = 1000 },
			},
			{
				id = "friends2",
				name = "Pet Equip II",
				description = "Increases maximum equipped pets by 2 total.",
				requireIds = { "friends1" },
				bonusSlots = 2,
				cost = { currency = "diamonds", amount = 2500 },
			},
			{
				id = "friends3",
				name = "Pet Equip III",
				description = "Increases maximum equipped pets by 3 total.",
				requireIds = { "friends2" },
				bonusSlots = 3,
				cost = { currency = "diamonds", amount = 5000 },
			},
		},
	},

	Shop = {
		-- The old timed Auto-Hatch product remains reserved in legacy balance and
		-- persisted preferences remain intact, but no catalog or server processing
		-- is permitted before its owning feature ships.
		AutoHatchRuntimeEnabled = false,
	},

	Potions = {
		-- QOF-13 keeps purchases inventory-only; QOF-14 activates a separate
		-- server-authoritative consume/effect contract.
		RuntimeEnabled = true,
		ConsumeRuntimeEnabled = true,
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
	assert(BalanceConfig.Variants.RuntimeEnabled == true, "Variants must be enabled in QOF-04")
	assert(BalanceConfig.Hatch.RuntimeEnabled == true, "direct Hatch outcomes must be enabled in QOF-06")
	assert(BalanceConfig.Hatch.EggQualityRuntimeEnabled == true, "Egg Quality must be enabled in QOF-07")
	assert(BalanceConfig.Hatch.MultiOpenRuntimeEnabled == true, "Multi-Open must be enabled in QOF-08")
	assert(BalanceConfig.Hatch.DirectVariantUpgradesRuntimeEnabled == true, "direct variant upgrades must be enabled in QOF-07")
	local futureSections = {
		Machines = BalanceConfig.Machines,
		Enchanting = BalanceConfig.Enchanting,
	}
	for name, section in pairs(futureSections) do
		assert(section.RuntimeEnabled == false, name .. " must remain disabled until its owning QOF")
	end
	assert(BalanceConfig.Potions.RuntimeEnabled == true, "Potion inventory purchases must be enabled in QOF-13")
	assert(
		BalanceConfig.Potions.ConsumeRuntimeEnabled == true,
		"Potion consumption must be enabled in QOF-14"
	)
	local core = BalanceConfig.CoreUpgrades
	assert(core.RuntimeEnabled == true, "Core upgrades must be enabled")
	assert(core.StorageRuntimeEnabled == true, "Storage upgrades must be enabled in QOF-10")
	assert(core.PetEquipSlotsRuntimeEnabled == true, "Pet Equip upgrades must be enabled in QOF-10")
	assert(core.SpeedRuntimeEnabled == true, "Speed upgrades must be enabled in QOF-12")
	assert(core.MagnetRuntimeEnabled == true, "Magnet upgrades must be enabled in QOF-12")
	assert(core.DoubleLuckRuntimeEnabled == true, "Double Luck must be enabled in QOF-11")
	assert(BalanceConfig.Shop.AutoHatchRuntimeEnabled == false, "Shop Auto-Hatch must remain disabled")

	for name, value in pairs(BalanceConfig.Limits) do
		assert(isFiniteNumber(value) and value > 0, name .. " limit must be positive")
	end
	assert(BalanceConfig.Limits.PetInventoryBase <= BalanceConfig.Limits.PetInventoryAbsolute, "pet inventory limits are inverted")
	assert(BalanceConfig.Limits.EquippedPetsBase <= BalanceConfig.Limits.EquippedPetsAbsolute, "equipped pet limits are inverted")

	local movement = core.Movement
	assert(movement.BaseWalkSpeed == 16, "base WalkSpeed must remain 16")
	assert(movement.MaxWalkSpeed == 128, "QOF-12 WalkSpeed cap must remain 128")
	assert(
		isFiniteNumber(movement.ReconcileIntervalSeconds) and movement.ReconcileIntervalSeconds > 0,
		"movement reconcile interval is invalid"
	)
	local collection = core.PickupCollection
	assert(collection.BaseRadius == 8, "base pickup radius must remain 8")
	assert(collection.MaxRadius == 32, "QOF-12 pickup radius cap must remain 32")
	assert(collection.MaxRadius >= collection.BaseRadius, "pickup radius limits are inverted")
	assert(
		isFiniteNumber(collection.PollIntervalSeconds) and collection.PollIntervalSeconds > 0,
		"pickup polling interval is invalid"
	)
	assert(
		isFiniteNumber(collection.LifetimeSeconds) and collection.LifetimeSeconds > 0,
		"pickup lifetime is invalid"
	)
	assert(
		isFiniteNumber(collection.MaxPendingPerPlayer)
			and collection.MaxPendingPerPlayer > 0
			and collection.MaxPendingPerPlayer % 1 == 0,
		"pickup pending cap is invalid"
	)

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

	local luckCaps = BalanceConfig.Hatch.LuckCaps
	assert(
		isFiniteNumber(luckCaps.SpeciesMultiplier) and luckCaps.SpeciesMultiplier >= 1,
		"species luck cap must be at least x1"
	)
	local directChanceCaps = {
		Golden = luckCaps.GoldenChance,
		Rainbow = luckCaps.RainbowChance,
		Shiny = luckCaps.ShinyChance,
	}
	for name, cap in pairs(directChanceCaps) do
		assert(
			isFiniteNumber(cap) and cap >= chances[name] and cap <= 1,
			name .. " luck cap must be finite and between its base chance and 100%"
		)
	end
	assert(
		directChanceCaps.Golden + directChanceCaps.Rainbow <= 1,
		"capped base variant chances exceed 100%"
	)

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

	local entitlementIds = {}
	local entitlementLevels = {}
	local function registerEntitlement(level, context)
		assert(type(level.id) == "string" and #level.id > 0 and #level.id <= 64, context .. " has an invalid ID")
		assert(entitlementIds[level.id] == nil, "duplicate hatch entitlement ID: " .. level.id)
		assert(type(level.name) == "string" and level.name ~= "", context .. " has an invalid name")
		validateCost(level.cost, context)
		assert(level.cost.amount > 0 and level.cost.amount % 1 == 0, context .. " cost must be a positive integer")
		entitlementIds[level.id] = true
		table.insert(entitlementLevels, level)
	end

	for index, level in ipairs(BalanceConfig.Hatch.EggQuality) do
		registerEntitlement(level, "Egg Quality " .. tostring(index))
		assert(type(level.requireIds) == "table", "Egg Quality prerequisites must be a table")
		assert(isFiniteNumber(level.rarityMultiplier) and level.rarityMultiplier > 1, "Egg Quality multiplier is invalid")
	end
	validateIncreasingCosts(BalanceConfig.Hatch.EggQuality, "Egg Quality")
	assert(
		BalanceConfig.Hatch.EggQuality[2].rarityMultiplier > BalanceConfig.Hatch.EggQuality[1].rarityMultiplier,
		"Egg Quality multipliers must increase"
	)

	for variant, levels in pairs(BalanceConfig.Hatch.DirectVariantUpgrades) do
		validateIncreasingCosts(levels, variant .. " hatch chance")
		local previousMultiplier = 0
		for index, level in ipairs(levels) do
			registerEntitlement(level, variant .. " hatch chance " .. tostring(index))
			assert(type(level.requireIds) == "table", variant .. " prerequisites must be a table")
			assert(isFiniteNumber(level.multiplier) and level.multiplier > previousMultiplier, variant .. " multipliers must increase")
			previousMultiplier = level.multiplier
		end
	end

	for index, level in ipairs(BalanceConfig.Hatch.MultiOpen) do
		registerEntitlement(level, "Multi-Open " .. tostring(index))
		assert(type(level.requireIds) == "table", "Multi-Open prerequisites must be a table")
		assert(
			type(level.eggCount) == "number" and level.eggCount > 1 and level.eggCount % 1 == 0,
			"Multi-Open count must be an integer above one"
		)
	end

	local function validateMultiplierProgression(levels, context, expectedIds, expectedMultipliers, expectedCosts)
		assert(#levels == #expectedIds, context .. " has an unexpected level count")
		for index, level in ipairs(levels) do
			registerEntitlement(level, context .. " " .. tostring(index))
			assert(level.id == expectedIds[index], context .. " has a non-canonical ID")
			assert(type(level.description) == "string" and level.description ~= "", context .. " description is invalid")
			assert(type(level.requireIds) == "table" and #level.requireIds == 1, context .. " must be a strict chain")
			local expectedRequirement = index == 1 and "Eggs II" or expectedIds[index - 1]
			assert(level.requireIds[1] == expectedRequirement, context .. " has an invalid prerequisite")
			assert(level.multiplier == expectedMultipliers[index], context .. " has a non-canonical multiplier")
			assert(level.cost.currency == "coins" and level.cost.amount == expectedCosts[index], context .. " has a non-canonical cost")
		end
		validateIncreasingCosts(levels, context)
	end

	validateMultiplierProgression(
		BalanceConfig.CoreUpgrades.Speed,
		"Movement Speed",
		{ "coreSpeed1", "coreSpeed2", "coreSpeed3", "coreSpeed4" },
		{ 1.05, 1.10, 1.15, 1.20 },
		{ 5000, 25000, 100000, 300000 }
	)
	validateMultiplierProgression(
		BalanceConfig.CoreUpgrades.Magnet,
		"Magnet",
		{ "coreMagnet1", "coreMagnet2", "coreMagnet3" },
		{ 1.25, 1.50, 2.00 },
		{ 10000, 50000, 200000 }
	)

	local function validateCapacityLevels(levels, context, expectedIds, expectedBonuses, expectedCosts)
		assert(#levels == #expectedIds, context .. " has an unexpected level count")
		for index, level in ipairs(levels) do
			registerEntitlement(level, context .. " " .. tostring(index))
			assert(level.id == expectedIds[index], context .. " has a non-canonical ID")
			assert(type(level.description) == "string" and level.description ~= "", context .. " description is invalid")
			assert(type(level.requireIds) == "table" and #level.requireIds == 1, context .. " must be a strict chain")
			local expectedRequirement = index == 1 and "Eggs II" or expectedIds[index - 1]
			assert(level.requireIds[1] == expectedRequirement, context .. " has an invalid prerequisite")
			assert(level.bonusSlots == expectedBonuses[index], context .. " has a non-canonical bonus")
			assert(level.cost.currency == "diamonds" and level.cost.amount == expectedCosts[index], context .. " has a non-canonical cost")
		end
		validateIncreasingCosts(levels, context)
	end

	validateCapacityLevels(
		BalanceConfig.CoreUpgrades.Storage,
		"Storage",
		{ "playtime1", "playtime2", "playtime3", "streak1", "streak2", "streak3" },
		{ 25, 50, 75, 100, 125, 150 },
		{ 250, 750, 2000, 5000, 10000, 20000 }
	)
	validateCapacityLevels(
		BalanceConfig.CoreUpgrades.PetEquipSlots,
		"Pet Equip",
		{ "friends1", "friends2", "friends3" },
		{ 1, 2, 3 },
		{ 1000, 2500, 5000 }
	)

	local doubleLuck = BalanceConfig.CoreUpgrades.DoubleLuck
	registerEntitlement(doubleLuck, "Double Luck")
	assert(doubleLuck.id == "doubleLuck", "Double Luck has a non-canonical ID")
	assert(type(doubleLuck.description) == "string" and doubleLuck.description ~= "", "Double Luck description is invalid")
	assert(
		type(doubleLuck.requireIds) == "table"
			and #doubleLuck.requireIds == 1
			and doubleLuck.requireIds[1] == "Eggs II",
		"Double Luck must require Eggs II"
	)
	assert(doubleLuck.multiplier == 2, "Double Luck must use the canonical x2 multiplier")
	assert(
		doubleLuck.cost.currency == "diamonds" and doubleLuck.cost.amount == 5000,
		"Double Luck has a non-canonical cost"
	)

	for _, level in ipairs(entitlementLevels) do
		for _, requiredId in ipairs(level.requireIds or {}) do
			assert(entitlementIds[requiredId] == true, level.id .. " has an unknown prerequisite")
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

	local expectedPotions = {
		LuckPotion = 100,
		MegaLuckPotion = 350,
		SpeedPotion = 50,
		CoinPotion = 125,
		ShinyPotion = 1000,
	}
	local potionCount = 0
	for potionId, potion in pairs(BalanceConfig.Potions.Catalog) do
		assert(type(potionId) == "string" and #potionId > 0 and #potionId <= 64, "potion ID is invalid")
		assert(expectedPotions[potionId] ~= nil, "unknown canonical potion ID: " .. potionId)
		validateCost(potion.cost, potionId)
		assert(potion.cost.currency == "diamonds", potionId .. " must cost diamonds")
		assert(
			potion.cost.amount == expectedPotions[potionId]
				and potion.cost.amount > 0
				and potion.cost.amount % 1 == 0,
			potionId .. " has a non-canonical cost"
		)
		assert(isFiniteNumber(potion.multiplier) and potion.multiplier > 0, potionId .. " multiplier is invalid")
		if potion.durationSeconds ~= nil then
			assert(isFiniteNumber(potion.durationSeconds) and potion.durationSeconds > 0, potionId .. " duration is invalid")
		end
		if potion.hatchCharges ~= nil then
			assert(potion.hatchCharges > 0 and potion.hatchCharges % 1 == 0, potionId .. " charges are invalid")
		end
		potionCount = potionCount + 1
	end
	assert(potionCount == 5, "potion catalog must contain exactly five canonical items")

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
