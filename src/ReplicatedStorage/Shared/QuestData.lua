--[[
	QuestData.lua - Quest definitions for unlocking upgrades
	Each quest has a requirement (action + count) and unlocks a specific upgrade.
	Players complete quests by playing the game (destroying things, hatching eggs,
	earning coins, reaching levels, playing for time, converting golden pets, etc.)

	Quest requirement types:
	- "destroyDestructibles" - destroy X total destructibles with pets
	- "hatchEggs" - hatch X eggs total
	- "earnCoins" - earn X total coins (lifetime)
	- "playtime" - play for X seconds total (cumulative across sessions)
	- "reachLevel" - reach player level X
	- "goldenPetsConverted" - convert X normal pets into golden pets
]]

local QuestData = {}

QuestData.Quests = {
	-- === DESTRUCTIBLE QUESTS ===
	StrongPets = {
		id = "StrongPets",
		displayName = "Strong Pets",
		description = "Your pets deal more damage",
		icon = "⚡",
		color = { 255, 80, 0 },
		requirement = {
			type = "destroyDestructibles",
			count = 2500,
			displayText = "Destroy 2,500 destructibles with pets",
		},
		levels = {
			{ bonus = 1.3 },
			{ bonus = 1.7 },
			{ bonus = 2.5 },
		},
		levelRequirements = { 2500, 7500, 20000 },
	},
	FasterPets = {
		id = "FasterPets",
		displayName = "Faster Pets",
		description = "Pets move faster",
		icon = "»",
		color = { 255, 200, 0 },
		requirement = {
			type = "destroyDestructibles",
			count = 1000,
			displayText = "Destroy 1,000 destructibles with pets",
		},
		levels = {
			{ bonus = 1.2 },
			{ bonus = 1.5 },
			{ bonus = 2.0 },
		},
		levelRequirements = { 1000, 4000, 12000 },
	},
	DropCloner = {
		id = "DropCloner",
		displayName = "Drop Cloner",
		description = "Chance to double drops",
		icon = "x2",
		color = { 0, 150, 255 },
		requirement = {
			type = "destroyDestructibles",
			count = 5000,
			displayText = "Destroy 5,000 destructibles with pets",
		},
		levels = {
			{ bonus = 0.10 },
			{ bonus = 0.20 },
			{ bonus = 0.35 },
		},
		levelRequirements = { 5000, 15000, 40000 },
	},
	ExtraSlots = {
		id = "ExtraSlots",
		displayName = "Extra Slots",
		description = "More pet inventory slots",
		icon = "+",
		color = { 100, 200, 0 },
		requirement = {
			type = "destroyDestructibles",
			count = 500,
			displayText = "Destroy 500 destructibles with pets",
		},
		levels = {
			{ bonus = 5 },
			{ bonus = 10 },
			{ bonus = 20 },
		},
		levelRequirements = { 500, 2000, 8000 },
	},

	-- === HATCH QUESTS ===
	Friendship = {
		id = "Friendship",
		displayName = "Friendship",
		description = "Equip more pets at once",
		icon = "♥",
		color = { 255, 100, 150 },
		requirement = {
			type = "hatchEggs",
			count = 10,
			displayText = "Hatch 10 eggs",
		},
		levels = {
			{ bonus = 1 },
			{ bonus = 2 },
			{ bonus = 3 },
		},
		levelRequirements = { 10, 30, 75 },
	},
	LuckyEggs = {
		id = "LuckyEggs",
		displayName = "Lucky Eggs",
		description = "Better chances from eggs",
		icon = "★",
		color = { 200, 100, 255 },
		requirement = {
			type = "hatchEggs",
			count = 25,
			displayText = "Hatch 25 eggs",
		},
		levels = {
			{ bonus = 1.2 },
			{ bonus = 1.5 },
			{ bonus = 2.0 },
		},
		levelRequirements = { 25, 60, 150 },
	},
	EggMaster = {
		id = "EggMaster",
		displayName = "Egg Master",
		description = "Hatch many eggs to become a master",
		icon = "🥚",
		color = { 240, 200, 150 },
		requirement = {
			type = "hatchEggs",
			count = 100,
			displayText = "Hatch 100 eggs",
		},
		levels = {
			{ bonus = 1.3 },
			{ bonus = 1.6 },
			{ bonus = 2.0 },
		},
		levelRequirements = { 100, 500, 1000 },
	},

	-- === COINS QUESTS ===
	Sprinting = {
		id = "Sprinting",
		displayName = "Sprinting",
		description = "Player moves faster",
		icon = "↑",
		color = { 0, 220, 150 },
		requirement = {
			type = "earnCoins",
			count = 5000,
			displayText = "Earn 5,000 total coins",
		},
		levels = {
			{ bonus = 1.2 },
			{ bonus = 1.5 },
			{ bonus = 2.0 },
		},
		levelRequirements = { 5000, 25000, 100000 },
	},
	CoinCollector = {
		id = "CoinCollector",
		displayName = "Coin Collector",
		description = "Earn massive amounts of coins",
		icon = "💰",
		color = { 255, 200, 0 },
		requirement = {
			type = "earnCoins",
			count = 10000,
			displayText = "Earn 10,000 total coins",
		},
		levels = {
			{ bonus = 1.2 },
			{ bonus = 1.5 },
			{ bonus = 2.0 },
		},
		levelRequirements = { 10000, 50000, 100000 },
	},

	-- === PLAYTIME QUESTS ===
	Dedication = {
		id = "Dedication",
		displayName = "Dedication",
		description = "Play the game for a long time",
		icon = "⏰",
		color = { 100, 180, 255 },
		requirement = {
			type = "playtime",
			count = 3600,
			displayText = "Play for 1 hour total",
		},
		levels = {
			{ bonus = 1.1 },
			{ bonus = 1.3 },
			{ bonus = 1.5 },
		},
		-- 1 hour, 5 hours, 24 hours (in seconds)
		levelRequirements = { 3600, 18000, 86400 },
	},
	Veteran = {
		id = "Veteran",
		displayName = "Veteran",
		description = "A true veteran player with massive playtime",
		icon = "🏆",
		color = { 200, 150, 0 },
		requirement = {
			type = "playtime",
			count = 18000,
			displayText = "Play for 5 hours total",
		},
		levels = {
			{ bonus = 1.2 },
			{ bonus = 1.5 },
			{ bonus = 2.0 },
		},
		-- 5 hours, 12 hours, 48 hours (in seconds)
		levelRequirements = { 18000, 43200, 172800 },
	},

	-- === LEVEL QUESTS ===
	Rising = {
		id = "Rising",
		displayName = "Rising Star",
		description = "Reach higher player levels",
		icon = "⭐",
		color = { 255, 220, 50 },
		requirement = {
			type = "reachLevel",
			count = 10,
			displayText = "Reach Level 10",
		},
		levels = {
			{ bonus = 1.2 },
			{ bonus = 1.5 },
			{ bonus = 2.0 },
		},
		levelRequirements = { 10, 20, 50 },
	},
	Legend = {
		id = "Legend",
		displayName = "Legend",
		description = "Become a legendary player",
		icon = "👑",
		color = { 255, 100, 0 },
		requirement = {
			type = "reachLevel",
			count = 25,
			displayText = "Reach Level 25",
		},
		levels = {
			{ bonus = 1.3 },
			{ bonus = 1.7 },
			{ bonus = 2.5 },
		},
		levelRequirements = { 25, 50, 100 },
	},

	-- === GOLDEN PET QUEST ===
	GoldenPetsChance = {
		id = "GoldenPetsChance",
		displayName = "Golden Pets",
		description = "Convert pets to golden - eggs can hatch golden pets (1% chance)",
		icon = "✦",
		color = { 255, 200, 0 },
		requirement = {
			type = "goldenPetsConverted",
			count = 500,
			displayText = "Convert 500 pets to Golden Pets",
		},
		levels = {
			{ bonus = 0.01 },
		},
		-- Single level: convert 500 pets to unlock 1% golden hatch chance
		levelRequirements = { 500 },
	},
}

-- Ordered list for UI display
QuestData.QuestOrder = {
	"StrongPets", "FasterPets", "DropCloner", "ExtraSlots",
	"Friendship", "LuckyEggs", "EggMaster",
	"Sprinting", "CoinCollector",
	"Dedication", "Veteran",
	"Rising", "Legend",
	"GoldenPetsChance",
}

return QuestData
