-- CurrencyService.spec.lua - QOF-07 canonical spend and raw-refund tests.

local originalRequire = require
local updates = {}
local updateShouldError = false
local currencyUpdated = {}
function currencyUpdated:FireClient(_, coins, diamonds)
	if updateShouldError then error("injected CurrencyUpdated failure") end
	table.insert(updates, { coins = coins, diamonds = diamonds })
end
local remotes = {}
function remotes:FindFirstChild(name)
	if name == "CurrencyUpdated" then return currencyUpdated end
	return nil
end
local replicatedStorage = {}
function replicatedStorage:FindFirstChild(name)
	if name == "Remotes" then return remotes end
	return nil
end
local gameMock = {}
function gameMock:GetService(name)
	if name == "ReplicatedStorage" then return replicatedStorage end
	error("Unexpected service: " .. tostring(name))
end
rawset(_G, "game", gameMock)

local CurrencyService = originalRequire("src/ServerScriptService/Services/CurrencyService")
local ProfileTransactionService = originalRequire("src/ServerScriptService/Services/ProfileTransactionService")
local player = { UserId = 7 }
local profile = nil
local bonuses = {}
local dataService = {}
function dataService.getPlayerData()
	return profile
end
function dataService.isMutationAdmissionOpen()
	return profile ~= nil
end
function dataService.isProfileSaveInProgress()
	return false
end
local upgradeService = {}
function upgradeService.getUpgradeBonus(_, id)
	return bonuses[id] or 0
end
ProfileTransactionService.init(dataService)
CurrencyService.init(dataService, upgradeService, ProfileTransactionService)

local function resetState()
	ProfileTransactionService.init(dataService)
	CurrencyService.init(dataService, upgradeService, ProfileTransactionService)
	profile = { coins = 1000, diamonds = 500 }
	bonuses = {}
	updates = {}
	updateShouldError = false
end

describe("CurrencyService QOF-07 transactions", function()
	it("spends either canonical currency exactly once", function()
		resetState()
		expect(CurrencyService.spend(player, "coins", 125)):toBeTrue()
		expect(CurrencyService.spend(player, "diamonds", 75)):toBeTrue()
		expect(profile.coins):toBe(875)
		expect(profile.diamonds):toBe(425)
		expect(#updates):toBe(2)
		expect(updates[2]):toEqual({ coins = 875, diamonds = 425 })
	end)

	it("rejects hostile amounts, unknown currencies, and insufficient balances", function()
		resetState()
		local invalidAmounts = { 0, -1, 0.5, math.huge, -math.huge, 0 / 0, "100" }
		for _, amount in ipairs(invalidAmounts) do
			expect(CurrencyService.spend(player, "coins", amount)):toBeFalse()
		end
		expect(CurrencyService.spend(player, "gems", 1)):toBeFalse()
		expect(CurrencyService.spend(player, "diamonds", 501)):toBeFalse()
		expect(profile):toEqual({ coins = 1000, diamonds = 500 })
		expect(#updates):toBe(0)
	end)

	it("keeps rollback credits exact even when earned rewards have multipliers", function()
		resetState()
		bonuses = { LuckyDrops = 2, CoinCollector = 3, DropCloner = 1 }
		local granted, earnedAmount = CurrencyService.addCoins(player, 10)
		expect(granted):toBeTrue()
		expect(earnedAmount):toBe(120)
		expect(profile.coins):toBe(1120)

		expect(CurrencyService.creditRaw(player, "coins", 10)):toBeTrue()
		expect(profile.coins):toBe(1130)
	end)

	it("snapshots earned bonuses once before an exact delayed credit", function()
		resetState()
		bonuses = { LuckyDrops = 2, CoinCollector = 3, DropCloner = 1, Diamonds = 2 }
		local coins = CurrencyService.resolveCoinReward(player, 10)
		local diamonds = CurrencyService.resolveDiamondReward(player, 10)
		expect(coins):toBe(120)
		expect(diamonds):toBe(20)
		expect(profile):toEqual({ coins = 1000, diamonds = 500 })
		expect(#updates):toBe(0)

		bonuses = { LuckyDrops = 10, CoinCollector = 10, DropCloner = 1, Diamonds = 10 }
		expect(CurrencyService.creditResolvedReward(player, "coins", coins)):toBeTrue()
		expect(CurrencyService.creditResolvedReward(player, "diamonds", diamonds)):toBeTrue()
		expect(profile):toEqual({ coins = 1120, diamonds = 520 })
		expect(#updates):toBe(2)
	end)

	it("credits a cached profile exactly for leave/shutdown persistence fallback", function()
		resetState()
		bonuses = { LuckyDrops = 10, CoinCollector = 10, DropCloner = 1 }
		expect(CurrencyService.creditResolvedRewardToProfile(profile, "coins", 25)):toBeTrue()
		expect(profile.coins):toBe(1025)
		expect(#updates):toBe(0)
		expect(CurrencyService.creditResolvedRewardToProfile(profile, "gems", 25)):toBeFalse()
	end)

	it("keeps compatibility deduction wrappers on the hardened spend path", function()
		resetState()
		expect(CurrencyService.removeCoins(player, 100)):toBeTrue()
		expect(CurrencyService.removeDiamonds(player, 50)):toBeTrue()
		expect(profile):toEqual({ coins = 900, diamonds = 450 })
	end)
end)


describe("CurrencyService composite spend transactions", function()
	it("rolls back silently against the captured profile without a second lookup", function()
		resetState()
		local capturedProfile = profile
		local transaction = CurrencyService.beginSpendTransaction(player, "diamonds", 125)
		expect(type(transaction)):toBe("table")
		expect(capturedProfile.diamonds):toBe(500)
		expect(#updates):toBe(0)

		-- Simulate DataService becoming unavailable after the reservation. Rollback
		-- uses only the captured owner/profile and never needs a refund mutation.
		profile = nil
		expect(CurrencyService.rollbackSpendTransaction(transaction)):toBeTrue()
		expect(capturedProfile.diamonds):toBe(500)
		expect(#updates):toBe(0)
		expect(CurrencyService.rollbackSpendTransaction(transaction)):toBeFalse()
		profile = capturedProfile
	end)

	it("publishes exactly one final balance only when a pending debit commits", function()
		resetState()
		local transaction = CurrencyService.beginSpendTransaction(player, "coins", 200)
		expect(type(transaction)):toBe("table")
		expect(profile.coins):toBe(1000)
		expect(#updates):toBe(0)
		expect(CurrencyService.commitSpendTransaction(transaction)):toBeTrue()
		expect(updates):toEqual({ { coins = 800, diamonds = 500 } })
		expect(CurrencyService.commitSpendTransaction(transaction)):toBeFalse()
		expect(CurrencyService.rollbackSpendTransaction(transaction)):toBeFalse()
	end)

	it("keeps commit terminal and successful when CurrencyUpdated throws", function()
		resetState()
		local transaction = CurrencyService.beginSpendTransaction(player, "diamonds", 100)
		updateShouldError = true
		expect(CurrencyService.commitSpendTransaction(transaction)):toBeTrue()
		expect(profile.diamonds):toBe(400)
		expect(#updates):toBe(0)
		expect(CurrencyService.commitSpendTransaction(transaction)):toBeFalse()
		expect(CurrencyService.rollbackSpendTransaction(transaction)):toBeFalse()
	end)

	it("retains a central owner until its registered rollback can settle", function()
		resetState()
		local transaction = CurrencyService.beginSpendTransaction(player, "diamonds", 125, "TestComposite")
		expect(profile.diamonds):toBe(500)
		local allowRollback = false
		expect(CurrencyService.setSpendSettler(transaction, function(current)
			if not allowRollback then return false end
			return CurrencyService.rollbackSpendTransaction(current)
		end)):toBeTrue()
		expect(ProfileTransactionService.settlePlayer(player)):toBeFalse()
		expect(ProfileTransactionService.hasPending(player)):toBeTrue()
		expect(CurrencyService.beginSpendTransaction(player, "coins", 1)):toBeNil()
		allowRollback = true
		expect(ProfileTransactionService.settlePlayer(player)):toBeTrue()
		expect(ProfileTransactionService.hasPending(player)):toBeFalse()
		expect(profile.diamonds):toBe(500)
		expect(CurrencyService.rollbackSpendTransaction(transaction)):toBeFalse()
	end)

	it("rejects invalid or unaffordable pending debits without mutation", function()
		resetState()
		expect(CurrencyService.beginSpendTransaction(player, "diamonds", 501)):toBeNil()
		expect(CurrencyService.beginSpendTransaction(player, "gems", 1)):toBeNil()
		expect(CurrencyService.beginSpendTransaction(player, "diamonds", 1.5)):toBeNil()
		expect(profile):toEqual({ coins = 1000, diamonds = 500 })
		expect(#updates):toBe(0)
	end)
end)
