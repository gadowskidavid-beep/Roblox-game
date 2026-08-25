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
	StrandEgg = {
		name = "Strand Egg",
		zone = 3,
		petPool = {
			{ petId = "Buddy", weight = 30 },
			{ petId = "Whiskers", weight = 35 },
			{ petId = "Blaze", weight = 25 },
			{ petId = "Inferno", weight = 10 },
		},
	},
	WuesteEgg = {
		name = "Wueste Egg",
		zone = 4,
		petPool = {
			{ petId = "Buddy", weight = 20 },
			{ petId = "Whiskers", weight = 30 },
			{ petId = "Blaze", weight = 35 },
			{ petId = "Inferno", weight = 15 },
		},
	},
	EisweltEgg = {
		name = "Eiswelt Egg",
		zone = 5,
		petPool = {
			{ petId = "Buddy", weight = 15 },
			{ petId = "Whiskers", weight = 25 },
			{ petId = "Blaze", weight = 40 },
			{ petId = "Inferno", weight = 20 },
		},
	},
	VulkanEgg = {
		name = "Vulkan Egg",
		zone = 6,
		petPool = {
			{ petId = "Buddy", weight = 10 },
			{ petId = "Whiskers", weight = 20 },
			{ petId = "Blaze", weight = 40 },
			{ petId = "Inferno", weight = 30 },
		},
	},
	HimmelEgg = {
		name = "Himmel Egg",
		zone = 7,
		petPool = {
			{ petId = "Buddy", weight = 5 },
			{ petId = "Whiskers", weight = 15 },
			{ petId = "Blaze", weight = 40 },
			{ petId = "Inferno", weight = 40 },
		},
	},
	WeltraumEgg = {
		name = "Weltraum Egg",
		zone = 8,
		petPool = {
			{ petId = "Buddy", weight = 5 },
			{ petId = "Whiskers", weight = 10 },
			{ petId = "Blaze", weight = 35 },
			{ petId = "Inferno", weight = 50 },
		},
	},
}

-- Variant definitions (all possible variants for each pet)
PetData.Variants = {"Normal", "Golden", "Shiny", "Rainbow"}

return PetData
