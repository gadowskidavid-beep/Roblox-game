--[[
	Config.lua - Main game configuration for Battle Pets
	Contains all game constants, upgrade definitions, zone costs, and campaign parameters.
]]

local Config = {}

-- General
Config.GameName = "Battle Pets"
Config.DataStoreName = "BattlePets_v1"
Config.AutoSaveInterval = 60
Config.SessionLockTimeout = 180

-- Hard limits protect DataStore size, rendering cost, and combat balance.
Config.MaxPetInventoryBase = 100
Config.MaxPetInventoryAbsolute = 250
Config.MaxExtraEquipSlots = 5
Config.MaxEquippedPetsAbsolute = 12
Config.AutoHatchInterval = 3
Config.DestructibleReplicationDistance = 300

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

-- Upgrade definitions (DEPRECATED - upgrades are now quest-based, see QuestData.lua)
-- Kept for reference only; UpgradeService now delegates to QuestService
Config.Upgrades = {}

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

-- Shiny/Rainbow variant chances (base, multiplied by LuckyEggs bonus)
Config.SHINY_CHANCE = 0.01    -- 1% base chance
Config.RAINBOW_CHANCE = 0.001 -- 0.1% base chance

return Config
