-- PotionService.spec.lua - Focused QOF-14 authoritative consumption regressions.

local originalRequire = require
local BalanceConfig = originalRequire("src/ReplicatedStorage/Shared/BalanceConfig")
local originalTime = os.time
local fakeTime = 1000
os.time = function() return fakeTime end

local players = {}
function players:GetPlayers() return {} end

local stateEvents = {}
local potionEvent = {}
function potionEvent:FireClient(_, state)
	table.insert(stateEvents, state)
end
local remotes = {}
function remotes:FindFirstChild(name)
	if name == "PotionStateUpdated" then return potionEvent end
	return nil
end
local replicatedStorage = { Shared = { BalanceConfig = BalanceConfig } }
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

local function mockRequire(path)
	if path == BalanceConfig then return BalanceConfig end
	return originalRequire(path)
end
rawset(_G, "require", mockRequire)
local PotionService = originalRequire("src/ServerScriptService/Services/PotionService")
rawset(_G, "require", originalRequire)

local player = { UserId = 314 }
local profile = nil
local currencyEvents = {}
local pending = {}
local refreshCalls = 0
local dataService = {}
function dataService.getPlayerData() return profile end
local currencyService = {}
function currencyService.beginSpendTransaction(_, currency, amount)
	if profile[currency] < amount then return nil end
	local transaction = {}
	profile[currency] = profile[currency] - amount
	pending[transaction] = { currency = currency, amount = amount }
	return transaction
end
function currencyService.commitSpendTransaction(transaction)
	if not pending[transaction] then return false end
	pending[transaction] = nil
	table.insert(currencyEvents, profile.diamonds)
	return true
end
function currencyService.rollbackSpendTransaction(transaction)
	local state = pending[transaction]
	if not state then return false end
	pending[transaction] = nil
	profile[state.currency] = profile[state.currency] + state.amount
	return true
end

local function consumeRequest(potionId)
	return { contractVersion = 1, action = "consumePotion", potionId = potionId }
end
local function upgradeRequest(upgradeId)
	return { contractVersion = 1, action = "purchasePotionUpgrade", upgradeId = upgradeId }
end
local function selectionRequest(potionId, selected)
	return {
		contractVersion = 1,
		action = "setAutoDrinkSelection",
		potionId = potionId,
		selected = selected,
	}
end

local function resetState()
	fakeTime = 1000
	profile = {
		coins = 100000,
		diamonds = 100000,
		potionInventory = {},
		activeBuffs = {},
		potionUpgrades = { slots = 2, durationLevel = 0, autoDrink = false },
		autoDrinkSelection = {},
	}
	stateEvents = {}
	currencyEvents = {}
	pending = {}
	refreshCalls = 0
	PotionService._mutationLocks = {}
	PotionService._stateRevisions = {}
	PotionService._pendingShinyCharges = setmetatable({}, { __mode = "k" })
	PotionService._transactionHook = nil
	PotionService.init(dataService, currencyService)
	PotionService.setMovementRefreshCallback(function() refreshCalls = refreshCalls + 1 end)
end

describe("PotionService QOF-14 timed sources", function()
	it("consumes inventory into a structured absolute-time source", function()
		resetState()
		profile.potionInventory.LuckPotion = 2
		local success, message, state = PotionService.consume(player, consumeRequest("LuckPotion"))
		expect(success):toBeTrue()
		expect(message):toBeNil()
		expect(profile.potionInventory.LuckPotion):toBe(1)
		expect(profile.activeBuffs.luck.sources.LuckPotion.expiresAt):toBe(1600)
		expect(state.activeBuffs.luck.effectiveMultiplier):toBe(2)
		expect(state.slots):toEqual({ active = 1, maximum = 2 })
		expect(#stateEvents):toBe(1)
	end)

	it("rejects manual timed consumption at the exact 30-day cap without mutation", function()
		resetState()
		local cap = fakeTime + BalanceConfig.Potions.Persistence.MaxTimedBuffSeconds
		profile.potionInventory.LuckPotion = 1
		profile.activeBuffs.luck = {
			sources = { LuckPotion = { expiresAt = cap } },
		}
		local beforeState = PotionService.getState(player)
		expect(beforeState.consumeAvailability.LuckPotion.canConsume):toBeFalse()
		expect(beforeState.consumeAvailability.LuckPotion.reason)
			:toBe("Maximum timed duration reached (30 days)")

		local success, message = PotionService.consume(player, consumeRequest("LuckPotion"))
		expect(success):toBeFalse()
		expect(message):toBe("Maximum timed duration reached (30 days)")
		expect(profile.potionInventory.LuckPotion):toBe(1)
		expect(profile.activeBuffs.luck.sources.LuckPotion.expiresAt):toBe(cap)
		expect(PotionService.getState(player).stateRevision):toBe(0)
		expect(#stateEvents):toBe(0)
	end)

	it("allows a near-cap manual drink as a partial extension exactly to the cap", function()
		resetState()
		local cap = fakeTime + BalanceConfig.Potions.Persistence.MaxTimedBuffSeconds
		profile.potionInventory.LuckPotion = 1
		profile.activeBuffs.luck = {
			sources = { LuckPotion = { expiresAt = cap - 1 } },
		}
		expect(PotionService.getState(player).consumeAvailability.LuckPotion.canConsume):toBeTrue()
		local success, message, state = PotionService.consume(player, consumeRequest("LuckPotion"))
		expect(success):toBeTrue()
		expect(message):toBeNil()
		expect(profile.potionInventory.LuckPotion):toBeNil()
		expect(profile.activeBuffs.luck.sources.LuckPotion.expiresAt):toBe(cap)
		expect(state.stateRevision):toBe(1)
		expect(#stateEvents):toBe(1)
	end)

	it("extends only the consumed source and applies the highest luck source in one slot", function()
		resetState()
		profile.potionInventory = { LuckPotion = 2, MegaLuckPotion = 2 }
		expect(PotionService.consume(player, consumeRequest("LuckPotion"))):toBeTrue()
		expect(PotionService.consume(player, consumeRequest("LuckPotion"))):toBeTrue()
		expect(PotionService.consume(player, consumeRequest("MegaLuckPotion"))):toBeTrue()
		expect(profile.activeBuffs.luck.sources.LuckPotion.expiresAt):toBe(2200)
		expect(profile.activeBuffs.luck.sources.MegaLuckPotion.expiresAt):toBe(1300)
		expect(PotionService.getMultiplier(player, "luck")):toBe(5)
		expect(PotionService.getState(player).slots.active):toBe(1)
		fakeTime = 1300
		expect(PotionService.getMultiplier(player, "luck")):toBe(2)
	end)

	it("counts distinct buff types and applies Duration only when a timed potion is consumed", function()
		resetState()
		profile.potionUpgrades.durationLevel = 1
		profile.potionInventory = { LuckPotion = 1, SpeedPotion = 1, CoinPotion = 1 }
		expect(PotionService.consume(player, consumeRequest("LuckPotion"))):toBeTrue()
		expect(PotionService.consume(player, consumeRequest("SpeedPotion"))):toBeTrue()
		expect(profile.activeBuffs.speed.sources.SpeedPotion.expiresAt):toBe(1375)
		local success, message = PotionService.consume(player, consumeRequest("CoinPotion"))
		expect(success):toBeFalse()
		expect(message):toBe("No active potion slots available")
		expect(profile.potionInventory.CoinPotion):toBe(1)
		expect(refreshCalls):toBe(1)
	end)

	it("caps Shiny charges at 30 without applying Duration", function()
		resetState()
		profile.potionUpgrades.durationLevel = 4
		profile.potionInventory.ShinyPotion = 1
		profile.activeBuffs.shinyChance = { charges = 29 }
		expect(PotionService.consume(player, consumeRequest("ShinyPotion"))):toBeTrue()
		expect(profile.activeBuffs.shinyChance):toEqual({ charges = 30 })
		expect(PotionService.getState(player).slots.active):toBe(1)
	end)

	it("rolls back inventory and buff state exactly on an injected consume fault", function()
		resetState()
		profile.potionInventory.SpeedPotion = 1
		PotionService._transactionHook = function(stage)
			if stage == "afterBuff" then error("injected") end
		end
		local success = PotionService.consume(player, consumeRequest("SpeedPotion"))
		expect(success):toBeFalse()
		expect(profile.potionInventory.SpeedPotion):toBe(1)
		expect(profile.activeBuffs.speed):toBeNil()
		expect(#stateEvents):toBe(0)
		expect(refreshCalls):toBe(0)
	end)
end)

describe("PotionService QOF-14 upgrades and Auto-Drink", function()
	it("uses server-owned upgrade costs and silently rolls back faults", function()
		resetState()
		local success, message, state = PotionService.purchaseUpgrade(player, upgradeRequest("PotionSlot"))
		expect(success):toBeTrue()
		expect(message):toBeNil()
		expect(profile.diamonds):toBe(99500)
		expect(profile.potionUpgrades.slots):toBe(3)
		expect(state.slots.maximum):toBe(3)
		expect(#currencyEvents):toBe(1)

		PotionService._transactionHook = function(stage)
			if stage == "afterUpgrade" then error("injected") end
		end
		local before = profile.diamonds
		success = PotionService.purchaseUpgrade(player, upgradeRequest("Duration"))
		expect(success):toBeFalse()
		expect(profile.diamonds):toBe(before)
		expect(profile.potionUpgrades.durationLevel):toBe(0)
		expect(#currencyEvents):toBe(1)
	end)

	it("defaults selection empty and requires the owned Auto-Drink upgrade", function()
		resetState()
		expect(PotionService.getState(player).autoDrinkSelection):toEqual({})
		local success = PotionService.setAutoDrinkSelection(player, selectionRequest("ShinyPotion", true))
		expect(success):toBeFalse()
		expect(profile.autoDrinkSelection):toEqual({})
		expect(PotionService.purchaseUpgrade(player, upgradeRequest("AutoDrink"))):toBeTrue()
		expect(PotionService.getState(player).upgradeOffers.AutoDrink):toBeNil()
		expect(PotionService.setAutoDrinkSelection(player, selectionRequest("LuckPotion", true))):toBeTrue()
		expect(profile.autoDrinkSelection):toEqual({ LuckPotion = true })
		expect(profile.autoDrinkSelection.ShinyPotion):toBeNil()
	end)

	it("Auto-Drinks Shiny only at zero charges and never preselects it", function()
		resetState()
		profile.potionUpgrades.autoDrink = true
		profile.autoDrinkSelection.ShinyPotion = true
		profile.potionInventory.ShinyPotion = 2
		profile.activeBuffs.shinyChance = { charges = 1 }
		expect(PotionService.processAutoDrink(player)):toBeFalse()
		expect(profile.potionInventory.ShinyPotion):toBe(2)
		profile.activeBuffs.shinyChance = nil
		expect(PotionService.processAutoDrink(player)):toBeTrue()
		expect(profile.potionInventory.ShinyPotion):toBe(1)
		expect(profile.activeBuffs.shinyChance):toEqual({ charges = 3 })
	end)

	it("consumes selected missing sources online in deterministic catalog order only", function()
		resetState()
		profile.potionUpgrades.autoDrink = true
		profile.autoDrinkSelection = { LuckPotion = true, MegaLuckPotion = true, ShinyPotion = false }
		profile.potionInventory = { LuckPotion = 2, MegaLuckPotion = 2, ShinyPotion = 2 }
		local order = {}
		PotionService._transactionHook = function(stage, context)
			if stage == "afterInventory" and context.origin == "auto" then
				table.insert(order, context.potionId)
			end
		end
		expect(PotionService.processAutoDrink(player)):toBeTrue()
		expect(order):toEqual({ "LuckPotion", "MegaLuckPotion" })
		expect(profile.potionInventory.LuckPotion):toBe(1)
		expect(profile.potionInventory.MegaLuckPotion):toBe(1)
		expect(profile.potionInventory.ShinyPotion):toBe(2)
		expect(PotionService.processAutoDrink(player)):toBeFalse()
		fakeTime = 1601
		expect(PotionService.processAutoDrink(player)):toBeTrue()
		expect(profile.potionInventory.LuckPotion):toBeNil()
		expect(profile.potionInventory.MegaLuckPotion):toBeNil()
	end)
end)

describe("PotionService QOF-14 Shiny hatch reservations", function()
	it("reserves at most the batch size and restores the exact charge state", function()
		resetState()
		profile.activeBuffs.shinyChance = { charges = 5 }
		local handle, reserved = PotionService.beginShinyChargeTransaction(player, 3)
		expect(reserved):toBe(3)
		expect(profile.activeBuffs.shinyChance.charges):toBe(2)
		expect(PotionService.rollbackShinyChargeTransaction(handle)):toBeTrue()
		expect(profile.activeBuffs.shinyChance):toEqual({ charges = 5 })
	end)

	it("commits reserved charges and emits authoritative state", function()
		resetState()
		profile.activeBuffs.shinyChance = { charges = 2 }
		local handle, reserved = PotionService.beginShinyChargeTransaction(player, 5)
		expect(reserved):toBe(2)
		expect(profile.activeBuffs.shinyChance):toBeNil()
		expect(PotionService.commitShinyChargeTransaction(handle)):toBeTrue()
		expect(#stateEvents):toBe(1)
		expect(stateEvents[1].activeBuffs.shinyChance):toBeNil()
	end)

	it("publishes monotonic revisions for mutation, purchase, and charge snapshots", function()
		resetState()
		expect(PotionService.getState(player).stateRevision):toBe(0)
		profile.potionInventory.LuckPotion = 1
		local success, _, consumedState = PotionService.consume(player, consumeRequest("LuckPotion"))
		expect(success):toBeTrue()
		expect(consumedState.stateRevision):toBe(1)
		expect(PotionService.getState(player).stateRevision):toBe(1)
		profile.potionInventory.SpeedPotion = 1
		local purchaseState = PotionService.notifyInventoryChanged(player)
		expect(purchaseState.stateRevision):toBe(2)
	end)

	it("uses strict versioned DTOs and reconciles expiry with speed refresh", function()
		resetState()
		profile.potionInventory.SpeedPotion = 1
		expect(PotionService.consume(player, {
			contractVersion = 1,
			action = "consumePotion",
			potionId = "SpeedPotion",
			extra = true,
		})):toBeFalse()
		expect(profile.potionInventory.SpeedPotion):toBe(1)
		expect(PotionService.consume(player, consumeRequest("SpeedPotion"))):toBeTrue()
		fakeTime = 1301
		expect(PotionService.reconcilePlayer(player, false)):toBeTrue()
		expect(profile.activeBuffs.speed):toBeNil()
		expect(refreshCalls):toBe(2)
	end)
end)

os.time = originalTime
