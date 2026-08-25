--[[
	MasteryData.lua - Mastery buff definitions
	Each level-up grants 1 mastery point. Points are spent on buffs in the Mastery tab.
	Each buff can be upgraded multiple times, each level costing more mastery points.

	ONLY player buffs here - NO pet-related improvements (those belong to quests).
]]

local MasteryData = {}

-- Mastery buffs: each can be leveled up with mastery points
-- Player-only buffs: coins, diamonds, luck, XP, run speed
MasteryData.Buffs = {
	MoreCoins = {
		id = "MoreCoins",
		displayName = "More Coins",
		description = "Increases coins earned per drop",
		icon = "$",
		color = { 255, 220, 0 },
		maxLevel = 10,
		pointsPerLevel = { 1, 1, 2, 2, 3, 3, 4, 4, 5, 5 },
		-- Bonus multiplier at each level (cumulative)
		bonusPerLevel = { 1.1, 1.2, 1.35, 1.5, 1.7, 1.9, 2.1, 2.4, 2.7, 3.0 },
	},
	MoreDiamonds = {
		id = "MoreDiamonds",
		displayName = "More Diamonds",
		description = "Increases diamonds earned per drop",
		icon = "◆",
		color = { 0, 180, 255 },
		maxLevel = 10,
		pointsPerLevel = { 1, 1, 2, 2, 3, 3, 4, 4, 5, 5 },
		bonusPerLevel = { 1.1, 1.2, 1.35, 1.5, 1.7, 1.9, 2.1, 2.4, 2.7, 3.0 },
	},
	BetterLuck = {
		id = "BetterLuck",
		displayName = "Better Luck",
		description = "Better chances for rare pets from eggs",
		icon = "★",
		color = { 200, 100, 255 },
		maxLevel = 10,
		pointsPerLevel = { 1, 1, 2, 2, 3, 3, 4, 4, 5, 5 },
		bonusPerLevel = { 1.1, 1.2, 1.35, 1.5, 1.7, 1.9, 2.1, 2.4, 2.7, 3.0 },
	},
	XPBoost = {
		id = "XPBoost",
		displayName = "XP Boost",
		description = "Earn more XP from destroying things",
		icon = "↑",
		color = { 0, 220, 100 },
		maxLevel = 10,
		pointsPerLevel = { 1, 1, 2, 2, 3, 3, 4, 4, 5, 5 },
		bonusPerLevel = { 1.1, 1.2, 1.35, 1.5, 1.7, 1.9, 2.1, 2.4, 2.7, 3.0 },
	},
	FasterRunning = {
		id = "FasterRunning",
		displayName = "Faster Running",
		description = "Player moves faster (walk speed boost)",
		icon = "⚡",
		color = { 255, 150, 0 },
		maxLevel = 10,
		pointsPerLevel = { 1, 1, 2, 2, 3, 3, 4, 4, 5, 5 },
		-- Multiplier on walk speed
		bonusPerLevel = { 1.05, 1.1, 1.15, 1.2, 1.3, 1.4, 1.5, 1.6, 1.75, 2.0 },
	},
	LongerBuffs = {
		id = "LongerBuffs",
		displayName = "Longer Buffs",
		description = "Shop potions last longer",
		icon = "⏱",
		color = { 100, 200, 255 },
		maxLevel = 5,
		pointsPerLevel = { 1, 2, 3, 4, 5 },
		bonusPerLevel = { 1.2, 1.4, 1.6, 1.8, 2.0 },
	},
	MorePetSlots = {
		id = "MorePetSlots",
		displayName = "More Pet Slots",
		description = "Equip more pets at once",
		icon = "🐾",
		color = { 180, 120, 60 },
		maxLevel = 5,
		pointsPerLevel = { 2, 3, 4, 5, 6 },
		bonusPerLevel = { 1, 2, 3, 4, 5 },
	},
	BiggerRange = {
		id = "BiggerRange",
		displayName = "Bigger Range",
		description = "Pets detect breakables from further away",
		icon = "◎",
		color = { 100, 255, 150 },
		maxLevel = 5,
		pointsPerLevel = { 1, 2, 2, 3, 3 },
		bonusPerLevel = { 1.2, 1.4, 1.6, 1.8, 2.0 },
	},
	QuickHatch = {
		id = "QuickHatch",
		displayName = "Quick Hatch",
		description = "Eggs hatch faster",
		icon = "🥚",
		color = { 255, 240, 180 },
		maxLevel = 5,
		pointsPerLevel = { 1, 1, 2, 2, 3 },
		bonusPerLevel = { 0.9, 0.8, 0.7, 0.6, 0.5 },
	},
	DropMagnet = {
		id = "DropMagnet",
		displayName = "Drop Magnet",
		description = "Collect drops from further away",
		icon = "🧲",
		color = { 255, 80, 80 },
		maxLevel = 5,
		pointsPerLevel = { 1, 2, 2, 3, 4 },
		bonusPerLevel = { 1.3, 1.6, 2.0, 2.5, 3.0 },
	},
	DoubleJump = {
		id = "DoubleJump",
		displayName = "Double Jump",
		description = "Unlocks extra jumps",
		icon = "⬆",
		color = { 150, 200, 255 },
		maxLevel = 3,
		pointsPerLevel = { 3, 5, 7 },
		bonusPerLevel = { 2, 2, 3 },
	},
	CritPower = {
		id = "CritPower",
		displayName = "Crit Power",
		description = "Crit hits deal more damage",
		icon = "💥",
		color = { 255, 100, 50 },
		maxLevel = 5,
		pointsPerLevel = { 1, 2, 3, 4, 5 },
		bonusPerLevel = { 3, 4, 5, 7, 10 },
	},
}

-- Ordered list for UI display
MasteryData.BuffOrder = {
	"MoreCoins", "MoreDiamonds", "BetterLuck", "XPBoost", "FasterRunning",
	"LongerBuffs", "MorePetSlots", "BiggerRange", "QuickHatch", "DropMagnet",
	"DoubleJump", "CritPower",
}

return MasteryData
