local originalRequire = require
local BalanceConfig = originalRequire("src/ReplicatedStorage/Shared/BalanceConfig")

local function newSignal()
	local signal = { listeners = {} }
	function signal:Connect(callback)
		local connection = { Connected = true }
		function connection:Disconnect()
			self.Connected = false
		end
		table.insert(self.listeners, { callback = callback, connection = connection })
		return connection
	end
	function signal:Fire(...)
		for _, entry in ipairs(self.listeners) do
			if entry.connection.Connected then
				entry.callback(...)
			end
		end
	end
	return signal
end

local runService = { Heartbeat = newSignal() }
local replicatedStorage = { Shared = { BalanceConfig = BalanceConfig } }
local gameMock = { ReplicatedStorage = replicatedStorage }
function gameMock:GetService(name)
	if name == "RunService" then return runService end
	error("Unexpected service: " .. tostring(name))
end
rawset(_G, "game", gameMock)

local function mockRequire(path)
	if path == BalanceConfig then return BalanceConfig end
	return originalRequire(path)
end
rawset(_G, "require", mockRequire)
local MovementService = originalRequire("src/ServerScriptService/Services/MovementService")
rawset(_G, "require", originalRequire)

local questMultiplier = 0
local masteryMultiplier = 0
local shopMultiplier = 1
local treeMultiplier = 1
local questService = {}
function questService.getUpgradeBonus()
	return questMultiplier
end
local masteryService = {}
function masteryService.getBuffBonus()
	return masteryMultiplier
end
local shopService = {}
function shopService.getShopMultiplier()
	return shopMultiplier
end
local treeService = {}
function treeService.getEntitlements()
	return { movementSpeedMultiplier = treeMultiplier }
end

local function newHumanoid()
	local changed = newSignal()
	local humanoid = { Parent = {}, WalkSpeed = 16, _changed = changed }
	function humanoid:GetPropertyChangedSignal(property)
		expect(property):toBe("WalkSpeed")
		return changed
	end
	function humanoid:IsA(className)
		return className == "Humanoid"
	end
	return humanoid
end

local function newCharacter(humanoid)
	local character = { ChildAdded = newSignal(), _humanoid = humanoid }
	function character:FindFirstChildOfClass(className)
		if className == "Humanoid" then return self._humanoid end
		return nil
	end
	return character
end

local function newPlayer(character)
	return {
		UserId = 101,
		Character = character,
		CharacterAdded = newSignal(),
		CharacterRemoving = newSignal(),
	}
end

local function resetSources()
	questMultiplier = 0
	masteryMultiplier = 0
	shopMultiplier = 1
	treeMultiplier = 1
	MovementService.init(questService, masteryService, shopService, treeService, runService)
end

describe("MovementService QOF-12 authority", function()
	it("composes all server-owned sources and clamps at 128", function()
		resetSources()
		local player = newPlayer(nil)
		expect(MovementService.resolveWalkSpeed(player)):toBe(16)
		questMultiplier = 2
		masteryMultiplier = 2
		shopMultiplier = 2
		treeMultiplier = 1.2
		expect(MovementService.resolveWalkSpeed(player)):toBe(128)
	end)

	it("neutralizes malformed and sub-neutral multipliers", function()
		resetSources()
		local player = newPlayer(nil)
		questMultiplier = 0 / 0
		masteryMultiplier = -2
		shopMultiplier = "forged"
		treeMultiplier = math.huge
		expect(MovementService.resolveWalkSpeed(player)):toBe(16)
	end)

	it("binds an existing character and restores authoritative WalkSpeed", function()
		resetSources()
		questMultiplier = 2
		treeMultiplier = 1.2
		local humanoid = newHumanoid()
		local player = newPlayer(newCharacter(humanoid))
		expect(MovementService.bindPlayer(player)):toBeTrue()
		expect(humanoid.WalkSpeed):toBe(38.4)

		humanoid.WalkSpeed = 999
		humanoid._changed:Fire()
		expect(humanoid.WalkSpeed):toBe(38.4)
		MovementService.unbindPlayer(player)
	end)

	it("moves authority across respawns and ignores removed characters", function()
		resetSources()
		treeMultiplier = 1.1
		local firstHumanoid = newHumanoid()
		local firstCharacter = newCharacter(firstHumanoid)
		local player = newPlayer(firstCharacter)
		MovementService.bindPlayer(player)
		expect(firstHumanoid.WalkSpeed):toBe(17.6)

		player.CharacterRemoving:Fire(firstCharacter)
		firstHumanoid.WalkSpeed = 300
		firstHumanoid._changed:Fire()
		expect(firstHumanoid.WalkSpeed):toBe(300)

		local secondHumanoid = newHumanoid()
		local secondCharacter = newCharacter(secondHumanoid)
		player.Character = secondCharacter
		player.CharacterAdded:Fire(secondCharacter)
		expect(secondHumanoid.WalkSpeed):toBe(17.6)
		MovementService.unbindPlayer(player)
	end)

	it("reconciles source changes on the bounded heartbeat", function()
		resetSources()
		local humanoid = newHumanoid()
		local player = newPlayer(newCharacter(humanoid))
		MovementService.bindPlayer(player)
		expect(humanoid.WalkSpeed):toBe(16)
		shopMultiplier = 2
		runService.Heartbeat:Fire(0.5)
		expect(humanoid.WalkSpeed):toBe(16)
		runService.Heartbeat:Fire(0.5)
		expect(humanoid.WalkSpeed):toBe(32)
		MovementService.unbindPlayer(player)
	end)
end)
