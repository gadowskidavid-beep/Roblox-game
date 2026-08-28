--[[
	Main.client.lua - Client entry point for Battle Pets
	Initializes all client controllers, connects to RemoteEvents/RemoteFunctions,
	sets up per-frame updates (pet following, effects), and handles input.

	INPUT SYSTEM (Pet Simulator 1 style):
	- Single left click on destructible: send 1 pet to attack it
	- Hold left click (0.3s+) on destructible: send ALL pets to attack it
	- E-key near an egg station: open the quoted manual-purchase dialog
	- Assigned pets keep attacking; target discovery is manual-only
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")

-- Get remotes folder from ReplicatedStorage
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PetData = require(Shared:WaitForChild("PetData"))
local CampaignData = require(Shared:WaitForChild("CampaignData"))
local ZoneData = require(Shared:WaitForChild("ZoneData"))
local QuestData = require(Shared:WaitForChild("QuestData"))
local MasteryData = require(Shared:WaitForChild("MasteryData"))

-- Require controllers
local UIController = require(script.Parent:WaitForChild("UIController"))
local PetController = require(script.Parent:WaitForChild("PetController"))
local CampaignController = require(script.Parent:WaitForChild("CampaignController"))
local EffectsController = require(script.Parent:WaitForChild("EffectsController"))
local MusicController = require(script.Parent:WaitForChild("MusicController"))
local UpgradeTreeController = require(script.Parent:WaitForChild("UpgradeTreeController"))

-- Create controller instances
local uiController = UIController.new()
local petController = PetController.new()
local campaignController = CampaignController.new()
local effectsController = EffectsController.new()
local musicController = MusicController.new()
local upgradeTreeController = UpgradeTreeController.new()

-- Player reference
local player = Players.LocalPlayer

--------------------------------------------------------------------------------
-- REMOTE REFERENCES
--------------------------------------------------------------------------------
-- RemoteFunctions
local GetPlayerData = Remotes:WaitForChild("GetPlayerData")
local HatchEgg = Remotes:WaitForChild("HatchEgg")
-- QOF-10 fresh manual-purchase quote; no currency is spent by this call.
local GetHatchPurchaseOptions = Remotes:WaitForChild("GetHatchPurchaseOptions")
local EquipPet = Remotes:WaitForChild("EquipPet")
local UnequipPet = Remotes:WaitForChild("UnequipPet")
local DeletePet = Remotes:WaitForChild("DeletePet")
local DeletePets = Remotes:WaitForChild("DeletePets")
local UnlockZone = Remotes:WaitForChild("UnlockZone")
local PurchaseUpgrade = Remotes:WaitForChild("PurchaseUpgrade")
local StartCampaignLevel = Remotes:WaitForChild("StartCampaignLevel")
local DeployPetInCampaign = Remotes:WaitForChild("DeployPetInCampaign")
local AttackDestructible = Remotes:WaitForChild("AttackDestructible")
-- Legacy remote name; it now only requests a server-authorized Crit-QTE window.
local RequestCritWindow = Remotes:WaitForChild("ClickAttackDestructible")
local CritAttackDestructible = Remotes:WaitForChild("CritAttackDestructible")
local GetQuestProgress = Remotes:WaitForChild("GetQuestProgress")
local PurchaseMasteryBuff = Remotes:WaitForChild("PurchaseMasteryBuff")
local GetMasteryState = Remotes:WaitForChild("GetMasteryState")
local ConvertToGoldenPet = Remotes:WaitForChild("ConvertToGoldenPet")
local GetDiscoveredPets = Remotes:WaitForChild("GetDiscoveredPets")
local PurchaseShopItem = Remotes:WaitForChild("PurchaseShopItem")
local GetShopBuffs = Remotes:WaitForChild("GetShopBuffs")

-- RemoteEvents
local CurrencyUpdated = Remotes:WaitForChild("CurrencyUpdated")
local PetInventoryUpdated = Remotes:WaitForChild("PetInventoryUpdated")
local PetEquipped = Remotes:WaitForChild("PetEquipped")
local PetUnequipped = Remotes:WaitForChild("PetUnequipped")
local ZoneUnlocked = Remotes:WaitForChild("ZoneUnlocked")
local DestructibleDamaged = Remotes:WaitForChild("DestructibleDamaged")
local DestructibleDestroyed = Remotes:WaitForChild("DestructibleDestroyed")
local EggHatchStart = Remotes:WaitForChild("EggHatchStart")
local EggHatchResult = Remotes:WaitForChild("EggHatchResult")
local CampaignBattleUpdate = Remotes:WaitForChild("CampaignBattleUpdate")
local CampaignVictory = Remotes:WaitForChild("CampaignVictory")
local CampaignDefeat = Remotes:WaitForChild("CampaignDefeat")
local UpgradeUpdated = Remotes:WaitForChild("UpgradeUpdated")
local CollectCurrency = Remotes:WaitForChild("CollectCurrency")
local ShopBuffsUpdated = Remotes:WaitForChild("ShopBuffsUpdated")

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------
local playerData = GetPlayerData:InvokeServer()
local hasLoadedPlayerData = playerData ~= nil
if not playerData then
	playerData = {
		coins = 0,
		diamonds = 0,
		xp = 0,
		level = 1,
		pets = {},
		unlockedZones = {1},
		campaignProgress = {},
		upgrades = {},
		equippedPets = {},
	}
end

-- Local list of currently equipped pet data tables (maintained incrementally)
local localEquippedPets = {}

-- Helper: resolve the initial equippedPets (array of string IDs) to full pet data
local function buildEquippedListFromData(data)
	local list = {}
	if not data or not data.equippedPets or not data.pets then
		return list
	end
	local petById = {}
	for _, pet in ipairs(data.pets) do
		petById[pet.id] = pet
	end
	for _, petId in ipairs(data.equippedPets) do
		local petData = petById[petId]
		if petData then
			table.insert(list, petData)
		end
	end
	return list
end

-- O(1) canonical visual lookup shared with PetController. Click targeting uses a
-- separate live hitbox-only list so pets, effects, and decorations cannot block it.
local destructibleIndex = {}
local clickHitboxesById = {}
local clickHitboxList = {}
local refreshOnboardingHint = function() end

local function rebuildClickHitboxList()
	clickHitboxList = {}
	for destructibleId, hitbox in pairs(clickHitboxesById) do
		if hitbox and hitbox.Parent then
			table.insert(clickHitboxList, hitbox)
		else
			clickHitboxesById[destructibleId] = nil
		end
	end
end

local function indexDestructibleDescendant(obj)
	if obj:IsA("BasePart") and obj.Name == "ClickHitbox" then
		local destructibleId = obj:GetAttribute("DestructibleId")
		if type(destructibleId) == "string" and destructibleId ~= "" then
			clickHitboxesById[destructibleId] = obj
			rebuildClickHitboxList()
		end
		return
	end

	local part = nil
	local idValue = nil
	if obj:IsA("BasePart") then
		part = obj
		idValue = obj:FindFirstChild("DestructibleId")
	elseif obj:IsA("StringValue") and obj.Name == "DestructibleId" and obj.Parent and obj.Parent:IsA("BasePart") then
		part = obj.Parent
		idValue = obj
	end
	if part and idValue and idValue.Value ~= "" then
		destructibleIndex[idValue.Value] = part
		task.defer(refreshOnboardingHint)
	end
end

local function removeDestructibleDescendant(obj)
	if obj:IsA("BasePart") and obj.Name == "ClickHitbox" then
		local destructibleId = obj:GetAttribute("DestructibleId")
		if clickHitboxesById[destructibleId] == obj then
			clickHitboxesById[destructibleId] = nil
			rebuildClickHitboxList()
		end
		return
	end

	if obj:IsA("StringValue") and obj.Name == "DestructibleId" then
		destructibleIndex[obj.Value] = nil
		task.defer(refreshOnboardingHint)
	elseif obj:IsA("BasePart") then
		local idValue = obj:FindFirstChild("DestructibleId")
		if idValue then
			destructibleIndex[idValue.Value] = nil
			task.defer(refreshOnboardingHint)
		end
	end
end

local function attachDestructibleIndex(zonesFolder)
	for _, obj in ipairs(zonesFolder:GetDescendants()) do
		indexDestructibleDescendant(obj)
	end
	zonesFolder.DescendantAdded:Connect(indexDestructibleDescendant)
	zonesFolder.DescendantRemoving:Connect(removeDestructibleDescendant)
end

local zonesFolder = workspace:FindFirstChild("Zones")
if zonesFolder then
	attachDestructibleIndex(zonesFolder)
else
	workspace.ChildAdded:Connect(function(child)
		if child.Name == "Zones" then
			attachDestructibleIndex(child)
		end
	end)
end

local function resolveDestructiblePart(destructibleId)
	local part = destructibleIndex[destructibleId]
	if part and part.Parent then
		return part
	end
	destructibleIndex[destructibleId] = nil
	return nil
end

-- Initialize all controllers
effectsController:init()
petController:init(Remotes)
petController:setDestructibleIndex(destructibleIndex)
campaignController:init(Remotes)
uiController:init(Remotes, playerData)
musicController:init()
upgradeTreeController:init(Remotes, playerData)

-- Reuse the UpgradeTreeController's authoritative initial request and every
-- subsequent server update. This avoids a competing one-shot remote call whose
-- failure could leave legacy Capacity bonuses hidden until the next purchase.
upgradeTreeController:setStateObserver(function(state)
	uiController:updateUpgradeTree(state)
end)

--------------------------------------------------------------------------------
-- LIGHTWEIGHT NEW-PLAYER ONBOARDING
--------------------------------------------------------------------------------
local ONBOARDING_STEPS = {
	{ key = "click", text = "Click a breakable to attack it." },
	{ key = "coins", text = "Destroy breakables to earn Coins." },
	{ key = "egg", text = "Go to the Basic Egg and press E." },
	{ key = "equip", text = "Open Pets and equip a pet." },
	{ key = "zone", text = "Earn 500 Coins and walk through the City gate." },
}

local onboardingCompleted = {}
local onboardingActive = hasLoadedPlayerData

local questStats = playerData.questStats or {}
local hasUnlockedLaterZone = false
for _, zoneId in ipairs(playerData.unlockedZones or {}) do
	local numericZoneId = tonumber(zoneId)
	if numericZoneId and numericZoneId > 1 then
		hasUnlockedLaterZone = true
		break
	end
end

local hasEquippedNonStarter = false
for _, petId in ipairs(playerData.equippedPets or {}) do
	if petId ~= "starter_pet_1" then
		hasEquippedNonStarter = true
		break
	end
end

-- Later persisted milestones imply the earlier onboarding context. Session facts
-- below remain monotonic so a completed hint never returns during this join.
onboardingCompleted.zone = hasUnlockedLaterZone
onboardingCompleted.equip = hasUnlockedLaterZone or hasEquippedNonStarter
onboardingCompleted.egg = hasUnlockedLaterZone or (tonumber(questStats.hatchEggs) or 0) > 0
onboardingCompleted.coins = onboardingCompleted.egg or (tonumber(questStats.earnCoins) or 0) > 0
onboardingCompleted.click = onboardingCompleted.coins
	or (tonumber(questStats.destroyDestructibles) or 0) > 0

local function findNearestDestructible()
	local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local nearestPart = nil
	local nearestDistance = math.huge
	for _, part in pairs(destructibleIndex) do
		if part and part.Parent then
			local distance = rootPart and (part.Position - rootPart.Position).Magnitude or 0
			if distance < nearestDistance then
				nearestDistance = distance
				nearestPart = part
			end
		end
	end
	return nearestPart
end

local function findBasicEgg()
	local stations = workspace:FindFirstChild("EggStations")
	if not stations then return nil end
	for _, obj in ipairs(stations:GetDescendants()) do
		if obj:IsA("StringValue") and obj.Name == "PromptEggType" and obj.Value == "BasicEgg"
			and obj.Parent and obj.Parent:IsA("BasePart") then
			return obj.Parent
		end
	end
	return nil
end

local function findCityGate()
	local gates = workspace:FindFirstChild("ZoneGates")
	local gateModel = gates and gates:FindFirstChild("ZoneGateModel_2")
	if not gateModel then return nil end
	return gateModel:FindFirstChild("GateBarrier_2", true)
		or gateModel:FindFirstChild("TopArch", true)
end

local function getOnboardingTarget(stepKey)
	if stepKey == "click" or stepKey == "coins" then
		return findNearestDestructible()
	elseif stepKey == "egg" then
		return findBasicEgg()
	elseif stepKey == "zone" then
		return findCityGate()
	end
	return nil
end

refreshOnboardingHint = function()
	if not onboardingActive then
		uiController:clearOnboardingHint()
		return
	end

	for stepNumber, step in ipairs(ONBOARDING_STEPS) do
		if not onboardingCompleted[step.key] then
			uiController:setOnboardingHint(
				stepNumber,
				#ONBOARDING_STEPS,
				step.text,
				getOnboardingTarget(step.key)
			)
			return
		end
	end

	onboardingActive = false
	uiController:clearOnboardingHint()
end

local function completeOnboardingStep(stepKey)
	if not onboardingActive or onboardingCompleted[stepKey] then return end
	onboardingCompleted[stepKey] = true
	refreshOnboardingHint()
end

refreshOnboardingHint()
-- World folders can arrive shortly after the HUD; refresh the same hint instead
-- of creating another tutorial system or blocking the player.
task.delay(2, refreshOnboardingHint)

-- Track the concrete egg prompt as well as its egg type. Every async quote or
-- purchase captures hatchOperationToken so a hidden/replaced prompt cannot
-- revive a stale dialog or apply stale feedback.
local function getEggTypeFromPrompt(prompt)
	if prompt.Name ~= "HatchPrompt" or not prompt.Parent then return nil end
	local eggTypeTag = prompt.Parent:FindFirstChild("PromptEggType")
	if eggTypeTag and eggTypeTag:IsA("StringValue") then
		return eggTypeTag.Value
	end
	return nil
end

local activeEggPrompt = nil
local activeEggType = nil
local hatchOperationToken = 0
local hatchQuoteInFlight = false
local hatchPurchaseInFlight = false

local function closeHatchPurchaseDialog()
	hatchOperationToken += 1
	hatchQuoteInFlight = false
	hatchPurchaseInFlight = false
	uiController:closeHatchPurchaseDialog()
end

local function describeHatchError(message, fallback)
	local text = tostring(message or fallback or "Hatch purchase is unavailable right now.")
	if text == "No feasible hatch purchase" then
		return "No eggs fit your current Coins and pet inventory slots."
	elseif text == "x1 hatch option unavailable" or text == "x3 hatch option unavailable" then
		return "That option is no longer available. Refresh the quote to check Coins, slots, and entitlement."
	elseif string.find(text, "Move closer", 1, true) then
		return "Move closer to this egg station, then refresh the quote."
	elseif string.find(text, "Not enough coins", 1, true) then
		return "You do not have enough Coins for that option. Refresh the quote."
	elseif string.find(text, "inventory", 1, true) or string.find(text, "Inventory", 1, true) then
		return "Your pet inventory does not have enough free slots. Refresh after making room."
	end
	return text
end

local function requestFreshHatchQuote()
	if hatchQuoteInFlight or hatchPurchaseInFlight then return end
	local prompt = activeEggPrompt
	local eggType = activeEggType
	if not prompt or not prompt.Parent or not eggType then
		closeHatchPurchaseDialog()
		return
	end

	hatchOperationToken += 1
	local token = hatchOperationToken
	hatchQuoteInFlight = true
	uiController:showHatchPurchaseLoading(eggType)
	task.spawn(function()
		local invoked, quote, quoteError = pcall(function()
			return GetHatchPurchaseOptions:InvokeServer(eggType)
		end)
		if token ~= hatchOperationToken
			or prompt ~= activeEggPrompt
			or eggType ~= activeEggType
			or not prompt.Parent then
			return
		end
		hatchQuoteInFlight = false
		if invoked and type(quote) == "table" and quote.eggType == eggType then
			uiController:showHatchPurchaseQuote(eggType, quote)
		else
			local message = invoked and quoteError or quote
			uiController:showHatchPurchaseError(describeHatchError(message, "Could not load a fresh quote."))
		end
	end)
end

local function confirmHatchPurchase(intent)
	if hatchQuoteInFlight or hatchPurchaseInFlight then return end
	local prompt = activeEggPrompt
	local eggType = activeEggType
	if not prompt or not prompt.Parent or not eggType or not uiController:isHatchPurchaseDialogOpen() then
		closeHatchPurchaseDialog()
		return
	end

	-- Rebuild, rather than forward, the only three intents accepted by QOF-10.
	-- MAX intentionally never carries the count from the displayed quote.
	local serverIntent = nil
	if type(intent) == "table" and intent.mode == "Fixed" and intent.count == 1 then
		serverIntent = { mode = "Fixed", count = 1 }
	elseif type(intent) == "table" and intent.mode == "Fixed" and intent.count == 3 then
		serverIntent = { mode = "Fixed", count = 3 }
	elseif type(intent) == "table" and intent.mode == "Max" then
		serverIntent = { mode = "Max" }
	end
	if not serverIntent then return end

	hatchOperationToken += 1
	local token = hatchOperationToken
	hatchPurchaseInFlight = true
	uiController:showHatchPurchaseBusy("Confirming purchase with the server…")
	task.spawn(function()
		local invoked, result, hatchError = pcall(function()
			return HatchEgg:InvokeServer(eggType, serverIntent)
		end)
		if token ~= hatchOperationToken
			or prompt ~= activeEggPrompt
			or eggType ~= activeEggType then
			return
		end
		hatchPurchaseInFlight = false
		if invoked and type(result) == "table" then
			-- EggHatchStart/EggHatchResult remain the sole QOF-09 cinematic owners.
			closeHatchPurchaseDialog()
		else
			local message = invoked and hatchError or result
			uiController:showHatchPurchaseError(describeHatchError(message, "Hatch purchase failed safely."))
		end
	end)
end

uiController:setHatchPurchaseCallbacks(
	confirmHatchPurchase,
	closeHatchPurchaseDialog,
	requestFreshHatchQuote
)

ProximityPromptService.PromptShown:Connect(function(prompt)
	local eggType = getEggTypeFromPrompt(prompt)
	if not eggType then return end
	if activeEggPrompt and activeEggPrompt ~= prompt then
		local previousEggType = activeEggType
		closeHatchPurchaseDialog()
		activeEggPrompt = nil
		activeEggType = nil
		if previousEggType then
			uiController:hideEggStationPrompt(previousEggType)
		end
	end
	activeEggPrompt = prompt
	activeEggType = eggType
	uiController:showEggStationPrompt(eggType)
end)

ProximityPromptService.PromptHidden:Connect(function(prompt)
	if prompt ~= activeEggPrompt then return end
	local eggType = activeEggType
	activeEggPrompt = nil
	activeEggType = nil
	closeHatchPurchaseDialog()
	if eggType then
		uiController:hideEggStationPrompt(eggType)
	end
end)

-- Prompt routing is centralized so respawns and delayed world creation never
-- add duplicate hatch connections. PotionShopPrompt behavior is unchanged.
ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
	if triggeringPlayer ~= nil and triggeringPlayer ~= player then
		return
	end
	if prompt.Name == "PotionShopPrompt" then
		uiController:openScreen("ShopScreen")
		return
	end
	local eggType = getEggTypeFromPrompt(prompt)
	if not eggType then return end
	if activeEggPrompt ~= prompt then
		local previousEggType = activeEggType
		closeHatchPurchaseDialog()
		if previousEggType then
			uiController:hideEggStationPrompt(previousEggType)
		end
		activeEggPrompt = prompt
		activeEggType = eggType
		uiController:showEggStationPrompt(eggType)
	end
	requestFreshHatchQuote()
end)

-- Initialize equipped pets visuals from initial data (called ONCE)
if playerData and playerData.equippedPets then
	localEquippedPets = buildEquippedListFromData(playerData)
	-- Deduplicate
	local seenIds = {}
	local dedupedList = {}
	for _, pet in ipairs(localEquippedPets) do
		if pet.id and not seenIds[pet.id] then
			seenIds[pet.id] = true
			table.insert(dedupedList, pet)
		end
	end
	localEquippedPets = dedupedList
	petController:updateEquippedPets(localEquippedPets)
	uiController:updateEquippedPets(localEquippedPets)
end

-- Apply FasterPets upgrade from initial data
if playerData and playerData.upgrades and playerData.upgrades.FasterPets then
	local fasterLevel = playerData.upgrades.FasterPets
	local fasterDef = QuestData.Quests.FasterPets
	if fasterDef and fasterDef.levels[fasterLevel] then
		petController:setFasterPetsMultiplier(fasterDef.levels[fasterLevel].bonus)
	end
end

--------------------------------------------------------------------------------
-- REMOTE EVENT HANDLERS
--------------------------------------------------------------------------------

CurrencyUpdated.OnClientEvent:Connect(function(coins, diamonds)
	uiController:updateCurrency(coins, diamonds)
end)

PetInventoryUpdated.OnClientEvent:Connect(function(pets)
	pets = type(pets) == "table" and pets or {}
	uiController:updatePetInventory(pets)

	-- Inventory snapshots can carry an equipped pet's updated visual identity.
	-- Refresh only already-equipped entries, preserving authoritative equip order
	-- and requiring no new remote or replicated world model.
	local petById = {}
	for _, petData in ipairs(pets) do
		if type(petData) == "table" and petData.id then
			petById[petData.id] = petData
		end
	end
	local equippedChanged = false
	for index, equippedPet in ipairs(localEquippedPets) do
		local updatedPet = equippedPet.id and petById[equippedPet.id]
		if updatedPet and updatedPet ~= equippedPet then
			localEquippedPets[index] = updatedPet
			equippedChanged = true
		end
	end
	if equippedChanged then
		petController:updateEquippedPets(localEquippedPets)
		uiController:updateEquippedPets(localEquippedPets)
	end
end)

PetEquipped.OnClientEvent:Connect(function(petData)
	print("[Client] PetEquipped event received: " .. tostring(petData and petData.name or "nil"))
	if petData and type(petData) == "table" and petData.id then
		completeOnboardingStep("equip")
		for i = #localEquippedPets, 1, -1 do
			if localEquippedPets[i].id == petData.id then
				table.remove(localEquippedPets, i)
			end
		end
		table.insert(localEquippedPets, petData)
	end
	petController:updateEquippedPets(localEquippedPets)
	uiController:updateEquippedPets(localEquippedPets)
end)

PetUnequipped.OnClientEvent:Connect(function(petInstanceId)
	print("[Client] PetUnequipped event received: " .. tostring(petInstanceId))
	if petInstanceId and type(petInstanceId) == "string" then
		for i, pet in ipairs(localEquippedPets) do
			if pet.id == petInstanceId then
				table.remove(localEquippedPets, i)
				break
			end
		end
	end
	petController:updateEquippedPets(localEquippedPets)
	uiController:updateEquippedPets(localEquippedPets)
end)

ZoneUnlocked.OnClientEvent:Connect(function(zoneId, gatePosition)
	uiController:unlockZone(zoneId)
	local numericZoneId = tonumber(zoneId)
	if numericZoneId and numericZoneId > 1 then
		completeOnboardingStep("zone")
	end
	if gatePosition then
		effectsController:showZoneUnlock(gatePosition)
	end
	-- Also hide the barrier on unlock (same as HideGateBarrier)
	local gatesFolder = workspace:FindFirstChild("ZoneGates")
	if gatesFolder then
		local gateModel = gatesFolder:FindFirstChild("ZoneGateModel_" .. tostring(zoneId))
		if gateModel then
			local barrierPart = gateModel:FindFirstChild("GateBarrier_" .. tostring(zoneId))
			if barrierPart then
				barrierPart.Transparency = 1
			end
		end
	end
end)

-- HideGateBarrier: server tells this client to hide a specific zone gate barrier
-- This is fired per-player on character spawn for already-unlocked zones
local HideGateBarrier = Remotes:WaitForChild("HideGateBarrier")
HideGateBarrier.OnClientEvent:Connect(function(zoneId)
	local gatesFolder = workspace:FindFirstChild("ZoneGates")
	if gatesFolder then
		local gateModel = gatesFolder:FindFirstChild("ZoneGateModel_" .. tostring(zoneId))
		if gateModel then
			local barrierPart = gateModel:FindFirstChild("GateBarrier_" .. tostring(zoneId))
			if barrierPart then
				barrierPart.Transparency = 1
			end
		end
	end
end)

DestructibleDamaged.OnClientEvent:Connect(function(destructibleId, currentHP, maxHP, damage)
	local destructiblePart = resolveDestructiblePart(destructibleId)
	if destructiblePart then
		effectsController:showProgressBar(destructiblePart, currentHP, maxHP)
		if damage and damage > 0 then
			petController:showDamageText(destructiblePart.Position, damage, damage == 2)
		end
	end
end)

DestructibleDestroyed.OnClientEvent:Connect(function(destructibleId)
	local destructiblePart = resolveDestructiblePart(destructibleId)
	if destructiblePart then
		effectsController:removeProgressBar(destructiblePart)
		local pos = destructiblePart.Position
		-- Show poof effect with the destructible's color. Currency popups are
		-- delivered separately through CollectCurrency to rewarded players only.
		local poofColor = destructiblePart.Color or Color3.fromRGB(200, 200, 200)
		effectsController:showDestructiblePoof(pos, poofColor)
	else
		effectsController:removeProgressBar(destructibleId)
	end
end)

local function normalizeHatchResult(payload)
	if type(payload) ~= "table" then return nil end
	local sourcePets = type(payload.pets) == "table" and payload.pets or { payload }
	local pets = {}
	for _, petData in ipairs(sourcePets) do
		if type(petData) == "table" then
			table.insert(pets, petData)
			if #pets == 10 then break end
		end
	end
	if #pets == 0 then return nil end

	-- Preserve the complete authoritative DTO. Only normalize the rolling QOF-07
	-- shape and clamp the presentation-only list to the supported x10 boundary.
	local normalized = {}
	for key, value in pairs(payload) do normalized[key] = value end
	normalized.pets = pets
	normalized.count = #pets
	return normalized
end

EggHatchStart.OnClientEvent:Connect(function(payload)
	local started, startError = xpcall(function()
		effectsController:handleHatchStart(payload)
	end, debug.traceback)
	if not started then
		warn("[Battle Pets] Hatch start feedback recovered from an error:\n" .. tostring(startError))
	end
end)

EggHatchResult.OnClientEvent:Connect(function(payload)
	local resultDto = normalizeHatchResult(payload)
	if not resultDto then
		local cleaned, cleanupError = xpcall(function()
			effectsController:handleInvalidHatchResult(payload)
		end, debug.traceback)
		if not cleaned then
			warn("[Battle Pets] Invalid hatch cleanup recovered from an error:\n" .. tostring(cleanupError))
		end
		return
	end

	-- Onboarding follows the committed server result, never presentation timing.
	completeOnboardingStep("egg")
	local pets = resultDto.pets
	local presented = false
	local function onPresented()
		if presented then return end
		presented = true
		local gridSucceeded, gridError = xpcall(function()
			uiController:showEggBatch(pets)
		end, debug.traceback)
		if not gridSucceeded then
			warn("[Battle Pets] Hatch result grid recovered from a UI error:\n" .. tostring(gridError))
		end

		-- DisplayOrder 100 discovery toasts are released only after the DisplayOrder
		-- 50 cinematic has finalized, so they cannot cover the rare reveal.
		for _, petData in ipairs(pets) do
			if petData.isNewDiscovery == true then
				local toastSucceeded, toastError = xpcall(function()
					uiController:enqueueDiscoveryToast(petData)
				end, debug.traceback)
				if not toastSucceeded then
					warn("[Battle Pets] Discovery toast recovered from a UI error:\n" .. tostring(toastError))
				end
			end
		end
	end

	local enqueueSucceeded, acceptedOrError = xpcall(function()
		return effectsController:enqueueHatchBatch(resultDto, onPresented)
	end, debug.traceback)
	if not enqueueSucceeded then
		-- A controller boundary error must not lose the committed result.
		onPresented()
		warn("[Battle Pets] Hatch queue recovered from an error:\n" .. tostring(acceptedOrError))
	end
	-- acceptedOrError == false is the intentional bounded batchId dedupe path.
end)

CampaignBattleUpdate.OnClientEvent:Connect(function(battleState)
	campaignController:updateBattle(battleState)
end)

CampaignVictory.OnClientEvent:Connect(function(levelNum, rewards)
	campaignController:onVictory(rewards)
end)

CampaignDefeat.OnClientEvent:Connect(function()
	campaignController:onDefeat()
end)

UpgradeUpdated.OnClientEvent:Connect(function(upgrades)
	uiController:updateUpgrades(upgrades)
	if upgrades and upgrades.FasterPets then
		local fasterLevel = upgrades.FasterPets
		local fasterDef = QuestData.Quests.FasterPets
		if fasterDef and fasterDef.levels[fasterLevel] then
			petController:setFasterPetsMultiplier(fasterDef.levels[fasterLevel].bonus)
		end
	end
end)

local QuestProgressUpdated = Remotes:WaitForChild("QuestProgressUpdated")
QuestProgressUpdated.OnClientEvent:Connect(function(questProgress)
	uiController:updateQuestProgress(questProgress)
end)

local MasteryUpdated = Remotes:WaitForChild("MasteryUpdated")
MasteryUpdated.OnClientEvent:Connect(function(masteryState)
	uiController:updateMastery(masteryState)
end)

CollectCurrency.OnClientEvent:Connect(function(position, amount, currencyType)
	if currencyType == "Coins" and amount > 0 then
		completeOnboardingStep("coins")
	end
	local popupPosition = position
	if currencyType == "Diamonds" then
		popupPosition = position + Vector3.new(0, 1, 0)
	end
	effectsController:showCurrencyPopup(popupPosition, amount, currencyType)
end)

ShopBuffsUpdated.OnClientEvent:Connect(function(state)
	uiController:updateShopBuffs(state)
end)

local XPUpdated = Remotes:WaitForChild("XPUpdated")
local _previousLevel = playerData and playerData.level or 1
XPUpdated.OnClientEvent:Connect(function(level, xp, xpNeeded)
	uiController:updateXP(level, xp, xpNeeded)
	-- Detect level-up and show celebration effect
	if level > _previousLevel then
		effectsController:showLevelUpCelebration(level)
		_previousLevel = level
	end
end)

--------------------------------------------------------------------------------
-- PER-FRAME UPDATE (RenderStepped)
--------------------------------------------------------------------------------
RunService.RenderStepped:Connect(function(deltaTime)
	petController:update(deltaTime)
end)

--------------------------------------------------------------------------------
-- INPUT HANDLING - manual pet targeting + Crit-QTE
-- Short click: assign one pet and offer one Crit-QTE (zero direct click damage)
-- Hold (0.3s+): assign all pets once (no auto-click and no player damage)
--------------------------------------------------------------------------------
local HOLD_THRESHOLD = 0.3 -- seconds to distinguish click from hold
local mouseDownTime = 0
local mouseDownTarget = nil -- { destructibleId, part }
local isMouseDown = false
local holdFired = false -- whether we already sent all-pets command during this hold

local function resetCurrentGesture()
	isMouseDown = false
	mouseDownTarget = nil
	holdFired = false
end

-- Raycast only against server-created query hitboxes. The returned part remains
-- the canonical visual part used by pet movement, effects, and damage UI.
local function raycastForDestructible(screenPosition)
	local camera = workspace.CurrentCamera
	if not camera then return nil end

	local ray = camera:ScreenPointToRay(screenPosition.X, screenPosition.Y)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = clickHitboxList

	local result = workspace:Raycast(ray.Origin, ray.Direction * 200, raycastParams)
	if not result or not result.Instance then return nil end

	local destructibleId = result.Instance:GetAttribute("DestructibleId")
	if type(destructibleId) ~= "string" or destructibleId == "" then return nil end

	local canonicalPart = resolveDestructiblePart(destructibleId)
	if not canonicalPart then return nil end

	return {
		destructibleId = destructibleId,
		part = canonicalPart,
	}
end

-- Request one server-authorized Crit-QTE. Selecting a breakable never mutates
-- HP; only a successful click on the spawned weak-point circle can deal damage.
local function offerCritQTE(target)
	if not target or not target.destructibleId then return end
	if not target.part or not target.part.Parent then return end
	if effectsController:hasCritButtonActive() then return end

	local invoked, windowOpened = pcall(function()
		return RequestCritWindow:InvokeServer(target.destructibleId)
	end)
	if not invoked or windowOpened ~= true then return end
	if not target.part or not target.part.Parent then return end

	completeOnboardingStep("click")
	effectsController:spawnCritButton(target.part, target.destructibleId, function()
		local critInvoked, critSucceeded = pcall(function()
			return CritAttackDestructible:InvokeServer(target.destructibleId)
		end)
		if not critInvoked or critSucceeded ~= true then return end
		if target.part and target.part.Parent then
			effectsController:playCritSound(target.part.Position)
		end
		-- Authoritative damage text comes from DestructibleDamaged; do not create
		-- a second local popup here.
	end)
end

-- Mouse/Touch down: track click vs hold and offer one Crit-QTE.
-- This input never deals direct damage.
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then

		local target = raycastForDestructible(input.Position)
		if target then
			mouseDownTime = tick()
			mouseDownTarget = target
			isMouseDown = true
			holdFired = false
			offerCritQTE(target)
		else
			-- A ray miss only abandons this gesture. Existing assignments keep
			-- attacking, so clicking the same visible breakable can never cancel
			-- pets because of a transient input/raycast miss.
			resetCurrentGesture()
		end
	end
end)

-- Mouse/Touch up: if released before hold threshold, send exactly one pet.
UserInputService.InputEnded:Connect(function(input, _gameProcessed)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then

		if isMouseDown and mouseDownTarget and not holdFired then
			local elapsed = tick() - mouseDownTime
			if elapsed < HOLD_THRESHOLD then
				petController:sendOnePetToTarget(mouseDownTarget.destructibleId, mouseDownTarget.part)
			else
				-- Heartbeat may not have observed the threshold before release.
				holdFired = true
				petController:sendAllPetsToTarget(mouseDownTarget.destructibleId, mouseDownTarget.part)
			end
		end

		isMouseDown = false
		mouseDownTarget = nil
		holdFired = false
	end
end)

-- Detect hold once. Holding never repeats QTE requests or player attacks.
RunService.Heartbeat:Connect(function()
	if not isMouseDown or not mouseDownTarget then return end

	if not mouseDownTarget.part or not mouseDownTarget.part.Parent then
		isMouseDown = false
		mouseDownTarget = nil
		holdFired = false
		return
	end

	if not holdFired and (tick() - mouseDownTime) >= HOLD_THRESHOLD then
		holdFired = true
		petController:sendAllPetsToTarget(mouseDownTarget.destructibleId, mouseDownTarget.part)
	end
end)

--------------------------------------------------------------------------------
-- CHARACTER SETUP (campaign portal, egg stations, ProximityPrompt)
--------------------------------------------------------------------------------
local function onCharacterAdded(character)
	character:WaitForChild("HumanoidRootPart")
	refreshOnboardingHint()

	-- Campaign portal proximity (touch detection)
	local campaignPortal = workspace:FindFirstChild("CampaignPortal")
	if campaignPortal and campaignPortal:IsA("BasePart") then
		campaignPortal.Touched:Connect(function(hit)
			if hit:IsDescendantOf(character) then
				campaignController:showCampaignSelect(CampaignData, playerData and playerData.campaignProgress)
			end
		end)
	end

	-- Egg and shop prompts are routed once through ProximityPromptService above;
	-- no per-character connections are created here.
end

-- Connect character lifecycle. ResetOnSpawn=false keeps the one dialog instance,
-- while removing a character invalidates all pending quote/purchase callbacks.
player.CharacterRemoving:Connect(function()
	local eggType = activeEggType
	activeEggPrompt = nil
	activeEggType = nil
	closeHatchPurchaseDialog()
	if eggType then
		uiController:hideEggStationPrompt(eggType)
	end
end)
if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)

--------------------------------------------------------------------------------
-- READY
--------------------------------------------------------------------------------
print("[Battle Pets] Client initialized successfully!")
