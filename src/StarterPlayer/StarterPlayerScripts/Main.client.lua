--[[
	Main.client.lua - Client entry point for Battle Pets
	Initializes all client controllers, connects to RemoteEvents/RemoteFunctions,
	sets up per-frame updates (pet following, effects), and handles input.
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

-- Require controllers
local UIController = require(script.Parent:WaitForChild("UIController"))
local PetController = require(script.Parent:WaitForChild("PetController"))
local CampaignController = require(script.Parent:WaitForChild("CampaignController"))
local EffectsController = require(script.Parent:WaitForChild("EffectsController"))

-- Create controller instances
local uiController = UIController.new()
local petController = PetController.new()
local campaignController = CampaignController.new()
local effectsController = EffectsController.new()

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

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------
-- Get initial player data from server (may be nil if DataService load fails)
local playerData = GetPlayerData:InvokeServer()
if not playerData then
	-- Use safe defaults so the UI still renders
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
	-- equippedPets is an array of string IDs; look up full pet data from pets array
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
-- Supports both single-part and multi-part (Model-based) destructibles
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

-- Initialize equipped pets visuals from initial data (called ONCE)
-- Build the local list from server data and update both controllers
if playerData and playerData.equippedPets then
	localEquippedPets = buildEquippedListFromData(playerData)
	-- Deduplicate: ensure no pet ID appears twice in the list
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
	local fasterDef = Config.Upgrades.FasterPets
	if fasterDef and fasterDef.levels[fasterLevel] then
		petController:setFasterPetsMultiplier(fasterDef.levels[fasterLevel].bonus)
	end
end

--------------------------------------------------------------------------------
-- REMOTE EVENT HANDLERS
--------------------------------------------------------------------------------

-- Currency updated from server
CurrencyUpdated.OnClientEvent:Connect(function(coins, diamonds)
	uiController:updateCurrency(coins, diamonds)
end)

-- Pet inventory updated (full refresh)
PetInventoryUpdated.OnClientEvent:Connect(function(pets)
	uiController:updatePetInventory(pets)
end)

-- Pet equipped (server sends a single pet table with .id field)
PetEquipped.OnClientEvent:Connect(function(petData)
	-- Add the newly equipped pet to our local list (strict deduplication)
	if petData and type(petData) == "table" and petData.id then
		-- Remove any existing entry with same ID first (prevents duplicates)
		for i = #localEquippedPets, 1, -1 do
			if localEquippedPets[i].id == petData.id then
				table.remove(localEquippedPets, i)
			end
		end
		-- Add the pet
		table.insert(localEquippedPets, petData)
	end
	petController:updateEquippedPets(localEquippedPets)
	uiController:updateEquippedPets(localEquippedPets)
end)

-- Pet unequipped (server sends a single string petInstanceId)
PetUnequipped.OnClientEvent:Connect(function(petInstanceId)
	-- Remove the unequipped pet from our local list
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

-- Zone unlocked
ZoneUnlocked.OnClientEvent:Connect(function(zoneId, gatePosition)
	if gatePosition then
		effectsController:showZoneUnlock(gatePosition)
	end
end)

-- Destructible damaged (server sends string destructibleId, currentHP, maxHP, damage)
DestructibleDamaged.OnClientEvent:Connect(function(destructibleId, currentHP, maxHP, damage)
	-- Resolve string ID to a Part in workspace.Zones
	local destructiblePart = resolveDestructiblePart(destructibleId)
	if destructiblePart then
		-- Show or update progress bar (show creates it if not existing)
		effectsController:showProgressBar(destructiblePart, currentHP, maxHP)
		if damage and damage > 0 then
			petController:showDamageText(destructiblePart.Position, damage)
		end
	end
end)

-- Destructible destroyed (server sends string destructibleId, drops table)
DestructibleDestroyed.OnClientEvent:Connect(function(destructibleId, drops)
	-- Resolve string ID to a Part in workspace.Zones
	local destructiblePart = resolveDestructiblePart(destructibleId)
	if destructiblePart then
		effectsController:removeProgressBar(destructiblePart)
		-- Show currency popup at destructible position
		local pos = destructiblePart.Position
		if drops then
			if drops.Coins and drops.Coins > 0 then
				effectsController:showCurrencyPopup(pos, drops.Coins, "Coins")
			end
			if drops.Diamonds and drops.Diamonds > 0 then
				effectsController:showCurrencyPopup(pos + Vector3.new(0, 1, 0), drops.Diamonds, "Diamonds")
			end
		end
	else
		-- Part may already be destroyed on server; just clean up by ID
		effectsController:removeProgressBar(destructibleId)
	end
end)

-- Egg hatch started (server sends eggType; start the egg animation early at player position)
EggHatchStart.OnClientEvent:Connect(function(eggType)
	-- Show the large egg appearing in front of the player as soon as hatch starts
	local hatchPosition = nil
	if player.Character then
		local hrp = player.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			-- Position the egg in front of the player
			local lookVector = hrp.CFrame.LookVector
			hatchPosition = hrp.Position + lookVector * 6 + Vector3.new(0, 0, 0)
		end
	end
	-- Store hatch position for the result handler
	if hatchPosition then
		effectsController._lastHatchPosition = hatchPosition
	end
end)

-- Egg hatch result (server sends newPet data; play full animation)
EggHatchResult.OnClientEvent:Connect(function(petData)
	-- Use stored hatch position or calculate from player
	local hatchPosition = effectsController._lastHatchPosition
	if not hatchPosition then
		if player.Character then
			local hrp = player.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local lookVector = hrp.CFrame.LookVector
				hatchPosition = hrp.Position + lookVector * 6
			end
		end
	end
	effectsController._lastHatchPosition = nil

	if hatchPosition then
		effectsController:showEggHatchAnimation(hatchPosition, petData)
	end
	-- Show UI overlay after animation completes (delay to match animation)
	task.delay(3, function()
		uiController:showEggHatch(petData)
	end)
end)

-- Campaign battle state update
CampaignBattleUpdate.OnClientEvent:Connect(function(battleState)
	campaignController:updateBattle(battleState)
end)

-- Campaign victory (server sends levelNum, rewards)
CampaignVictory.OnClientEvent:Connect(function(levelNum, rewards)
	campaignController:onVictory(rewards)
end)

-- Campaign defeat
CampaignDefeat.OnClientEvent:Connect(function()
	campaignController:onDefeat()
end)

-- Upgrade purchased/updated
UpgradeUpdated.OnClientEvent:Connect(function(upgrades)
	uiController:updateUpgrades(upgrades)
	-- Apply FasterPets upgrade to PetController
	if upgrades and upgrades.FasterPets then
		local fasterLevel = upgrades.FasterPets
		local fasterDef = Config.Upgrades.FasterPets
		if fasterDef and fasterDef.levels[fasterLevel] then
			petController:setFasterPetsMultiplier(fasterDef.levels[fasterLevel].bonus)
		end
	end
end)

-- Currency collected (floating popup at position)
CollectCurrency.OnClientEvent:Connect(function(position, amount, currencyType)
	effectsController:showCurrencyPopup(position, amount, currencyType)
end)

-- XP updated from server (level, xp, xpNeeded)
local XPUpdated = Remotes:WaitForChild("XPUpdated")
XPUpdated.OnClientEvent:Connect(function(level, xp, xpNeeded)
	uiController:updateXP(level, xp, xpNeeded)
end)

--------------------------------------------------------------------------------
-- PER-FRAME UPDATE (RenderStepped)
--------------------------------------------------------------------------------
RunService.RenderStepped:Connect(function(deltaTime)
	-- Update pet following/orbiting
	petController:update(deltaTime)

	-- NOTE: We do NOT check for HP/MaxHP IntValue children here.
	-- The server-side ZoneService only creates a StringValue "DestructibleId"
	-- on each destructible Part. The client learns HP state through the
	-- DestructibleDamaged remote event, which calls effectsController:updateProgressBar.
	-- The progress bar is shown when the first DestructibleDamaged event arrives.
end)

--------------------------------------------------------------------------------
-- INPUT HANDLING
--------------------------------------------------------------------------------
-- Manual click/tap on a destructible is optional - pets auto-attack nearby targets.
-- Clicking a specific destructible will immediately direct pets to attack it.
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		-- Raycast to check if player clicked a destructible
		local camera = workspace.CurrentCamera
		if not camera then return end

		local position = input.Position
		local ray = camera:ViewportPointToRay(position.X, position.Y)
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.FilterDescendantsInstances = { player.Character }

		local result = workspace:Raycast(ray.Origin, ray.Direction * 200, raycastParams)
		if result and result.Instance then
			local hit = result.Instance
			-- Check if the hit object is in the Zones folder (where destructibles live)
			local zonesFolder = workspace:FindFirstChild("Zones")
			if zonesFolder and hit:IsDescendantOf(zonesFolder) then
				-- Verify this is a destructible (has DestructibleId value on self or parent model)
				local destructibleIdValue = hit:FindFirstChild("DestructibleId")
				-- If the hit part doesn't have the ID, check parent (Model-based destructibles)
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
				if destructibleIdValue then
					-- Extract the string ID to send to the server
					local destructibleId = destructibleIdValue.Value

					-- Send all equipped pets to visually attack (animation only)
					for uniqueId, _ in pairs(petController._equippedPets) do
						petController:sendPetToAttack(uniqueId, destructibleId, hit)
					end

					-- Fire ONE attack remote call (server sums all equipped pet damage)
					petController:fireAttackRemote(destructibleId)
				end
			end
		end
	end
end)

-- Campaign portal interaction (touch detection)
local function onCharacterAdded(character)
	local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

	-- Check for campaign portal proximity
	local campaignPortal = workspace:FindFirstChild("CampaignPortal")
	if campaignPortal and campaignPortal:IsA("BasePart") then
		local touchConnection
		touchConnection = campaignPortal.Touched:Connect(function(hit)
			if hit:IsDescendantOf(character) then
				campaignController:showCampaignSelect(CampaignData, playerData and playerData.campaignProgress)
			end
		end)
	end

	-- Egg station proximity detection: when player touches the interact zone, trigger hatch
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
	-- Listen for ProximityPrompts on egg model parts
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
							uiController:showEggStationPrompt(promptTag.Value)
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
