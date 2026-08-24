--[[
	Config.lua - Main game configuration for Battle Pets
	Contains all game constants, upgrade definitions, zone costs, and campaign parameters.
]]

local Config = {}

-- General
Config.GameName = "Battle Pets"
Config.DataStoreName = "BattlePets_v1"

-- Currency types
Config.Currencies = {
	Coins = "Coins",
	Diamonds = "Diamonds",
}

-- Pet rarity weights (must sum to 100)
Config.RarityWeights = {
	Common = 60,
	Uncommon = 25,
	Rare = 10,
	Epic = 4,
	Legendary = 1,
}

-- Egg costs per zone
Config.EggCosts = {
	[1] = { Coins = 100 },
	[2] = { Coins = 500 },
	[3] = { Coins = 2000 },
	[4] = { Coins = 5000 },
	[5] = { Coins = 15000 },
	[6] = { Coins = 40000 },
	[7] = { Coins = 100000 },
	[8] = { Coins = 300000 },
}

-- Max equipped pets (base value before upgrades)
Config.MaxEquippedPetsBase = 3

-- Upgrade definitions
Config.Upgrades = {
	Friendship = {
		displayName = "Friendship",
		description = "Equip more pets at once",
		levels = {
			{ cost = 500, bonus = 1 },
			{ cost = 2000, bonus = 2 },
			{ cost = 10000, bonus = 3 },
		},
	},
	Diamonds = {
		displayName = "Diamonds",
		description = "More diamonds per drop",
		levels = {
			{ cost = 1000, bonus = 1.5 },
			{ cost = 5000, bonus = 2.0 },
			{ cost = 20000, bonus = 3.0 },
		},
	},
	ExtraSlots = {
		displayName = "Extra Slots",
		description = "More pet inventory slots",
		levels = {
			{ cost = 750, bonus = 5 },
			{ cost = 3000, bonus = 10 },
			{ cost = 12000, bonus = 20 },
		},
	},
	FasterPets = {
		displayName = "Faster Pets",
		description = "Pets move faster",
		levels = {
			{ cost = 600, bonus = 1.2 },
			{ cost = 2500, bonus = 1.5 },
			{ cost = 10000, bonus = 2.0 },
		},
	},
	StrongPets = {
		displayName = "Strong Pets",
		description = "Pets deal more damage",
		levels = {
			{ cost = 800, bonus = 1.3 },
			{ cost = 3500, bonus = 1.7 },
			{ cost = 15000, bonus = 2.5 },
		},
	},
	LuckyEggs = {
		displayName = "Lucky Eggs",
		description = "Better chances from eggs",
		levels = {
			{ cost = 1200, bonus = 1.2 },
			{ cost = 5000, bonus = 1.5 },
			{ cost = 25000, bonus = 2.0 },
		},
	},
	GoldenPetsChance = {
		displayName = "Golden Pets Chance",
		description = "Chance to hatch golden variants",
		levels = {
			{ cost = 2000, bonus = 0.05 },
			{ cost = 8000, bonus = 0.10 },
			{ cost = 30000, bonus = 0.20 },
		},
	},
	Sprinting = {
		displayName = "Sprinting",
		description = "Player moves faster",
		levels = {
			{ cost = 400, bonus = 1.2 },
			{ cost = 1500, bonus = 1.5 },
			{ cost = 6000, bonus = 2.0 },
		},
	},
	DropCloner = {
		displayName = "Drop Cloner",
		description = "Chance to double drops",
		levels = {
			{ cost = 1500, bonus = 0.10 },
			{ cost = 6000, bonus = 0.20 },
			{ cost = 25000, bonus = 0.35 },
		},
	},
	LuckyDrops = {
		displayName = "Lucky Drops",
		description = "More coins per drop",
		levels = {
			{ cost = 500, bonus = 1.3 },
			{ cost = 2000, bonus = 1.7 },
			{ cost = 8000, bonus = 2.5 },
		},
	},
}

-- Zone gate costs (coins required to unlock each zone)
Config.ZoneGateCosts = {
	[1] = 0,         -- Gruene Wiesen (free/starter)
	[2] = 500,       -- Stadt
	[3] = 2000,      -- Strand
	[4] = 5000,      -- Wueste
	[5] = 15000,     -- Eiswelt
	[6] = 40000,     -- Vulkan
	[7] = 100000,    -- Himmel
	[8] = 300000,    -- Weltraum
}

-- Campaign parameters
Config.Campaign = {
	EnergyRegenRate = 1,   -- energy per second
	MaxEnergy = 100,
	BaseHealth = 500,      -- base HP for player's base
	EnemyBaseHealth = 500, -- base HP for enemy base (scales with level)
	PetDeployCosts = {
		Common = 10,
		Uncommon = 20,
		Rare = 35,
		Epic = 45,
		Legendary = 50,
	},
}

return Config
