-- UpgradeTreeService.spec.lua - QOF-07/QOF-08 entitlement and purchase tests.

local originalRequire = require
local BalanceConfig = originalRequire("src/ReplicatedStorage/Shared/BalanceConfig")
local updateStates = {}
local updateShouldError = false
local updateEvent = {}
function updateEvent:FireClient(_, state)
	if updateShouldError then
		error("injected UpgradeTreeUpdated failure")
	end
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
local spendOwners = {}
local commits = 0
local rollbacks = {}
local currencyUpdates = {}
local pendingSpend = nil
local registeredSettler = nil
local lastSettler = nil
local centralBusy = false
local commitBehavior = "success"
local rollbackBehavior = "success"
local dataLookupOverride = nil
local dataService = {}
function dataService.getPlayerData()
	if dataLookupOverride then
		return dataLookupOverride()
	end
	return profile
end
local currencyService = {}
function currencyService.beginSpendTransaction(_, currency, amount, ownerName)
	table.insert(spends, { currency = currency, amount = amount })
	table.insert(spendOwners, ownerName)
	if centralBusy or pendingSpend or profile[currency] < amount then
		return nil
	end
	local handle = {}
	pendingSpend = {
		handle = handle,
		currency = currency,
		amount = amount,
	}
	return handle
end
function currencyService.setSpendSettler(handle, settler)
	if not pendingSpend or pendingSpend.handle ~= handle then
		return false
	end
	registeredSettler = function()
		return settler(handle)
	end
	lastSettler = registeredSettler
	return true
end
function currencyService.commitSpendTransaction(handle)
	commits = commits + 1
	if commitBehavior == "error" then
		error("injected commit failure")
	end
	if commitBehavior == "false" or not pendingSpend or pendingSpend.handle ~= handle then
		return false
	end
	profile[pendingSpend.currency] = profile[pendingSpend.currency] - pendingSpend.amount
	table.insert(currencyUpdates, { coins = profile.coins, diamonds = profile.diamonds })
	pendingSpend = nil
	registeredSettler = nil
	return true
end
function currencyService.rollbackSpendTransaction(handle)
	if not pendingSpend or pendingSpend.handle ~= handle then
		return false
	end
	table.insert(rollbacks, {
		currency = pendingSpend.currency,
		amount = pendingSpend.amount,
	})
	if rollbackBehavior == "error" then
		error("injected rollback failure")
	end
	if rollbackBehavior == "false" then
		return false
	end
	pendingSpend = nil
	registeredSettler = nil
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
	spendOwners = {}
	commits = 0
	rollbacks = {}
	currencyUpdates = {}
	pendingSpend = nil
	registeredSettler = nil
	lastSettler = nil
	centralBusy = false
	commitBehavior = "success"
	rollbackBehavior = "success"
	dataLookupOverride = nil
	updateStates = {}
	updateShouldError = false
	UpgradeTreeService._purchaseLocks[player.UserId] = nil
	UpgradeTreeService._transactionHook = nil
end

describe("UpgradeTreeService QOF-07/QOF-08 entitlements", function()
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
			["Eggs III"] = true,
			["Eggs IV"] = true,
			["Eggs V"] = true,
		})
		expect(entitlements.eggQualityMultiplier):toBe(1.6)
		expect(entitlements.directVariantMultipliers.Golden):toBe(2)
		expect(entitlements.directVariantMultipliers.Rainbow):toBe(1.25)
		expect(entitlements.directVariantMultipliers.Shiny):toBe(1.5)
		expect(entitlements.multiOpenCount):toBe(10)
	end)

	it("ignores unknown, skipped, and sparse Multi-Open purchase IDs", function()
		local entitlements = UpgradeTreeService.resolveEntitlements({
			["Eggs II"] = true,
			epicLuck3 = true,
			["Eggs V"] = true,
			forgedJackpot = true,
		})
		expect(entitlements.eggQualityMultiplier):toBe(1)
		expect(entitlements.directVariantMultipliers.Golden):toBe(1)
		expect(entitlements.multiOpenCount):toBe(1)
		expect(entitlements.storageBonusSlots):toBe(0)
		expect(entitlements.petEquipBonusSlots):toBe(0)
	end)

	it("requires canonical Eggs II for Double Luck and ignores legacy Luck flags", function()
		local legacyOnly = UpgradeTreeService.resolveEntitlements({
			["luck I"] = true,
			["luck II"] = true,
			["luck III"] = true,
			["luck IV"] = true,
			doubleLuck = true,
		})
		expect(legacyOnly.generalLuckMultiplier):toBe(1)

		local canonical = UpgradeTreeService.resolveEntitlements({
			["Eggs I"] = true,
			["Eggs II"] = true,
			doubleLuck = true,
		})
		expect(canonical.generalLuckMultiplier):toBe(2)
	end)

	it("requires canonical contiguous Movement and Magnet chains", function()
		local forged = UpgradeTreeService.resolveEntitlements({
			coreSpeed1 = true,
			coreSpeed4 = true,
			coreMagnet1 = true,
			coreMagnet3 = true,
			["eggSpeed I"] = true,
		})
		expect(forged.movementSpeedMultiplier):toBe(1)
		expect(forged.magnetRangeMultiplier):toBe(1)

		local canonical = UpgradeTreeService.resolveEntitlements({
			["Eggs I"] = true,
			["Eggs II"] = true,
			coreSpeed1 = true,
			coreSpeed2 = true,
			coreSpeed3 = true,
			coreSpeed4 = true,
			coreMagnet1 = true,
			coreMagnet2 = true,
			coreMagnet3 = true,
		})
		expect(canonical.movementSpeedMultiplier):toBe(1.2)
		expect(canonical.magnetRangeMultiplier):toBe(2)
	end)

	it("grandfathers full legacy capacity chains without external Eggs flags", function()
		local entitlements = UpgradeTreeService.resolveEntitlements({
			playtime1 = true,
			playtime2 = true,
			playtime3 = true,
			streak1 = true,
			streak2 = true,
			streak3 = true,
			friends1 = true,
			friends2 = true,
			friends3 = true,
		})
		expect(entitlements.storageBonusSlots):toBe(150)
		expect(entitlements.petEquipBonusSlots):toBe(3)
	end)

	it("grants only the highest contiguous legacy capacity prefix", function()
		local firstOnly = UpgradeTreeService.resolveEntitlements({
			playtime1 = true,
			playtime3 = true,
			streak1 = true,
			friends1 = true,
			friends3 = true,
		})
		expect(firstOnly.storageBonusSlots):toBe(25)
		expect(firstOnly.petEquipBonusSlots):toBe(1)

		local interrupted = UpgradeTreeService.resolveEntitlements({
			playtime1 = true,
			playtime2 = true,
			streak1 = true,
			streak2 = true,
			friends2 = true,
			friends3 = true,
		})
		expect(interrupted.storageBonusSlots):toBe(50)
		expect(interrupted.petEquipBonusSlots):toBe(0)

		local missingRoots = UpgradeTreeService.resolveEntitlements({
			playtime2 = true,
			playtime3 = true,
			streak1 = true,
			friends2 = true,
		})
		expect(missingRoots.storageBonusSlots):toBe(0)
		expect(missingRoots.petEquipBonusSlots):toBe(0)
	end)
end)

describe("UpgradeTreeService QOF-07/QOF-08 purchases", function()
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

	it("purchases the strict Eggs II to V chain at canonical Diamond costs", function()
		resetState()
		expect(UpgradeTreeService.purchase(player, "Eggs I")):toBeTrue()
		expect(UpgradeTreeService.purchase(player, "Eggs II")):toBeTrue()
		expect(UpgradeTreeService.purchase(player, "Eggs III")):toBeTrue()
		expect(UpgradeTreeService.getState(player).entitlements.multiOpenCount):toBe(2)
		expect(UpgradeTreeService.purchase(player, "Eggs IV")):toBeTrue()
		expect(UpgradeTreeService.getState(player).entitlements.multiOpenCount):toBe(5)
		local success, _, state = UpgradeTreeService.purchase(player, "Eggs V")
		expect(success):toBeTrue()
		expect(state.entitlements.multiOpenCount):toBe(10)
		expect(profile.diamonds):toBe(87000)
		expect(spends[3]):toEqual({ currency = "diamonds", amount = 500 })
		expect(spends[4]):toEqual({ currency = "diamonds", amount = 2500 })
		expect(spends[5]):toEqual({ currency = "diamonds", amount = 10000 })
	end)

	it("blocks every no-op legacy node without charging", function()
		resetState()
		for _, id in ipairs({ "luck I", "coinMult1", "forged" }) do
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
		expect(state.available["Eggs III"]):toBeTrue()
		expect(state.available.playtime1):toBeTrue()
		expect(state.available.streak3):toBeTrue()
		expect(state.available.friends3):toBeTrue()
		expect(state.available.doubleLuck):toBeTrue()
		expect(state.available.coreSpeed1):toBeTrue()
		expect(state.available.coreSpeed4):toBeTrue()
		expect(state.available.coreMagnet1):toBeTrue()
		expect(state.available.coreMagnet3):toBeTrue()
		expect(state.entitlements.multiOpenCount):toBe(1)
		expect(state.entitlements.generalLuckMultiplier):toBe(1)
		expect(state.entitlements.movementSpeedMultiplier):toBe(1)
		expect(state.entitlements.magnetRangeMultiplier):toBe(1)
		expect(state.entitlements.storageBonusSlots):toBe(0)
		expect(state.entitlements.petEquipBonusSlots):toBe(0)
	end)

	it("purchases canonical Movement and Magnet roots only after Eggs II", function()
		resetState()
		local speedBlocked, speedError = UpgradeTreeService.purchase(player, "coreSpeed1")
		expect(speedBlocked):toBeFalse()
		expect(speedError):toBe("Missing prerequisite")
		local magnetBlocked, magnetError = UpgradeTreeService.purchase(player, "coreMagnet1")
		expect(magnetBlocked):toBeFalse()
		expect(magnetError):toBe("Missing prerequisite")
		expect(#spends):toBe(0)

		expect(UpgradeTreeService.purchase(player, "Eggs I")):toBeTrue()
		expect(UpgradeTreeService.purchase(player, "Eggs II")):toBeTrue()
		expect(UpgradeTreeService.purchase(player, "coreSpeed1")):toBeTrue()
		expect(UpgradeTreeService.purchase(player, "coreMagnet1")):toBeTrue()
		expect(spends[3]):toEqual({ currency = "coins", amount = 5000 })
		expect(spends[4]):toEqual({ currency = "coins", amount = 10000 })
		local state = UpgradeTreeService.getState(player)
		expect(state.entitlements.movementSpeedMultiplier):toBe(1.05)
		expect(state.entitlements.magnetRangeMultiplier):toBe(1.25)
	end)

	it("purchases canonical Double Luck only after Eggs II", function()
		resetState()
		profile.upgradeTreePurchases["luck I"] = true
		local blocked, blockedError = UpgradeTreeService.purchase(player, "doubleLuck")
		expect(blocked):toBeFalse()
		expect(blockedError):toBe("Missing prerequisite")
		expect(#spends):toBe(0)
		expect(UpgradeTreeService.getState(player).entitlements.generalLuckMultiplier):toBe(1)

		expect(UpgradeTreeService.purchase(player, "Eggs I")):toBeTrue()
		expect(UpgradeTreeService.purchase(player, "Eggs II")):toBeTrue()
		local success, message, state = UpgradeTreeService.purchase(player, "doubleLuck")
		expect(success):toBeTrue()
		expect(message):toBe("Purchased doubleLuck")
		expect(profile.diamonds):toBe(95000)
		expect(spends[3]):toEqual({ currency = "diamonds", amount = 5000 })
		expect(state.entitlements.generalLuckMultiplier):toBe(2)

		local duplicate, duplicateError = UpgradeTreeService.purchase(player, "doubleLuck")
		expect(duplicate):toBeFalse()
		expect(duplicateError):toBe("Already purchased")
		expect(#spends):toBe(3)
	end)

	it("keeps Eggs II mandatory for new purchases after grandfathered capacity flags", function()
		resetState()
		profile.upgradeTreePurchases = {
			playtime1 = true,
			friends1 = true,
		}
		expect(UpgradeTreeService.getState(player).entitlements.storageBonusSlots):toBe(25)
		expect(UpgradeTreeService.getState(player).entitlements.petEquipBonusSlots):toBe(1)

		local storageSuccess, storageError = UpgradeTreeService.purchase(player, "playtime2")
		expect(storageSuccess):toBeFalse()
		expect(storageError):toBe("Missing prerequisite")
		local equipSuccess, equipError = UpgradeTreeService.purchase(player, "friends2")
		expect(equipSuccess):toBeFalse()
		expect(equipError):toBe("Missing prerequisite")
		expect(#spends):toBe(0)

		expect(UpgradeTreeService.purchase(player, "Eggs I")):toBeTrue()
		expect(UpgradeTreeService.purchase(player, "Eggs II")):toBeTrue()
		expect(UpgradeTreeService.purchase(player, "playtime2")):toBeTrue()
		expect(UpgradeTreeService.purchase(player, "friends2")):toBeTrue()
	end)

	it("purchases strict Storage and Pet Equip chains with canonical costs", function()
		resetState()
		expect(UpgradeTreeService.purchase(player, "playtime1")):toBeFalse()
		expect(UpgradeTreeService.purchase(player, "friends1")):toBeFalse()
		expect(#spends):toBe(0)
		expect(UpgradeTreeService.purchase(player, "Eggs I")):toBeTrue()
		expect(UpgradeTreeService.purchase(player, "Eggs II")):toBeTrue()

		for _, id in ipairs({ "playtime1", "playtime2", "playtime3", "streak1", "streak2", "streak3" }) do
			expect(UpgradeTreeService.purchase(player, id)):toBeTrue()
		end
		for _, id in ipairs({ "friends1", "friends2", "friends3" }) do
			expect(UpgradeTreeService.purchase(player, id)):toBeTrue()
		end

		local state = UpgradeTreeService.getState(player)
		expect(state.entitlements.storageBonusSlots):toBe(150)
		expect(state.entitlements.petEquipBonusSlots):toBe(3)
		expect(profile.diamonds):toBe(53500)
		expect(spends[3]):toEqual({ currency = "diamonds", amount = 250 })
		expect(spends[8]):toEqual({ currency = "diamonds", amount = 20000 })
		expect(spends[9]):toEqual({ currency = "diamonds", amount = 1000 })
		expect(spends[11]):toEqual({ currency = "diamonds", amount = 5000 })
	end)

	it("keeps reservations silent and publishes one projected final state at commit", function()
		resetState()
		local observedStages = {}
		UpgradeTreeService._transactionHook = function(stage)
			table.insert(observedStages, {
				stage = stage,
				diamonds = profile.diamonds,
				currencyUpdates = #currencyUpdates,
				settlerRegistered = registeredSettler ~= nil,
			})
		end

		local success, _, state = UpgradeTreeService.purchase(player, "epicLuck1")
		expect(success):toBeTrue()
		expect(observedStages):toEqual({
			{ stage = "afterSpend", diamonds = 100000, currencyUpdates = 0, settlerRegistered = true },
			{ stage = "afterEntitlement", diamonds = 100000, currencyUpdates = 0, settlerRegistered = true },
			{ stage = "afterState", diamonds = 100000, currencyUpdates = 0, settlerRegistered = true },
		})
		expect(profile.diamonds):toBe(99500)
		expect(state.currency.diamonds):toBe(99500)
		expect(updateStates[1].currency.diamonds):toBe(99500)
		expect(currencyUpdates):toEqual({ { coins = 100000, diamonds = 99500 } })
		expect(#updateStates):toBe(1)
		expect(commits):toBe(1)
		expect(#rollbacks):toBe(0)
		expect(spendOwners):toEqual({ "UpgradeTreeService" })
	end)

	it("rolls back silently and exactly at every precommit fault hook", function()
		for _, faultStage in ipairs({ "afterSpend", "afterEntitlement", "afterState" }) do
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
			expect(rollbacks):toEqual({ { currency = "diamonds", amount = 500 } })
			expect(#currencyUpdates):toBe(0)
			expect(#updateStates):toBe(0)
			expect(pendingSpend):toBeNil()
			expect(UpgradeTreeService._purchaseLocks[player.UserId]):toBeNil()
		end
		UpgradeTreeService._transactionHook = nil
	end)

	it("restores a preexisting malformed purchases field on failure", function()
		resetState()
		profile.upgradeTreePurchases = "legacy-value"
		UpgradeTreeService._transactionHook = function(stage)
			if stage == "afterEntitlement" then
				error("injected afterEntitlement")
			end
		end
		local success, message = UpgradeTreeService.purchase(player, "Eggs I")
		expect(success):toBeFalse()
		expect(message):toBe("Purchase failed safely")
		expect(profile.upgradeTreePurchases):toBe("legacy-value")
		expect(profile.coins):toBe(100000)
		expect(#currencyUpdates):toBe(0)
		expect(#updateStates):toBe(0)
	end)

	it("restores entitlement and reservation when commit fails or throws", function()
		for _, behavior in ipairs({ "false", "error" }) do
			resetState()
			commitBehavior = behavior
			local success, message = UpgradeTreeService.purchase(player, "epicLuck1")
			expect(success):toBeFalse()
			expect(message):toBe("Purchase failed safely")
			expect(profile.diamonds):toBe(100000)
			expect(profile.upgradeTreePurchases.epicLuck1):toBeNil()
			expect(rollbacks):toEqual({ { currency = "diamonds", amount = 500 } })
			expect(#currencyUpdates):toBe(0)
			expect(#updateStates):toBe(0)
			expect(UpgradeTreeService._purchaseLocks[player.UserId]):toBeNil()
		end
	end)

	it("retains failed and throwing rollbacks for lifecycle retry", function()
		for _, behavior in ipairs({ "false", "error" }) do
			resetState()
			rollbackBehavior = behavior
			UpgradeTreeService._transactionHook = function(stage)
				if stage == "afterEntitlement" then
					error("injected afterEntitlement")
				end
			end
			local success, message = UpgradeTreeService.purchase(player, "epicLuck1")
			expect(success):toBeFalse()
			expect(message):toBe("Purchase rollback failed")
			expect(profile.diamonds):toBe(100000)
			expect(profile.upgradeTreePurchases.epicLuck1):toBeNil()
			expect(type(pendingSpend)):toBe("table")
			expect(type(lastSettler)):toBe("function")
			expect(UpgradeTreeService._purchaseLocks[player.UserId] ~= nil):toBeTrue()

			local busySuccess, busyMessage = UpgradeTreeService.purchase(player, "Eggs I")
			expect(busySuccess):toBeFalse()
			expect(busyMessage):toBe("Purchase already in progress")

			rollbackBehavior = "success"
			expect(lastSettler()):toBeTrue()
			expect(pendingSpend):toBeNil()
			expect(UpgradeTreeService._purchaseLocks[player.UserId]):toBeNil()
			expect(lastSettler()):toBeFalse()
			expect(profile.diamonds):toBe(100000)
			expect(#currencyUpdates):toBe(0)
		end
	end)

	it("retains profile-replacement rollback for lifecycle retry", function()
		resetState()
		local originalProfile = profile
		local replacementProfile = {
			coins = 7,
			diamonds = 11,
			upgradeTreePurchases = {},
		}
		local lookups = 0
		dataLookupOverride = function()
			lookups = lookups + 1
			if lookups == 1 then
				return originalProfile
			end
			return replacementProfile
		end
		rollbackBehavior = "false"

		local success, message = UpgradeTreeService.purchase(player, "epicLuck1")
		expect(success):toBeFalse()
		expect(message):toBe("Purchase rollback failed")
		expect(originalProfile.diamonds):toBe(100000)
		expect(replacementProfile.diamonds):toBe(11)
		expect(type(lastSettler)):toBe("function")
		expect(UpgradeTreeService._purchaseLocks[player.UserId] ~= nil):toBeTrue()

		rollbackBehavior = "success"
		expect(lastSettler()):toBeTrue()
		expect(pendingSpend):toBeNil()
		expect(UpgradeTreeService._purchaseLocks[player.UserId]):toBeNil()
	end)

	it("never overwrites a replacement purchases table during retained rollback", function()
		resetState()
		local ownedPurchases = profile.upgradeTreePurchases
		local replacementPurchases = { newerUpgrade = true }
		UpgradeTreeService._transactionHook = function(stage)
			if stage == "afterEntitlement" then
				profile.upgradeTreePurchases = replacementPurchases
				error("injected ownership conflict")
			end
		end

		local success, message = UpgradeTreeService.purchase(player, "epicLuck1")
		expect(success):toBeFalse()
		expect(message):toBe("Purchase rollback failed")
		expect(profile.upgradeTreePurchases == replacementPurchases):toBeTrue()
		expect(profile.upgradeTreePurchases.newerUpgrade):toBeTrue()
		expect(profile.diamonds):toBe(100000)
		expect(#rollbacks):toBe(0)
		expect(type(pendingSpend)):toBe("table")
		expect(UpgradeTreeService._purchaseLocks[player.UserId] ~= nil):toBeTrue()

		profile.upgradeTreePurchases = ownedPurchases
		expect(lastSettler()):toBeTrue()
		expect(ownedPurchases.epicLuck1):toBeNil()
		expect(pendingSpend):toBeNil()
		expect(UpgradeTreeService._purchaseLocks[player.UserId]):toBeNil()
	end)

	it("treats postcommit UpgradeTreeUpdated failures as terminal", function()
		resetState()
		updateShouldError = true
		local success, message, state = UpgradeTreeService.purchase(player, "epicLuck1")
		expect(success):toBeTrue()
		expect(message):toBe("Purchased epicLuck1")
		expect(state.currency.diamonds):toBe(99500)
		expect(profile.diamonds):toBe(99500)
		expect(profile.upgradeTreePurchases.epicLuck1):toBeTrue()
		expect(#currencyUpdates):toBe(1)
		expect(#updateStates):toBe(0)
		expect(#rollbacks):toBe(0)
		expect(pendingSpend):toBeNil()
		expect(UpgradeTreeService._purchaseLocks[player.UserId]):toBeNil()
	end)

	it("rejects local concurrency, central reservation contention, and insufficient balances safely", function()
		resetState()
		UpgradeTreeService._purchaseLocks[player.UserId] = true
		local lockedSuccess, lockedError = UpgradeTreeService.purchase(player, "Eggs I")
		expect(lockedSuccess):toBeFalse()
		expect(lockedError):toBe("Purchase already in progress")
		UpgradeTreeService._purchaseLocks[player.UserId] = nil

		centralBusy = true
		local busySuccess, busyError = UpgradeTreeService.purchase(player, "epicLuck1")
		expect(busySuccess):toBeFalse()
		expect(busyError):toBe("Not enough diamonds")
		expect(profile.diamonds):toBe(100000)
		expect(profile.upgradeTreePurchases.epicLuck1):toBeNil()
		expect(#currencyUpdates):toBe(0)
		expect(#updateStates):toBe(0)
		expect(UpgradeTreeService._purchaseLocks[player.UserId]):toBeNil()

		centralBusy = false
		profile.diamonds = 0
		local poorSuccess, poorError = UpgradeTreeService.purchase(player, "epicLuck1")
		expect(poorSuccess):toBeFalse()
		expect(poorError):toBe("Not enough diamonds")
		expect(profile.upgradeTreePurchases.epicLuck1):toBeNil()
		expect(#currencyUpdates):toBe(0)
		expect(#updateStates):toBe(0)
	end)
end)
