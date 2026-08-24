--[[
	PetData.lua - Pet and Egg definitions for Battle Pets
	Defines all pets with their stats and egg types with weighted pet pools.
]]

local PetData = {}

-- Pet definitions
PetData.Pets = {
	Buddy = {
		name = "Buddy",
		species = "Dog",
		rarity = "Common",
		baseDamage = 1,
		baseSpeed = 10,
		modelDescription = "A friendly brown dog with floppy ears and a wagging tail",
	},
	Whiskers = {
		name = "Whiskers",
		species = "Cat",
		rarity = "Uncommon",
		baseDamage = 8,
		baseSpeed = 12,
		modelDescription = "A sleek gray cat with bright green eyes and a long tail",
	},
	Blaze = {
		name = "Blaze",
		species = "Dragon",
		rarity = "Rare",
		baseDamage = 15,
		baseSpeed = 8,
		modelDescription = "A small red dragon with tiny wings and glowing orange scales",
	},
	Inferno = {
		name = "Inferno",
		species = "Phoenix",
		rarity = "Legendary",
		baseDamage = 30,
		baseSpeed = 14,
		modelDescription = "A majestic golden phoenix wreathed in bright flames",
	},
}

-- Egg type definitions
PetData.Eggs = {
	BasicEgg = {
		name = "Basic Egg",
		zone = 1,
		petPool = {
			{ petId = "Buddy", weight = 70 },
			{ petId = "Whiskers", weight = 30 },
		},
	},
	PremiumEgg = {
		name = "Premium Egg",
		zone = 2,
		petPool = {
			{ petId = "Buddy", weight = 40 },
			{ petId = "Whiskers", weight = 30 },
			{ petId = "Blaze", weight = 20 },
			{ petId = "Inferno", weight = 10 },
		},
	},
}

return PetData
