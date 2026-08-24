--[[
	QuestData.lua - Quest definitions for unlocking upgrades
	Each quest has a requirement (action + count) and unlocks a specific upgrade.
	Players complete quests by playing the game (destroying things, hatching eggs, etc.)
]]

local QuestData = {}

-- Quest requirement types:
-- "destroyDestructibles" - destroy X total destructibles with pets
-- "hatchEggs" - hatch X eggs total
-- "earnCoins" - earn X total coins (lifetime)
-- "destroyType" - destroy X of a specific destructible type
-- "reachLevel" - reach mastery level X

QuestData.Quests = {
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
		-- Each level requires more completions of the same quest type
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
	GoldenPetsChance = {
		id = "GoldenPetsChance",
		displayName = "Golden Pets",
		description = "Chance to hatch golden variants",
		icon = "✦",
		color = { 255, 200, 0 },
		requirement = {
			type = "hatchEggs",
			count = 50,
			displayText = "Hatch 50 eggs",
		},
		levels = {
			{ bonus = 0.05 },
			{ bonus = 0.10 },
			{ bonus = 0.20 },
		},
		levelRequirements = { 50, 120, 300 },
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
}

-- Ordered list for UI display
QuestData.QuestOrder = {
	"StrongPets", "FasterPets", "Friendship", "LuckyEggs",
	"Sprinting", "DropCloner", "GoldenPetsChance", "ExtraSlots",
}

return QuestData
