--[[
	MasteryData.lua - Mastery buff definitions
	Each level-up grants 1 mastery point. Points are spent on buffs in the Mastery tab.
	Each buff can be upgraded multiple times, each level costing more mastery points.
]]

local MasteryData = {}

-- Mastery buffs: each can be leveled up with mastery points
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
	PetSpeed = {
		id = "PetSpeed",
		displayName = "Pet Speed",
		description = "Pets follow and attack faster",
		icon = "»",
		color = { 0, 200, 255 },
		maxLevel = 5,
		pointsPerLevel = { 1, 2, 3, 4, 5 },
		bonusPerLevel = { 1.1, 1.2, 1.35, 1.5, 1.7 },
	},
	MoreDiamonds = {
		id = "MoreDiamonds",
		displayName = "More Diamonds",
		description = "Increases diamonds earned per drop",
		icon = "◆",
		color = { 0, 180, 255 },
		maxLevel = 5,
		pointsPerLevel = { 2, 2, 3, 4, 5 },
		bonusPerLevel = { 1.2, 1.5, 1.8, 2.2, 3.0 },
	},
	XPBoost = {
		id = "XPBoost",
		displayName = "XP Boost",
		description = "Earn more XP from destroying things",
		icon = "↑",
		color = { 0, 220, 100 },
		maxLevel = 5,
		pointsPerLevel = { 1, 2, 2, 3, 4 },
		bonusPerLevel = { 1.2, 1.4, 1.7, 2.0, 2.5 },
	},
}

-- Ordered list for UI display
MasteryData.BuffOrder = {
	"MoreCoins", "BetterLuck", "PetSpeed", "MoreDiamonds", "XPBoost",
}

return MasteryData
