-- CurrencyService.spec.lua - QOF-07 canonical spend and raw-refund tests.

local originalRequire = require
local updates = {}
local currencyUpdated = {}
function currencyUpdated:FireClient(_, coins, diamonds)
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
local player = { UserId = 7 }
local profile = nil
local bonuses = {}
local dataService = {}
function dataService.getPlayerData()
	return profile
end
local upgradeService = {}
function upgradeService.getUpgradeBonus(_, id)
	return bonuses[id] or 0
end
CurrencyService.init(dataService, upgradeService)

local function resetState()
	profile = { coins = 1000, diamonds = 500 }
	bonuses = {}
	updates = {}
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

	it("keeps compatibility deduction wrappers on the hardened spend path", function()
		resetState()
		expect(CurrencyService.removeCoins(player, 100)):toBeTrue()
		expect(CurrencyService.removeDiamonds(player, 50)):toBeTrue()
		expect(profile):toEqual({ coins = 900, diamonds = 450 })
	end)
end)
