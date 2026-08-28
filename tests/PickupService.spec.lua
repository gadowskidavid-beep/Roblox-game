local originalRequire = require
local BalanceConfig = originalRequire("src/ReplicatedStorage/Shared/BalanceConfig")

local function newSignal()
	local signal = { listeners = {} }
	function signal:Connect(callback)
		local connection = { Connected = true }
		function connection:Disconnect() self.Connected = false end
		table.insert(self.listeners, { callback = callback, connection = connection })
		return connection
	end
	function signal:Fire(...)
		for _, entry in ipairs(self.listeners) do
			if entry.connection.Connected then entry.callback(...) end
		end
	end
	return signal
end

local function vector(x, y, z)
	local value = { X = x, Y = y, Z = z, Magnitude = math.sqrt(x * x + y * y + z * z) }
	return setmetatable(value, {
		__sub = function(a, b)
			return vector(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
		end,
	})
end

local collected = {}
local collectEvent = {}
function collectEvent:FireClient(player, position, amount, currencyType)
	table.insert(collected, { player = player, position = position, amount = amount, currencyType = currencyType })
end
local remotes = {}
function remotes:FindFirstChild(name)
	if name == "CollectCurrency" then return collectEvent end
	return nil
end
local replicatedStorage = { Shared = { BalanceConfig = BalanceConfig } }
function replicatedStorage:FindFirstChild(name)
	if name == "Remotes" then return remotes end
	return nil
end
local runService = { Heartbeat = newSignal() }
local pickupFolder = { Name = "CurrencyPickups" }
local workspaceMock = {}
function workspaceMock:FindFirstChild(name)
	if name == "CurrencyPickups" then return pickupFolder end
	return nil
end
local players = {}
function players:GetPlayerByUserId() return nil end
local httpService = {}
function httpService:GenerateGUID() return "unused" end
local gameMock = { ReplicatedStorage = replicatedStorage }
function gameMock:GetService(name)
	if name == "Players" then return players end
	if name == "ReplicatedStorage" then return replicatedStorage end
	if name == "RunService" then return runService end
	if name == "Workspace" then return workspaceMock end
	if name == "HttpService" then return httpService end
	error("Unexpected service: " .. tostring(name))
end
rawset(_G, "game", gameMock)

local function mockRequire(path)
	if path == BalanceConfig then return BalanceConfig end
	return originalRequire(path)
end
rawset(_G, "require", mockRequire)
local PickupService = originalRequire("src/ServerScriptService/Services/PickupService")
rawset(_G, "require", originalRequire)

local now = 0
local guidCounter = 0
local credited = {}
local fallbackCredits = {}
local profiles = {}
local creditShouldFail = false
local fallbackShouldFail = false
local questUpdates = {}
local destroyedVisuals = 0
local masteryMultiplier = 0
local treeMultiplier = 1
local dataService = {}
function dataService.getPlayerData(player)
	return profiles[player.UserId]
end
local currencyService = {}
function currencyService.creditResolvedReward(player, currency, amount)
	if creditShouldFail then return false end
	table.insert(credited, { player = player, currency = currency, amount = amount })
	return true
end
function currencyService.creditResolvedRewardToProfile(profile, currency, amount)
	if fallbackShouldFail or not profile then return false end
	profile[currency] = profile[currency] + amount
	table.insert(fallbackCredits, { currency = currency, amount = amount })
	return true
end
local questService = {}
function questService.incrementStat(player, stat, amount)
	table.insert(questUpdates, { player = player, stat = stat, amount = amount })
end
local masteryService = {}
function masteryService.getBuffBonus(_, id)
	if id == "DropMagnet" then return masteryMultiplier end
	return 0
end
local upgradeTreeService = {}
function upgradeTreeService.getEntitlements()
	return { magnetRangeMultiplier = treeMultiplier }
end

local function newPlayer(userId, rootPosition)
	profiles[userId] = profiles[userId] or { coins = 0, diamonds = 0 }
	local humanoid = { Health = 100 }
	local root = { Position = rootPosition }
	local character = {}
	function character:FindFirstChild(name)
		if name == "HumanoidRootPart" then return root end
		return nil
	end
	function character:FindFirstChildOfClass(className)
		if className == "Humanoid" then return humanoid end
		return nil
	end
	return { UserId = userId, Parent = {}, Character = character, _root = root }
end

local function resetState()
	now = 0
	guidCounter = 0
	credited = {}
	fallbackCredits = {}
	profiles = {}
	collected = {}
	questUpdates = {}
	destroyedVisuals = 0
	creditShouldFail = false
	fallbackShouldFail = false
	masteryMultiplier = 0
	treeMultiplier = 1
	PickupService.init(dataService, currencyService, questService, masteryService, upgradeTreeService, {
		runService = runService,
		workspace = workspaceMock,
		clock = function() return now end,
		guid = function()
			guidCounter = guidCounter + 1
			return "pickup-" .. tostring(guidCounter)
		end,
		visualFactory = function()
			local visual = {}
			function visual:Destroy()
				destroyedVisuals = destroyedVisuals + 1
			end
			return visual
		end,
	})
end

describe("PickupService QOF-12 server claims", function()
	it("composes tree and DropMagnet range with a 32-stud cap", function()
		resetState()
		local player = newPlayer(1, vector(0, 0, 0))
		expect(PickupService.getCollectionRadius(player)):toBe(8)
		treeMultiplier = 2
		masteryMultiplier = 3
		expect(PickupService.getCollectionRadius(player)):toBe(32)
		treeMultiplier = 0 / 0
		masteryMultiplier = -1
		expect(PickupService.getCollectionRadius(player)):toBe(8)
	end)

	it("credits only its owner inside the authoritative radius", function()
		resetState()
		local owner = newPlayer(1, vector(0, 0, 0))
		local other = newPlayer(2, vector(0, 0, 0))
		local created, pickupId = PickupService.createPickup(owner, "coins", 125, vector(9, 0, 0))
		expect(created):toBeTrue()
		expect(PickupService.claimPickup(other, pickupId)):toBeFalse()
		expect(PickupService.claimPickup(owner, pickupId)):toBeFalse()
		expect(#credited):toBe(0)

		treeMultiplier = 1.25
		expect(PickupService.claimPickup(owner, pickupId)):toBeTrue()
		expect(credited[1]):toEqual({ player = owner, currency = "coins", amount = 125 })
		expect(questUpdates[1]):toEqual({ player = owner, stat = "earnCoins", amount = 125 })
		expect(collected[1].currencyType):toBe("Coins")
		expect(PickupService.getPendingCount(owner)):toBe(0)
		expect(destroyedVisuals):toBe(1)
	end)

	it("makes duplicate and concurrent-style claims idempotent", function()
		resetState()
		local owner = newPlayer(1, vector(0, 0, 0))
		local _, pickupId = PickupService.createPickup(owner, "diamonds", 20, vector(1, 0, 0))
		expect(PickupService.claimPickup(owner, pickupId)):toBeTrue()
		expect(PickupService.claimPickup(owner, pickupId)):toBeFalse()
		expect(#credited):toBe(1)
		expect(#collected):toBe(1)
		expect(#questUpdates):toBe(0)
	end)

	it("keeps a failed credit pending and retries safely", function()
		resetState()
		local owner = newPlayer(1, vector(0, 0, 0))
		local _, pickupId = PickupService.createPickup(owner, "coins", 10, vector(1, 0, 0))
		creditShouldFail = true
		expect(PickupService.claimPickup(owner, pickupId)):toBeFalse()
		expect(PickupService.getPendingCount(owner)):toBe(1)
		creditShouldFail = false
		expect(PickupService.claimPickup(owner, pickupId)):toBeTrue()
		expect(#credited):toBe(1)
	end)

	it("preserves leave records until exact persistence fallback succeeds", function()
		resetState()
		local owner = newPlayer(1, vector(0, 0, 0))
		PickupService.createPickup(owner, "coins", 15, vector(20, 0, 0))
		creditShouldFail = true
		fallbackShouldFail = true
		expect(PickupService.onPlayerRemoving(owner)):toBeFalse()
		expect(PickupService.getPendingCount(owner)):toBe(1)
		expect(destroyedVisuals):toBe(0)

		fallbackShouldFail = false
		expect(PickupService.settlePlayer(owner)):toBeTrue()
		expect(PickupService.getPendingCount(owner)):toBe(0)
		expect(profiles[owner.UserId].coins):toBe(15)
		expect(destroyedVisuals):toBe(1)
	end)

	it("settles expired and leaving-player pickups exactly once", function()
		resetState()
		local owner = newPlayer(1, vector(100, 0, 0))
		PickupService.createPickup(owner, "coins", 10, vector(0, 0, 0))
		now = 15
		runService.Heartbeat:Fire(0.2)
		expect(#credited):toBe(1)

		PickupService.createPickup(owner, "diamonds", 5, vector(0, 0, 0))
		creditShouldFail = true
		expect(PickupService.onPlayerRemoving(owner)):toBeTrue()
		expect(#credited):toBe(1)
		expect(#fallbackCredits):toBe(1)
		expect(profiles[owner.UserId].diamonds):toBe(5)
		expect(PickupService.getPendingCount(owner)):toBe(0)
		expect(#collected):toBe(1)
	end)

	it("rejects malformed pickup creation without registry mutation", function()
		resetState()
		local owner = newPlayer(1, vector(0, 0, 0))
		expect(PickupService.createPickup(owner, "gems", 10, vector(0, 0, 0))):toBeFalse()
		expect(PickupService.createPickup(owner, "coins", 0, vector(0, 0, 0))):toBeFalse()
		expect(PickupService.createPickup(owner, "coins", 1.5, vector(0, 0, 0))):toBeFalse()
		expect(PickupService.getPendingCount(owner)):toBe(0)
	end)
end)
