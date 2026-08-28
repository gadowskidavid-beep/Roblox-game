-- UpgradeTreeService.spec.lua - QOF-07 entitlement and purchase tests.

local originalRequire = require
local BalanceConfig = originalRequire("src/ReplicatedStorage/Shared/BalanceConfig")
local updateStates = {}
local updateEvent = {}
function updateEvent:FireClient(_, state)
	table.insert(updateStates, state)
end
local remotes = {}
function remotes:FindFirstChild(name)
	if name == "UpgradeTreeUpdated" then return updateEvent end
	return nil
end
local replicatedStorage = { Shared = { BalanceConfig = BalanceConfig } }
function replicatedStorage:FindFirstChild(name)
	if name == "Remotes" then return remotes end
	return nil
end
local gameMock = { ReplicatedStorage = replicatedStorage }
function gameMock:GetService(name)
	if name == "ReplicatedStorage" then return replicatedStorage end
	error("Unexpected service: " .. tostring(name))
end
rawset(_G, "game", gameMock)

local function mockRequire(path)
	if path == BalanceConfig then return BalanceConfig end
	return originalRequire(path)
end
rawset(_G, "require", mockRequire)
local UpgradeTreeService = originalRequire("src/ServerScriptService/Services/UpgradeTreeService")
rawset(_G, "require", originalRequire)

local player = { UserId = 17 }
local profile = nil
local spends = {}
local refunds = {}
local dataService = {}
function dataService.getPlayerData()
	return profile
end
local currencyService = {}
function currencyService.spend(_, currency, amount)
	table.insert(spends, { currency = currency, amount = amount })
	if profile[currency] < amount then
		return false
	end
	profile[currency] = profile[currency] - amount
	return true
end
function currencyService.creditRaw(_, currency, amount)
	table.insert(refunds, { currency = currency, amount = amount })
	profile[currency] = profile[currency] + amount
	return true
end
UpgradeTreeService.init(dataService, currencyService)

local function resetState()
	profile = {
		coins = 100000,
		diamonds = 100000,
		upgradeTreePurchases = {},
	}
	spends = {}
	refunds = {}
	updateStates = {}
	UpgradeTreeService._purchaseLocks[player.UserId] = nil
	UpgradeTreeService._transactionHook = nil
end

describe("UpgradeTreeService QOF-07 entitlements", function()
	it("uses only the highest contiguous Egg Quality and direct variant stages", function()
		local entitlements = UpgradeTreeService.resolveEntitlements({
			["Eggs I"] = true,
			["Eggs II"] = true,
			epicLuck1 = true,
			epicLuck2 = true,
			epicLuck3 = true,
			legendLuck1 = true,
			rerollLuck1 = true,
			rerollLuck2 = true,
		})
		expect(entitlements.eggQualityMultiplier):toBe(1.6)
		expect(entitlements.directVariantMultipliers.Golden):toBe(2)
		expect(entitlements.directVariantMultipliers.Rainbow):toBe(1.25)
		expect(entitlements.directVariantMultipliers.Shiny):toBe(1.5)
		expect(entitlements.multiOpenCount):toBe(1)
	end)

	it("ignores unknown, skipped, and dormant Multi-Open purchase IDs", function()
		local entitlements = UpgradeTreeService.resolveEntitlements({
			["Eggs II"] = true,
			epicLuck3 = true,
			["Eggs V"] = true,
			forgedJackpot = true,
		})
		expect(entitlements.eggQualityMultiplier):toBe(1)
		expect(entitlements.directVariantMultipliers.Golden):toBe(1)
		expect(entitlements.multiOpenCount):toBe(1)
	end)
end)

describe("UpgradeTreeService QOF-07 purchases", function()
	it("purchases canonical Coin and Diamond nodes with server-owned costs", function()
		resetState()
		local qualitySuccess, _, qualityState = UpgradeTreeService.purchase(player, "Eggs I")
		expect(qualitySuccess):toBeTrue()
		expect(profile.coins):toBe(95000)
		expect(profile.upgradeTreePurchases["Eggs I"]):toBeTrue()
		expect(spends[1]):toEqual({ currency = "coins", amount = 5000 })
		expect(qualityState.currency):toEqual({ coins = 95000, diamonds = 100000 })

		local goldSuccess, _, goldState = UpgradeTreeService.purchase(player, "epicLuck1")
		expect(goldSuccess):toBeTrue()
		expect(profile.diamonds):toBe(99500)
		expect(spends[2]):toEqual({ currency = "diamonds", amount = 500 })
		expect(goldState.entitlements.directVariantMultipliers.Golden):toBe(1.25)
		expect(#updateStates):toBe(2)
	end)

	it("enforces prerequisites and prevents duplicate debits", function()
		resetState()
		local missingSuccess, missingError = UpgradeTreeService.purchase(player, "Eggs II")
		expect(missingSuccess):toBeFalse()
		expect(missingError):toBe("Missing prerequisite")
		expect(#spends):toBe(0)

		expect(UpgradeTreeService.purchase(player, "Eggs I")):toBeTrue()
		local duplicateSuccess, duplicateError = UpgradeTreeService.purchase(player, "Eggs I")
		expect(duplicateSuccess):toBeFalse()
		expect(duplicateError):toBe("Already purchased")
		expect(#spends):toBe(1)
	end)

	it("blocks Multi-Open and every no-op legacy node without charging", function()
		resetState()
		for _, id in ipairs({ "Eggs III", "luck I", "coinMult1", "forged" }) do
			local success, message = UpgradeTreeService.purchase(player, id)
			expect(success):toBeFalse()
			expect(message):toBe("Upgrade not available yet")
		end
		expect(#spends):toBe(0)
		expect(profile):toEqual({ coins = 100000, diamonds = 100000, upgradeTreePurchases = {} })
	end)

	it("returns dual-currency availability and preserves legacy purchased flags", function()
		resetState()
		profile.upgradeTreePurchases = { ["coins I"] = true, ["Eggs V"] = true }
		local state = UpgradeTreeService.getState(player)
		expect(state.currency):toEqual({ coins = 100000, diamonds = 100000 })
		expect(state.purchased["coins I"]):toBeTrue()
		expect(state.purchased["Eggs V"]):toBeTrue()
		expect(state.available["Eggs I"]):toBeTrue()
		expect(state.available.epicLuck1):toBeTrue()
		expect(state.available["Eggs III"]):toBeNil()
		expect(state.entitlements.multiOpenCount):toBe(1)
	end)

	it("rolls back both mutations after post-debit or post-entitlement faults", function()
		for _, faultStage in ipairs({ "afterSpend", "afterEntitlement" }) do
			resetState()
			UpgradeTreeService._transactionHook = function(stage)
				if stage == faultStage then
					error("injected " .. stage)
				end
			end
			local success, message = UpgradeTreeService.purchase(player, "epicLuck1")
			expect(success):toBeFalse()
			expect(message):toBe("Purchase failed safely")
			expect(profile.diamonds):toBe(100000)
			expect(profile.upgradeTreePurchases.epicLuck1):toBeNil()
			expect(refunds):toEqual({ { currency = "diamonds", amount = 500 } })
			expect(UpgradeTreeService._purchaseLocks[player.UserId]):toBeNil()
		end
		UpgradeTreeService._transactionHook = nil
	end)

	it("rejects concurrent requests and insufficient balances safely", function()
		resetState()
		UpgradeTreeService._purchaseLocks[player.UserId] = true
		local lockedSuccess, lockedError = UpgradeTreeService.purchase(player, "Eggs I")
		expect(lockedSuccess):toBeFalse()
		expect(lockedError):toBe("Purchase already in progress")
		UpgradeTreeService._purchaseLocks[player.UserId] = nil

		profile.diamonds = 0
		local poorSuccess, poorError = UpgradeTreeService.purchase(player, "epicLuck1")
		expect(poorSuccess):toBeFalse()
		expect(poorError):toBe("Not enough diamonds")
		expect(profile.upgradeTreePurchases.epicLuck1):toBeNil()
	end)
end)
