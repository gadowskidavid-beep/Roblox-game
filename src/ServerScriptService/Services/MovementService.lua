--[[
	MovementService.lua - Single server-authoritative owner of player WalkSpeed.
	QOF-12 composes existing quest, mastery, and shop sources with the canonical
	Upgrade Tree entitlement, clamps once, and reconciles character lifecycle.
]]

local RunService = game:GetService("RunService")
local BalanceConfig = require(game.ReplicatedStorage.Shared.BalanceConfig)

local MovementService = {}

MovementService._questService = nil
MovementService._masteryService = nil
MovementService._shopService = nil
MovementService._upgradeTreeService = nil
MovementService._runService = nil
MovementService._heartbeatConnection = nil
MovementService._states = {}
MovementService._accumulator = 0

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

local function disconnect(connection)
	if connection then
		connection:Disconnect()
	end
end

function MovementService.resolveWalkSpeed(player)
	local movement = BalanceConfig.CoreUpgrades.Movement
	local questMultiplier = 1
	if MovementService._questService then
		questMultiplier = MovementService._questService.getUpgradeBonus(player, "Sprinting")
	end

	local masteryMultiplier = 1
	if MovementService._masteryService then
		masteryMultiplier = MovementService._masteryService.getBuffBonus(player, "FasterRunning")
	end

	local shopMultiplier = 1
	if MovementService._shopService then
		shopMultiplier = MovementService._shopService.getShopMultiplier(player, "speed")
	end

	local treeMultiplier = 1
	if MovementService._upgradeTreeService then
		local entitlements = MovementService._upgradeTreeService.getEntitlements(player)
		if type(entitlements) == "table" then
			treeMultiplier = entitlements.movementSpeedMultiplier
		end
	end

	local speed = movement.BaseWalkSpeed
		* normalizedMultiplier(questMultiplier)
		* normalizedMultiplier(masteryMultiplier)
		* normalizedMultiplier(shopMultiplier)
		* normalizedMultiplier(treeMultiplier)
	return math.min(math.max(speed, movement.BaseWalkSpeed), movement.MaxWalkSpeed)
end

function MovementService.refresh(player)
	local state = MovementService._states[player]
	if not state or not state.humanoid or state.humanoid.Parent == nil then
		return false
	end
	local expected = MovementService.resolveWalkSpeed(player)
	state.expectedWalkSpeed = expected
	if state.humanoid.WalkSpeed ~= expected then
		state.applying = true
		state.humanoid.WalkSpeed = expected
		state.applying = false
	end
	return true, expected
end

local function setHumanoid(player, state, humanoid, generation)
	if MovementService._states[player] ~= state or state.generation ~= generation then
		return
	end
	disconnect(state.humanoidChangedConnection)
	state.humanoid = humanoid
	state.humanoidChangedConnection = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		if not state.applying
			and MovementService._states[player] == state
			and state.humanoid == humanoid
			and state.expectedWalkSpeed ~= nil
			and humanoid.WalkSpeed ~= state.expectedWalkSpeed then
			MovementService.refresh(player)
		end
	end)
	MovementService.refresh(player)
end

local function attachCharacter(player, state, character)
	state.generation = state.generation + 1
	local generation = state.generation
	disconnect(state.childAddedConnection)
	disconnect(state.humanoidChangedConnection)
	state.childAddedConnection = nil
	state.humanoidChangedConnection = nil
	state.character = character
	state.humanoid = nil
	state.expectedWalkSpeed = nil

	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		setHumanoid(player, state, humanoid, generation)
		return
	end
	if character then
		state.childAddedConnection = character.ChildAdded:Connect(function(child)
			if child:IsA("Humanoid") then
				disconnect(state.childAddedConnection)
				state.childAddedConnection = nil
				setHumanoid(player, state, child, generation)
			end
		end)
	end
end

function MovementService.unbindPlayer(player)
	local state = MovementService._states[player]
	if not state then
		return
	end
	MovementService._states[player] = nil
	state.generation = state.generation + 1
	disconnect(state.characterAddedConnection)
	disconnect(state.characterRemovingConnection)
	disconnect(state.childAddedConnection)
	disconnect(state.humanoidChangedConnection)
end

function MovementService.bindPlayer(player)
	if not player then
		return false
	end
	MovementService.unbindPlayer(player)
	local state = {
		generation = 0,
		applying = false,
	}
	MovementService._states[player] = state
	state.characterAddedConnection = player.CharacterAdded:Connect(function(character)
		attachCharacter(player, state, character)
	end)
	state.characterRemovingConnection = player.CharacterRemoving:Connect(function(character)
		if state.character == character then
			attachCharacter(player, state, nil)
		end
	end)
	if player.Character then
		attachCharacter(player, state, player.Character)
	end
	return true
end

function MovementService.step(deltaTime)
	local interval = BalanceConfig.CoreUpgrades.Movement.ReconcileIntervalSeconds
	MovementService._accumulator = MovementService._accumulator + (finiteNumber(deltaTime) and math.max(deltaTime, 0) or interval)
	if MovementService._accumulator < interval then
		return false
	end
	MovementService._accumulator = MovementService._accumulator % interval
	for player in pairs(MovementService._states) do
		MovementService.refresh(player)
	end
	return true
end

function MovementService.init(questService, masteryService, shopService, upgradeTreeService, runService)
	MovementService._questService = questService
	MovementService._masteryService = masteryService
	MovementService._shopService = shopService
	MovementService._upgradeTreeService = upgradeTreeService
	MovementService._runService = runService or RunService
	MovementService._accumulator = 0
	disconnect(MovementService._heartbeatConnection)
	MovementService._heartbeatConnection = MovementService._runService.Heartbeat:Connect(function(deltaTime)
		MovementService.step(deltaTime)
	end)
end

return MovementService
