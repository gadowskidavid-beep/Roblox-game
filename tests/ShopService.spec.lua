-- ShopService.spec.lua - QOF-10 dormant Auto-Hatch gate regressions.

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
local replicatedStorage = {
	Shared = {
		PetData = PetData,
		Config = Config,
		BalanceConfig = BalanceConfig,
		ShopData = ShopData,
	},
}
function replicatedStorage:FindFirstChild()
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
local charged = 0
local hatchCalls = 0
local dataService = {}
function dataService.getPlayerData()
	return profile
end
local currencyService = {}
function currencyService.removeDiamonds(_, amount)
	charged = charged + amount
	return true
end
local eggService = {}
function eggService.purchaseAndHatch()
	hatchCalls = hatchCalls + 1
end

local function resetState()
	profile = { shopPurchases = { extraEquipSlots = 0 }, unlockedZones = { 1 } }
	charged = 0
	hatchCalls = 0
	ShopService._activeBuffs = {}
	ShopService.init(dataService, currencyService)
	ShopService.setEggService(eggService)
end

describe("ShopService QOF-10 Auto-Hatch gate", function()
	it("removes Auto-Hatch from both shared catalog surfaces", function()
		expect(BalanceConfig.Shop.AutoHatchRuntimeEnabled):toBeFalse()
		expect(ShopData.Items.AutoHatch):toBeNil()
		for _, itemId in ipairs(ShopData.Order) do
			if itemId == "AutoHatch" then
				error("AutoHatch leaked into ShopData.Order")
			end
		end
	end)

	it("rejects direct Auto-Hatch purchases without charging", function()
		resetState()
		local success, message = ShopService.purchaseItem(player, "AutoHatch")
		expect(success):toBeFalse()
		expect(message):toBe("Auto-Hatch is not available yet")
		expect(charged):toBe(0)
		expect(ShopService._activeBuffs[player.UserId]):toBeNil()
	end)

	it("never processes even a stale in-memory Auto-Hatch buff", function()
		resetState()
		ShopService._activeBuffs[player.UserId] = { autoHatch = os.clock() + 600 }
		expect(ShopService._processAutoHatch()):toBeFalse()
		expect(hatchCalls):toBe(0)
	end)

	it("keeps other shop purchases unchanged", function()
		resetState()
		local success, message = ShopService.purchaseItem(player, "ExtraEquipSlot")
		expect(success):toBeTrue()
		expect(message):toBeNil()
		expect(charged):toBe(1000)
		expect(profile.shopPurchases.extraEquipSlots):toBe(1)
	end)
end)
