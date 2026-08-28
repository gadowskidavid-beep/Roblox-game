--[[
	ShopData.lua - Shared presentation metadata for the current potion shop.
	Balance comes from BalanceConfig.Legacy.Shop until the persistent potion
	inventory is activated in QOF-13/QOF-14.
]]

local BalanceConfig = require(script.Parent.BalanceConfig)

local ShopData = {}

ShopData.Order = {
	"LuckyPotion",
	"SpeedPotion",
	"PowerPotion",
	"CoinPotion",
	"AutoHatch",
	"ExtraEquipSlot",
}

local function legacyItem(itemId, presentation)
	local balance = BalanceConfig.Legacy.Shop[itemId]
	assert(balance, "Missing legacy shop balance for " .. itemId)

	local item = {}
	for key, value in pairs(presentation) do
		item[key] = value
	end
	for key, value in pairs(balance) do
		item[key] = value
	end
	return item
end

ShopData.Items = {
	LuckyPotion = legacyItem("LuckyPotion", {
		displayName = "Lucky Potion",
		description = "2x egg and pet variant luck for 5 minutes",
		buffType = "luck",
		permanent = false,
		artType = "potion",
		color = { 70, 210, 105 },
		accentColor = { 185, 255, 155 },
		durationLabel = "5 min",
	}),
	SpeedPotion = legacyItem("SpeedPotion", {
		displayName = "Speed Potion",
		description = "2x player walk speed for 5 minutes",
		buffType = "speed",
		permanent = false,
		artType = "potion",
		color = { 40, 210, 225 },
		accentColor = { 165, 250, 255 },
		durationLabel = "5 min",
	}),
	PowerPotion = legacyItem("PowerPotion", {
		displayName = "Power Potion",
		description = "2x pet damage for 5 minutes",
		buffType = "damage",
		permanent = false,
		artType = "potion",
		color = { 235, 70, 40 },
		accentColor = { 255, 155, 55 },
		durationLabel = "5 min",
	}),
	CoinPotion = legacyItem("CoinPotion", {
		displayName = "Coin Potion",
		description = "2x breakable coin rewards for 5 minutes",
		buffType = "coins",
		permanent = false,
		artType = "potion",
		color = { 245, 185, 35 },
		accentColor = { 255, 235, 125 },
		durationLabel = "5 min",
	}),
	AutoHatch = legacyItem("AutoHatch", {
		displayName = "Auto-Hatch",
		description = "Automatically buys and hatches normal eggs for 10 minutes",
		buffType = "autoHatch",
		permanent = false,
		artType = "egg",
		color = { 245, 125, 35 },
		accentColor = { 255, 205, 105 },
		durationLabel = "10 min",
	}),
	ExtraEquipSlot = legacyItem("ExtraEquipSlot", {
		displayName = "Extra Equip Slot",
		description = "Permanently equip 1 more pet (maximum 5)",
		buffType = "equipSlot",
		permanent = true,
		artType = "pawPlus",
		color = { 235, 90, 170 },
		accentColor = { 255, 180, 220 },
		durationLabel = "Permanent",
	}),
}

return ShopData
