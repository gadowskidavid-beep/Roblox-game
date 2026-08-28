-- ZoneService.spec.lua - QOF-24 fractional aggregation and overkill boundary.

local originalRequire = require
local originalGame = rawget(_G, "game")
local originalVector3 = rawget(_G, "Vector3")
local originalColor3 = rawget(_G, "Color3")
local originalEnum = rawget(_G, "Enum")

local function newVector(x, y, z)
	local vector = { X = x, Y = y, Z = z }
	vector.Magnitude = math.sqrt(x * x + y * y + z * z)
	return setmetatable(vector, {
		__sub = function(left, right)
			return newVector(left.X - right.X, left.Y - right.Y, left.Z - right.Z)
		end,
	})
end

rawset(_G, "Vector3", { new = newVector })
rawset(_G, "Color3", {
	fromRGB = function(r, g, b) return { R = r, G = g, B = b } end,
})
rawset(_G, "Enum", {
	Material = { Metal = "Metal", Neon = "Neon" },
})

local Config = {}
local ZoneData = { Zones = {} }
local BalanceConfig = {}
local PetData = { Pets = {} }
local ReplicatedStorage = {
	Shared = {
		Config = Config,
		ZoneData = ZoneData,
		BalanceConfig = BalanceConfig,
		PetData = PetData,
	},
}
function ReplicatedStorage:FindFirstChild()
	return nil
end
local Players = {}
local HttpService = {}
local gameMock = { ReplicatedStorage = ReplicatedStorage }
function gameMock:GetService(name)
	if name == "ReplicatedStorage" then return ReplicatedStorage end
	if name == "Players" then return Players end
	if name == "HttpService" then return HttpService end
	error("Unexpected service: " .. tostring(name))
end
rawset(_G, "game", gameMock)
rawset(_G, "require", function(path)
	if path == Config then return Config end
	if path == ZoneData then return ZoneData end
	if path == BalanceConfig then return BalanceConfig end
	if path == PetData then return PetData end
	return originalRequire(path)
end)
local ZoneService = originalRequire("src/ServerScriptService/Services/ZoneService")
rawset(_G, "require", originalRequire)
rawset(_G, "game", originalGame)
rawset(_G, "Vector3", originalVector3)
rawset(_G, "Color3", originalColor3)
rawset(_G, "Enum", originalEnum)

local player = {
	UserId = 2424,
	Character = {
		FindFirstChild = function(_, name)
			if name == "HumanoidRootPart" then
				return { Position = newVector(0, 0, 0) }
			end
			return nil
		end,
	},
}
local profile = {
	unlockedZones = { 1 },
	pets = {
		{ id = "pet-a", equipped = true },
		{ id = "pet-b", equipped = true },
	},
}

ZoneService._dataService = {
	getPlayerData = function(receivedPlayer)
		expect(receivedPlayer):toBe(player)
		return profile
	end,
}
ZoneService._petService = {
	getPetDamage = function(_, receivedPlayer)
		expect(receivedPlayer):toBe(player)
		return 4.5
	end,
}
ZoneService._petTargets[player.UserId] = {
	["pet-a"] = "fractional-target",
	["pet-b"] = "fractional-target",
}

local lastNearbyDamage = nil
ZoneService._fireDamageNearby = function(_, _, damage)
	lastNearbyDamage = damage
end
local finalizedDamage = nil
ZoneService._finalizeDestroyedDestructible = function(_, destructible)
	finalizedDamage = destructible.contributors[player.UserId]
end

describe("ZoneService QOF-24 fractional damage boundary", function()
	it("sums two 4.5 pets to exactly 9 without per-pet rounding", function()
		lastNearbyDamage = nil
		finalizedDamage = nil
		ZoneService._attackCooldowns[player.UserId] = -100
		local destructible = {
			zoneId = 1,
			hp = 10,
			position = newVector(0, 0, 0),
			contributors = {},
		}
		ZoneService._destructibles["fractional-target"] = destructible

		local success, reason = ZoneService.attackDestructible(player, "fractional-target")
		expect(success):toBeTrue()
		expect(reason):toBeNil()
		expect(destructible.hp):toBe(1)
		expect(destructible.contributors[player.UserId]):toBe(9)
		expect(lastNearbyDamage):toBe(9)
		expect(finalizedDamage):toBeNil()
	end)

	it("clamps 9 overkill once to an 8 HP final boundary", function()
		lastNearbyDamage = nil
		finalizedDamage = nil
		ZoneService._attackCooldowns[player.UserId] = -100
		local destructible = {
			zoneId = 1,
			hp = 8,
			position = newVector(0, 0, 0),
			contributors = {},
		}
		ZoneService._destructibles["fractional-target"] = destructible

		local success, reason = ZoneService.attackDestructible(player, "fractional-target")
		expect(success):toBeTrue()
		expect(reason):toBeNil()
		expect(destructible.hp):toBe(0)
		expect(destructible.contributors[player.UserId]):toBe(8)
		expect(finalizedDamage):toBe(8)
		expect(lastNearbyDamage):toBeNil()
	end)
end)
