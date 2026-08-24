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
-- Get initial player data from server
local playerData = GetPlayerData:InvokeServer()

-- Initialize all controllers
effectsController:init()
petController:init(Remotes)
campaignController:init(Remotes)
uiController:init(Remotes, playerData)

-- Initialize equipped pets visuals
if playerData and playerData.equippedPets then
	petController:updateEquippedPets(playerData.equippedPets)
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

-- Pet equipped
PetEquipped.OnClientEvent:Connect(function(equippedPets)
	uiController:updateEquippedPets(equippedPets)
	petController:updateEquippedPets(equippedPets)
end)

-- Pet unequipped
PetUnequipped.OnClientEvent:Connect(function(equippedPets)
	uiController:updateEquippedPets(equippedPets)
	petController:updateEquippedPets(equippedPets)
end)

-- Zone unlocked
ZoneUnlocked.OnClientEvent:Connect(function(zoneId, gatePosition)
	if gatePosition then
		effectsController:showZoneUnlock(gatePosition)
	end
end)

-- Destructible damaged
DestructibleDamaged.OnClientEvent:Connect(function(destructible, currentHP, maxHP, damage)
	effectsController:updateProgressBar(destructible, currentHP, maxHP)
	if destructible and destructible:IsA("BasePart") then
		petController:showDamageText(destructible.Position, damage)
	end
end)

-- Destructible destroyed
DestructibleDestroyed.OnClientEvent:Connect(function(destructible, drops)
	effectsController:removeProgressBar(destructible)
	-- Show currency popup at destructible position
	if destructible and destructible:IsA("BasePart") then
		local pos = destructible.Position
		if drops then
			if drops.Coins and drops.Coins > 0 then
				effectsController:showCurrencyPopup(pos, drops.Coins, "Coins")
			end
			if drops.Diamonds and drops.Diamonds > 0 then
				effectsController:showCurrencyPopup(pos + Vector3.new(0, 1, 0), drops.Diamonds, "Diamonds")
			end
		end
	end
end)

-- Egg hatch started (play animation)
EggHatchStart.OnClientEvent:Connect(function(eggPosition, eggType)
	-- Animation will play at the egg position
	-- The result will come in EggHatchResult
end)

-- Egg hatch result
EggHatchResult.OnClientEvent:Connect(function(petData, eggPosition)
	if eggPosition then
		effectsController:showEggHatchAnimation(eggPosition, petData)
	end
	uiController:showEggHatch(petData)
end)

-- Campaign battle state update
CampaignBattleUpdate.OnClientEvent:Connect(function(battleState)
	campaignController:updateBattle(battleState)
end)

-- Campaign victory
CampaignVictory.OnClientEvent:Connect(function(rewards)
	campaignController:onVictory(rewards)
end)

-- Campaign defeat
CampaignDefeat.OnClientEvent:Connect(function()
	campaignController:onDefeat()
end)

-- Upgrade purchased/updated
UpgradeUpdated.OnClientEvent:Connect(function(upgrades)
	uiController:updateUpgrades(upgrades)
end)

-- Currency collected (floating popup at position)
CollectCurrency.OnClientEvent:Connect(function(position, amount, currencyType)
	effectsController:showCurrencyPopup(position, amount, currencyType)
end)

--------------------------------------------------------------------------------
-- PER-FRAME UPDATE (RenderStepped)
--------------------------------------------------------------------------------
RunService.RenderStepped:Connect(function(deltaTime)
	-- Update pet following/orbiting
	petController:update(deltaTime)

	-- Check if player is near a destructible and send pets to attack
	local nearestDestructible = petController:getNearestDestructible(20)
	if nearestDestructible then
		-- Show progress bar
		local hpValue = nearestDestructible:FindFirstChild("HP")
		local maxHPValue = nearestDestructible:FindFirstChild("MaxHP")
		if hpValue and maxHPValue then
			effectsController:showProgressBar(nearestDestructible, hpValue.Value, maxHPValue.Value)
		end
	end
end)

--------------------------------------------------------------------------------
-- INPUT HANDLING
--------------------------------------------------------------------------------
-- Auto-attack: when player clicks/taps on a destructible
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

		local result = workspace:Raycast(ray.Origin, ray.Direction * 100, raycastParams)
		if result and result.Instance then
			local hit = result.Instance
			-- Check if the hit object is in the Destructibles folder
			local destructiblesFolder = workspace:FindFirstChild("Destructibles")
			if destructiblesFolder and hit:IsDescendantOf(destructiblesFolder) then
				-- Send all equipped pets to attack this destructible
				for uniqueId, _ in pairs(petController._equippedPets) do
					petController:sendPetToAttack(uniqueId, hit)
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
