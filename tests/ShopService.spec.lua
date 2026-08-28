-- ShopService.spec.lua - Focused QOF-13 persistent potion purchase regressions.

local originalRequire = require
local BalanceConfig = originalRequire("src/ReplicatedStorage/Shared/BalanceConfig")
local PetData = originalRequire("src/ReplicatedStorage/Shared/PetData")
local Config = {
	AutoHatchInterval = 3,
	MaxExtraEquipSlots = 5,
}

local sharedMock = { BalanceConfig = BalanceConfig }
rawset(_G, "script", { Parent = sharedMock })
local function shopDataRequire(path)
	if path == BalanceConfig then return BalanceConfig end
	return originalRequire(path)
end
rawset(_G, "require", shopDataRequire)
local ShopData = originalRequire("src/ReplicatedStorage/Shared/ShopData")

local players = {}
function players:GetPlayers()
	return {}
end

local eventPayloads = {}
local eventShouldError = false
local shopEvent = {}
function shopEvent:FireClient(_, state)
	if eventShouldError then
		error("injected event failure")
	end
	table.insert(eventPayloads, state)
end
local remotes = {}
function remotes:FindFirstChild(name)
	if name == "ShopBuffsUpdated" then return shopEvent end
	return nil
end
local replicatedStorage = {
	Shared = {
		PetData = PetData,
		Config = Config,
		BalanceConfig = BalanceConfig,
		ShopData = ShopData,
	},
}
function replicatedStorage:FindFirstChild(name)
	if name == "Remotes" then return remotes end
	return nil
end
local gameMock = { ReplicatedStorage = replicatedStorage }
function gameMock:GetService(name)
	if name == "ReplicatedStorage" then return replicatedStorage end
	if name == "Players" then return players end
	error("Unexpected service: " .. tostring(name))
end
rawset(_G, "game", gameMock)

local function mockRequire(path)
	if path == PetData then return PetData end
	if path == Config then return Config end
	if path == BalanceConfig then return BalanceConfig end
	if path == ShopData then return ShopData end
	return originalRequire(path)
end
rawset(_G, "require", mockRequire)
local ShopService = originalRequire("src/ServerScriptService/Services/ShopService")
rawset(_G, "require", originalRequire)

local player = { UserId = 55 }
local profile = nil
local spendCalls = {}
local spendOwnerNames = {}
local rollbackCalls = {}
local currencyEvents = {}
local pendingCurrencyTransactions = {}
local centralOwner = nil
local rollbackFailuresRemaining = 0
local settlerRegistrations = 0
local hatchCalls = 0
local dataService = {}
function dataService.getPlayerData()
	return profile
end
local currencyService = {}
function currencyService.beginSpendTransaction(_, currency, amount, ownerName)
	table.insert(spendCalls, { currency = currency, amount = amount })
	table.insert(spendOwnerNames, ownerName)
	if centralOwner ~= nil
		or not profile
		or type(profile[currency]) ~= "number"
		or profile[currency] < amount then
		return nil
	end
	local transaction = {}
	local pending = {
		transaction = transaction,
		profile = profile,
		currency = currency,
		amount = amount,
		ownerName = ownerName,
		settler = nil,
	}
	pendingCurrencyTransactions[transaction] = pending
	centralOwner = pending
	return transaction
end
function currencyService.setSpendSettler(transaction, settler)
	local pending = pendingCurrencyTransactions[transaction]
	if not pending or centralOwner ~= pending or type(settler) ~= "function" then
		return false
	end
	pending.settler = settler
	settlerRegistrations = settlerRegistrations + 1
	return true
end
function currencyService.commitSpendTransaction(transaction)
	local pending = pendingCurrencyTransactions[transaction]
	if not pending or centralOwner ~= pending then return false end
	local balance = pending.profile[pending.currency]
	if type(balance) ~= "number" or balance < pending.amount then return false end
	pending.profile[pending.currency] = balance - pending.amount
	pendingCurrencyTransactions[transaction] = nil
	centralOwner = nil
	table.insert(currencyEvents, {
		coins = pending.profile.coins,
		diamonds = pending.profile.diamonds,
	})
	return true
end
function currencyService.rollbackSpendTransaction(transaction)
	local pending = pendingCurrencyTransactions[transaction]
	if not pending or centralOwner ~= pending then return false end
	table.insert(rollbackCalls, { currency = pending.currency, amount = pending.amount })
	if rollbackFailuresRemaining > 0 then
		rollbackFailuresRemaining = rollbackFailuresRemaining - 1
		return false
	end
	pendingCurrencyTransactions[transaction] = nil
	centralOwner = nil
	return true
end

local function settleCentralOwner()
	local pending = centralOwner
	if not pending then return true end
	if type(pending.settler) ~= "function" then return false end
	local ok, restored = pcall(pending.settler, pending.transaction)
	if ok and restored == true then
		if centralOwner == pending then
			pendingCurrencyTransactions[pending.transaction] = nil
			centralOwner = nil
		end
		return true
	end
	return false
end
local eggService = {}
function eggService.purchaseAndHatch()
	hatchCalls = hatchCalls + 1
end

local currentPotionLease = nil
local potionRevision = 0
local potionService = {}
function potionService.beginMutation(ownerPlayer, ownerName)
	if currentPotionLease ~= nil then return nil, "BUSY" end
	currentPotionLease = { player = ownerPlayer, owner = ownerName }
	return currentPotionLease, nil
end
function potionService.isMutationCurrent(ownerPlayer, lease)
	return currentPotionLease == lease and lease.player == ownerPlayer
end
function potionService.endMutation(ownerPlayer, lease)
	if not potionService.isMutationCurrent(ownerPlayer, lease) then return false end
	currentPotionLease = nil
	return true
end
function potionService.notifyInventoryChanged(ownerPlayer, lease)
	if not potionService.isMutationCurrent(ownerPlayer, lease) then return nil, "BUSY" end
	potionRevision = potionRevision + 1
	return {
		contractVersion = 1,
		stateRevision = potionRevision,
		potionInventory = profile and profile.potionInventory or {},
	}
end
function potionService.getState()
	return {
		contractVersion = 1,
		stateRevision = potionRevision,
		potionInventory = profile and profile.potionInventory or {},
	}
end
function potionService.getMultiplier() return 1 end

local function potionRequest(itemId)
	return {
		contractVersion = 2,
		action = "purchasePotion",
		itemId = itemId,
		quantity = 1,
	}
end

local function resetState()
	profile = {
		coins = 100000,
		diamonds = 100000,
		shopPurchases = { extraEquipSlots = 0 },
		potionInventory = {},
		activeBuffs = {},
		potionUpgrades = { slots = 2, durationLevel = 0, autoDrink = false },
		unlockedZones = { 1 },
	}
	spendCalls = {}
	spendOwnerNames = {}
	rollbackCalls = {}
	currencyEvents = {}
	pendingCurrencyTransactions = {}
	centralOwner = nil
	rollbackFailuresRemaining = 0
	settlerRegistrations = 0
	eventPayloads = {}
	eventShouldError = false
	hatchCalls = 0
	ShopService._activeBuffs = {}
	ShopService._purchaseLocks = {}
	ShopService._activeTransactions = {}
	ShopService._shuttingDown = false
	ShopService._transactionHook = nil
	currentPotionLease = nil
	potionRevision = 0
	ShopService.setPotionService(potionService)
	ShopService.setWalkSpeedRefreshCallback(nil)
	ShopService.init(dataService, currencyService)
	ShopService.setEggService(eggService)
end

describe("ShopService QOF-13 canonical potion purchases", function()
	it("purchases all five canonical IDs at server-owned catalog costs", function()
		local expected = {
			LuckPotion = 100,
			MegaLuckPotion = 350,
			SpeedPotion = 50,
			CoinPotion = 125,
			ShinyPotion = 1000,
		}
		for itemId, amount in pairs(expected) do
			resetState()
			local success, message, state = ShopService.purchaseItem(player, potionRequest(itemId))
			expect(success):toBeTrue()
			expect(message):toBeNil()
			expect(profile.potionInventory[itemId]):toBe(1)
			expect(spendCalls):toEqual({ { currency = "diamonds", amount = amount } })
			expect(spendOwnerNames):toEqual({ "ShopService" })
			expect(settlerRegistrations):toBe(1)
			expect(state.contractVersion):toBe(2)
			expect(state.purchaseMode):toBe("inventoryOnly")
			expect(state.potionInventory[itemId]):toBe(1)
			expect(state.maxPotionInventory):toBe(999)
		end
	end)

	it("allows 998 to 999 and rejects the next purchase without debit", function()
		resetState()
		profile.potionInventory.LuckPotion = 998
		local before = profile.diamonds
		expect(ShopService.purchaseItem(player, potionRequest("LuckPotion"))):toBeTrue()
		expect(profile.potionInventory.LuckPotion):toBe(999)
		expect(profile.diamonds):toBe(before - 100)

		local success = ShopService.purchaseItem(player, potionRequest("LuckPotion"))
		expect(success):toBeFalse()
		expect(profile.potionInventory.LuckPotion):toBe(999)
		expect(profile.diamonds):toBe(before - 100)
		expect(#spendCalls):toBe(1)
	end)

	it("applies the inventory cap independently per canonical ID", function()
		resetState()
		profile.potionInventory.LuckPotion = 999
		expect(ShopService.purchaseItem(player, potionRequest("LuckPotion"))):toBeFalse()
		expect(ShopService.purchaseItem(player, potionRequest("SpeedPotion"))):toBeTrue()
		expect(profile.potionInventory.LuckPotion):toBe(999)
		expect(profile.potionInventory.SpeedPotion):toBe(1)
		expect(spendCalls):toEqual({ { currency = "diamonds", amount = 50 } })
	end)

	it("fails closed for insufficient balance, unknown IDs, invalid DTOs, and no profile", function()
		resetState()
		profile.diamonds = 99
		expect(ShopService.purchaseItem(player, potionRequest("LuckPotion"))):toBeFalse()
		expect(profile.potionInventory):toEqual({})
		expect(profile.diamonds):toBe(99)

		resetState()
		expect(ShopService.purchaseItem(player, potionRequest("UnknownPotion"))):toBeFalse()
		expect(ShopService.purchaseItem(player, {
			contractVersion = 2,
			action = "purchasePotion",
			itemId = "LuckPotion",
			quantity = 2,
		})):toBeFalse()
		expect(ShopService.purchaseItem(player, {
			contractVersion = 2,
			action = "purchasePotion",
			itemId = "LuckPotion",
			quantity = 1,
			extra = true,
		})):toBeFalse()
		expect(#spendCalls):toBe(0)

		profile = nil
		expect(ShopService.purchaseItem(player, potionRequest("LuckPotion"))):toBeFalse()
		expect(#spendCalls):toBe(0)
	end)

	it("rejects every legacy potion string, including overlapping IDs, without debit", function()
		resetState()
		for _, itemId in ipairs({ "LuckyPotion", "PowerPotion", "SpeedPotion", "CoinPotion" }) do
			expect(ShopService.purchaseItem(player, itemId)):toBeFalse()
		end
		expect(#spendCalls):toBe(0)
		expect(profile.potionInventory):toEqual({})
	end)

	it("rejects concurrent purchase attempts under the per-player lock", function()
		resetState()
		ShopService._purchaseLocks[player.UserId] = true
		local success, message = ShopService.purchaseItem(player, potionRequest("LuckPotion"))
		expect(success):toBeFalse()
		expect(message):toBe("BUSY")
		expect(#spendCalls):toBe(0)
		expect(profile.potionInventory):toEqual({})
	end)
end)

describe("ShopService QOF-13 transaction boundaries", function()
	it("cancels without balance flicker or events when afterSpend fails", function()
		resetState()
		local before = profile.diamonds
		ShopService._transactionHook = function(stage)
			if stage == "afterSpend" then
				expect(profile.diamonds):toBe(before)
				expect(#currencyEvents):toBe(0)
				error("injected afterSpend")
			end
		end
		local success = ShopService.purchaseItem(player, potionRequest("LuckPotion"))
		expect(success):toBeFalse()
		expect(profile.diamonds):toBe(before)
		expect(profile.potionInventory.LuckPotion):toBeNil()
		expect(rollbackCalls):toEqual({ { currency = "diamonds", amount = 100 } })
		expect(#currencyEvents):toBe(0)
		expect(#eventPayloads):toBe(0)
		expect(ShopService._purchaseLocks[player.UserId]):toBeNil()
	end)

	it("restores an absent inventory key and cancels without debit after mutation failure", function()
		resetState()
		local before = profile.diamonds
		ShopService._transactionHook = function(stage)
			if stage == "afterMutation" then
				expect(profile.diamonds):toBe(before)
				expect(profile.potionInventory.LuckPotion):toBe(1)
				error("injected afterMutation")
			end
		end
		local success = ShopService.purchaseItem(player, potionRequest("LuckPotion"))
		expect(success):toBeFalse()
		expect(profile.diamonds):toBe(before)
		expect(profile.potionInventory.LuckPotion):toBeNil()
		expect(rollbackCalls):toEqual({ { currency = "diamonds", amount = 100 } })
		expect(#currencyEvents):toBe(0)
		expect(#eventPayloads):toBe(0)
	end)

	it("retains central ownership when currency rollback fails and settles on retry", function()
		resetState()
		local before = profile.diamonds
		rollbackFailuresRemaining = 1
		ShopService._transactionHook = function(stage)
			if stage == "afterMutation" then error("injected afterMutation") end
		end

		local success, message = ShopService.purchaseItem(player, potionRequest("LuckPotion"))
		expect(success):toBeFalse()
		expect(message):toBe("Purchase rollback failed")
		expect(profile.diamonds):toBe(before)
		expect(profile.potionInventory.LuckPotion):toBeNil()
		expect(centralOwner ~= nil):toBeTrue()
		expect(centralOwner.ownerName):toBe("ShopService")
		expect(#rollbackCalls):toBe(1)
		expect(ShopService._purchaseLocks[player.UserId]):toBeTrue()

		-- Both the Shop owner and shared Potion lease remain retained until the
		-- exact rollback closure succeeds.
		ShopService._transactionHook = nil
		expect(ShopService.purchaseItem(player, potionRequest("SpeedPotion"))):toBeFalse()
		expect(profile.diamonds):toBe(before)
		expect(profile.potionInventory.SpeedPotion):toBeNil()
		expect(#spendCalls):toBe(1)
		expect(settleCentralOwner()):toBeTrue()
		expect(centralOwner):toBeNil()
		expect(#rollbackCalls):toBe(2)
		expect(profile.diamonds):toBe(before)
		expect(#currencyEvents):toBe(0)

		expect(ShopService.purchaseItem(player, potionRequest("SpeedPotion"))):toBeTrue()
		expect(profile.diamonds):toBe(before - 50)
	end)

	it("does not release central ownership until mutation undo succeeds", function()
		resetState()
		local before = profile.diamonds
		local inventory = profile.potionInventory
		ShopService._transactionHook = function(stage)
			if stage == "afterMutation" then
				rawset(inventory, "LuckPotion", nil)
				setmetatable(inventory, {
					__newindex = function()
						error("injected undo failure")
					end,
				})
				error("injected transaction failure")
			end
		end

		local success, message = ShopService.purchaseItem(player, potionRequest("LuckPotion"))
		expect(success):toBeFalse()
		expect(message):toBe("Purchase rollback failed")
		expect(profile.diamonds):toBe(before)
		expect(centralOwner ~= nil):toBeTrue()
		-- Currency rollback must not run while the profile undo is failing.
		expect(#rollbackCalls):toBe(0)
		expect(#currencyEvents):toBe(0)

		setmetatable(inventory, nil)
		expect(settleCentralOwner()):toBeTrue()
		expect(centralOwner):toBeNil()
		expect(#rollbackCalls):toBe(1)
		expect(profile.diamonds):toBe(before)
		expect(profile.potionInventory.LuckPotion):toBeNil()
	end)

	it("commits before a protected event and returns independent DTO copies", function()
		resetState()
		local success, _, state = ShopService.purchaseItem(player, potionRequest("CoinPotion"))
		expect(success):toBeTrue()
		expect(#currencyEvents):toBe(1)
		expect(currencyEvents[1]):toEqual({ coins = 100000, diamonds = 100000 - 125 })
		expect(#eventPayloads):toBe(1)
		state.potionInventory.CoinPotion = 77
		state.purchases.extraEquipSlots = 4
		expect(profile.potionInventory.CoinPotion):toBe(1)
		expect(eventPayloads[1].potionInventory.CoinPotion):toBe(1)
		eventPayloads[1].potionInventory.CoinPotion = 88
		expect(profile.potionInventory.CoinPotion):toBe(1)

		resetState()
		eventShouldError = true
		success = ShopService.purchaseItem(player, potionRequest("SpeedPotion"))
		expect(success):toBeTrue()
		expect(profile.potionInventory.SpeedPotion):toBe(1)
		expect(profile.diamonds):toBe(100000 - 50)
	end)

	it("never mutates legacy buffs or refreshes movement while building purchase state", function()
		resetState()
		local refreshCalls = 0
		ShopService.setWalkSpeedRefreshCallback(function()
			refreshCalls = refreshCalls + 1
		end)
		profile.activeBuffs = { luck = 1500 }
		ShopService._activeBuffs[player.UserId] = { speed = os.clock() - 1 }
		local activeBuffs = profile.activeBuffs
		local transientBuffs = ShopService._activeBuffs
		local legacyPlayerBuffs = ShopService._activeBuffs[player.UserId]
		local success, _, state = ShopService.purchaseItem(player, potionRequest("SpeedPotion"))
		expect(success):toBeTrue()
		expect(profile.activeBuffs):toBe(activeBuffs)
		expect(profile.activeBuffs):toEqual({ luck = 1500 })
		expect(ShopService._activeBuffs):toBe(transientBuffs)
		expect(ShopService._activeBuffs[player.UserId]):toBe(legacyPlayerBuffs)
		expect(ShopService._activeBuffs[player.UserId].speed ~= nil):toBeTrue()
		expect(state.buffs):toEqual({})
		expect(refreshCalls):toBe(0)

		resetState()
		expect(ShopService.getShopMultiplier(player, "speed")):toBe(1)
	end)

	it("cancels reservation and inventory when authoritative state construction fails", function()
		resetState()
		local before = profile.diamonds
		local calls = 0
		local originalGetPlayerData = dataService.getPlayerData
		dataService.getPlayerData = function()
			calls = calls + 1
			if calls == 1 then
				return profile
			end
			error("injected state construction failure")
		end
		local success, message = ShopService.purchaseItem(player, potionRequest("LuckPotion"))
		dataService.getPlayerData = originalGetPlayerData
		expect(success):toBeFalse()
		expect(message):toBe("Purchase failed")
		expect(profile.diamonds):toBe(before)
		expect(profile.potionInventory.LuckPotion):toBeNil()
		expect(rollbackCalls):toEqual({ { currency = "diamonds", amount = 100 } })
		expect(#currencyEvents):toBe(0)
		expect(#eventPayloads):toBe(0)
		expect(ShopService._purchaseLocks[player.UserId]):toBeNil()
	end)

	it("keeps unexpected dependency errors generic and releases the lock", function()
		resetState()
		local originalGetPlayerData = dataService.getPlayerData
		dataService.getPlayerData = function()
			error("private dependency detail")
		end
		local success, message = ShopService.purchaseItem(player, potionRequest("LuckPotion"))
		dataService.getPlayerData = originalGetPlayerData
		expect(success):toBeFalse()
		expect(message):toBe("Purchase failed")
		expect(ShopService._purchaseLocks[player.UserId]):toBeNil()
		expect(#spendCalls):toBe(0)
	end)
end)

describe("ShopService retained shop contracts", function()
	it("keeps ExtraEquipSlot price, maximum, lock, rollback, and state semantics", function()
		resetState()
		local success, message, state = ShopService.purchaseItem(player, "ExtraEquipSlot")
		expect(success):toBeTrue()
		expect(message):toBeNil()
		expect(spendCalls):toEqual({ { currency = "diamonds", amount = 1000 } })
		expect(profile.shopPurchases.extraEquipSlots):toBe(1)
		expect(state.purchases.extraEquipSlots):toBe(1)
		expect(state.maxExtraEquipSlots):toBe(5)

		resetState()
		profile.shopPurchases.extraEquipSlots = 5
		expect(ShopService.purchaseItem(player, "ExtraEquipSlot")):toBeFalse()
		expect(#spendCalls):toBe(0)

		resetState()
		ShopService._purchaseLocks[player.UserId] = true
		expect(ShopService.purchaseItem(player, "ExtraEquipSlot")):toBeFalse()
		expect(#spendCalls):toBe(0)

		resetState()
		ShopService._transactionHook = function(stage)
			if stage == "afterMutation" then error("extra slot failure") end
		end
		expect(ShopService.purchaseItem(player, "ExtraEquipSlot")):toBeFalse()
		expect(profile.shopPurchases.extraEquipSlots):toBe(0)
		expect(profile.diamonds):toBe(100000)
		expect(rollbackCalls):toEqual({ { currency = "diamonds", amount = 1000 } })
		expect(#currencyEvents):toBe(0)
		expect(#eventPayloads):toBe(0)
	end)

	it("keeps legacy AutoHatch fail-closed while the dedicated service owns QOF-18", function()
		resetState()
		expect(BalanceConfig.Shop.AutoHatchRuntimeEnabled):toBeTrue()
		expect(ShopData.Items.AutoHatch.itemType):toBe("autoHatch")
		expect(ShopData.Items.AutoHatch.cost):toBe(500)
		local success, message = ShopService.purchaseItem(player, "AutoHatch")
		expect(success):toBeFalse()
		expect(message):toBe("Auto-Hatch is not available yet")
		expect(#spendCalls):toBe(0)

		ShopService._activeBuffs[player.UserId] = { autoHatch = os.clock() + 600 }
		expect(ShopService._processAutoHatch()):toBeFalse()
		expect(hatchCalls):toBe(0)
	end)

	it("delegates potion state and effect reads while retaining purchase ownership", function()
		resetState()
		local potionReads = 0
		local potionService = {}
		function potionService.getMultiplier(_, buffType)
			expect(buffType):toBe("luck")
			return 5
		end
		function potionService.getState()
			potionReads = potionReads + 1
			return { contractVersion = 1, potionInventory = { LuckPotion = 2 } }
		end
		ShopService.setPotionService(potionService)
		expect(ShopService.getShopMultiplier(player, "luck")):toBe(5)
		local state = ShopService.getShopState(player)
		expect(state.contractVersion):toBe(2)
		expect(state.purchaseMode):toBe("inventoryOnly")
		expect(state.potionState.contractVersion):toBe(1)
		expect(potionReads):toBe(1)
	end)

	it("never guesses an ownerless Shop lock stale on player removal", function()
		resetState()
		profile.potionInventory.LuckPotion = 3
		ShopService._purchaseLocks[player.UserId] = true
		ShopService._activeBuffs[player.UserId] = { luck = os.clock() + 60 }
		expect(ShopService.onPlayerRemoving(player)):toBeFalse()
		expect(ShopService._purchaseLocks[player.UserId]):toBeTrue()
		expect(ShopService._activeBuffs[player.UserId] ~= nil):toBeTrue()
		expect(profile.potionInventory.LuckPotion):toBe(3)
	end)
end)


describe("ShopData QOF-18 presentation", function()
	it("exposes five canonical potions, paid Auto-Hatch, and ExtraEquipSlot", function()
		expect(ShopData.ContractVersion):toBe(2)
		expect(ShopData.AutoHatchContractVersion):toBe(1)
		expect(ShopData.PurchaseMode):toBe("inventoryOnly")
		expect(ShopData.MaxPotionInventory):toBe(999)
		expect(ShopData.Order):toEqual({
			"LuckPotion",
			"MegaLuckPotion",
			"SpeedPotion",
			"CoinPotion",
			"ShinyPotion",
			"AutoHatch",
			"ExtraEquipSlot",
		})
		expect(ShopData.Items.LuckyPotion):toBeNil()
		expect(ShopData.Items.PowerPotion):toBeNil()
		expect(ShopData.Items.AutoHatch.cost):toBe(500)
		expect(ShopData.Items.AutoHatch.durationSeconds):toBe(600)
		for potionId, potion in pairs(BalanceConfig.Potions.Catalog) do
			local item = ShopData.Items[potionId]
			expect(item.itemType):toBe("potion")
			expect(item.cost):toBe(potion.cost.amount)
			expect(item.currency):toBe(potion.cost.currency)
		end
	end)
end)


describe("ShopService QOF-26 shared Potion lease and lifecycle", function()
	it("returns BUSY before currency work while a Hatch owns the Potion lease", function()
		resetState()
		local hatchLease = potionService.beginMutation(player, "EggService.ShinyReservation")
		local success, reason = ShopService.purchaseItem(player, potionRequest("ShinyPotion"))
		expect(success):toBeFalse()
		expect(reason):toBe("BUSY")
		expect(#spendCalls):toBe(0)
		expect(profile.potionInventory.ShinyPotion):toBeNil()
		expect(potionService.endMutation(player, hatchLease)):toBeTrue()
	end)

	it("retains ExtraEquipSlot ownership until a failed rollback can settle", function()
		resetState()
		rollbackFailuresRemaining = 1
		ShopService._transactionHook = function(stage)
			if stage == "afterMutation" then error("injected extra-slot failure") end
		end
		local success, reason = ShopService.purchaseItem(player, "ExtraEquipSlot")
		expect(success):toBeFalse()
		expect(reason):toBe("Purchase rollback failed")
		expect(profile.shopPurchases.extraEquipSlots):toBe(0)
		expect(ShopService._activeTransactions[player.UserId] ~= nil):toBeTrue()
		expect(ShopService._purchaseLocks[player.UserId]):toBeTrue()
		expect(ShopService.onPlayerRemoving(player)):toBeTrue()
		expect(ShopService._activeTransactions[player.UserId]):toBeNil()
		expect(ShopService._purchaseLocks[player.UserId]):toBeNil()
		expect(profile.diamonds):toBe(100000)
	end)

	it("closes new Shop admission at shutdown without discarding retained owners", function()
		resetState()
		rollbackFailuresRemaining = 1
		ShopService._transactionHook = function(stage)
			if stage == "afterMutation" then error("injected retained purchase") end
		end
		local success = ShopService.purchaseItem(player, potionRequest("LuckPotion"))
		expect(success):toBeFalse()
		expect(ShopService._activeTransactions[player.UserId] ~= nil):toBeTrue()
		ShopService.beginShutdown()
		local blocked, reason = ShopService.purchaseItem(player, "ExtraEquipSlot")
		expect(blocked):toBeFalse()
		expect(reason):toBe("SERVICE_UNAVAILABLE")
		expect(ShopService.prepareForShutdown()):toBeTrue()
		expect(ShopService._activeTransactions[player.UserId]):toBeNil()
		expect(currentPotionLease):toBeNil()
		expect(profile.potionInventory.LuckPotion):toBeNil()
	end)
end)
