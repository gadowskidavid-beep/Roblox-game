--[[
	EggService.lua - Egg hatching orchestration
	Validates purchase, triggers animation events, and delegates to PetService for hatching.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(game.ReplicatedStorage.Shared.Config)
local PetData = require(game.ReplicatedStorage.Shared.PetData)

local EggService = {}

-- References to other services
EggService._dataService = nil
EggService._currencyService = nil
EggService._petService = nil

function EggService.init(dataService, currencyService, petService)
	EggService._dataService = dataService
	EggService._currencyService = currencyService
	EggService._petService = petService
end

-- Purchase and hatch an egg (full flow with animation delay)
function EggService.purchaseAndHatch(player, eggType)
	if not player or type(eggType) ~= "string" then
		return nil, "Invalid parameters"
	end

	-- Validate egg type exists
	local eggDef = PetData.Eggs[eggType]
	if not eggDef then
		return nil, "Unknown egg type: " .. tostring(eggType)
	end

	local data = EggService._dataService.getPlayerData(player)
	if not data then
		return nil, "No player data"
	end

	-- Validate player has unlocked the required zone for this egg
	local zoneRequired = eggDef.zone
	local zoneUnlocked = false
	for _, unlockedId in ipairs(data.unlockedZones) do
		if unlockedId == zoneRequired then
			zoneUnlocked = true
			break
		end
	end
	if not zoneUnlocked then
		return nil, "Zone not unlocked for this egg type"
	end

	-- Validate cost (check before deducting - PetService.hatchEgg also deducts)
	local eggCost = Config.EggCosts[zoneRequired]
	if eggCost and eggCost.Coins then
		local balance = EggService._currencyService.getBalance(player)
		if balance.coins < eggCost.Coins then
			return nil, "Not enough coins"
		end
	end

	-- Fire hatch start event to client (triggers animation)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local event = remotes:FindFirstChild("EggHatchStart")
		if event then
			event:FireClient(player, eggType)
		end
	end

	-- Short delay to allow client to play animation
	task.wait(2)

	-- Delegate to PetService for actual hatching (handles cost deduction)
	local newPet, err = EggService._petService.hatchEgg(player, eggType)
	if not newPet then
		return nil, err
	end

	-- Fire hatch result event with the new pet data
	if remotes then
		local event = remotes:FindFirstChild("EggHatchResult")
		if event then
			event:FireClient(player, newPet)
		end
	end

	return newPet, nil
end

-- Get eggs available to a player based on their unlocked zones
function EggService.getAvailableEggs(player)
	if not player then
		return {}
	end

	local data = EggService._dataService.getPlayerData(player)
	if not data then
		return {}
	end

	local available = {}
	for eggType, eggDef in pairs(PetData.Eggs) do
		for _, unlockedId in ipairs(data.unlockedZones) do
			if unlockedId == eggDef.zone then
				table.insert(available, {
					eggType = eggType,
					name = eggDef.name,
					zone = eggDef.zone,
					cost = Config.EggCosts[eggDef.zone],
				})
				break
			end
		end
	end

	return available
end

return EggService
