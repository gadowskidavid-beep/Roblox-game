-- ProfileTransactionService.spec.lua - QOF-25 central profile owner contract.

local ProfileTransactionService = require("src/ServerScriptService/Services/ProfileTransactionService")

local profiles = {}
local admissionOpen = {}
local saving = {}
local dataService = {}
function dataService.getPlayerData(player)
	return profiles[player.UserId]
end
function dataService.isMutationAdmissionOpen(player)
	return admissionOpen[player.UserId] == true
end
function dataService.isProfileSaveInProgress(player)
	return saving[player.UserId] == true
end

local function player(userId)
	return { UserId = userId }
end

local function reset()
	profiles = {
		[1] = { coins = 100 },
		[2] = { coins = 200 },
	}
	admissionOpen = { [1] = true, [2] = true }
	saving = {}
	ProfileTransactionService.init(dataService)
end

describe("ProfileTransactionService QOF-25 ownership", function()
	it("serializes one exact owner per profile while isolating other profiles", function()
		reset()
		local first = player(1)
		local second = player(2)
		local owner = ProfileTransactionService.begin(first, "ShopService")
		expect(type(owner)):toBe("table")
		expect(ProfileTransactionService.getOwnerName(first)):toBe("ShopService")
		expect(ProfileTransactionService.begin(first, "UpgradeTreeService")):toBeNil()
		local independent = ProfileTransactionService.begin(second, "EggService")
		expect(type(independent)):toBe("table")
		expect(ProfileTransactionService.commit(owner)):toBeTrue()
		expect(ProfileTransactionService.commit(independent)):toBeTrue()
	end)

	it("rejects admission and save races before registering an owner", function()
		reset()
		local first = player(1)
		admissionOpen[1] = false
		expect(ProfileTransactionService.begin(first, "Closed")):toBeNil()
		admissionOpen[1] = true
		saving[1] = true
		expect(ProfileTransactionService.begin(first, "Saving")):toBeNil()
		expect(ProfileTransactionService.hasPending(first)):toBeFalse()
	end)

	it("closes new admission without invalidating a retryable owner", function()
		reset()
		local first = player(1)
		local owner = ProfileTransactionService.begin(first, "MachineService")
		local attempts = 0
		expect(ProfileTransactionService.setSettler(owner, function()
			attempts = attempts + 1
			return attempts >= 2
		end)):toBeTrue()
		expect(ProfileTransactionService.closeAdmission(first)):toBeTrue()
		expect(ProfileTransactionService.begin(first, "Late")):toBeNil()
		expect(ProfileTransactionService.settlePlayer(first)):toBeFalse()
		expect(ProfileTransactionService.hasPending(first)):toBeTrue()
		expect(ProfileTransactionService.settlePlayer(first)):toBeTrue()
		expect(ProfileTransactionService.hasPending(first)):toBeFalse()
		expect(ProfileTransactionService.isAdmissionOpen(first)):toBeFalse()
	end)

	it("requires exact opaque identity and keeps terminal operations idempotent", function()
		reset()
		local first = player(1)
		local owner = ProfileTransactionService.begin(first, "EnchantingService")
		expect(ProfileTransactionService.commit({ userId = 1 })):toBeFalse()
		expect(ProfileTransactionService.hasPending(first)):toBeTrue()
		expect(ProfileTransactionService.commit(owner)):toBeTrue()
		expect(ProfileTransactionService.commit(owner)):toBeFalse()
		expect(ProfileTransactionService.rollback(owner)):toBeFalse()
	end)

	it("retains a throwing settler and retries it later", function()
		reset()
		local first = player(1)
		local owner = ProfileTransactionService.begin(first, "AutoHatchService")
		local shouldThrow = true
		ProfileTransactionService.setSettler(owner, function()
			if shouldThrow then error("injected rollback failure") end
			return true
		end)
		expect(ProfileTransactionService.rollback(owner)):toBeFalse()
		expect(ProfileTransactionService.hasPending(first)):toBeTrue()
		shouldThrow = false
		expect(ProfileTransactionService.rollback(owner)):toBeTrue()
		expect(ProfileTransactionService.hasPending(first)):toBeFalse()
	end)
end)
