-- QOF26PotionLifecycle.spec.lua - Shared Potion lease integration and races.

local originalRequire = require
local BalanceConfig = originalRequire("src/ReplicatedStorage/Shared/BalanceConfig")
local PetData = originalRequire("src/ReplicatedStorage/Shared/PetData")
local Config = {
	EggCosts = { [1] = { Coins = 100 } },
	MaxExtraEquipSlots = 5,
}
local shopShared = { BalanceConfig = BalanceConfig }
rawset(_G, "script", { Parent = shopShared })
rawset(_G, "require", function(path)
	if path == BalanceConfig then return BalanceConfig end
	return originalRequire(path)
end)
local ShopData = originalRequire("src/ReplicatedStorage/Shared/ShopData")

local players = {}
function players:GetPlayers() return {} end
local potionEvents = {}
local potionEvent = {}
function potionEvent:FireClient(_, state) table.insert(potionEvents, state) end
local remotes = {}
function remotes:FindFirstChild(name)
	if name == "PotionStateUpdated" then return potionEvent end
	return nil
end
local replicatedStorage = {
	Shared = {
		BalanceConfig = BalanceConfig,
		PetData = PetData,
		Config = Config,
		ShopData = ShopData,
	},
}
function replicatedStorage:FindFirstChild(name)
	if name == "Remotes" then return remotes end
	return nil
end
local gameMock = { ReplicatedStorage = replicatedStorage }
function gameMock:GetService(name)
	if name == "Players" then return players end
	if name == "ReplicatedStorage" then return replicatedStorage end
	error("Unexpected service: " .. tostring(name))
end
rawset(_G, "game", gameMock)
rawset(_G, "require", function(path)
	if path == BalanceConfig then return BalanceConfig end
	if path == PetData then return PetData end
	if path == Config then return Config end
	if path == ShopData then return ShopData end
	return originalRequire(path)
end)
local PotionService = originalRequire("src/ServerScriptService/Services/PotionService")
local EggService = originalRequire("src/ServerScriptService/Services/EggService")
local ShopService = originalRequire("src/ServerScriptService/Services/ShopService")
rawset(_G, "require", originalRequire)

local player = { UserId = 2601, Name = "PotionRace" }
local profile
local currencyBegins
local pendingSpends
local inventoryLease
local dataService = {}
function dataService.getPlayerData() return profile end

local currencyService = {}
function currencyService.beginSpendTransaction(_, currency, amount)
	currencyBegins = currencyBegins + 1
	if profile[currency] < amount then return nil end
	local handle = {}
	pendingSpends[handle] = { currency = currency, amount = amount }
	return handle
end
function currencyService.setSpendSettler(handle, settler)
	if not pendingSpends[handle] then return false end
	pendingSpends[handle].settler = settler
	return true
end
function currencyService.commitSpendTransaction(handle)
	local pending = pendingSpends[handle]
	if not pending then return false end
	profile[pending.currency] = profile[pending.currency] - pending.amount
	pendingSpends[handle] = nil
	return true
end
function currencyService.rollbackSpendTransaction(handle)
	if not pendingSpends[handle] then return false end
	pendingSpends[handle] = nil
	return true
end

local petService = {}
function petService.beginInventoryMutation(ownerPlayer)
	if inventoryLease then return nil end
	inventoryLease = { player = ownerPlayer }
	return inventoryLease
end
function petService.isInventoryMutationCurrent(ownerPlayer, lease)
	return inventoryLease == lease and lease.player == ownerPlayer
end
function petService.endInventoryMutation(ownerPlayer, lease)
	if not petService.isInventoryMutationCurrent(ownerPlayer, lease) then return false end
	inventoryLease = nil
	return true
end
function petService.getMaxInventory() return 100 end
function petService.canAddPets() return true end
function petService.prepareHatchBatch(_, _, count, options)
	local pets = {}
	for index = 1, count do
		table.insert(pets, { id = "qof26-" .. tostring(index), petId = "Buddy", name = "Buddy" })
	end
	return {
		pets = pets,
		originalPetCount = #profile.pets,
		mutationStarted = false,
		shinyBoostCount = options.shinyBoostCount,
	}
end
function petService.commitHatchBatch(_, prepared, lease)
	if not petService.isInventoryMutationCurrent(player, lease) then return false end
	prepared.mutationStarted = true
	for _, pet in ipairs(prepared.pets) do table.insert(profile.pets, pet) end
	return true
end
function petService.rollbackHatchBatch(prepared)
	while #profile.pets > prepared.originalPetCount do table.remove(profile.pets) end
	prepared.mutationStarted = false
	return true
end
function petService.replicateInventory() end

local upgradeTreeService = {}
function upgradeTreeService.getEntitlements() return { multiOpenCount = 10 } end
local directProfileOwner = nil
local profileAdmissionError = nil
local profileTransactionService = {}
function profileTransactionService.begin(ownerPlayer, ownerName)
	if directProfileOwner then return nil, "BUSY" end
	if profileAdmissionError then return nil, profileAdmissionError end
	directProfileOwner = { player = ownerPlayer, ownerName = ownerName, profile = profile }
	return directProfileOwner, nil
end
function profileTransactionService.commit(owner)
	if owner ~= directProfileOwner then return false end
	directProfileOwner = nil
	return true
end
function profileTransactionService.setSettler() return true end

local function consumeRequest()
	return { contractVersion = 1, action = "consumePotion", potionId = "ShinyPotion" }
end
local function upgradeRequest()
	return { contractVersion = 1, action = "purchasePotionUpgrade", upgradeId = "Duration" }
end
local function selectionRequest()
	return {
		contractVersion = 1,
		action = "setAutoDrinkSelection",
		potionId = "ShinyPotion",
		selected = true,
	}
end
local function shopPotionRequest()
	return {
		contractVersion = 2,
		action = "purchasePotion",
		itemId = "ShinyPotion",
		quantity = 1,
	}
end

local function reset(initialCharges)
	profile = {
		coins = 10000,
		diamonds = 10000,
		unlockedZones = { 1 },
		pets = {},
		capacity = 100,
		hatchPreferences = { preferredBatchCount = 1 },
		potionInventory = { ShinyPotion = 1 },
		activeBuffs = { shinyChance = { charges = initialCharges } },
		potionUpgrades = { slots = 2, durationLevel = 0, autoDrink = true },
		autoDrinkSelection = { ShinyPotion = true },
	}
	currencyBegins = 0
	pendingSpends = {}
	inventoryLease = nil
	directProfileOwner = nil
	profileAdmissionError = nil
	potionEvents = {}
	PotionService._potionLeases = {}
	PotionService._leaseGenerations = {}
	PotionService._stateRevisions = {}
	PotionService._pendingShinyCharges = {}
	PotionService._activeTransactions = {}
	PotionService._transactionHook = nil
	PotionService._shuttingDown = false
	PotionService.init(dataService, currencyService, profileTransactionService)
	ShopService._purchaseLocks = {}
	ShopService._activeTransactions = {}
	ShopService._activeBuffs = {}
	ShopService._shuttingDown = false
	ShopService._transactionHook = nil
	ShopService.init(dataService, currencyService)
	ShopService.setPotionService(PotionService)
	EggService.init(dataService, currencyService, petService, upgradeTreeService, profileTransactionService)
	EggService.setPotionService(PotionService)
	EggService.setStationAuthority({ validateManual = function() return true end })
	EggService._transactionHook = nil
end

describe("QOF-26 Egg and Potion lease race", function()
	it("holds one lease at afterPrepare and rolls 5, 29, and 30 back exactly", function()
		for _, initialCharges in ipairs({ 5, 29, 30 }) do
			reset(initialCharges)
			local attemptsChecked = false
			EggService._transactionHook = function(stage, transaction)
				if stage ~= "afterPrepare" then return end
				expect(transaction.executing):toBeTrue()
				expect(transaction.shinyBoostCount):toBe(3)
				expect(profile.activeBuffs.shinyChance.charges):toBe(initialCharges - 3)
				local inventoryBefore = profile.potionInventory.ShinyPotion
				local beginBefore = currencyBegins
				local revisionBefore = PotionService.getState(player).stateRevision

				local consumed, consumeReason = PotionService.consume(player, consumeRequest())
				expect(consumed):toBeFalse()
				expect(consumeReason):toBe("BUSY")
				local autoDrank, autoReason = PotionService.processAutoDrink(player)
				expect(autoDrank):toBeFalse()
				expect(autoReason):toBe("BUSY")
				local upgraded, upgradeReason = PotionService.purchaseUpgrade(player, upgradeRequest())
				expect(upgraded):toBeFalse()
				expect(upgradeReason):toBe("BUSY")
				local selected, selectionReason = PotionService.setAutoDrinkSelection(player, selectionRequest())
				expect(selected):toBeFalse()
				expect(selectionReason):toBe("BUSY")
				local purchased, purchaseReason = ShopService.purchaseItem(player, shopPotionRequest())
				expect(purchased):toBeFalse()
				expect(purchaseReason):toBe("BUSY")
				local reconciled, reconcileReason = PotionService.reconcilePlayer(player, true)
				expect(reconciled):toBeFalse()
				expect(reconcileReason):toBe("BUSY")

				expect(profile.potionInventory.ShinyPotion):toBe(inventoryBefore)
				expect(profile.activeBuffs.shinyChance.charges):toBe(initialCharges - 3)
				expect(currencyBegins):toBe(beginBefore)
				expect(PotionService.getState(player).stateRevision):toBe(revisionBefore)
				expect(#potionEvents):toBe(0)
				-- Lifecycle observers must not steal the executing Egg's settlement
				-- decision or restore its reservation underneath the hatch.
				expect(EggService.cleanup(player)):toBeFalse()
				expect(PotionService.cleanup(player)):toBeFalse()
				expect(profile.activeBuffs.shinyChance.charges):toBe(initialCharges - 3)
				attemptsChecked = true
				error("injected technical hatch failure")
			end

			local result, hatchError = EggService.purchaseFromIntent(player, "BasicEgg", {
				mode = "Fixed",
				count = 3,
			})
			expect(result):toBeNil()
			expect(hatchError):toBe("Hatch failed safely")
			expect(attemptsChecked):toBeTrue()
			expect(profile.activeBuffs.shinyChance):toEqual({ charges = initialCharges })
			expect(profile.potionInventory.ShinyPotion):toBe(1)
			expect(PotionService.getState(player).stateRevision):toBe(0)
			expect(#potionEvents):toBe(0)
			expect(PotionService.isPotionMutationIdle(player)):toBeTrue()
		end
	end)

	it("commits exactly the reserved amount and publishes one revision", function()
		reset(5)
		local result, hatchError = EggService.purchaseFromIntent(player, "BasicEgg", {
			mode = "Fixed",
			count = 3,
		})
		expect(hatchError):toBeNil()
		expect(result.count):toBe(3)
		expect(profile.activeBuffs.shinyChance):toEqual({ charges = 2 })
		expect(profile.potionInventory.ShinyPotion):toBe(1)
		expect(PotionService.getState(player).stateRevision):toBe(1)
		expect(#potionEvents):toBe(1)
		expect(PotionService.isPotionMutationIdle(player)):toBeTrue()
	end)

	it("keeps a post-PONR Egg reservation for commit retry, never Potion rollback", function()
		reset(5)
		local originalCommit = PotionService.commitShinyChargeTransaction
		local failCommit = true
		PotionService.commitShinyChargeTransaction = function(handle)
			if failCommit then return false end
			return originalCommit(handle)
		end
		local result, hatchError = EggService.purchaseFromIntent(player, "BasicEgg", {
			mode = "Fixed",
			count = 3,
		})
		expect(hatchError):toBeNil()
		expect(result.count):toBe(3)
		expect(profile.coins):toBe(9700)
		expect(profile.activeBuffs.shinyChance):toEqual({ charges = 2 })
		expect(EggService.cleanup(player)):toBeFalse()
		expect(PotionService.cleanup(player)):toBeFalse()
		expect(profile.activeBuffs.shinyChance):toEqual({ charges = 2 })
		expect(PotionService.getState(player).stateRevision):toBe(0)
		failCommit = false
		expect(EggService.cleanup(player)):toBeTrue()
		expect(PotionService.cleanup(player)):toBeTrue()
		expect(profile.activeBuffs.shinyChance):toEqual({ charges = 2 })
		expect(#potionEvents):toBe(1)
		PotionService.commitShinyChargeTransaction = originalCommit
	end)
end)

describe("QOF-26 exact Potion lease lifecycle", function()
	it("keeps getState pure and rejects stale, wrong, and double releases", function()
		reset(5)
		profile.activeBuffs.speed = { sources = { SpeedPotion = { expiresAt = 1 } } }
		local lease = PotionService.beginMutation(player, "test")
		local activeBuffs = profile.activeBuffs
		local revision = PotionService.getState(player).stateRevision
		local state = PotionService.getState(player)
		expect(state.activeBuffs.speed):toBeNil()
		expect(profile.activeBuffs):toBe(activeBuffs)
		expect(profile.activeBuffs.speed ~= nil):toBeTrue()
		expect(PotionService.getState(player).stateRevision):toBe(revision)
		expect(#potionEvents):toBe(0)
		expect(PotionService.endMutation({ UserId = player.UserId }, lease)):toBeFalse()
		expect(PotionService.endMutation(player, {})):toBeFalse()
		expect(PotionService.endMutation(player, lease)):toBeTrue()
		expect(PotionService.endMutation(player, lease)):toBeFalse()
		local nextLease = PotionService.beginMutation(player, "next")
		expect(PotionService.endMutation(player, lease)):toBeFalse()
		expect(PotionService.endMutation(player, nextLease)):toBeTrue()
	end)

	it("retains a failed additive Shiny restore through cleanup and retries once", function()
		reset(30)
		local handle, reserved = PotionService.beginShinyChargeTransaction(player, 3)
		expect(reserved):toBe(3)
		expect(profile.activeBuffs.shinyChance.charges):toBe(27)
		-- Inject an impossible same-lease state. Rollback must never clamp or discard
		-- the handle; every other Potion mutation remains BUSY.
		profile.activeBuffs.shinyChance.charges = 30
		expect(PotionService.rollbackShinyChargeTransaction(handle)):toBeFalse()
		expect(PotionService.cleanup(player)):toBeFalse()
		local consumed, reason = PotionService.consume(player, consumeRequest())
		expect(consumed):toBeFalse()
		expect(reason):toBe("BUSY")
		expect(profile.potionInventory.ShinyPotion):toBe(1)
		profile.activeBuffs.shinyChance.charges = 27
		expect(PotionService.rollbackShinyChargeTransaction(handle)):toBeTrue()
		expect(PotionService.cleanup(player)):toBeTrue()
		expect(profile.activeBuffs.shinyChance):toEqual({ charges = 30 })
		expect(PotionService.rollbackShinyChargeTransaction(handle)):toBeFalse()
	end)

	it("rejects direct Potion mutations while save or leave admission is closed", function()
		for _, admissionReason in ipairs({ "SAVE_IN_PROGRESS", "ADMISSION_CLOSED" }) do
			reset(5)
			profileAdmissionError = admissionReason
			local inventoryBefore = profile.potionInventory.ShinyPotion
			local chargesBefore = profile.activeBuffs.shinyChance.charges
			local consumed, consumeReason = PotionService.consume(player, consumeRequest())
			expect(consumed):toBeFalse()
			expect(consumeReason):toBe(admissionReason)
			local autoDrank, autoReason = PotionService.processAutoDrink(player)
			expect(autoDrank):toBeFalse()
			expect(autoReason):toBe(admissionReason)
			local selected, selectionReason = PotionService.setAutoDrinkSelection(player, selectionRequest())
			expect(selected):toBeFalse()
			expect(selectionReason):toBe(admissionReason)
			local reconciled, reconcileReason = PotionService.reconcilePlayer(player, true)
			expect(reconciled):toBeFalse()
			expect(reconcileReason):toBe(admissionReason)
			expect(profile.potionInventory.ShinyPotion):toBe(inventoryBefore)
			expect(profile.activeBuffs.shinyChance.charges):toBe(chargesBefore)
			expect(PotionService.getState(player).stateRevision):toBe(0)
			expect(#potionEvents):toBe(0)
			expect(PotionService.isPotionMutationIdle(player)):toBeTrue()
		end
	end)

	it("closes admission at shutdown while an existing handle remains settleable", function()
		reset(5)
		local handle = PotionService.beginShinyChargeTransaction(player, 3)
		PotionService.beginShutdown()
		local consumed, reason = PotionService.consume(player, consumeRequest())
		expect(consumed):toBeFalse()
		expect(reason):toBe("SERVICE_UNAVAILABLE")
		expect(PotionService.rollbackShinyChargeTransaction(handle)):toBeTrue()
		expect(profile.activeBuffs.shinyChance):toEqual({ charges = 5 })
	end)
end)
