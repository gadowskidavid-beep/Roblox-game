-- ProgressionServices.spec.lua - QOF-23 hostile runtime progression contracts.

local originalRequire = require
local QuestData = originalRequire("src/ReplicatedStorage/Shared/QuestData")
local MasteryData = originalRequire("src/ReplicatedStorage/Shared/MasteryData")

local SharedMock = {
	QuestData = QuestData,
	MasteryData = MasteryData,
}
local ReplicatedStorageMock = { Shared = SharedMock }
function ReplicatedStorageMock:FindFirstChild()
	return nil
end
local gameMock = { ReplicatedStorage = ReplicatedStorageMock }
function gameMock:GetService(name)
	if name == "ReplicatedStorage" then
		return ReplicatedStorageMock
	end
	error("Unexpected service: " .. tostring(name))
end
rawset(_G, "game", gameMock)
rawset(_G, "script", {})

local function mockRequire(path)
	if path == QuestData then return QuestData end
	if path == MasteryData then return MasteryData end
	if path == SharedMock.ProgressionMath then return SharedMock.ProgressionMath end
	return originalRequire(path)
end
rawset(_G, "require", mockRequire)
local ProgressionMath = originalRequire("src/ReplicatedStorage/Shared/ProgressionMath")
SharedMock.ProgressionMath = ProgressionMath
local QuestService = originalRequire("src/ServerScriptService/Services/QuestService")
local MasteryService = originalRequire("src/ServerScriptService/Services/MasteryService")
local UpgradeService = originalRequire("src/ServerScriptService/Services/UpgradeService")
rawset(_G, "require", originalRequire)

local player = { UserId = 23 }
local profile = {}
local DataService = {}
function DataService.getPlayerData(candidate)
	if candidate == player then return profile end
	return nil
end
QuestService.init(DataService, {})
MasteryService.init(DataService)
UpgradeService.init(DataService, {})
UpgradeService.setMasteryService(MasteryService)

local function resetProfile()
	profile = {
		upgrades = {},
		questStats = {},
		masteryPoints = 100,
		masteryBuffs = {},
		level = 10,
	}
end

describe("ProgressionMath QOF-23 canonical boundaries", function()
	it("derives quest maxima from levels and mastery maxima from every consistent bound", function()
		expect(ProgressionMath.getQuestMaxLevel("StrongPets")):toBe(3)
		expect(ProgressionMath.getQuestMaxLevel("GoldenPetsChance")):toBe(1)
		expect(ProgressionMath.getQuestMaxLevel("Unknown")):toBe(0)
		expect(ProgressionMath.getMasteryMaxLevel("MoreCoins")):toBe(10)
		expect(ProgressionMath.getMasteryMaxLevel("LongerBuffs")):toBe(5)
		expect(ProgressionMath.getMasteryMaxLevel("Unknown")):toBe(0)

		local savedBonus = MasteryData.Buffs.MoreCoins.bonusPerLevel[10]
		MasteryData.Buffs.MoreCoins.bonusPerLevel[10] = nil
		expect(ProgressionMath.getMasteryMaxLevel("MoreCoins")):toBe(9)
		MasteryData.Buffs.MoreCoins.bonusPerLevel[10] = savedBonus
	end)

	it("accepts only finite integers in range and strips unknown IDs", function()
		local invalidValues = { -1, 1.5, "1", true, {}, function() end, math.huge, -math.huge, 0 / 0 }
		for _, invalid in ipairs(invalidValues) do
			expect(ProgressionMath.normalizeQuestLevels({ StrongPets = invalid })):toEqual({})
			expect(ProgressionMath.normalizeMasteryLevels({ MoreCoins = invalid })):toEqual({})
		end
		expect(ProgressionMath.normalizeQuestLevels({ StrongPets = 3, Unknown = 1 }))
			:toEqual({ StrongPets = 3 })
		expect(ProgressionMath.normalizeMasteryLevels({ MoreCoins = 10, Unknown = 1 }))
			:toEqual({ MoreCoins = 10 })
		expect(ProgressionMath.normalizeQuestLevels({ StrongPets = 4 })):toEqual({})
		expect(ProgressionMath.normalizeMasteryLevels({ MoreCoins = 11 })):toEqual({})
	end)
end)

describe("QOF-23 public progression resolvers", function()
	it("returns neutral values after every hostile runtime level mutation", function()
		local invalidValues = { -1, 1.5, "1", true, {}, function() end, math.huge, -math.huge, 0 / 0, 999 }
		for _, invalid in ipairs(invalidValues) do
			resetProfile()
			profile.upgrades.StrongPets = invalid
			profile.masteryBuffs.MoreCoins = invalid
			profile.questStats = true
			expect(QuestService.getUpgradeLevel(player, "StrongPets")):toBe(0)
			expect(QuestService.getUpgradeBonus(player, "StrongPets")):toBe(0)
			expect(UpgradeService.getUpgradeLevel(player, "StrongPets")):toBe(0)
			expect(UpgradeService.getUpgradeBonus(player, "StrongPets")):toBe(0)
			expect(MasteryService.getBuffBonus(player, "MoreCoins")):toBe(0)
			expect(QuestService.getQuestProgress(player).StrongPets.currentLevel):toBe(0)
			expect(MasteryService.getMasteryState(player).buffs):toEqual({})
		end
	end)

	it("returns exact max-level bonuses for valid live state", function()
		resetProfile()
		profile.upgrades.StrongPets = 3
		profile.masteryBuffs.MoreCoins = 10
		expect(QuestService.getUpgradeLevel(player, "StrongPets")):toBe(3)
		expect(QuestService.getUpgradeBonus(player, "StrongPets")):toBe(2.5)
		expect(UpgradeService.getUpgradeBonus(player, "StrongPets")):toBe(2.5)
		expect(MasteryService.getBuffBonus(player, "MoreCoins")):toBe(3)
	end)

	it("rejects a hostile mastery purchase without spending and safely repairs quest awards", function()
		resetProfile()
		profile.masteryBuffs.MoreCoins = "9"
		profile.masteryBuffs.MoreDiamonds = 2
		profile.masteryBuffs.UnknownMastery = 1
		local purchased, purchaseError = MasteryService.purchaseBuff(player, "MoreCoins")
		expect(purchased):toBeFalse()
		expect(purchaseError):toBe("Invalid level")
		expect(profile.masteryPoints):toBe(100)
		expect(profile.masteryBuffs):toEqual({ MoreDiamonds = 2 })

		profile.upgrades.StrongPets = 999
		profile.upgrades.FasterPets = 2
		profile.upgrades.UnknownQuest = 1
		profile.questStats.destroyDestructibles = 2500
		QuestService._checkQuestCompletions(player, profile)
		expect(profile.upgrades.StrongPets):toBe(1)
		expect(profile.upgrades.FasterPets):toBe(2)
		expect(profile.upgrades.UnknownQuest):toBeNil()
		expect(QuestService.getUpgradeBonus(player, "StrongPets")):toBe(1.3)
	end)
end)
