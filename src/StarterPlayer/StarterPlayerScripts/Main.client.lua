--[[
	Main.client.lua - Client entry point for Battle Pets
	Initializes all client controllers, connects to RemoteEvents/RemoteFunctions,
	sets up per-frame updates (pet following, effects), and handles input.

	INPUT SYSTEM (Pet Simulator 1 style):
	- Single left click on destructible: send 1 pet to attack it
	- Hold left click (0.3s+) on destructible: send ALL pets to attack it
	- E-key: hatch egg when near egg station (via ProximityPrompt)
	- When not clicking: pets auto-distribute to different nearby destructibles
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

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

-- Create controller instances
local uiController = UIController.new()
local petController = PetController.new()
local campaignController = CampaignController.new()
local effectsController = EffectsController.new()
local musicController = MusicController.new()

-- Player reference
local player = Players.LocalPlayer

--------------------------------------------------------------------------------
-- REMOTE REFERENCES
--------------------------------------------------------------------------------
-- RemoteFunctions
local GetPlayerData = Remotes:WaitForChild("GetPlayerData")
local HatchEgg = Remotes:WaitForChild("HatchEgg")
local EquipPet = Remotes:WaitForChild("EquipPet")
local UnequipPet = Remotes:WaitForChild("UnequipPet")
local DeletePet = Remotes:WaitForChild("DeletePet")
local DeletePets = Remotes:WaitForChild("DeletePets")
local UnlockZone = Remotes:WaitForChild("UnlockZone")
local PurchaseUpgrade = Remotes:WaitForChild("PurchaseUpgrade")
local StartCampaignLevel = Remotes:WaitForChild("StartCampaignLevel")
local DeployPetInCampaign = Remotes:WaitForChild("DeployPetInCampaign")
local AttackDestructible = Remotes:WaitForChild("AttackDestructible")
local ClickAttackDestructible = Remotes:WaitForChild("ClickAttackDestructible")
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

-- Helper: find a Part in workspace.Zones that has a DestructibleId StringValue matching the given ID
local function resolveDestructiblePart(destructibleId)
	local zonesFolder = workspace:FindFirstChild("Zones")
	if not zonesFolder then return nil end
	for _, obj in ipairs(zonesFolder:GetDescendants()) do
		if obj:IsA("BasePart") then
			local idValue = obj:FindFirstChild("DestructibleId")
			if idValue and idValue.Value == destructibleId then
				return obj
			end
		end
	end
	return nil
end

-- Initialize all controllers
effectsController:init()
petController:init(Remotes)
campaignController:init(Remotes)
uiController:init(Remotes, playerData)
musicController:init()

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

-- Apply BiggerRange and DropMagnet mastery buffs from initial mastery state
local function applyMasteryBuffsToClient(masteryState)
	if not masteryState or not masteryState.buffs then return end

	-- BiggerRange: multiplies pet detection range
	local biggerRangeLevel = masteryState.buffs.BiggerRange or 0
	if biggerRangeLevel > 0 then
		local buffDef = MasteryData.Buffs.BiggerRange
		if buffDef and buffDef.bonusPerLevel[biggerRangeLevel] then
			petController:setBiggerRangeMultiplier(buffDef.bonusPerLevel[biggerRangeLevel])
		end
	else
		petController:setBiggerRangeMultiplier(1)
	end

	-- DropMagnet: multiplies drop collection radius (cosmetic-ready)
	local dropMagnetLevel = masteryState.buffs.DropMagnet or 0
	if dropMagnetLevel > 0 then
		local buffDef = MasteryData.Buffs.DropMagnet
		if buffDef and buffDef.bonusPerLevel[dropMagnetLevel] then
			petController:setDropMagnetMultiplier(buffDef.bonusPerLevel[dropMagnetLevel])
		end
	else
		petController:setDropMagnetMultiplier(1)
	end
end

-- Fetch initial mastery state and apply client-side buffs
local initialMasteryState = GetMasteryState:InvokeServer()
applyMasteryBuffsToClient(initialMasteryState)

--------------------------------------------------------------------------------
-- REMOTE EVENT HANDLERS
--------------------------------------------------------------------------------

CurrencyUpdated.OnClientEvent:Connect(function(coins, diamonds)
	uiController:updateCurrency(coins, diamonds)
end)

PetInventoryUpdated.OnClientEvent:Connect(function(pets)
	uiController:updatePetInventory(pets)
end)

PetEquipped.OnClientEvent:Connect(function(petData)
	print("[Client] PetEquipped event received: " .. tostring(petData and petData.name or "nil"))
	if petData and type(petData) == "table" and petData.id then
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
	if gatePosition then
		effectsController:showZoneUnlock(gatePosition)
	end
end)

DestructibleDamaged.OnClientEvent:Connect(function(destructibleId, currentHP, maxHP, damage)
	local destructiblePart = resolveDestructiblePart(destructibleId)
	if destructiblePart then
		effectsController:showProgressBar(destructiblePart, currentHP, maxHP)
		if damage and damage > 0 then
			petController:showDamageText(destructiblePart.Position, damage)
		end
	end
end)

DestructibleDestroyed.OnClientEvent:Connect(function(destructibleId, drops)
	local destructiblePart = resolveDestructiblePart(destructibleId)
	if destructiblePart then
		effectsController:removeProgressBar(destructiblePart)
		local pos = destructiblePart.Position
		-- Show poof effect with the destructible's color
		local poofColor = destructiblePart.Color or Color3.fromRGB(200, 200, 200)
		effectsController:showDestructiblePoof(pos, poofColor)
		if drops then
			if drops.Coins and drops.Coins > 0 then
				effectsController:showCurrencyPopup(pos, drops.Coins, "Coins")
			end
			if drops.Diamonds and drops.Diamonds > 0 then
				effectsController:showCurrencyPopup(pos + Vector3.new(0, 1, 0), drops.Diamonds, "Diamonds")
			end
		end
	else
		effectsController:removeProgressBar(destructibleId)
	end
end)

EggHatchStart.OnClientEvent:Connect(function(eggType)
	local hatchPosition = nil
	if player.Character then
		local hrp = player.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local lookVector = hrp.CFrame.LookVector
			hatchPosition = hrp.Position + lookVector * 6 + Vector3.new(0, 0, 0)
		end
	end
	if hatchPosition then
		effectsController._lastHatchPosition = hatchPosition
	end
	-- Start the egg wobble animation immediately so the player sees feedback right away
	effectsController:startEggWobble()
end)

EggHatchResult.OnClientEvent:Connect(function(petData)
	effectsController._lastHatchPosition = nil

	-- Complete the egg hatch animation (cancels wobble, does shakes + reveal)
	effectsController:completeEggHatch(petData)

	-- Delay the UIController modal until after the EffectsController animation
	-- finishes (~4s total: shakes + crack + flash + reveal + auto-dismiss)
	task.delay(4, function()
		uiController:showEggHatch(petData, petData and petData.isNewDiscovery)
	end)
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
	-- Reapply client-side mastery buffs (BiggerRange, DropMagnet, DoubleJump)
	applyMasteryBuffsToClient(masteryState)
end)

CollectCurrency.OnClientEvent:Connect(function(position, amount, currencyType)
	effectsController:showCurrencyPopup(position, amount, currencyType)
end)

ShopBuffsUpdated.OnClientEvent:Connect(function(buffs)
	uiController:updateShopBuffs(buffs)
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
-- INPUT HANDLING - Pet Simulator 1 style targeting + QTE Click-to-Damage
-- Single click: send 1 pet to target + deal 1 click damage
-- Hold click (0.3s+): send ALL pets to target + auto-click every 0.2s for damage
-- Each click deals 1 damage (player click damage, separate from pet auto-attack)
--------------------------------------------------------------------------------
local HOLD_THRESHOLD = 0.3 -- seconds to distinguish click from hold
local CLICK_COOLDOWN = 0.2 -- seconds between click damage (spam protection)
local AUTO_CLICK_INTERVAL = 0.2 -- seconds between auto-clicks when holding
local mouseDownTime = 0
local mouseDownTarget = nil -- { destructibleId, part }
local isMouseDown = false
local holdFired = false -- whether we already sent all-pets command during this hold
local lastClickDamageTime = 0 -- cooldown tracker for click damage
local autoClickActive = false -- whether auto-click is running from hold

-- Helper: Raycast from screen position to find a destructible
local function raycastForDestructible(screenPosition)
	local camera = workspace.CurrentCamera
	if not camera then return nil end

	local ray = camera:ViewportPointToRay(screenPosition.X, screenPosition.Y)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { player.Character }

	local result = workspace:Raycast(ray.Origin, ray.Direction * 200, raycastParams)
	if not result or not result.Instance then return nil end

	local hit = result.Instance
	local zonesFolder = workspace:FindFirstChild("Zones")
	if not zonesFolder or not hit:IsDescendantOf(zonesFolder) then return nil end

	-- Check if the hit part has a DestructibleId
	local destructibleIdValue = hit:FindFirstChild("DestructibleId")
	-- If not on the hit part, check parent Model children
	if not destructibleIdValue and hit.Parent then
		for _, sibling in ipairs(hit.Parent:GetChildren()) do
			if sibling:IsA("BasePart") then
				local idVal = sibling:FindFirstChild("DestructibleId")
				if idVal then
					destructibleIdValue = idVal
					hit = sibling
					break
				end
			end
		end
	end

	if not destructibleIdValue then return nil end

	return {
		destructibleId = destructibleIdValue.Value,
		part = hit,
	}
end

-- Helper: fire click damage to server and show effects
local function fireClickDamage(target)
	if not target or not target.destructibleId then return end

	local now = tick()
	if (now - lastClickDamageTime) < CLICK_COOLDOWN then return end
	lastClickDamageTime = now

	-- Fire click attack to server (always 1 damage)
	ClickAttackDestructible:InvokeServer(target.destructibleId)

	-- Spawn a crit button only if there is NOT already one active
	-- Prevents spammy rapid spawn/destroy cycles on every click
	if target.part and target.part.Parent and not effectsController:hasCritButtonActive() then
		effectsController:spawnCritButton(target.part, target.destructibleId, function()
			-- Crit button was clicked: fire crit attack to server
			CritAttackDestructible:InvokeServer(target.destructibleId)

			-- Show crit visual feedback
			effectsController:playCritSound(target.part.Position)

			-- Show gold "CRIT! 2" popup
			local critPos = target.part.Position + Vector3.new(0, 2, 0)
			petController:showDamageText(critPos, 2, true)
		end)
	end

	-- Show visual effects for the click
	if target.part and target.part.Parent then
		-- Show "1" damage popup at the destructible position
		local popupPos = target.part.Position + Vector3.new(
			(math.random() - 0.5) * 2,
			1,
			(math.random() - 0.5) * 2
		)
		petController:showDamageText(popupPos, 1)

		-- Show hit effect (shake/flash) on the destructible
		effectsController:showClickHitEffect(target.part)

		-- Play satisfying click sound
		effectsController:playClickSound(target.part.Position)
	end
end

-- Mouse/Touch down: start tracking for click vs hold + immediate click damage
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
			autoClickActive = false

			-- Immediate click damage on first press
			fireClickDamage(target)
		else
			-- Clicked on empty space: cancel all pet attacks, return them to player
			petController:cancelAllAttacks()
			isMouseDown = false
			mouseDownTarget = nil
			holdFired = false
			autoClickActive = false
		end
	end
end)

-- Mouse/Touch up: if released before hold threshold, it is a single click (send 1 pet)
UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then

		if isMouseDown and mouseDownTarget and not holdFired then
			local elapsed = tick() - mouseDownTime
			if elapsed < HOLD_THRESHOLD then
				-- SINGLE CLICK: send only 1 pet to the target
				petController:sendOnePetToTarget(mouseDownTarget.destructibleId, mouseDownTarget.part)
			end
		end

		-- Reset state
		isMouseDown = false
		mouseDownTarget = nil
		holdFired = false
		autoClickActive = false
	end
end)

-- Per-frame check: detect hold (0.3s+) while mouse is still down
-- Also handles auto-click damage every 0.2s while holding
RunService.Heartbeat:Connect(function()
	if not isMouseDown or not mouseDownTarget then return end

	local elapsed = tick() - mouseDownTime

	-- Send all pets once when hold threshold reached
	if not holdFired and elapsed >= HOLD_THRESHOLD then
		holdFired = true
		autoClickActive = true
		petController:sendAllPetsToTarget(mouseDownTarget.destructibleId, mouseDownTarget.part)
	end

	-- Auto-click damage while holding (every AUTO_CLICK_INTERVAL seconds)
	if autoClickActive and mouseDownTarget then
		-- Check if the target still exists
		if mouseDownTarget.part and mouseDownTarget.part.Parent then
			fireClickDamage(mouseDownTarget)
		else
			-- Target destroyed, stop auto-clicking
			autoClickActive = false
			isMouseDown = false
			mouseDownTarget = nil
			holdFired = false
		end
	end
end)

--------------------------------------------------------------------------------
-- CHARACTER SETUP (campaign portal, egg stations, ProximityPrompt)
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- DOUBLE JUMP SYSTEM
-- Shared state lives outside onCharacterAdded so that MasteryUpdated and
-- JumpRequest connections are created only once (avoiding event leaks on respawn).
--------------------------------------------------------------------------------
local _djJumpCount = 0
local _djMaxJumps = 1 -- default: single jump only
local _djHumanoid = nil -- current humanoid reference, updated on each respawn

-- Compute maxJumps from mastery state
local function updateMaxJumps(masteryState)
	if masteryState and masteryState.buffs then
		local djLevel = masteryState.buffs.DoubleJump or 0
		if djLevel > 0 then
			local buffDef = MasteryData.Buffs.DoubleJump
			if buffDef and buffDef.bonusPerLevel[djLevel] then
				_djMaxJumps = buffDef.bonusPerLevel[djLevel]
			end
		else
			_djMaxJumps = 1
		end
	end
end

-- Apply from initial mastery state
updateMaxJumps(initialMasteryState)

-- Listen for mastery updates to refresh maxJumps (single connection, never leaks)
MasteryUpdated.OnClientEvent:Connect(function(masteryState)
	updateMaxJumps(masteryState)
end)

-- Handle jump requests for extra jumps (single connection, never leaks)
UserInputService.JumpRequest:Connect(function()
	if _djMaxJumps <= 1 then return end -- no double jump mastery
	if not _djHumanoid or not _djHumanoid.Parent then return end
	if _djHumanoid:GetState() == Enum.HumanoidStateType.Freefall then
		if _djJumpCount < _djMaxJumps then
			_djHumanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end
end)

local function onCharacterAdded(character)
	local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
	local humanoid = character:WaitForChild("Humanoid")

	-- Update shared DoubleJump state for this new character
	_djHumanoid = humanoid
	_djJumpCount = 0

	-- StateChanged is scoped to this humanoid instance (garbage-collected on death)
	humanoid.StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.Landed then
			_djJumpCount = 0
		elseif newState == Enum.HumanoidStateType.Jumping then
			_djJumpCount = _djJumpCount + 1
		end
	end)

	-- Campaign portal proximity (touch detection)
	local campaignPortal = workspace:FindFirstChild("CampaignPortal")
	if campaignPortal and campaignPortal:IsA("BasePart") then
		campaignPortal.Touched:Connect(function(hit)
			if hit:IsDescendantOf(character) then
				campaignController:showCampaignSelect(CampaignData, playerData and playerData.campaignProgress)
			end
		end)
	end

	-- Egg station proximity detection (touch-based fallback)
	local eggStationsFolder = workspace:FindFirstChild("EggStations")
	if eggStationsFolder then
		for _, obj in ipairs(eggStationsFolder:GetChildren()) do
			if obj:IsA("BasePart") and obj.Name:find("InteractZone_") then
				local eggTypeTag = obj:FindFirstChild("EggType")
				if eggTypeTag then
					obj.Touched:Connect(function(hit)
						if hit:IsDescendantOf(character) then
							uiController:showEggStationPrompt(eggTypeTag.Value)
						end
					end)
				end
			end
		end
	end

	-- ProximityPrompt interaction for egg stations (E-key)
	-- This is the primary egg interaction method: directly invokes HatchEgg on server
	local function connectEggPrompts()
		local stationsFolder = workspace:FindFirstChild("EggStations")
		if not stationsFolder then return end
		for _, obj in ipairs(stationsFolder:GetChildren()) do
			if obj:IsA("BasePart") and obj.Name == "EggModel" then
				local prompt = obj:FindFirstChild("HatchPrompt")
				local promptTag = obj:FindFirstChild("PromptEggType")
				if prompt and promptTag then
					prompt.Triggered:Connect(function(triggerPlayer)
						if triggerPlayer == player then
							-- Directly invoke HatchEgg on server (validates cost server-side)
							local eggType = promptTag.Value
							HatchEgg:InvokeServer(eggType)
						end
					end)
				end
			end
		end
	end
	connectEggPrompts()
	-- Also listen for any future egg stations (in case they spawn after character loads)
	task.delay(2, connectEggPrompts)
end

-- Connect character added
if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)

--------------------------------------------------------------------------------
-- READY
--------------------------------------------------------------------------------
print("[Battle Pets] Client initialized successfully!")
