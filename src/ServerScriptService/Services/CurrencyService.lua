--[[
	CurrencyService.lua - Server-authoritative coin and diamond transactions.
	QOF-07 centralizes validated spending and bonus-free raw refunds so purchases
	cannot trust client currency data or accidentally apply reward multipliers.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CurrencyService = {}

CurrencyService._dataService = nil
CurrencyService._upgradeService = nil

local VALID_CURRENCIES = {
	coins = true,
	diamonds = true,
}

-- Opaque pending debits keep the already validated profile reference private.
-- Shop transactions can therefore roll back silently without a second
-- DataService lookup or any pre-commit client event.
local pendingSpendTransactions = setmetatable({}, { __mode = "k" })

local function isFiniteNumber(value)
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
end

local function normalizePositiveAmount(amount, requireInteger)
	if not isFiniteNumber(amount) or amount <= 0 then
		return nil
	end
	if requireInteger and amount % 1 ~= 0 then
		return nil
	end
	local normalized = math.floor(amount)
	if normalized <= 0 then
		return nil
	end
	return normalized
end

local function getProfile(player)
	if not player or not CurrencyService._dataService then
		return nil
	end
	local data = CurrencyService._dataService.getPlayerData(player)
	if not data
		or not isFiniteNumber(data.coins)
		or data.coins < 0
		or not isFiniteNumber(data.diamonds)
		or data.diamonds < 0 then
		return nil
	end
	return data
end

local function fireCurrencyUpdate(player, data)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local event = remotes and remotes:FindFirstChild("CurrencyUpdated")
	if event then
		pcall(function()
			event:FireClient(player, data.coins, data.diamonds)
		end)
	end
end

function CurrencyService.init(dataService, upgradeService)
	CurrencyService._dataService = dataService
	CurrencyService._upgradeService = upgradeService
end

-- Resolve existing quest/mastery reward bonuses exactly once for a future credit.
local function applyCoinBonuses(player, amount)
	local finalAmount = amount
	if CurrencyService._upgradeService then
		local luckyDropsBonus = CurrencyService._upgradeService.getUpgradeBonus(player, "LuckyDrops")
		if isFiniteNumber(luckyDropsBonus) and luckyDropsBonus > 0 then
			finalAmount = math.floor(finalAmount * luckyDropsBonus)
		end

		local coinCollectorBonus = CurrencyService._upgradeService.getUpgradeBonus(player, "CoinCollector")
		if isFiniteNumber(coinCollectorBonus) and coinCollectorBonus > 0 then
			finalAmount = math.floor(finalAmount * coinCollectorBonus)
		end

		local dropClonerBonus = CurrencyService._upgradeService.getUpgradeBonus(player, "DropCloner")
		if isFiniteNumber(dropClonerBonus) and dropClonerBonus > 0 and math.random() < dropClonerBonus then
			finalAmount = finalAmount * 2
		end
	end
	return normalizePositiveAmount(finalAmount, true)
end

function CurrencyService.resolveCoinReward(player, amount)
	amount = normalizePositiveAmount(amount, false)
	if not amount or not getProfile(player) then
		return nil
	end
	return applyCoinBonuses(player, amount)
end

function CurrencyService.resolveDiamondReward(player, amount)
	amount = normalizePositiveAmount(amount, false)
	if not amount or not getProfile(player) then
		return nil
	end
	local finalAmount = amount
	if CurrencyService._upgradeService then
		local diamondBonus = CurrencyService._upgradeService.getUpgradeBonus(player, "Diamonds")
		if isFiniteNumber(diamondBonus) and diamondBonus > 0 then
			finalAmount = math.floor(finalAmount * diamondBonus)
		end
	end
	return normalizePositiveAmount(finalAmount, true)
end

-- Exact credit for a reward whose bonuses were snapshotted previously. This is
-- intentionally separate from rollback credit even though both mutate exactly.
function CurrencyService.creditResolvedReward(player, currency, amount)
	amount = normalizePositiveAmount(amount, true)
	if not amount or VALID_CURRENCIES[currency] ~= true then
		return false
	end
	local data = getProfile(player)
	if not data then
		return false
	end
	data[currency] = data[currency] + amount
	fireCurrencyUpdate(player, data)
	return true
end

-- Shutdown/leave fallback for an already-resolved reward. The caller must pass
-- the authoritative cached profile before DataService snapshots and releases it.
function CurrencyService.creditResolvedRewardToProfile(data, currency, amount)
	amount = normalizePositiveAmount(amount, true)
	if not amount
		or VALID_CURRENCIES[currency] ~= true
		or type(data) ~= "table"
		or not isFiniteNumber(data.coins)
		or data.coins < 0
		or not isFiniteNumber(data.diamonds)
		or data.diamonds < 0 then
		return false
	end
	data[currency] = data[currency] + amount
	return true
end

function CurrencyService.addCoins(player, amount)
	local finalAmount = CurrencyService.resolveCoinReward(player, amount)
	if not finalAmount then
		return false
	end
	if not CurrencyService.creditResolvedReward(player, "coins", finalAmount) then
		return false
	end
	return true, finalAmount
end

function CurrencyService.addDiamonds(player, amount)
	local finalAmount = CurrencyService.resolveDiamondReward(player, amount)
	if not finalAmount then
		return false
	end
	if not CurrencyService.creditResolvedReward(player, "diamonds", finalAmount) then
		return false
	end
	return true, finalAmount
end

-- Begin a silent exact debit against one already validated profile. The opaque
-- handle can be committed once (publishing one CurrencyUpdated event) or rolled
-- back once (publishing nothing). This is the atomic boundary used by systems
-- that must mutate another profile field before the purchase can commit.
function CurrencyService.beginSpendTransaction(player, currency, amount)
	amount = normalizePositiveAmount(amount, true)
	if not amount or VALID_CURRENCIES[currency] ~= true then
		return nil
	end
	local data = getProfile(player)
	if not data or data[currency] < amount then
		return nil
	end

	data[currency] = data[currency] - amount
	local transaction = {}
	pendingSpendTransactions[transaction] = {
		player = player,
		profile = data,
		currency = currency,
		amount = amount,
	}
	return transaction
end

function CurrencyService.commitSpendTransaction(transaction)
	local pending = type(transaction) == "table" and pendingSpendTransactions[transaction] or nil
	if not pending then
		return false
	end
	pendingSpendTransactions[transaction] = nil
	fireCurrencyUpdate(pending.player, pending.profile)
	return true
end

function CurrencyService.rollbackSpendTransaction(transaction)
	local pending = type(transaction) == "table" and pendingSpendTransactions[transaction] or nil
	if not pending then
		return false
	end
	local balance = pending.profile[pending.currency]
	if not isFiniteNumber(balance) or balance < 0 then
		return false
	end
	local restoredBalance = balance + pending.amount
	if not isFiniteNumber(restoredBalance) or restoredBalance < balance then
		return false
	end
	pending.profile[pending.currency] = restoredBalance
	-- A failed restore must leave the opaque handle pending so lifecycle code can
	-- retry it. Consume the handle only after the exact refund is observable.
	pendingSpendTransactions[transaction] = nil
	return true
end

-- Canonical immediate deduction API. Currency and amount always come from
-- server-owned configuration; only exact positive integer transactions are
-- accepted. Composite purchases use the explicit transaction API above.
function CurrencyService.spend(player, currency, amount)
	local transaction = CurrencyService.beginSpendTransaction(player, currency, amount)
	if not transaction then
		return false
	end
	return CurrencyService.commitSpendTransaction(transaction)
end

-- Exact, bonus-free credit for transaction rollback. This must never call the
-- earned-reward APIs because quest/mastery multipliers would inflate refunds.
function CurrencyService.creditRaw(player, currency, amount)
	amount = normalizePositiveAmount(amount, true)
	if not amount or VALID_CURRENCIES[currency] ~= true then
		return false
	end
	local data = getProfile(player)
	if not data then
		return false
	end
	data[currency] = data[currency] + amount
	fireCurrencyUpdate(player, data)
	return true
end

function CurrencyService.removeCoins(player, amount)
	return CurrencyService.spend(player, "coins", amount)
end

function CurrencyService.removeDiamonds(player, amount)
	return CurrencyService.spend(player, "diamonds", amount)
end

function CurrencyService.getBalance(player)
	local data = getProfile(player)
	if not data then
		return { coins = 0, diamonds = 0 }
	end
	return { coins = data.coins, diamonds = data.diamonds }
end

return CurrencyService
