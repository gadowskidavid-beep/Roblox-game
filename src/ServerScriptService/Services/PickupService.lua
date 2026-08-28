--[[
	PickupService.lua - Server-owned transient currency pickup and claim layer.
	QOF-12 snapshots earned reward bonuses at destruction time, then credits each
	owner exactly once after authoritative proximity, timeout, or leave settlement.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local BalanceConfig = require(game.ReplicatedStorage.Shared.BalanceConfig)

local PickupService = {}

PickupService._dataService = nil
PickupService._currencyService = nil
PickupService._questService = nil
PickupService._masteryService = nil
PickupService._upgradeTreeService = nil
PickupService._players = Players
PickupService._runService = RunService
PickupService._clock = os.clock
PickupService._guid = function()
	return HttpService:GenerateGUID(false)
end
PickupService._visualFactory = nil
PickupService._folder = nil
PickupService._records = {}
PickupService._ownerIds = {}
PickupService._heartbeatConnection = nil
PickupService._accumulator = 0

local VALID_CURRENCIES = {
	coins = true,
	diamonds = true,
}

local function finiteNumber(value)
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
end

local function normalizedMultiplier(value)
	if not finiteNumber(value) or value <= 1 then
		return 1
	end
	return value
end

local function defaultVisualFactory(record, folder)
	local part = Instance.new("Part")
	part.Name = record.currency == "coins" and "CoinPickup" or "DiamondPickup"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1.5, 1.5, 1.5)
	part.Position = record.position
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Material = Enum.Material.Neon
	part.Color = record.currency == "coins"
		and Color3.fromRGB(255, 221, 61)
		or Color3.fromRGB(65, 205, 255)
	part:SetAttribute("PickupId", record.id)
	part:SetAttribute("OwnerUserId", record.ownerUserId)
	part.Parent = folder
	return part
end

local function removeOwnerId(ownerUserId, pickupId)
	local ids = PickupService._ownerIds[ownerUserId]
	if not ids then
		return
	end
	for index, id in ipairs(ids) do
		if id == pickupId then
			table.remove(ids, index)
			break
		end
	end
	if #ids == 0 then
		PickupService._ownerIds[ownerUserId] = nil
	end
end

local function removeRecord(record)
	PickupService._records[record.id] = nil
	removeOwnerId(record.ownerUserId, record.id)
	if record.visual then
		pcall(function()
			record.visual:Destroy()
		end)
		record.visual = nil
	end
end

local function fireCollected(record)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local event = remotes and remotes:FindFirstChild("CollectCurrency")
	if event then
		event:FireClient(
			record.player,
			record.position,
			record.amount,
			record.currency == "coins" and "Coins" or "Diamonds"
		)
	end
end

function PickupService.getCollectionRadius(player)
	local settings = BalanceConfig.CoreUpgrades.PickupCollection
	local treeMultiplier = 1
	if PickupService._upgradeTreeService then
		local entitlements = PickupService._upgradeTreeService.getEntitlements(player)
		if type(entitlements) == "table" then
			treeMultiplier = entitlements.magnetRangeMultiplier
		end
	end

	local masteryMultiplier = 1
	if PickupService._masteryService then
		masteryMultiplier = PickupService._masteryService.getBuffBonus(player, "DropMagnet")
	end

	local radius = settings.BaseRadius
		* normalizedMultiplier(treeMultiplier)
		* normalizedMultiplier(masteryMultiplier)
	return math.min(math.max(radius, settings.BaseRadius), settings.MaxRadius)
end

local function isWithinCollectionRadius(record)
	local player = record.player
	if not player or player.Parent == nil then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and finiteNumber(humanoid.Health) and humanoid.Health <= 0 then
		return false
	end
	local ok, distance = pcall(function()
		return (root.Position - record.position).Magnitude
	end)
	return ok and finiteNumber(distance) and distance <= PickupService.getCollectionRadius(player)
end

local function commitRecord(record, notifyClient)
	-- Remove authority before non-critical notifications so callback failure can
	-- never make an exact credited reward claimable twice.
	record.state = "claimed"
	removeRecord(record)
	if record.currency == "coins" and PickupService._questService then
		pcall(function()
			PickupService._questService.incrementStat(record.player, "earnCoins", record.amount)
		end)
	end
	if notifyClient then
		pcall(fireCollected, record)
	end
	return true, record.amount
end

local function settleRecord(record)
	if not record or record.state ~= "pending" then
		return false, "Pickup is not pending"
	end
	record.state = "claiming"
	local credited = PickupService._currencyService.creditResolvedReward(
		record.player,
		record.currency,
		record.amount
	)
	if not credited then
		record.state = "pending"
		return false, "Credit failed"
	end
	return commitRecord(record, true)
end

local function settleRecordForPersistence(record)
	local settled = settleRecord(record)
	if settled == true then
		return true
	end
	if not record or record.state ~= "pending" or not PickupService._dataService then
		return false
	end
	local data = PickupService._dataService.getPlayerData(record.player)
	record.state = "claiming"
	local credited = PickupService._currencyService.creditResolvedRewardToProfile(
		data,
		record.currency,
		record.amount
	)
	if not credited then
		record.state = "pending"
		return false
	end
	return commitRecord(record, false)
end

function PickupService.claimPickup(player, pickupId)
	if not player or type(pickupId) ~= "string" or #pickupId == 0 or #pickupId > 64 then
		return false, "Invalid pickup"
	end
	local record = PickupService._records[pickupId]
	if not record or record.player ~= player or record.ownerUserId ~= player.UserId then
		return false, "Pickup unavailable"
	end
	if not isWithinCollectionRadius(record) then
		return false, "Pickup out of range"
	end
	return settleRecord(record)
end

function PickupService.createPickup(player, currency, amount, position)
	if not player
		or VALID_CURRENCIES[currency] ~= true
		or not finiteNumber(amount)
		or amount <= 0
		or amount % 1 ~= 0
		or position == nil then
		return false, "Invalid pickup"
	end
	local ownerUserId = player.UserId
	if type(ownerUserId) ~= "number" then
		return false, "Invalid owner"
	end

	local settings = BalanceConfig.CoreUpgrades.PickupCollection
	local ids = PickupService._ownerIds[ownerUserId]
	if ids and #ids >= settings.MaxPendingPerPlayer then
		local oldest = PickupService._records[ids[1]]
		local settled = oldest and settleRecord(oldest)
		if settled ~= true then
			return false, "Pending pickup limit reached"
		end
	end

	local pickupId = PickupService._guid()
	if type(pickupId) ~= "string" or #pickupId == 0 or #pickupId > 64 or PickupService._records[pickupId] then
		return false, "Pickup ID unavailable"
	end
	local now = PickupService._clock()
	local record = {
		id = pickupId,
		player = player,
		ownerUserId = ownerUserId,
		currency = currency,
		amount = amount,
		position = position,
		createdAt = now,
		expiresAt = now + settings.LifetimeSeconds,
		state = "pending",
		visual = nil,
	}
	PickupService._records[pickupId] = record
	PickupService._ownerIds[ownerUserId] = PickupService._ownerIds[ownerUserId] or {}
	table.insert(PickupService._ownerIds[ownerUserId], pickupId)

	local factory = PickupService._visualFactory or defaultVisualFactory
	local visualOk, visual = pcall(factory, record, PickupService._folder)
	if visualOk then
		record.visual = visual
	end
	return true, pickupId
end

function PickupService.step(deltaTime)
	local settings = BalanceConfig.CoreUpgrades.PickupCollection
	PickupService._accumulator = PickupService._accumulator
		+ (finiteNumber(deltaTime) and math.max(deltaTime, 0) or settings.PollIntervalSeconds)
	if PickupService._accumulator < settings.PollIntervalSeconds then
		return false
	end
	PickupService._accumulator = PickupService._accumulator % settings.PollIntervalSeconds

	local now = PickupService._clock()
	local pending = {}
	for _, record in pairs(PickupService._records) do
		if record.state == "pending" then
			table.insert(pending, record)
		end
	end
	for _, record in ipairs(pending) do
		if PickupService._records[record.id] == record then
			if now >= record.expiresAt then
				settleRecord(record)
			elseif isWithinCollectionRadius(record) then
				settleRecord(record)
			end
		end
	end
	return true
end

function PickupService.getPendingCount(player)
	local ids = player and PickupService._ownerIds[player.UserId]
	return ids and #ids or 0
end

function PickupService.settlePlayer(player)
	if not player then
		return false
	end
	local ids = PickupService._ownerIds[player.UserId]
	if not ids then
		return true
	end
	local snapshot = {}
	for _, id in ipairs(ids) do
		table.insert(snapshot, id)
	end
	local allSettled = true
	for _, id in ipairs(snapshot) do
		local record = PickupService._records[id]
		if record and settleRecordForPersistence(record) ~= true then
			-- Keep authority and the exact amount pending. A later leave/shutdown
			-- retry may settle it; deleting here would silently lose earned value.
			allSettled = false
		end
	end
	return allSettled
end

function PickupService.onPlayerRemoving(player)
	return PickupService.settlePlayer(player)
end

function PickupService.settleAllPlayers()
	local allSettled = true
	for _, player in ipairs(PickupService._players:GetPlayers()) do
		if not PickupService.settlePlayer(player) then
			allSettled = false
		end
	end
	return allSettled
end

function PickupService.init(dataService, currencyService, questService, masteryService, upgradeTreeService, options)
	options = type(options) == "table" and options or {}
	PickupService._dataService = dataService
	PickupService._currencyService = currencyService
	PickupService._questService = questService
	PickupService._masteryService = masteryService
	PickupService._upgradeTreeService = upgradeTreeService
	PickupService._players = options.players or Players
	PickupService._runService = options.runService or RunService
	PickupService._clock = options.clock or os.clock
	PickupService._guid = options.guid or function()
		return HttpService:GenerateGUID(false)
	end
	PickupService._visualFactory = options.visualFactory
	PickupService._records = {}
	PickupService._ownerIds = {}
	PickupService._accumulator = 0

	if PickupService._heartbeatConnection then
		PickupService._heartbeatConnection:Disconnect()
	end
	local parent = options.workspace or Workspace
	local folder = parent:FindFirstChild("CurrencyPickups")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "CurrencyPickups"
		folder.Parent = parent
	end
	PickupService._folder = folder
	PickupService._heartbeatConnection = PickupService._runService.Heartbeat:Connect(function(deltaTime)
		PickupService.step(deltaTime)
	end)
end

return PickupService
