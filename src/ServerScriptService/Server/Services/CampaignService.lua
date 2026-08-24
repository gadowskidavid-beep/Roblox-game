--[[
	CampaignService.lua - Campaign battle logic (Battle Cats style)
	Manages battle state per player: deploying pets, enemy waves, combat, and victory/defeat.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(game.ReplicatedStorage.Shared.Config)
local CampaignData = require(game.ReplicatedStorage.Shared.CampaignData)

local CampaignService = {}

-- References to other services
CampaignService._dataService = nil
CampaignService._currencyService = nil
CampaignService._petService = nil

-- Active battles indexed by player UserId
CampaignService._activeBattles = {}

-- Lane configuration
local LANE_LENGTH = 100
local PET_START_X = 0
local ENEMY_START_X = LANE_LENGTH

function CampaignService.init(dataService, currencyService, petService)
	CampaignService._dataService = dataService
	CampaignService._currencyService = currencyService
	CampaignService._petService = petService

	-- Connect to Heartbeat for battle updates
	RunService.Heartbeat:Connect(function(dt)
		CampaignService.update(dt)
	end)
end

-- Start a campaign level for a player
function CampaignService.startLevel(player, levelNum)
	if not player or type(levelNum) ~= "number" then
		return false, "Invalid parameters"
	end

	-- Validate level exists
	levelNum = math.floor(levelNum)
	if levelNum < 1 or levelNum > 48 then
		return false, "Invalid level number"
	end

	local levelDef = CampaignData.Levels[levelNum]
	if not levelDef then
		return false, "Level data not found"
	end

	local data = CampaignService._dataService.getPlayerData(player)
	if not data then
		return false, "No player data"
	end

	-- Validate prerequisite: must have beaten previous level (or this is level 1)
	if levelNum > 1 then
		local prevLevel = levelNum - 1
		local beaten = false
		for _, completedLevel in ipairs(data.campaignProgress) do
			if completedLevel == prevLevel then
				beaten = true
				break
			end
		end
		if not beaten then
			return false, "Must complete level " .. tostring(prevLevel) .. " first"
		end
	end

	-- Check not already in a battle
	if CampaignService._activeBattles[player.UserId] then
		return false, "Already in a battle"
	end

	-- Build initial enemy queue from waves
	local enemyWaves = {}
	for waveNum, wave in ipairs(levelDef.waves) do
		local waveEnemies = {}
		for _, spawn in ipairs(wave) do
			local enemyDef = CampaignData.Enemies[spawn.enemy]
			if enemyDef then
				for _ = 1, spawn.count do
					table.insert(waveEnemies, {
						name = spawn.enemy,
						hp = enemyDef.hp,
						maxHp = enemyDef.hp,
						damage = enemyDef.damage,
						speed = enemyDef.speed,
						isBoss = enemyDef.isBoss or false,
					})
				end
			end
		end
		enemyWaves[waveNum] = waveEnemies
	end

	-- Create battle state
	local battleState = {
		levelNum = levelNum,
		levelDef = levelDef,
		energy = Config.Campaign.MaxEnergy,
		maxEnergy = Config.Campaign.MaxEnergy,
		energyRegenRate = Config.Campaign.EnergyRegenRate,
		playerBaseHP = Config.Campaign.BaseHealth,
		enemyBaseHP = levelDef.enemyBaseHP,
		deployedPets = {},
		enemies = {},
		currentWave = 1,
		waveSpawnTimer = 0,
		waveSpawnInterval = 5, -- seconds between waves
		enemyWaves = enemyWaves,
		totalWaves = #levelDef.waves,
		active = true,
		spawnedCurrentWave = false,
	}

	CampaignService._activeBattles[player.UserId] = battleState

	-- Spawn first wave
	CampaignService._spawnWave(player.UserId, battleState)

	return true, nil
end

-- Deploy a pet into the current battle
function CampaignService.deployPet(player, petInstanceId)
	if not player or type(petInstanceId) ~= "string" then
		return false, "Invalid parameters"
	end

	local battle = CampaignService._activeBattles[player.UserId]
	if not battle or not battle.active then
		return false, "No active battle"
	end

	local data = CampaignService._dataService.getPlayerData(player)
	if not data then
		return false, "No player data"
	end

	-- Find the pet in player's inventory
	local petInstance = nil
	for _, pet in ipairs(data.pets) do
		if pet.id == petInstanceId then
			petInstance = pet
			break
		end
	end

	if not petInstance then
		return false, "Pet not found in inventory"
	end

	-- Get energy cost from rarity
	local deployCost = CampaignData.DeployCosts[petInstance.rarity]
	if not deployCost then
		return false, "Unknown rarity for deploy cost"
	end

	-- Validate energy
	if battle.energy < deployCost then
		return false, "Not enough energy"
	end

	-- Deduct energy
	battle.energy = battle.energy - deployCost

	-- Calculate effective damage with upgrades
	local effectiveDamage = CampaignService._petService.getPetDamage(petInstance, player)

	-- Get pet base speed from PetData
	local PetData = require(game.ReplicatedStorage.Shared.PetData)
	local petDef = PetData.Pets[petInstance.petId]
	local speed = petDef and petDef.baseSpeed or 10

	-- Add pet entity to deployed list
	table.insert(battle.deployedPets, {
		id = petInstanceId,
		name = petInstance.name,
		rarity = petInstance.rarity,
		hp = effectiveDamage * 5, -- HP based on damage as simple scaling
		maxHp = effectiveDamage * 5,
		damage = effectiveDamage,
		speed = speed,
		position = PET_START_X,
		attacking = false,
		target = nil,
	})

	-- Fire update event
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local event = remotes:FindFirstChild("CampaignBattleUpdate")
		if event then
			event:FireClient(player, CampaignService._getBattleSnapshot(battle))
		end
	end

	return true, nil
end

-- Spawn a wave of enemies
function CampaignService._spawnWave(userId, battle)
	local waveEnemies = battle.enemyWaves[battle.currentWave]
	if not waveEnemies then
		return
	end

	for _, enemyData in ipairs(waveEnemies) do
		table.insert(battle.enemies, {
			name = enemyData.name,
			hp = enemyData.hp,
			maxHp = enemyData.maxHp,
			damage = enemyData.damage,
			speed = enemyData.speed,
			isBoss = enemyData.isBoss,
			position = ENEMY_START_X,
			attacking = false,
			target = nil,
		})
	end

	battle.spawnedCurrentWave = true
end

-- Main update loop (called every Heartbeat)
function CampaignService.update(dt)
	for userId, battle in pairs(CampaignService._activeBattles) do
		if battle.active then
			CampaignService._updateBattle(userId, battle, dt)
		end
	end
end

-- Update a single battle
function CampaignService._updateBattle(userId, battle, dt)
	-- Regenerate energy
	battle.energy = math.min(battle.energy + battle.energyRegenRate * dt, battle.maxEnergy)

	-- Wave timer: advance to next wave after interval
	battle.waveSpawnTimer = battle.waveSpawnTimer + dt
	if battle.waveSpawnTimer >= battle.waveSpawnInterval then
		battle.waveSpawnTimer = 0
		if battle.currentWave < battle.totalWaves then
			battle.currentWave = battle.currentWave + 1
			CampaignService._spawnWave(userId, battle)
		end
	end

	-- Move and process deployed pets
	for i = #battle.deployedPets, 1, -1 do
		local pet = battle.deployedPets[i]
		pet.attacking = false
		pet.target = nil

		-- Find closest enemy
		local closestEnemy = nil
		local closestDist = math.huge
		for _, enemy in ipairs(battle.enemies) do
			local dist = enemy.position - pet.position
			if dist > 0 and dist < closestDist then
				closestDist = dist
				closestEnemy = enemy
			end
		end

		if closestEnemy and closestDist <= 3 then
			-- Attack the enemy
			pet.attacking = true
			pet.target = closestEnemy
			closestEnemy.hp = closestEnemy.hp - pet.damage * dt
		elseif closestEnemy then
			-- Move toward enemy
			pet.position = pet.position + pet.speed * dt
		else
			-- No enemies, advance toward enemy base
			pet.position = pet.position + pet.speed * dt

			-- Check if reached enemy base
			if pet.position >= LANE_LENGTH then
				battle.enemyBaseHP = battle.enemyBaseHP - pet.damage * dt
			end
		end
	end

	-- Move and process enemies
	for i = #battle.enemies, 1, -1 do
		local enemy = battle.enemies[i]
		enemy.attacking = false
		enemy.target = nil

		-- Find closest pet
		local closestPet = nil
		local closestDist = math.huge
		for _, pet in ipairs(battle.deployedPets) do
			local dist = pet.position - enemy.position
			if dist < 0 then
				-- Pet is to the left (enemy advances left)
				local absDist = math.abs(dist)
				if absDist < closestDist then
					closestDist = absDist
					closestPet = pet
				end
			end
		end

		if closestPet and closestDist <= 3 then
			-- Attack the pet
			enemy.attacking = true
			enemy.target = closestPet
			closestPet.hp = closestPet.hp - enemy.damage * dt
		else
			-- Move toward player base
			enemy.position = enemy.position - enemy.speed * dt

			-- Check if reached player base
			if enemy.position <= 0 then
				battle.playerBaseHP = battle.playerBaseHP - enemy.damage * dt
			end
		end
	end

	-- Remove dead pets
	for i = #battle.deployedPets, 1, -1 do
		if battle.deployedPets[i].hp <= 0 then
			table.remove(battle.deployedPets, i)
		end
	end

	-- Remove dead enemies
	for i = #battle.enemies, 1, -1 do
		if battle.enemies[i].hp <= 0 then
			table.remove(battle.enemies, i)
		end
	end

	-- Check victory condition: enemy base destroyed
	if battle.enemyBaseHP <= 0 then
		CampaignService._onVictory(userId, battle)
		return
	end

	-- Check defeat condition: player base destroyed
	if battle.playerBaseHP <= 0 then
		CampaignService._onDefeat(userId, battle)
		return
	end
end

-- Handle victory
function CampaignService._onVictory(userId, battle)
	battle.active = false

	local player = game:GetService("Players"):GetPlayerByUserId(userId)
	if not player then
		CampaignService._activeBattles[userId] = nil
		return
	end

	local data = CampaignService._dataService.getPlayerData(player)
	if data then
		-- Record level completion
		local alreadyCompleted = false
		for _, completedLevel in ipairs(data.campaignProgress) do
			if completedLevel == battle.levelNum then
				alreadyCompleted = true
				break
			end
		end
		if not alreadyCompleted then
			table.insert(data.campaignProgress, battle.levelNum)
		end

		-- Award rewards
		local rewards = battle.levelDef.rewards
		if rewards.Coins then
			CampaignService._currencyService.addCoins(player, rewards.Coins)
		end
		if rewards.Diamonds then
			CampaignService._currencyService.addDiamonds(player, rewards.Diamonds)
		end
	end

	-- Fire victory event
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local event = remotes:FindFirstChild("CampaignVictory")
		if event then
			event:FireClient(player, battle.levelNum, battle.levelDef.rewards)
		end
	end

	-- Cleanup
	CampaignService._activeBattles[userId] = nil
end

-- Handle defeat
function CampaignService._onDefeat(userId, battle)
	battle.active = false

	local player = game:GetService("Players"):GetPlayerByUserId(userId)
	if not player then
		CampaignService._activeBattles[userId] = nil
		return
	end

	-- Fire defeat event
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local event = remotes:FindFirstChild("CampaignDefeat")
		if event then
			event:FireClient(player, battle.levelNum)
		end
	end

	-- Cleanup
	CampaignService._activeBattles[userId] = nil
end

-- Get a serializable snapshot of the battle state for client
function CampaignService._getBattleSnapshot(battle)
	return {
		energy = battle.energy,
		maxEnergy = battle.maxEnergy,
		playerBaseHP = battle.playerBaseHP,
		enemyBaseHP = battle.enemyBaseHP,
		currentWave = battle.currentWave,
		totalWaves = battle.totalWaves,
		petCount = #battle.deployedPets,
		enemyCount = #battle.enemies,
	}
end

-- Cancel/cleanup if player disconnects mid-battle
function CampaignService.onPlayerRemoving(player)
	if player then
		CampaignService._activeBattles[player.UserId] = nil
	end
end

return CampaignService
