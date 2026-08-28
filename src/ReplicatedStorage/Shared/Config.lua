--[[
	Config.lua - Runtime and infrastructure configuration for Battle Pets.
	Gameplay/economy values come from BalanceConfig; compatibility aliases keep
	existing systems unchanged while they migrate through the QOF roadmap.
]]

local BalanceConfig = require(script.Parent.BalanceConfig)

local Config = {}

-- Expose the canonical balance module for compatibility and diagnostics.
Config.Balance = BalanceConfig

-- General infrastructure
Config.GameName = "Battle Pets"
Config.DataStoreName = "BattlePets_v1"
Config.AutoSaveInterval = 60
Config.SessionLockTimeout = 180

-- Hard limits protect DataStore size, rendering cost, and combat balance.
Config.MaxPetInventoryBase = BalanceConfig.Limits.PetInventoryBase
Config.MaxPetInventoryAbsolute = BalanceConfig.Limits.PetInventoryAbsolute
Config.MaxExtraEquipSlots = BalanceConfig.Limits.ExtraEquipSlots
Config.MaxEquippedPetsBase = BalanceConfig.Limits.EquippedPetsBase
Config.MaxEquippedPetsAbsolute = BalanceConfig.Limits.EquippedPetsAbsolute
Config.AutoHatchInterval = BalanceConfig.Limits.AutoHatchInterval
Config.DestructibleReplicationDistance = BalanceConfig.Limits.DestructibleReplicationDistance

-- Existing display-facing currency names.
Config.Currencies = {
	Coins = "Coins",
	Diamonds = "Diamonds",
}

Config.RarityWeights = BalanceConfig.World.RarityWeights

-- Existing consumers expect { Coins = amount } per zone.
Config.EggCosts = {}
for zoneId, amount in pairs(BalanceConfig.World.EggCoinCostsByZone) do
	Config.EggCosts[zoneId] = { Coins = amount }
end

-- Upgrade definitions (deprecated; upgrades are quest/tree based).
Config.Upgrades = {}

Config.ZoneGateCosts = BalanceConfig.World.ZoneGateCoinCosts
Config.Campaign = BalanceConfig.World.Campaign

-- Legacy aliases remain for untouched compatibility consumers. QOF-06 PetService
-- uses the canonical BalanceConfig.Hatch model instead of these exclusive odds.
Config.SHINY_CHANCE = BalanceConfig.Legacy.Hatch.ShinyChance
Config.RAINBOW_CHANCE = BalanceConfig.Legacy.Hatch.RainbowChance

return Config
