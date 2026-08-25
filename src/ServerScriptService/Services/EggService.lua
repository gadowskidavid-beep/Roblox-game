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
EggService._questService = nil

-- Per-player purchase lock to prevent concurrent hatch exploits
EggService._hatchLock = {}

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

	-- Per-player lock: prevent concurrent egg hatching
	if EggService._hatchLock[player.UserId] then
		return nil, "Already hatching an egg"
	end
	EggService._hatchLock[player.UserId] = true

	-- Wrap in a function so we can always release the lock
	local function doHatch()
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

		-- Deduct cost BEFORE the animation delay to prevent TOCTOU race condition
		local eggCost = Config.EggCosts[zoneRequired]
		if eggCost and eggCost.Coins then
			local success = EggService._currencyService.removeCoins(player, eggCost.Coins)
			if not success then
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

		-- Short delay to allow client to start animation (1 second; wobble begins immediately on client)
		task.wait(1)

		-- Delegate to PetService for actual hatching (cost already deducted)
		local newPet, err = EggService._petService.hatchEgg(player, eggType, true)
		if not newPet then
			-- Refund the coins if hatching failed for some reason
			if eggCost and eggCost.Coins then
				EggService._currencyService.addCoins(player, eggCost.Coins)
			end
			return nil, err
		end

		-- Fire hatch result event with the new pet data
		if remotes then
			local event = remotes:FindFirstChild("EggHatchResult")
			if event then
				event:FireClient(player, newPet)
			end
		end

		-- Strip isNewDiscovery from the pet table so it does not persist in DataStore
		newPet.isNewDiscovery = nil

		-- Track quest progress: egg hatched
		if EggService._questService then
			EggService._questService.incrementStat(player, "hatchEggs", 1)
		end

		return newPet, nil
	end

	local newPet, err = doHatch()
	EggService._hatchLock[player.UserId] = nil
	return newPet, err
end

-- Set quest service reference (called after init to avoid circular deps)
function EggService.setQuestService(questService)
	EggService._questService = questService
end

-- Hatch an egg for free (used by auto-hatch; no cost deduction, still validates zone)
function EggService.hatchFree(player, eggType)
	if not player or type(eggType) ~= "string" then
		return nil, "Invalid parameters"
	end

	-- Per-player lock: prevent concurrent egg hatching
	if EggService._hatchLock[player.UserId] then
		return nil, "Already hatching an egg"
	end
	EggService._hatchLock[player.UserId] = true

	local function doHatch()
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

		-- No cost deduction for auto-hatch (player already paid for the buff)

		-- Fire hatch start event to client (triggers animation)
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		if remotes then
			local event = remotes:FindFirstChild("EggHatchStart")
			if event then
				event:FireClient(player, eggType)
			end
		end

		-- Short delay to allow client to start animation
		task.wait(1)

		-- Delegate to PetService for actual hatching (skip cost deduction)
		local newPet, err = EggService._petService.hatchEgg(player, eggType, true)
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

		-- Strip isNewDiscovery from the pet table so it does not persist in DataStore
		newPet.isNewDiscovery = nil

		-- Track quest progress: egg hatched
		if EggService._questService then
			EggService._questService.incrementStat(player, "hatchEggs", 1)
		end

		return newPet, nil
	end

	local newPet, err = doHatch()
	EggService._hatchLock[player.UserId] = nil
	return newPet, err
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
