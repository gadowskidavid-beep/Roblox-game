local originalRequire = require
local Config = {
	Campaign = { MaxEnergy = 100, EnergyRegenRate = 5, BaseHealth = 100 },
}
local CampaignData = originalRequire("src/ReplicatedStorage/Shared/CampaignData")

local heartbeat = {}
function heartbeat:Connect(callback)
	self.callback = callback
	return { Disconnect = function() end }
end
local RunService = { Heartbeat = heartbeat }
local ReplicatedStorage = { Shared = { Config = Config, CampaignData = CampaignData } }
function ReplicatedStorage:FindFirstChild()
	return nil
end
local Players = {}
local gameMock = { ReplicatedStorage = ReplicatedStorage }
function gameMock:GetService(name)
	if name == "RunService" then return RunService end
	if name == "ReplicatedStorage" then return ReplicatedStorage end
	if name == "Players" then return Players end
	error("Unexpected service: " .. tostring(name))
end
rawset(_G, "game", gameMock)
rawset(_G, "require", function(path)
	if path == Config then return Config end
	if path == CampaignData then return CampaignData end
	return originalRequire(path)
end)
local CampaignService = originalRequire("src/ServerScriptService/Services/CampaignService")
rawset(_G, "require", originalRequire)

describe("CampaignService QOF-19 Agile deploy snapshot", function()
	it("uses PetService campaign lane speed once at deploy and keeps the snapshot", function()
		local player = { UserId = 1919 }
		local pet = {
			id = "pet-1", petId = "Buddy", name = "Buddy", rarity = "Common",
			enchantId = "AgileIII",
		}
		local profile = { pets = { pet } }
		local speedCalls = 0
		local currentSpeed = 13.5
		CampaignService._dataService = {
			getPlayerData = function() return profile end,
		}
		CampaignService._petService = {
			getPetDamage = function() return 10 end,
			getCampaignLaneSpeed = function(received)
				expect(received):toBe(pet)
				speedCalls = speedCalls + 1
				return currentSpeed
			end,
		}
		CampaignService._activeBattles[player.UserId] = {
			active = true,
			energy = 100,
			deployedPets = {},
		}

		local success, reason = CampaignService.deployPet(player, "pet-1")
		expect(success):toBeTrue()
		expect(reason):toBeNil()
		expect(speedCalls):toBe(1)
		expect(CampaignService._activeBattles[player.UserId].energy):toBe(90)
		local deployed = CampaignService._activeBattles[player.UserId].deployedPets[1]
		expect(deployed.speed):toBe(13.5)

		-- A later reroll changes the inventory pet but not the deployed lane snapshot.
		pet.enchantId = "StrongIII"
		currentSpeed = 99
		expect(deployed.speed):toBe(13.5)
		expect(speedCalls):toBe(1)
		CampaignService._activeBattles[player.UserId] = nil
	end)
end)


describe("CampaignService hardened deploy calculations", function()
	it("never consumes energy when damage or speed calculation fails", function()
		local player = { UserId = 1920 }
		local pet = { id = "pet-2", petId = "Buddy", name = "Buddy", rarity = "Common" }
		local profile = { pets = { pet } }
		CampaignService._dataService = { getPlayerData = function() return profile end }

		local cases = {
			{ damage = function() error("damage failed") end, speed = function() return 10 end },
			{ damage = function() return nil end, speed = function() return 10 end },
			{ damage = function() return "bad" end, speed = function() return 10 end },
			{ damage = function() return 0 / 0 end, speed = function() return 10 end },
			{ damage = function() return math.huge end, speed = function() return 10 end },
			{ damage = function() return 1 end, speed = function() error("speed failed") end },
			{ damage = function() return 1 end, speed = function() return "bad" end },
			{ damage = function() return 1 end, speed = function() return -math.huge end },
		}
		for _, case in ipairs(cases) do
			CampaignService._petService = {
				getPetDamage = case.damage,
				getCampaignLaneSpeed = case.speed,
			}
			CampaignService._activeBattles[player.UserId] = {
				active = true, energy = 100, deployedPets = {},
			}
			local success, reason = CampaignService.deployPet(player, "pet-2")
			expect(success):toBeFalse()
			expect(reason):toBe("Pet stats unavailable")
			expect(CampaignService._activeBattles[player.UserId].energy):toBe(100)
			expect(#CampaignService._activeBattles[player.UserId].deployedPets):toBe(0)
		end
		CampaignService._petService = nil
		CampaignService._activeBattles[player.UserId] = {
			active = true, energy = 100, deployedPets = {},
		}
		local success, reason = CampaignService.deployPet(player, "pet-2")
		expect(success):toBeFalse()
		expect(reason):toBe("Pet stats unavailable")
		expect(CampaignService._activeBattles[player.UserId].energy):toBe(100)
		CampaignService._activeBattles[player.UserId] = nil
	end)
end)



describe("CampaignService QOF-23 hostile boss claim state", function()
	it("treats only exact true as claimed and never lets a poisoned value suppress the egg", function()
		local player = { UserId = 2323 }
		function Players:GetPlayerByUserId(userId)
			return userId == player.UserId and player or nil
		end
		local profile = {
			campaignProgress = {},
			campaignBossRewards = { ["6"] = "claimed" },
		}
		local hatchCalls = 0
		CampaignService._dataService = { getPlayerData = function() return profile end }
		CampaignService._currencyService = {
			addCoins = function() end,
			addDiamonds = function() end,
		}
		CampaignService._petService = {
			hatchEgg = function(_, eggId, bypass)
				expect(eggId):toBe("BasicEgg")
				expect(bypass):toBeTrue()
				hatchCalls = hatchCalls + 1
				return { name = "Buddy", isNewDiscovery = true }
			end,
		}

		CampaignService._activeBattles[player.UserId] = {
			active = true,
			levelNum = 6,
			levelDef = CampaignData.Levels[6],
		}
		CampaignService._onVictory(player.UserId, CampaignService._activeBattles[player.UserId])
		expect(hatchCalls):toBe(1)
		expect(profile.campaignBossRewards["6"]):toBeTrue()

		CampaignService._activeBattles[player.UserId] = {
			active = true,
			levelNum = 6,
			levelDef = CampaignData.Levels[6],
		}
		CampaignService._onVictory(player.UserId, CampaignService._activeBattles[player.UserId])
		expect(hatchCalls):toBe(1)
		CampaignService._activeBattles[player.UserId] = nil
	end)
end)
