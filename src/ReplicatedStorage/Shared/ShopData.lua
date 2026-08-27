--[[
	ShopData.lua - Shared display and gameplay metadata for the potion shop.
	Clients may use this catalog for presentation, but the server remains
	authoritative for validation, currency deduction, and effect application.
]]

local ShopData = {}

-- Stable card order for deterministic shop rendering.
ShopData.Order = {
	"LuckyPotion",
	"SpeedPotion",
	"PowerPotion",
	"CoinPotion",
	"AutoHatch",
	"ExtraEquipSlot",
}

ShopData.Items = {
	LuckyPotion = {
		displayName = "Lucky Potion",
		description = "2x egg and pet variant luck for 5 minutes",
		cost = 100,
		currency = "diamonds",
		buffType = "luck",
		multiplier = 2,
		duration = 300,
		permanent = false,
		artType = "potion",
		color = { 70, 210, 105 },
		accentColor = { 185, 255, 155 },
		durationLabel = "5 min",
	},
	SpeedPotion = {
		displayName = "Speed Potion",
		description = "2x player walk speed for 5 minutes",
		cost = 50,
		currency = "diamonds",
		buffType = "speed",
		multiplier = 2,
		duration = 300,
		permanent = false,
		artType = "potion",
		color = { 40, 210, 225 },
		accentColor = { 165, 250, 255 },
		durationLabel = "5 min",
	},
	PowerPotion = {
		displayName = "Power Potion",
		description = "2x pet damage for 5 minutes",
		cost = 150,
		currency = "diamonds",
		buffType = "damage",
		multiplier = 2,
		duration = 300,
		permanent = false,
		artType = "potion",
		color = { 235, 70, 40 },
		accentColor = { 255, 155, 55 },
		durationLabel = "5 min",
	},
	CoinPotion = {
		displayName = "Coin Potion",
		description = "2x breakable coin rewards for 5 minutes",
		cost = 125,
		currency = "diamonds",
		buffType = "coins",
		multiplier = 2,
		duration = 300,
		permanent = false,
		artType = "potion",
		color = { 245, 185, 35 },
		accentColor = { 255, 235, 125 },
		durationLabel = "5 min",
	},
	AutoHatch = {
		displayName = "Auto-Hatch",
		description = "Automatically buys and hatches normal eggs for 10 minutes",
		cost = 500,
		currency = "diamonds",
		buffType = "autoHatch",
		multiplier = 1,
		duration = 600,
		permanent = false,
		artType = "egg",
		color = { 245, 125, 35 },
		accentColor = { 255, 205, 105 },
		durationLabel = "10 min",
	},
	ExtraEquipSlot = {
		displayName = "Extra Equip Slot",
		description = "Permanently equip 1 more pet (maximum 5)",
		cost = 1000,
		currency = "diamonds",
		buffType = "equipSlot",
		multiplier = 1,
		duration = 0,
		permanent = true,
		maxPurchases = 5,
		artType = "pawPlus",
		color = { 235, 90, 170 },
		accentColor = { 255, 180, 220 },
		durationLabel = "Permanent",
	},
}

return ShopData
