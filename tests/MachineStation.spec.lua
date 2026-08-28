-- MachineStation.spec.lua - QOF-16 private Gold station authority tests.

local originalRequire = require
local BalanceConfig = originalRequire("src/ReplicatedStorage/Shared/BalanceConfig")

local vectorMt = {}
vectorMt.__index = function(value, key)
	if key == "Magnitude" then
		return math.sqrt(value.X * value.X + value.Y * value.Y + value.Z * value.Z)
	end
	return nil
end
vectorMt.__sub = function(left, right)
	return setmetatable({ X = left.X - right.X, Y = left.Y - right.Y, Z = left.Z - right.Z }, vectorMt)
end
vectorMt.__add = function(left, right)
	return setmetatable({ X = left.X + right.X, Y = left.Y + right.Y, Z = left.Z + right.Z }, vectorMt)
end
vectorMt.__eq = function(left, right)
	return left.X == right.X and left.Y == right.Y and left.Z == right.Z
end

local Vector3 = {}
function Vector3.new(x, y, z)
	return setmetatable({ X = x, Y = y, Z = z }, vectorMt)
end

local cframeMt = {}
cframeMt.__eq = function(left, right)
	return left.Position == right.Position
end
local CFrame = {}
function CFrame.new(x, y, z)
	return setmetatable({ Position = Vector3.new(x, y, z) }, cframeMt)
end

local Color3 = {}
function Color3.fromRGB(r, g, b)
	return { R = r, G = g, B = b }
end

local instanceMethods = {}
local instanceMt = {}

local function removeChild(parent, child)
	if not parent then return end
	for index, candidate in ipairs(parent._children) do
		if candidate == child then
			table.remove(parent._children, index)
			return
		end
	end
end

local function setParent(instance, parent)
	local oldParent = rawget(instance, "_parent")
	if oldParent == parent then return end
	removeChild(oldParent, instance)
	rawset(instance, "_parent", parent)
	if parent then
		table.insert(parent._children, instance)
	end
end

instanceMt.__index = function(instance, key)
	if key == "Parent" then
		return rawget(instance, "_parent")
	end
	if instanceMethods[key] then
		return instanceMethods[key]
	end
	return instance._properties[key]
end
instanceMt.__newindex = function(instance, key, value)
	if key == "Parent" then
		setParent(instance, value)
		return
	end
	instance._properties[key] = value
	if key == "CFrame" and value then
		instance._properties.Position = value.Position
	end
end

local function newInstance(className)
	return setmetatable({
		_className = className,
		_children = {},
		_attributes = {},
		_properties = {},
	}, instanceMt)
end

function instanceMethods:IsA(className)
	if self._className == className then return true end
	return className == "BasePart" and self._className == "Part"
end
function instanceMethods:SetAttribute(name, value)
	self._attributes[name] = value
end
function instanceMethods:GetAttribute(name)
	return self._attributes[name]
end
function instanceMethods:FindFirstChild(name)
	for _, child in ipairs(self._children) do
		if child.Name == name then return child end
	end
	return nil
end
function instanceMethods:GetChildren()
	local copy = {}
	for index, child in ipairs(self._children) do
		copy[index] = child
	end
	return copy
end
function instanceMethods:IsDescendantOf(ancestor)
	local current = self.Parent
	while current do
		if current == ancestor then return true end
		current = current.Parent
	end
	return false
end
function instanceMethods:Destroy()
	self.Parent = nil
end

local Instance = {}
function Instance.new(className)
	return newInstance(className)
end

local workspace = nil
local HttpService = {}
function HttpService:GenerateGUID()
	return "server-generated-gold-token"
end
local ReplicatedStorage = {
	Shared = {
		Config = {},
		ZoneData = { Zones = {} },
		BalanceConfig = BalanceConfig,
	},
}
local gameMock = { ReplicatedStorage = ReplicatedStorage }
function gameMock:GetService(name)
	if name == "ReplicatedStorage" then return ReplicatedStorage end
	if name == "Players" then return {} end
	if name == "HttpService" then return HttpService end
	if name == "Workspace" then return workspace end
	error("Unexpected service: " .. tostring(name))
end

rawset(_G, "Vector3", Vector3)
rawset(_G, "CFrame", CFrame)
rawset(_G, "Color3", Color3)
rawset(_G, "Instance", Instance)
rawset(_G, "Enum", { Material = { Metal = "Metal" } })
rawset(_G, "game", gameMock)
rawset(_G, "require", function(path)
	if path == ReplicatedStorage.Shared.Config then return ReplicatedStorage.Shared.Config end
	if path == ReplicatedStorage.Shared.ZoneData then return ReplicatedStorage.Shared.ZoneData end
	if path == BalanceConfig then return BalanceConfig end
	return originalRequire(path)
end)

local ZoneService
if io and io.open and load then
	-- Standard Lua cannot parse the one Luau `continue` used much later in this
	-- large module. Load the complete machine-authority prefix only; every world
	-- builder called by init is replaced below before execution.
	local sourceFile = assert(io.open("src/ServerScriptService/Services/ZoneService.lua", "rb"))
	local source = sourceFile:read("*a")
	sourceFile:close()
	local marker = assert(string.find(source, "function ZoneService._spawnZoneGates()", 1, true))
	local chunk = assert(load(string.sub(source, 1, marker - 1) .. "\nreturn ZoneService\n", "@ZoneService.machine-prefix"))
	ZoneService = chunk()
else
	ZoneService = originalRequire("src/ServerScriptService/Services/ZoneService")
end
rawset(_G, "require", originalRequire)

ZoneService._spawnLobby = function() end
ZoneService._spawnZoneGates = function() end
ZoneService._spawnEggStations = function() end
ZoneService._spawnWorldDecoration = function() end
ZoneService._spawnBarriers = function() end
ZoneService.spawnZone = function(zoneId)
	local zone = Instance.new("Folder")
	zone.Name = "Zone_" .. tostring(zoneId)
	zone.Parent = ZoneService._zonesFolder
end

local profile = nil
local dataService = {}
function dataService.getPlayerData()
	return profile
end

local function countDescendantsNamed(root, name)
	local count = root.Name == name and 1 or 0
	for _, child in ipairs(root:GetChildren()) do
		count = count + countDescendantsNamed(child, name)
	end
	return count
end

local function createFixture()
	workspace = newInstance("Workspace")
	workspace.Name = "Workspace"
	profile = { unlockedZones = { 1, 2, 3 } }
	local validator = ZoneService.init(dataService, {}, {})
	local zones = workspace:FindFirstChild("Zones")
	local zone3 = zones:FindFirstChild("Zone_3")
	local model = zone3:FindFirstChild("GoldMachine")
	local anchor = model:FindFirstChild("Anchor")
	local prompt = anchor:FindFirstChild("UseMachinePrompt")
	local character = newInstance("Model")
	character.Name = "Character"
	character.Parent = workspace
	local root = newInstance("Part")
	root.Name = "HumanoidRootPart"
	root.Position = anchor.Position
	root.Parent = character
	local player = newInstance("Player")
	player.Name = "StationTester"
	player.UserId = 902
	player.Character = character
	return {
		validator = validator,
		zones = zones,
		zone3 = zone3,
		model = model,
		anchor = anchor,
		prompt = prompt,
		character = character,
		root = root,
		player = player,
		token = model:GetAttribute("MachineIdentityToken"),
	}
end

describe("QOF-16 Gold machine station authority", function()
	it("creates exactly one visible Gold Model/Anchor/Prompt in Zone 3 and no Rainbow station", function()
		local fixture = createFixture()
		expect(type(fixture.validator)):toBe("function")
		expect(countDescendantsNamed(fixture.zones, "GoldMachine")):toBe(1)
		expect(countDescendantsNamed(fixture.zones, "RainbowMachine")):toBe(0)
		expect(fixture.model:IsA("Model")):toBeTrue()
		expect(fixture.model.Parent):toBe(fixture.zone3)
		expect(fixture.anchor:IsA("BasePart")):toBeTrue()
		expect(fixture.anchor.Anchored):toBeTrue()
		expect(fixture.prompt:IsA("ProximityPrompt")):toBeTrue()
		expect(fixture.prompt.Enabled):toBeTrue()
		expect(fixture.token):toBe("server-generated-gold-token")
	end)

	it("accepts only the registered token with Zone 3 unlocked and a nearby exact HRP", function()
		local fixture = createFixture()
		local allowed = fixture.validator(fixture.player, "GoldMachine", fixture.token)
		expect(allowed):toBeTrue()
		expect(fixture.validator(fixture.player, "GoldMachine", "copied-token")):toBeFalse()
		expect(fixture.validator(fixture.player, "RainbowMachine", fixture.token)):toBeFalse()

		fixture.root.Position = fixture.anchor.Position + Vector3.new(12, 0, 0)
		expect(fixture.validator(fixture.player, "GoldMachine", fixture.token)):toBeTrue()
		fixture.root.Position = fixture.anchor.Position + Vector3.new(12.001, 0, 0)
		expect(fixture.validator(fixture.player, "GoldMachine", fixture.token)):toBeFalse()
	end)

	it("rejects a copied station even when names, attributes, and token match", function()
		local fixture = createFixture()
		local copy = Instance.new("Model")
		copy.Name = "GoldMachine"
		copy:SetAttribute("MachineId", "GoldMachine")
		copy:SetAttribute("MachineZoneId", 3)
		copy:SetAttribute("MachineIdentityToken", fixture.token)
		local copyAnchor = Instance.new("Part")
		copyAnchor.Name = "Anchor"
		copyAnchor.Anchored = true
		copyAnchor.Size = fixture.anchor.Size
		copyAnchor.CFrame = fixture.anchor.CFrame
		copyAnchor.Parent = copy
		copy.PrimaryPart = copyAnchor
		local copyPrompt = Instance.new("ProximityPrompt")
		copyPrompt.Name = "UseMachinePrompt"
		copyPrompt.ActionText = "Use Machine"
		copyPrompt.ObjectText = "Gold Machine"
		copyPrompt.Enabled = true
		copyPrompt.MaxActivationDistance = 12
		copyPrompt.Parent = copyAnchor
		copy.Parent = fixture.zone3

		fixture.model.Parent = nil
		expect(fixture.validator(fixture.player, "GoldMachine", fixture.token)):toBeFalse()
		fixture.model.Parent = fixture.zone3
		copy:Destroy()
		expect(fixture.validator(fixture.player, "GoldMachine", fixture.token)):toBeTrue()
	end)

	it("fails closed for station, ancestry, prompt, unlock, character, and HRP tampering", function()
		local fixture = createFixture()

		fixture.prompt.Enabled = false
		expect(fixture.validator(fixture.player, "GoldMachine", fixture.token)):toBeFalse()
		fixture.prompt.Enabled = true

		fixture.prompt.Parent = fixture.model
		expect(fixture.validator(fixture.player, "GoldMachine", fixture.token)):toBeFalse()
		fixture.prompt.Parent = fixture.anchor

		fixture.model:SetAttribute("MachineIdentityToken", "forged")
		expect(fixture.validator(fixture.player, "GoldMachine", fixture.token)):toBeFalse()
		fixture.model:SetAttribute("MachineIdentityToken", fixture.token)

		profile.unlockedZones = { 1, 2 }
		expect(fixture.validator(fixture.player, "GoldMachine", fixture.token)):toBeFalse()
		profile.unlockedZones = { 1, 2, 3 }

		fixture.player.Character = nil
		expect(fixture.validator(fixture.player, "GoldMachine", fixture.token)):toBeFalse()
		fixture.player.Character = fixture.character

		fixture.root.Parent = workspace
		expect(fixture.validator(fixture.player, "GoldMachine", fixture.token)):toBeFalse()
		fixture.root.Parent = fixture.character
		expect(fixture.validator(fixture.player, "GoldMachine", fixture.token)):toBeTrue()
	end)
end)
