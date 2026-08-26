--[[
	CurrencyService.lua - Manages coin and diamond transactions
	Server-authoritative: validates all transactions and prevents negative balances.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(game.ReplicatedStorage.Shared.Config)

local CurrencyService = {}

-- Reference to DataService (set during init)
CurrencyService._dataService = nil
CurrencyService._upgradeService = nil

function CurrencyService.init(dataService, upgradeService)
	CurrencyService._dataService = dataService
	CurrencyService._upgradeService = upgradeService
end

-- Apply DropCloner, LuckyDrops, and CoinCollector bonuses to coin amounts
local function applyBonuses(player, amount)
	local finalAmount = amount

	-- Apply LuckyDrops multiplier (maps to MoreCoins mastery via UpgradeService)
	if CurrencyService._upgradeService then
		local luckyDropsBonus = CurrencyService._upgradeService.getUpgradeBonus(player, "LuckyDrops")
		if luckyDropsBonus > 0 then
			finalAmount = math.floor(finalAmount * luckyDropsBonus)
		end
	end

	-- Apply CoinCollector quest bonus multiplier
	if CurrencyService._upgradeService then
		local coinCollectorBonus = CurrencyService._upgradeService.getUpgradeBonus(player, "CoinCollector")
		if coinCollectorBonus > 0 then
			finalAmount = math.floor(finalAmount * coinCollectorBonus)
		end
	end

	-- Apply DropCloner chance to double
	if CurrencyService._upgradeService then
		local dropClonerBonus = CurrencyService._upgradeService.getUpgradeBonus(player, "DropCloner")
		if dropClonerBonus > 0 then
			if math.random() < dropClonerBonus then
				finalAmount = finalAmount * 2
			end
		end
	end

	return finalAmount
end

-- Add coins to player (with upgrade bonuses applied)
function CurrencyService.addCoins(player, amount)
	if not player or type(amount) ~= "number" or amount <= 0 then
		return false
	end

	local data = CurrencyService._dataService.getPlayerData(player)
	if not data then
		return false
	end

	local finalAmount = applyBonuses(player, math.floor(amount))
	data.coins = data.coins + finalAmount

	-- Fire client update
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local event = remotes:FindFirstChild("CurrencyUpdated")
		if event then
			event:FireClient(player, data.coins, data.diamonds)
		end
	end

	return true, finalAmount
end

-- Remove coins from player (no bonuses applied to deductions)
function CurrencyService.removeCoins(player, amount)
	if not player or type(amount) ~= "number" or amount <= 0 then
		return false
	end

	local data = CurrencyService._dataService.getPlayerData(player)
	if not data then
		return false
	end

	amount = math.floor(amount)
	if data.coins < amount then
		return false
	end

	data.coins = data.coins - amount

	-- Fire client update
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local event = remotes:FindFirstChild("CurrencyUpdated")
		if event then
			event:FireClient(player, data.coins, data.diamonds)
		end
	end

	return true
end

-- Add diamonds to player
function CurrencyService.addDiamonds(player, amount)
	if not player or type(amount) ~= "number" or amount <= 0 then
		return false
	end

	local data = CurrencyService._dataService.getPlayerData(player)
	if not data then
		return false
	end

	local finalAmount = math.floor(amount)

	-- Apply Diamonds upgrade multiplier
	if CurrencyService._upgradeService then
		local diamondBonus = CurrencyService._upgradeService.getUpgradeBonus(player, "Diamonds")
		if diamondBonus > 0 then
			finalAmount = math.floor(finalAmount * diamondBonus)
		end
	end

	data.diamonds = data.diamonds + finalAmount

	-- Fire client update
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local event = remotes:FindFirstChild("CurrencyUpdated")
		if event then
			event:FireClient(player, data.coins, data.diamonds)
		end
	end

	return true, finalAmount
end

-- Remove diamonds from player
function CurrencyService.removeDiamonds(player, amount)
	if not player or type(amount) ~= "number" or amount <= 0 then
		return false
	end

	local data = CurrencyService._dataService.getPlayerData(player)
	if not data then
		return false
	end

	amount = math.floor(amount)
	if data.diamonds < amount then
		return false
	end

	data.diamonds = data.diamonds - amount

	-- Fire client update
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local event = remotes:FindFirstChild("CurrencyUpdated")
		if event then
			event:FireClient(player, data.coins, data.diamonds)
		end
	end

	return true
end

-- Get current balance for player
function CurrencyService.getBalance(player)
	if not player then
		return { coins = 0, diamonds = 0 }
	end

	local data = CurrencyService._dataService.getPlayerData(player)
	if not data then
		return { coins = 0, diamonds = 0 }
	end

	return { coins = data.coins, diamonds = data.diamonds }
end

return CurrencyService
