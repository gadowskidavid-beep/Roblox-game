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
	Splash = {
		name = "Splash",
		species = "Dolphin",
		rarity = "Common",
		baseDamage = 3,
		baseSpeed = 14,
		modelDescription = "A playful blue dolphin that leaps through the air with grace",
	},
	Sandy = {
		name = "Sandy",
		species = "Turtle",
		rarity = "Uncommon",
		baseDamage = 12,
		baseSpeed = 6,
		modelDescription = "A sturdy green turtle with a sandy shell and calm demeanor",
	},
	Dusty = {
		name = "Dusty",
		species = "Camel",
		rarity = "Common",
		baseDamage = 4,
		baseSpeed = 8,
		modelDescription = "A tan camel with a dusty coat and two strong humps",
	},
	Scorpio = {
		name = "Scorpio",
		species = "Scorpion",
		rarity = "Uncommon",
		baseDamage = 18,
		baseSpeed = 10,
		modelDescription = "A dark purple scorpion with a venomous glowing tail",
	},
	Frost = {
		name = "Frost",
		species = "Penguin",
		rarity = "Common",
		baseDamage = 5,
		baseSpeed = 12,
		modelDescription = "A cheerful penguin with icy blue markings and a frosty aura",
	},
	Glacier = {
		name = "Glacier",
		species = "Polar Bear",
		rarity = "Rare",
		baseDamage = 25,
		baseSpeed = 9,
		modelDescription = "A massive white polar bear with crystalline ice armor",
	},
	Ember = {
		name = "Ember",
		species = "Fire Lizard",
		rarity = "Uncommon",
		baseDamage = 20,
		baseSpeed = 11,
		modelDescription = "A fiery orange lizard with smoldering scales and a flickering tail",
	},
	Magma = {
		name = "Magma",
		species = "Lava Golem",
		rarity = "Rare",
		baseDamage = 35,
		baseSpeed = 7,
		modelDescription = "A hulking golem made of molten rock with veins of flowing lava",
	},
	Zephyr = {
		name = "Zephyr",
		species = "Eagle",
		rarity = "Rare",
		baseDamage = 30,
		baseSpeed = 16,
		modelDescription = "A majestic silver eagle that rides the wind with outstretched wings",
	},
	Nimbus = {
		name = "Nimbus",
		species = "Cloud Fox",
		rarity = "Epic",
		baseDamage = 50,
		baseSpeed = 13,
		modelDescription = "A mystical white fox surrounded by swirling clouds and lightning",
	},
	Cosmic = {
		name = "Cosmic",
		species = "Alien",
		rarity = "Epic",
		baseDamage = 45,
		baseSpeed = 15,
		modelDescription = "A glowing alien creature with translucent skin and orbiting stars",
	},
	Nova = {
		name = "Nova",
		species = "Star Dragon",
		rarity = "Legendary",
		baseDamage = 80,
		baseSpeed = 18,
		modelDescription = "A celestial dragon made of starlight with a blazing cosmic mane",
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
			{ petId = "Splash", weight = 40 },
			{ petId = "Sandy", weight = 30 },
			{ petId = "Buddy", weight = 20 },
			{ petId = "Whiskers", weight = 10 },
		},
	},
	WuesteEgg = {
		name = "Wueste Egg",
		zone = 4,
		petPool = {
			{ petId = "Dusty", weight = 35 },
			{ petId = "Scorpio", weight = 30 },
			{ petId = "Sandy", weight = 20 },
			{ petId = "Whiskers", weight = 15 },
		},
	},
	EisweltEgg = {
		name = "Eiswelt Egg",
		zone = 5,
		petPool = {
			{ petId = "Frost", weight = 30 },
			{ petId = "Glacier", weight = 25 },
			{ petId = "Scorpio", weight = 20 },
			{ petId = "Blaze", weight = 15 },
			{ petId = "Dusty", weight = 10 },
		},
	},
	VulkanEgg = {
		name = "Vulkan Egg",
		zone = 6,
		petPool = {
			{ petId = "Ember", weight = 30 },
			{ petId = "Magma", weight = 25 },
			{ petId = "Glacier", weight = 20 },
			{ petId = "Blaze", weight = 15 },
			{ petId = "Frost", weight = 10 },
		},
	},
	HimmelEgg = {
		name = "Himmel Egg",
		zone = 7,
		petPool = {
			{ petId = "Zephyr", weight = 30 },
			{ petId = "Nimbus", weight = 20 },
			{ petId = "Magma", weight = 20 },
			{ petId = "Ember", weight = 15 },
			{ petId = "Inferno", weight = 15 },
		},
	},
	WeltraumEgg = {
		name = "Weltraum Egg",
		zone = 8,
		petPool = {
			{ petId = "Cosmic", weight = 30 },
			{ petId = "Nova", weight = 20 },
			{ petId = "Nimbus", weight = 20 },
			{ petId = "Zephyr", weight = 15 },
			{ petId = "Inferno", weight = 15 },
		},
	},
}

-- Variant definitions (all possible variants for each pet)
PetData.Variants = {"Normal", "Golden", "Shiny", "Rainbow"}

return PetData
