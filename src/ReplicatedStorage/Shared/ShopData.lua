--[[
	ShopData.lua - Shared presentation metadata for the potion shop.
	Potion purchase prices remain canonical in BalanceConfig; QOF-14 consumption
	uses an independent authoritative state contract.
]]

local BalanceConfig = require(script.Parent.BalanceConfig)

local ShopData = {
	ContractVersion = 2,
	PotionContractVersion = 1,
	AutoHatchContractVersion = BalanceConfig.Shop.AutoHatch.ContractVersion,
	PurchaseMode = "inventoryOnly",
	MaxPotionInventory = BalanceConfig.Potions.Persistence.MaxInventoryPerPotion,
}

ShopData.Order = {
	"LuckPotion",
	"MegaLuckPotion",
	"SpeedPotion",
	"CoinPotion",
	"ShinyPotion",
	"AutoHatch",
	"ExtraEquipSlot",
}

local function potionItem(itemId, presentation)
	local balance = BalanceConfig.Potions.Catalog[itemId]
	assert(balance, "Missing canonical potion balance for " .. itemId)

	local item = {
		itemType = "potion",
		permanent = false,
		currency = balance.cost.currency,
		cost = balance.cost.amount,
		buffType = balance.buffType,
		multiplier = balance.multiplier,
		durationSeconds = balance.durationSeconds,
		hatchCharges = balance.hatchCharges,
	}
	for key, value in pairs(presentation) do
		item[key] = value
	end
	return item
end

local extraSlotBalance = BalanceConfig.Legacy.Shop.ExtraEquipSlot

ShopData.Items = {
	LuckPotion = potionItem("LuckPotion", {
		displayName = "Luck Potion",
		description = "Adds a 2x Luck Potion to your persistent inventory.",
		artType = "potion",
		color = { 70, 210, 105 },
		accentColor = { 185, 255, 155 },
	}),
	MegaLuckPotion = potionItem("MegaLuckPotion", {
		displayName = "Mega Luck Potion",
		description = "Adds a powerful 5x Luck Potion to your persistent inventory.",
		artType = "potion",
		color = { 126, 84, 235 },
		accentColor = { 216, 190, 255 },
	}),
	SpeedPotion = potionItem("SpeedPotion", {
		displayName = "Speed Potion",
		description = "Adds a 2x Walk Speed Potion to your persistent inventory.",
		artType = "potion",
		color = { 40, 210, 225 },
		accentColor = { 165, 250, 255 },
	}),
	CoinPotion = potionItem("CoinPotion", {
		displayName = "Coin Potion",
		description = "Adds a 2x Coin Potion to your persistent inventory.",
		artType = "potion",
		color = { 245, 185, 35 },
		accentColor = { 255, 235, 125 },
	}),
	ShinyPotion = potionItem("ShinyPotion", {
		displayName = "Shiny Potion",
		description = "Adds a potion with 3 future 10x Shiny-chance charges.",
		artType = "potion",
		color = { 245, 92, 191 },
		accentColor = { 255, 202, 239 },
	}),
	AutoHatch = {
		itemType = "autoHatch",
		displayName = "Auto-Hatch Access",
		description = "10 minutes of paid, station-bound automatic egg batches.",
		permanent = false,
		artType = "pawPlus",
		color = { 68, 145, 220 },
		accentColor = { 190, 225, 255 },
		durationLabel = "10 minutes",
		cost = BalanceConfig.Shop.AutoHatch.cost.amount,
		currency = BalanceConfig.Shop.AutoHatch.cost.currency,
		durationSeconds = BalanceConfig.Shop.AutoHatch.durationSeconds,
	},
	ExtraEquipSlot = {
		itemType = "permanent",
		displayName = "Extra Equip Slot",
		description = "Permanently equip 1 more pet (maximum 5).",
		buffType = "equipSlot",
		permanent = true,
		artType = "pawPlus",
		color = { 235, 90, 170 },
		accentColor = { 255, 180, 220 },
		durationLabel = "Permanent",
		cost = extraSlotBalance.cost,
		currency = extraSlotBalance.currency,
		maxPurchases = extraSlotBalance.maxPurchases,
	},
}

return ShopData
