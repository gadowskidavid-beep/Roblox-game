--[[
	Main.server.lua - Server entry point for Battle Pets
	Initializes all services, creates RemoteEvents/RemoteFunctions,
	and connects player lifecycle events.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Require all services
local DataService = require(script.Parent.Services.DataService)
local CurrencyService = require(script.Parent.Services.CurrencyService)
local UpgradeService = require(script.Parent.Services.UpgradeService)
local PetService = require(script.Parent.Services.PetService)
local MachineService = require(script.Parent.Services.MachineService)
local MachineAuthorityBootstrap = require(script.Parent.Services.MachineAuthorityBootstrap)
local ZoneService = require(script.Parent.Services.ZoneService)
local CampaignService = require(script.Parent.Services.CampaignService)
local EggService = require(script.Parent.Services.EggService)
local QuestService = require(script.Parent.Services.QuestService)
local MasteryService = require(script.Parent.Services.MasteryService)
local ShopService = require(script.Parent.Services.ShopService)
local PotionService = require(script.Parent.Services.PotionService)
local UpgradeTreeService = require(script.Parent.Services.UpgradeTreeService)
local MovementService = require(script.Parent.Services.MovementService)
local PickupService = require(script.Parent.Services.PickupService)
local BalanceConfig = require(ReplicatedStorage.Shared.BalanceConfig)

----------------------------------------------
-- Central Rate Limiter
----------------------------------------------

local rateLimits = {}
local burstLimits = {}
local function canCall(player, action, cooldown)
	rateLimits[player.UserId] = rateLimits[player.UserId] or {}
	local now = os.clock()
	local last = rateLimits[player.UserId][action] or 0
	if now - last < cooldown then
		return false
	end
	rateLimits[player.UserId][action] = now
	return true
end

local function canCallBurst(player, action, maxCalls, windowSeconds)
	burstLimits[player.UserId] = burstLimits[player.UserId] or {}
	local now = os.clock()
	local bucket = burstLimits[player.UserId][action]
	if not bucket or now - bucket.startedAt >= windowSeconds then
		burstLimits[player.UserId][action] = { startedAt = now, count = 1 }
		return true
	end
	if bucket.count >= maxCalls then
		return false
	end
	bucket.count = bucket.count + 1
	return true
end

local function isValidIdentifier(value)
	return type(value) == "string" and #value > 0 and #value <= 64
end

local function isValidMachinePetIdList(petInstanceIds)
	if type(petInstanceIds) ~= "table" or getmetatable(petInstanceIds) ~= nil then
		return false
	end
	local count = 0
	for key in next, petInstanceIds do
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 then
			return false
		end
		count = count + 1
		if count > BalanceConfig.Machines.MaxInputs then
			return false
		end
	end
	if count < BalanceConfig.Machines.MinInputs
		or count > BalanceConfig.Machines.MaxInputs
		or rawlen(petInstanceIds) ~= count then
		return false
	end
	for index = 1, count do
		local petId = rawget(petInstanceIds, index)
		if type(petId) ~= "string" or petId == "" or #petId > 128 then
			return false
		end
	end
	return true
end

local function isValidShopPurchaseRequest(request)
	if type(request) == "string" then
		-- ExtraEquipSlot is the sole legacy purchase contract. AutoHatch is
		-- admitted only so ShopService can return its specific dormant gate.
		return request == "ExtraEquipSlot" or request == "AutoHatch"
	end
	if type(request) ~= "table" then
		return false
	end
	local fieldCount = 0
	for key in pairs(request) do
		if key ~= "contractVersion" and key ~= "action" and key ~= "itemId" and key ~= "quantity" then
			return false
		end
		fieldCount = fieldCount + 1
	end
	return fieldCount == 4
		and request.contractVersion == 2
		and request.action == "purchasePotion"
		and isValidIdentifier(request.itemId)
		and request.quantity == 1
end

----------------------------------------------
-- Create Remotes Folder in ReplicatedStorage
----------------------------------------------

local remotesFolder = Instance.new("Folder")
remotesFolder.Name = "Remotes"
remotesFolder.Parent = ReplicatedStorage

-- Create all RemoteEvents
local remoteEvents = {
	"CurrencyUpdated",
	"PetInventoryUpdated",
	"PetEquipped",
	"PetUnequipped",
	"ZoneUnlocked",
	"HideGateBarrier",
	"DestructibleDamaged",
	"DestructibleDestroyed",
	"EggHatchStart",
	"EggHatchResult",
	"CampaignBattleUpdate",
	"CampaignVictory",
	"CampaignDefeat",
	"UpgradeUpdated",
	"CollectCurrency",
	"XPUpdated",
	"QuestProgressUpdated",
	"MasteryUpdated",
	"ShopBuffsUpdated",
	"PotionStateUpdated",
	"UpgradeTreeUpdated",
}

for _, eventName in ipairs(remoteEvents) do
	local event = Instance.new("RemoteEvent")
	event.Name = eventName
	event.Parent = remotesFolder
end

-- Create all RemoteFunctions
local remoteFunctions = {
	"HatchEgg",
	"GetHatchPurchaseOptions",
	"SetHatchBatchSize",
	"EquipPet",
	"UnequipPet",
	"DeletePet",
	"DeletePets",
	"SetPetFavorite",
	"UnlockZone",
	"PurchaseUpgrade",
	"GetPlayerData",
	"StartCampaignLevel",
	"DeployPetInCampaign",
	"AttackDestructible",
	"ClickAttackDestructible",
	"CritAttackDestructible",
	"GetQuestProgress",
	"PurchaseMasteryBuff",
	"GetMasteryState",
	-- Rolling-client compatibility only. Its handler is permanently fail-closed.
	"ConvertToGoldenPet",
	"UseMachine",
	"AssignPetTarget",
	"GetDiscoveredPets",
	"PurchaseShopItem",
	"GetShopBuffs",
	"GetPotionState",
	"ConsumePotion",
	"PurchasePotionUpgrade",
	"SetAutoDrinkSelection",
	"PurchaseTreeUpgrade",
	"GetUpgradeTreeState",
}

for _, funcName in ipairs(remoteFunctions) do
	local func = Instance.new("RemoteFunction")
	func.Name = funcName
	func.Parent = remotesFolder
end

----------------------------------------------
-- Initialize Services (order matters for dependencies)
----------------------------------------------

-- Init currency first (with nil upgradeService, we set it after)
CurrencyService.init(DataService, nil)
UpgradeService.init(DataService, CurrencyService)
-- Now set the upgrade reference for CurrencyService
CurrencyService._upgradeService = UpgradeService

-- Initialize quest and mastery services
QuestService.init(DataService, CurrencyService)
MasteryService.init(DataService)
ShopService.init(DataService, CurrencyService)
PotionService.init(DataService, CurrencyService)
ShopService.setPotionService(PotionService)
UpgradeTreeService.init(DataService, CurrencyService)
PickupService.init(DataService, CurrencyService, QuestService, MasteryService, UpgradeTreeService)

-- Set cross-references
UpgradeService.setQuestService(QuestService)
UpgradeService.setMasteryService(MasteryService)

PetService.init(DataService, CurrencyService, UpgradeService)
PetService.setMasteryService(MasteryService)
PetService.setShopService(ShopService)
PetService.setUpgradeTreeService(UpgradeTreeService)
MachineService.init(DataService, CurrencyService, PetService)
MachineService.setQuestService(QuestService)
EggService.init(DataService, CurrencyService, PetService, UpgradeTreeService)
EggService.setQuestService(QuestService)
EggService.setPotionService(PotionService)
ShopService.setEggService(EggService)

-- World generation should not prevent remotes, player data, and the GUI from
-- starting if a future world builder fails. The current failure is still logged
-- with a traceback so it is visible in the Roblox Studio server output.
local zoneInitSucceeded, activationValidatorOrError = xpcall(function()
	return ZoneService.init(DataService, CurrencyService, PetService)
end, debug.traceback)
if not zoneInitSucceeded then
	warn("[Battle Pets] ZoneService failed to initialize:\n" .. tostring(activationValidatorOrError))
elseif not MachineAuthorityBootstrap.install(
	MachineService,
	zoneInitSucceeded,
	activationValidatorOrError
) then
	warn("[Battle Pets] ZoneService did not provide machine activation authority")
end
ZoneService.setQuestService(QuestService)
ZoneService.setMasteryService(MasteryService)
ZoneService.setShopService(ShopService)
ZoneService.setPickupService(PickupService)

CampaignService.init(DataService, CurrencyService, PetService)

-- Start DataService auto-save loop
DataService.startAutoSave()

-- Settle transient pickup rewards before shutdown snapshots cached profiles.
DataService.bindToClose(PickupService.settleAllPlayers)

-- QOF-12 centralizes every WalkSpeed source and owns character reconciliation.
MovementService.init(QuestService, MasteryService, ShopService, UpgradeTreeService)
ShopService.setWalkSpeedRefreshCallback(MovementService.refresh)
PotionService.setMovementRefreshCallback(MovementService.refresh)
PotionService.start()

----------------------------------------------
-- Connect RemoteFunction handlers (server-authoritative validation)
----------------------------------------------

local function getRemoteFunction(name)
	return remotesFolder:FindFirstChild(name)
end

-- GetPlayerData (returns sanitized copy, not the cache reference)
getRemoteFunction("GetPlayerData").OnServerInvoke = function(player)
	if not player or not player:IsA("Player") then
		return nil
	end
	if not canCall(player, "GetPlayerData", 0.2) then
		return nil
	end
	local deadline = os.clock() + 15
	while player.Parent and not DataService.getPlayerData(player) and os.clock() < deadline do
		task.wait(0.1)
	end
	return DataService.getClientData(player)
end

-- GetHatchPurchaseOptions returns a fresh server-authoritative manual quote.
getRemoteFunction("GetHatchPurchaseOptions").OnServerInvoke = function(player, eggType)
	if not player or not player:IsA("Player") then
		return nil, "Invalid player"
	end
	if not canCall(player, "GetHatchPurchaseOptions", 0.15)
		or not canCallBurst(player, "GetHatchPurchaseOptions", 12, 10) then
		return nil, "Please wait before requesting hatch options again"
	end
	if not isValidIdentifier(eggType) then
		return nil, "Invalid egg type"
	end
	return EggService.getHatchPurchaseOptions(player, eggType)
end

-- HatchEgg confirms only the strict QOF-10 intent DTO. Manual purchases must
-- pass through the confirmation dialog contract instead of raw numeric counts.
getRemoteFunction("HatchEgg").OnServerInvoke = function(player, eggType, intent)
	if not player or not player:IsA("Player") then
		return nil, "Invalid player"
	end
	if not canCall(player, "HatchEgg", 3) then
		return nil, "Please wait before hatching again"
	end
	if not isValidIdentifier(eggType) then
		return nil, "Invalid hatch parameters"
	end
	if type(intent) == "table" then
		return EggService.purchaseFromIntent(player, eggType, intent)
	end
	return nil, "Invalid hatch parameters"
end

-- The compatibility remote remains present for rolling clients, but is fail-closed
-- and cannot mutate persisted Auto-Hatch preferences before the owning QOF ships.
getRemoteFunction("SetHatchBatchSize").OnServerInvoke = function(player, requestedCount)
	if not player or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if BalanceConfig.Shop.AutoHatchRuntimeEnabled ~= true then
		return false, "Auto-Hatch is not available yet", EggService.getBatchState(player)
	end
	if not canCall(player, "SetHatchBatchSize", 0.15) then
		return false, "Please wait before changing batch size", EggService.getBatchState(player)
	end
	return EggService.setSelectedBatchCount(player, requestedCount)
end

-- EquipPet (0.5 second cooldown)
getRemoteFunction("EquipPet").OnServerInvoke = function(player, petInstanceId)
	if not player or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if not canCall(player, "EquipPet", 0.5) then
		return false, "Please wait before equipping again"
	end
	if type(petInstanceId) ~= "string" then
		return false, "Invalid pet ID parameter"
	end
	return PetService.equipPet(player, petInstanceId)
end

-- UnequipPet (0.5 second cooldown)
getRemoteFunction("UnequipPet").OnServerInvoke = function(player, petInstanceId)
	if not player or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if not canCall(player, "UnequipPet", 0.5) then
		return false, "Please wait before unequipping again"
	end
	if type(petInstanceId) ~= "string" then
		return false, "Invalid pet ID parameter"
	end
	return PetService.unequipPet(player, petInstanceId)
end

-- DeletePet (1 second cooldown)
getRemoteFunction("DeletePet").OnServerInvoke = function(player, petInstanceId)
	if not player or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if not canCall(player, "DeletePet", 1) then
		return false, "Please wait before deleting again"
	end
	if type(petInstanceId) ~= "string" then
		return false, "Invalid pet ID parameter"
	end
	return PetService.deletePet(player, petInstanceId)
end

-- DeletePets (bulk delete, 1 second cooldown, bounded by inventory capacity)
getRemoteFunction("DeletePets").OnServerInvoke = function(player, petInstanceIds)
	if not player or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if not canCall(player, "DeletePets", 1) then
		return false, "Please wait before deleting again"
	end
	if type(petInstanceIds) ~= "table" then
		return false, "Invalid pet IDs parameter"
	end
	-- Bulk delete size limit is bounded by the server-authoritative inventory capacity.
	if #petInstanceIds > PetService.getMaxInventory(player) then
		return false, "Too many pets"
	end
	-- Validate each ID is a string
	for _, id in ipairs(petInstanceIds) do
		if type(id) ~= "string" then
			return false, "Invalid pet ID in list"
		end
	end
	return PetService.deletePets(player, petInstanceIds)
end

-- SetPetFavorite (idempotent favorite state, 0.25 second cooldown)
getRemoteFunction("SetPetFavorite").OnServerInvoke = function(player, petInstanceId, isFavorite)
	if not player or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if not canCall(player, "SetPetFavorite", 0.25) then
		return false, "Please wait before changing favorites again"
	end
	if not isValidIdentifier(petInstanceId) or type(isFavorite) ~= "boolean" then
		return false, "Invalid favorite parameters"
	end
	return PetService.setPetFavorite(player, petInstanceId, isFavorite)
end

-- UnlockZone (2 second cooldown)
getRemoteFunction("UnlockZone").OnServerInvoke = function(player, zoneId)
	if not player or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if not canCall(player, "UnlockZone", 2) then
		return false, "Please wait before unlocking again"
	end
	if type(zoneId) ~= "number" then
		return false, "Invalid zone ID parameter"
	end
	return ZoneService.unlockZone(player, math.floor(zoneId))
end

-- PurchaseUpgrade (1 second cooldown)
getRemoteFunction("PurchaseUpgrade").OnServerInvoke = function(player, upgradeId)
	if not player or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if not canCall(player, "PurchaseUpgrade", 1) then
		return false, "Please wait before purchasing again"
	end
	if type(upgradeId) ~= "string" then
		return false, "Invalid upgrade ID parameter"
	end
	return UpgradeService.purchaseUpgrade(player, upgradeId)
end

-- GetQuestProgress
getRemoteFunction("GetQuestProgress").OnServerInvoke = function(player)
	if not player or not player:IsA("Player") then
		return {}
	end
	if not canCall(player, "GetQuestProgress", 0.25) then return {} end
	return QuestService.getQuestProgress(player)
end

-- PurchaseMasteryBuff (1 second cooldown)
getRemoteFunction("PurchaseMasteryBuff").OnServerInvoke = function(player, buffId)
	if not player or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if not canCall(player, "PurchaseMasteryBuff", 1) then
		return false, "Please wait before purchasing again"
	end
	if type(buffId) ~= "string" then
		return false, "Invalid buff ID parameter"
	end
	local success, msg = MasteryService.purchaseBuff(player, buffId)
	-- Refresh every composed source after a movement mastery purchase.
	if success then
		MovementService.refresh(player)
	end
	return success, msg
end

-- GetMasteryState
getRemoteFunction("GetMasteryState").OnServerInvoke = function(player)
	if not player or not player:IsA("Player") then
		return {}
	end
	if not canCall(player, "GetMasteryState", 0.25) then return {} end
	return MasteryService.getMasteryState(player)
end

-- GetUpgradeTreeState
getRemoteFunction("GetUpgradeTreeState").OnServerInvoke = function(player)
	if not player or not player:IsA("Player") then
		return { currency = { coins = 0, diamonds = 0 }, purchased = {}, available = {}, entitlements = {} }
	end
	if not canCall(player, "GetUpgradeTreeState", 0.25) then
		return nil
	end
	return UpgradeTreeService.getState(player)
end

-- PurchaseTreeUpgrade (server validates canonical ID, prerequisites, and currency cost)
getRemoteFunction("PurchaseTreeUpgrade").OnServerInvoke = function(player, upgradeId)
	if not player or not player:IsA("Player") then
		return false, "Invalid player", { currency = { coins = 0 }, purchased = {} }
	end
	if not canCall(player, "PurchaseTreeUpgrade", 0.35) then
		return false, "Please wait before purchasing again", UpgradeTreeService.getState(player)
	end
	if not isValidIdentifier(upgradeId) then
		return false, "Invalid upgrade ID", UpgradeTreeService.getState(player)
	end
	local success, message, state = UpgradeTreeService.purchase(player, upgradeId)
	if success then
		MovementService.refresh(player)
	end
	return success, message, state
end

-- Rolling clients may still wait for this historical remote during startup.
-- Retaining a mutation-free rejection avoids deadlocking their entire client
-- while guaranteeing that no free conversion path survives QOF-16.
getRemoteFunction("ConvertToGoldenPet").OnServerInvoke = function()
	return nil, "Legacy conversion unavailable; use the Gold Machine in Zone 3"
end

-- UseMachine is the sole machine mutation entry point. Main validates only request
-- identity/shape and abuse limits; all world, pet, currency, RNG, and quest
-- semantics remain owned by MachineService and its injected ZoneService authority.
getRemoteFunction("UseMachine").OnServerInvoke = function(player, machineId, activationToken, petInstanceIds)
	if not player or not player:IsA("Player") then
		return nil, "Invalid player"
	end
	-- Account every request from a valid player before traversing caller-owned
	-- data so malformed traffic cannot bypass either abuse-control bucket.
	local cooldownAllowed = canCall(player, "UseMachine", 0.25)
	local burstAllowed = canCallBurst(player, "UseMachine", 8, 10)
	if not cooldownAllowed or not burstAllowed then
		return nil, "Please wait before using a machine again"
	end
	if not isValidIdentifier(machineId) then
		return nil, "Invalid machine ID"
	end
	if type(activationToken) ~= "string" or activationToken == "" or #activationToken > 128 then
		return nil, "Invalid machine activation"
	end
	if not isValidMachinePetIdList(petInstanceIds) then
		return nil, "Invalid pet IDs parameter (expected plain dense list)"
	end
	return MachineService.attemptConversion(player, machineId, activationToken, petInstanceIds)
end

-- StartCampaignLevel (2 second cooldown)
getRemoteFunction("StartCampaignLevel").OnServerInvoke = function(player, levelNum)
	if not player or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if not canCall(player, "StartCampaignLevel", 2) then
		return false, "Please wait before starting again"
	end
	if type(levelNum) ~= "number" then
		return false, "Invalid level number parameter"
	end
	return CampaignService.startLevel(player, math.floor(levelNum))
end

-- DeployPetInCampaign (0.5 second cooldown)
getRemoteFunction("DeployPetInCampaign").OnServerInvoke = function(player, petInstanceId)
	if not player or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if not canCall(player, "DeployPetInCampaign", 0.5) then
		return false, "Please wait before deploying again"
	end
	if type(petInstanceId) ~= "string" then
		return false, "Invalid pet ID parameter"
	end
	return CampaignService.deployPet(player, petInstanceId)
end

-- AttackDestructible
getRemoteFunction("AttackDestructible").OnServerInvoke = function(player, destructibleId)
	if not player or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if not isValidIdentifier(destructibleId) then
		return false, "Invalid destructible ID parameter"
	end
	return ZoneService.attackDestructible(player, destructibleId)
end

-- ClickAttackDestructible now only authorizes one Crit-QTE and deals zero damage.
-- The legacy remote name is retained for place/client compatibility.
getRemoteFunction("ClickAttackDestructible").OnServerInvoke = function(player, destructibleId)
	if not player or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if not isValidIdentifier(destructibleId) then
		return false, "Invalid destructible ID parameter"
	end
	return ZoneService.requestCritWindow(player, destructibleId)
end

-- CritAttackDestructible (player clicked a crit circle - deals 2 damage if crit window active)
getRemoteFunction("CritAttackDestructible").OnServerInvoke = function(player, destructibleId)
	if not player or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if not canCall(player, "CritAttackDestructible", 0.2) then
		return false, "Please wait before crit attacking again"
	end
	if not isValidIdentifier(destructibleId) then
		return false, "Invalid destructible ID parameter"
	end
	return ZoneService.critAttackDestructible(player, destructibleId)
end

-- AssignPetTarget (client tells server which pet targets which destructible)
getRemoteFunction("AssignPetTarget").OnServerInvoke = function(player, petInstanceId, destructibleId)
	if not player or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if not canCallBurst(player, "AssignPetTarget", 30, 1) then
		return false, "Too many target changes"
	end
	if not isValidIdentifier(petInstanceId) then
		return false, "Invalid pet ID parameter"
	end
	-- destructibleId can be nil (clearing target) or a bounded identifier.
	if destructibleId ~= nil and not isValidIdentifier(destructibleId) then
		return false, "Invalid destructible ID parameter"
	end
	return ZoneService.assignPetTarget(player, petInstanceId, destructibleId)
end

-- GetDiscoveredPets (returns player's discovered pets table)
getRemoteFunction("GetDiscoveredPets").OnServerInvoke = function(player)
	if not player or not player:IsA("Player") then
		return {}
	end
	if not canCall(player, "GetDiscoveredPets", 0.25) then return {} end
	local data = DataService.getPlayerData(player)
	if not data then
		return {}
	end
	return data.discoveredPets or {}
end

-- PurchaseShopItem accepts the exact QOF-13 potion DTO plus the one retained
-- ExtraEquipSlot string contract. Validate bounded input before consuming quota.
getRemoteFunction("PurchaseShopItem").OnServerInvoke = function(player, request)
	if not player or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if not isValidShopPurchaseRequest(request) then
		return false, "Invalid purchase request"
	end
	if not canCall(player, "PurchaseShopItem", 2) then
		return false, "Please wait before purchasing again"
	end
	return ShopService.purchaseItem(player, request)
end

-- GetShopBuffs is a legacy remote name; it now returns the purchase state and
-- a delegated potion-state snapshot for rolling clients.
getRemoteFunction("GetShopBuffs").OnServerInvoke = function(player)
	if not player or not player:IsA("Player") then
		return nil
	end
	if not canCall(player, "GetShopBuffs", 0.25) then
		return nil
	end
	return ShopService.getShopState(player)
end

getRemoteFunction("GetPotionState").OnServerInvoke = function(player)
	if not player or not player:IsA("Player") then return nil end
	if not canCall(player, "GetPotionState", 0.2) then return nil end
	return PotionService.getState(player)
end

getRemoteFunction("ConsumePotion").OnServerInvoke = function(player, request)
	if not player or not player:IsA("Player") then return false, "Invalid player" end
	if type(request) ~= "table" then return false, "Invalid consume request" end
	if not canCall(player, "ConsumePotion", 0.2) then
		return false, "Please wait before drinking again", PotionService.getState(player)
	end
	return PotionService.consume(player, request)
end

getRemoteFunction("PurchasePotionUpgrade").OnServerInvoke = function(player, request)
	if not player or not player:IsA("Player") then return false, "Invalid player" end
	if type(request) ~= "table" then return false, "Invalid upgrade request" end
	if not canCall(player, "PurchasePotionUpgrade", 0.5) then
		return false, "Please wait before purchasing again", PotionService.getState(player)
	end
	return PotionService.purchaseUpgrade(player, request)
end

getRemoteFunction("SetAutoDrinkSelection").OnServerInvoke = function(player, request)
	if not player or not player:IsA("Player") then return false, "Invalid player" end
	if type(request) ~= "table" then return false, "Invalid Auto-Drink request" end
	if not canCall(player, "SetAutoDrinkSelection", 0.15) then
		return false, "Please wait before changing Auto-Drink", PotionService.getState(player)
	end
	return PotionService.setAutoDrinkSelection(player, request)
end

----------------------------------------------
-- Player Lifecycle
----------------------------------------------

-- Track session join times for playtime calculation
local _sessionJoinTimes = {}

Players.PlayerAdded:Connect(function(player)
	-- Acquire the player's profile before any gameplay system can mutate it.
	local loadedData, loadError = DataService.loadPlayerData(player)
	if not loadedData then
		player:Kick(loadError or "Your data could not be loaded safely. Please rejoin.")
		return
	end

	-- Auto-give currency to admins (workaround: TextChatService does NOT fire player.Chatted)
	local ADMIN_IDS = {357069526}
	if table.find(ADMIN_IDS, player.UserId) or game:GetService("RunService"):IsStudio() then
		task.delay(2, function()
			CurrencyService.addCoins(player, 50000)
			CurrencyService.addDiamonds(player, 5000)
			print("[Admin] Auto-gave 50000 coins + 5000 diamonds to " .. player.Name)
		end)
	end

	-- Record join time for playtime tracking
	_sessionJoinTimes[player.UserId] = os.time()

	-- Reconcile persisted absolute potion timers and online-only Auto-Drink before
	-- binding movement so the first character speed uses authoritative state.
	PotionService.onPlayerAdded(player)
	MovementService.bindPlayer(player)

	-- Create leaderstats folder for Roblox built-in leaderboard
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local data = DataService.getPlayerData(player)

	local levelStat = Instance.new("IntValue")
	levelStat.Name = "Level"
	levelStat.Value = data and data.level or 1
	levelStat.Parent = leaderstats

	local diamondsStat = Instance.new("IntValue")
	diamondsStat.Name = "Diamonds"
	diamondsStat.Value = data and data.diamonds or 0
	diamondsStat.Parent = leaderstats

	-- Check level-based quests on join (in case they already meet requirements)
	if data then
		QuestService.setStat(player, "reachLevel", data.level or 1)
	end

	----------------------------------------------
	-- Admin Chat Commands (game owner only)
	----------------------------------------------
	player.Chatted:Connect(function(message)
		-- Only allow admins to use commands (game owner, hardcoded IDs, or Studio)
		local ADMIN_IDS = {357069526}
		local isAdmin = table.find(ADMIN_IDS, player.UserId) or (player.UserId == game.CreatorId) or game:GetService("RunService"):IsStudio()
		if not isAdmin then
			return
		end

		local lower = string.lower(message)
		local args = string.split(lower, " ")
		local cmd = args[1]

		if cmd == "!give" or cmd == "!coins" then
			local amount = tonumber(args[2]) or 10000
			CurrencyService.addCoins(player, amount)
			print("[Admin] Gave " .. amount .. " coins to " .. player.Name)

		elseif cmd == "!diamonds" or cmd == "!gems" then
			local amount = tonumber(args[2]) or 1000
			CurrencyService.addDiamonds(player, amount)
			print("[Admin] Gave " .. amount .. " diamonds to " .. player.Name)

		elseif cmd == "!level" then
			local level = tonumber(args[2]) or 20
			local pData = DataService.getPlayerData(player)
			if pData then
				pData.level = level
				-- Fire XP updated event so client UI refreshes
				local remotes = ReplicatedStorage:FindFirstChild("Remotes")
				if remotes then
					local xpEvent = remotes:FindFirstChild("XPUpdated")
					if xpEvent then
						xpEvent:FireClient(player, level, pData.xp or 0, level * 100)
					end
				end
				-- Update leaderstats
				local ls = player:FindFirstChild("leaderstats")
				if ls then
					local lvStat = ls:FindFirstChild("Level")
					if lvStat then
						lvStat.Value = level
					end
				end
				print("[Admin] Set level to " .. level .. " for " .. player.Name)
			end

		elseif cmd == "!unlockall" then
			local pData = DataService.getPlayerData(player)
			if pData then
				pData.unlockedZones = pData.unlockedZones or {}
				local remotes = ReplicatedStorage:FindFirstChild("Remotes")
				local zoneEvent = remotes and remotes:FindFirstChild("ZoneUnlocked")
				for zoneId = 2, 8 do
					if not table.find(pData.unlockedZones, zoneId) then
						table.insert(pData.unlockedZones, zoneId)
						if zoneEvent then
							zoneEvent:FireClient(player, zoneId)
						end
					end
				end
				print("[Admin] Unlocked all zones for " .. player.Name)
			end
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	-- Accumulate playtime before saving
	local joinTime = _sessionJoinTimes[player.UserId]
	if joinTime then
		local sessionSeconds = os.time() - joinTime
		if sessionSeconds > 0 then
			QuestService.incrementStat(player, "playtime", sessionSeconds)
		end
		_sessionJoinTimes[player.UserId] = nil
	end

	-- Cleanup rate limits
	rateLimits[player.UserId] = nil
	burstLimits[player.UserId] = nil

	-- Cleanup QOF-12 movement listeners before the profile is released.
	MovementService.unbindPlayer(player)

	-- Settle transient owner-only pickups before the profile is saved/released.
	if not PickupService.onPlayerRemoving(player) then
		warn("[Battle Pets] Pending pickup settlement did not complete before player data cleanup for " .. player.Name)
	end

	-- Cleanup QOF-09 transient hatch locks/cache; the profile preference persists
	EggService.onPlayerRemoving(player)

	-- Cleanup QOF-16 machine transaction locks.
	MachineService.cleanup(player)

	-- Cleanup QOF-14 potion locks/reservations before profile persistence.
	PotionService.onPlayerRemoving(player)

	-- Cleanup ShopService transient locks and legacy buff compatibility state.
	ShopService.onPlayerRemoving(player)

	-- Cleanup ZoneService player state (attack cooldowns, pet targets)
	ZoneService.onPlayerRemoving(player)

	-- Cleanup campaign battle if any
	CampaignService.onPlayerRemoving(player)
	-- Save and cleanup player data
	DataService.onPlayerRemoving(player)
end)

-- Handle players who joined before script loaded
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		local loadedData, loadError = DataService.loadPlayerData(player)
		if not loadedData then
			player:Kick(loadError or "Your data could not be loaded safely. Please rejoin.")
			return
		end
		_sessionJoinTimes[player.UserId] = os.time()
		PotionService.onPlayerAdded(player)
		MovementService.bindPlayer(player)

		-- Create leaderstats for already-connected players
		local leaderstats = player:FindFirstChild("leaderstats")
		if not leaderstats then
			leaderstats = Instance.new("Folder")
			leaderstats.Name = "leaderstats"
			leaderstats.Parent = player
		end

		local data = DataService.getPlayerData(player)

		local levelStat = leaderstats:FindFirstChild("Level")
		if not levelStat then
			levelStat = Instance.new("IntValue")
			levelStat.Name = "Level"
			levelStat.Parent = leaderstats
		end
		levelStat.Value = data and data.level or 1

		local diamondsStat = leaderstats:FindFirstChild("Diamonds")
		if not diamondsStat then
			diamondsStat = Instance.new("IntValue")
			diamondsStat.Name = "Diamonds"
			diamondsStat.Parent = leaderstats
		end
		diamondsStat.Value = data and data.diamonds or 0

		if data then
			QuestService.setStat(player, "reachLevel", data.level or 1)
		end
	end)
end

-- Helper: update leaderstats for a player from their current data
local function updateLeaderstats(player)
	local data = DataService.getPlayerData(player)
	if not data then return end
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end
	local levelStat = leaderstats:FindFirstChild("Level")
	if levelStat then
		levelStat.Value = data.level or 1
	end
	local diamondsStat = leaderstats:FindFirstChild("Diamonds")
	if diamondsStat then
		diamondsStat.Value = data.diamonds or 0
	end
end

-- Update leaderstats whenever currency or XP changes
-- Hook into existing remote events: listen for CurrencyUpdated and XPUpdated firing
local originalCurrencyUpdatedFire = nil
-- Use a periodic check (every 5 seconds) to keep leaderstats in sync
task.spawn(function()
	while true do
		task.wait(5)
		for _, player in ipairs(Players:GetPlayers()) do
			updateLeaderstats(player)
		end
	end
end)

-- Periodic playtime tracking: every 60 seconds, update playtime stats
-- This ensures quest progress is visible even during long sessions
task.spawn(function()
	while true do
		task.wait(60)
		for _, player in ipairs(Players:GetPlayers()) do
			local joinTime = _sessionJoinTimes[player.UserId]
			if joinTime then
				local sessionSeconds = os.time() - joinTime
				if sessionSeconds > 0 then
					-- Update the stat with total accumulated playtime
					local data = DataService.getPlayerData(player)
					if data and data.questStats then
						-- Calculate new total: stored + current session
						local storedPlaytime = data.questStats.playtime or 0
						-- We set the stat to stored + session so far
						-- But we must be careful not to double-count
						-- Instead, flush the session time into the stat and reset join time
						QuestService.incrementStat(player, "playtime", sessionSeconds)
						_sessionJoinTimes[player.UserId] = os.time()
					end
				end
			end
		end
	end
end)

print("[Battle Pets] Server initialized successfully!")
