-- MachineStation.spec.lua - QOF-17 private Gold/Rainbow station authority tests.

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
	return left.Position == right.Position and left._rotation == right._rotation
end
cframeMt.__mul = function(left, right)
	return setmetatable({ Position = left.Position, _rotation = right._rotation }, cframeMt)
end
local CFrame = {}
function CFrame.new(x, y, z)
	return setmetatable({ Position = Vector3.new(x, y, z), _rotation = "identity" }, cframeMt)
end
function CFrame.Angles(x, y, z)
	return setmetatable({ Position = Vector3.new(0, 0, 0), _rotation = tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z) }, cframeMt)
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
function instanceMethods:GetDescendants()
	local descendants = {}
	local function collect(instance)
		for _, child in ipairs(instance._children) do
			table.insert(descendants, child)
			collect(child)
		end
	end
	collect(self)
	return descendants
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
local guidCounter = 0
local HttpService = {}
function HttpService:GenerateGUID()
	guidCounter = guidCounter + 1
	return "server-machine-token-" .. tostring(guidCounter)
end
local PetData = originalRequire("src/ReplicatedStorage/Shared/PetData")
local eggCosts = {}
for zoneId = 1, 8 do eggCosts[zoneId] = { Coins = zoneId * 100 } end
local ReplicatedStorage = {
	Shared = {
		Config = { EggCosts = eggCosts },
		ZoneData = { Zones = {} },
		BalanceConfig = BalanceConfig,
		PetData = PetData,
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
rawset(_G, "UDim", { new = function(scale, offset) return { Scale = scale, Offset = offset } end })
rawset(_G, "UDim2", {
	fromOffset = function(x, y) return { X = x, Y = y } end,
	fromScale = function(x, y) return { X = x, Y = y } end,
	new = function(...) return { ... } end,
})
rawset(_G, "Instance", Instance)
rawset(_G, "Enum", {
	Material = { Metal = "Metal", Neon = "Neon", Marble = "Marble", SmoothPlastic = "SmoothPlastic" },
	PartType = { Block = "Block", Cylinder = "Cylinder", Ball = "Ball" },
	KeyCode = { E = "E" },
	Font = { GothamBold = "GothamBold" },
	FillDirection = { Vertical = "Vertical" },
	HorizontalAlignment = { Center = "Center" },
})
rawset(_G, "game", gameMock)
rawset(_G, "require", function(path)
	if path == ReplicatedStorage.Shared.Config then return ReplicatedStorage.Shared.Config end
	if path == ReplicatedStorage.Shared.ZoneData then return ReplicatedStorage.Shared.ZoneData end
	if path == BalanceConfig then return BalanceConfig end
	if path == PetData then return PetData end
	return originalRequire(path)
end)

local ZoneService
if io and io.open and load then
	-- Standard Lua cannot parse the Luau syntax used later in this large module.
	-- Load its complete machine-authority prefix and replace world builders below.
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

local function station(zones, machineType)
	local definition = BalanceConfig.Machines[machineType]
	local zone = zones:FindFirstChild("Zone_" .. tostring(definition.zoneId))
	local model = zone:FindFirstChild(definition.id)
	local anchor = model:FindFirstChild("Anchor")
	return {
		definition = definition,
		zone = zone,
		model = model,
		anchor = anchor,
		prompt = anchor:FindFirstChild("UseMachinePrompt"),
		token = model:GetAttribute("MachineIdentityToken"),
	}
end

local function createFixture()
	workspace = newInstance("Workspace")
	workspace.Name = "Workspace"
	profile = { unlockedZones = { 1, 2, 3, 4, 5, 6 } }
	guidCounter = 0
	local validator, eggAuthority = ZoneService.init(dataService, {}, {})
	local zones = workspace:FindFirstChild("Zones")
	local gold = station(zones, "Gold")
	local rainbow = station(zones, "Rainbow")
	local character = newInstance("Model")
	character.Name = "Character"
	character.Parent = workspace
	local root = newInstance("Part")
	root.Name = "HumanoidRootPart"
	root.Position = gold.anchor.Position
	root.Parent = character
	local player = newInstance("Player")
	player.Name = "StationTester"
	player.UserId = 902
	player.Character = character
	return {
		validator = validator,
		eggAuthority = eggAuthority,
		zones = zones,
		gold = gold,
		rainbow = rainbow,
		character = character,
		root = root,
		player = player,
	}
end

local function expectAllowed(fixture, current)
	fixture.root.Position = current.anchor.Position
	expect(fixture.validator(fixture.player, current.definition.id, current.token)):toBeTrue()
end

local function expectDeniedAfterMutation(fixture, current, target, property, forgedValue)
	local original = target[property]
	target[property] = forgedValue
	expect(fixture.validator(fixture.player, current.definition.id, current.token)):toBeFalse()
	target[property] = original
	expectAllowed(fixture, current)
end

describe("QOF-17 machine station authority", function()
	it("creates exactly one complete Gold station in Zone 3 and Rainbow station in Zone 6", function()
		local fixture = createFixture()
		expect(type(fixture.validator)):toBe("function")
		expect(countDescendantsNamed(fixture.zones, "GoldMachine")):toBe(1)
		expect(countDescendantsNamed(fixture.zones, "RainbowMachine")):toBe(1)
		expect(fixture.gold.zone.Name):toBe("Zone_3")
		expect(fixture.rainbow.zone.Name):toBe("Zone_6")
		expect(fixture.gold.model:IsA("Model")):toBeTrue()
		expect(fixture.rainbow.model:IsA("Model")):toBeTrue()
		expect(fixture.gold.anchor:IsA("BasePart")):toBeTrue()
		expect(fixture.rainbow.anchor:IsA("BasePart")):toBeTrue()
		expect(fixture.gold.prompt.ObjectText):toBe("Gold Machine")
		expect(fixture.rainbow.prompt.ObjectText):toBe("Rainbow Machine")
		expect(fixture.gold.token ~= fixture.rainbow.token):toBeTrue()
		expect(fixture.gold.token):toBe("server-machine-token-9")
		expect(fixture.rainbow.token):toBe("server-machine-token-10")
	end)

	it("binds each machine ID to only its own GUID, unlock, HRP, and 12-stud radius", function()
		local fixture = createFixture()
		for _, current in ipairs({ fixture.gold, fixture.rainbow }) do
			expectAllowed(fixture, current)
			expect(fixture.validator(fixture.player, current.definition.id, "copied-token")):toBeFalse()
			fixture.root.Position = current.anchor.Position + Vector3.new(12, 0, 0)
			expect(fixture.validator(fixture.player, current.definition.id, current.token)):toBeTrue()
			fixture.root.Position = current.anchor.Position + Vector3.new(12.001, 0, 0)
			expect(fixture.validator(fixture.player, current.definition.id, current.token)):toBeFalse()
		end
		expect(fixture.validator(fixture.player, "GoldMachine", fixture.rainbow.token)):toBeFalse()
		expect(fixture.validator(fixture.player, "RainbowMachine", fixture.gold.token)):toBeFalse()

		fixture.root.Position = fixture.rainbow.anchor.Position
		profile.unlockedZones = { 1, 2, 3, 4, 5 }
		expect(fixture.validator(fixture.player, "RainbowMachine", fixture.rainbow.token)):toBeFalse()
		profile.unlockedZones = { 1, 2, 3, 4, 5, 6 }
		expectAllowed(fixture, fixture.rainbow)
	end)

	it("rejects cloned Gold and Rainbow stations even with copied names, attributes, and tokens", function()
		local fixture = createFixture()
		for _, current in ipairs({ fixture.gold, fixture.rainbow }) do
			local copy = Instance.new("Model")
			copy.Name = current.definition.id
			copy:SetAttribute("MachineId", current.definition.id)
			copy:SetAttribute("MachineZoneId", current.definition.zoneId)
			copy:SetAttribute("MachineIdentityToken", current.token)
			local copyAnchor = Instance.new("Part")
			copyAnchor.Name = "Anchor"
			copyAnchor.Shape = current.anchor.Shape
			copyAnchor.Anchored = true
			copyAnchor.CanCollide = current.anchor.CanCollide
			copyAnchor.Size = current.anchor.Size
			copyAnchor.CFrame = current.anchor.CFrame
			copyAnchor.Color = current.anchor.Color
			copyAnchor.Material = current.anchor.Material
			copyAnchor.Parent = copy
			copy.PrimaryPart = copyAnchor
			local copyPrompt = Instance.new("ProximityPrompt")
			copyPrompt.Name = "UseMachinePrompt"
			copyPrompt.ActionText = "Use Machine"
			copyPrompt.ObjectText = current.prompt.ObjectText
			copyPrompt.Enabled = true
			copyPrompt.HoldDuration = 0
			copyPrompt.RequiresLineOfSight = false
			copyPrompt.MaxActivationDistance = 12
			copyPrompt.Parent = copyAnchor
			copy.Parent = current.zone

			fixture.root.Position = current.anchor.Position
			expect(fixture.validator(fixture.player, current.definition.id, current.token)):toBeFalse()
			copy.Name = "VisualClone"
			expect(fixture.validator(fixture.player, current.definition.id, current.token)):toBeFalse()
			copy:SetAttribute("MachineId", nil)
			expect(fixture.validator(fixture.player, current.definition.id, current.token)):toBeFalse()
			current.model.Parent = nil
			fixture.root.Position = copyAnchor.Position
			expect(fixture.validator(fixture.player, current.definition.id, current.token)):toBeFalse()
			current.model.Parent = current.zone
			copy:Destroy()
			expectAllowed(fixture, current)
		end
	end)

	it("fails closed on exact Model, Anchor, Prompt, ancestry, Character, and HRP tampering", function()
		local fixture = createFixture()
		for _, current in ipairs({ fixture.gold, fixture.rainbow }) do
			expectDeniedAfterMutation(fixture, current, current.model, "Name", "ForgedMachine")
			expectDeniedAfterMutation(fixture, current, current.model, "PrimaryPart", nil)
			local originalToken = current.model:GetAttribute("MachineIdentityToken")
			current.model:SetAttribute("MachineIdentityToken", "forged")
			expect(fixture.validator(fixture.player, current.definition.id, current.token)):toBeFalse()
			current.model:SetAttribute("MachineIdentityToken", originalToken)

			expectDeniedAfterMutation(fixture, current, current.anchor, "Name", "ForgedAnchor")
			expectDeniedAfterMutation(fixture, current, current.anchor, "Shape", "Ball")
			expectDeniedAfterMutation(fixture, current, current.anchor, "Anchored", false)
			expectDeniedAfterMutation(fixture, current, current.anchor, "CanCollide", false)
			expectDeniedAfterMutation(fixture, current, current.anchor, "Size", Vector3.new(1, 1, 1))
			expectDeniedAfterMutation(fixture, current, current.anchor, "CFrame", CFrame.new(0, 0, 0))
			expectDeniedAfterMutation(fixture, current, current.anchor, "Color", Color3.fromRGB(1, 2, 3))
			expectDeniedAfterMutation(fixture, current, current.anchor, "Material", "Plastic")

			expectDeniedAfterMutation(fixture, current, current.prompt, "Name", "ForgedPrompt")
			expectDeniedAfterMutation(fixture, current, current.prompt, "Enabled", false)
			expectDeniedAfterMutation(fixture, current, current.prompt, "HoldDuration", 1)
			expectDeniedAfterMutation(fixture, current, current.prompt, "RequiresLineOfSight", true)
			expectDeniedAfterMutation(fixture, current, current.prompt, "MaxActivationDistance", 99)
			expectDeniedAfterMutation(fixture, current, current.prompt, "ActionText", "Free Convert")
			expectDeniedAfterMutation(fixture, current, current.prompt, "ObjectText", "Forged Machine")

			local extraPrompt = Instance.new("ProximityPrompt")
			extraPrompt.Name = "UseMachinePrompt"
			extraPrompt.Parent = current.anchor
			expect(fixture.validator(fixture.player, current.definition.id, current.token)):toBeFalse()
			extraPrompt:Destroy()
			expectAllowed(fixture, current)

			current.prompt.Parent = current.model
			expect(fixture.validator(fixture.player, current.definition.id, current.token)):toBeFalse()
			current.prompt.Parent = current.anchor
			expectAllowed(fixture, current)
		end

		fixture.root.Position = fixture.gold.anchor.Position
		fixture.player.Character = nil
		expect(fixture.validator(fixture.player, "GoldMachine", fixture.gold.token)):toBeFalse()
		fixture.player.Character = fixture.character
		fixture.root.Parent = workspace
		expect(fixture.validator(fixture.player, "GoldMachine", fixture.gold.token)):toBeFalse()
		fixture.root.Parent = fixture.character
		expectAllowed(fixture, fixture.gold)
	end)
end)


local function eggStationFixture(fixture, eggType)
	local folder = workspace:FindFirstChild("EggStations")
	for _, candidate in ipairs(folder:GetChildren()) do
		if candidate:IsA("BasePart") and candidate.Name == "EggModel"
			and candidate:GetAttribute("EggType") == eggType then
			return {
				folder = folder,
				pedestal = folder:FindFirstChild("EggStation_" .. eggType),
				egg = candidate,
				interactZone = folder:FindFirstChild("InteractZone_" .. eggType),
				stationId = candidate:GetAttribute("EggStationId"),
				token = candidate:GetAttribute("EggStationIdentityToken"),
				prompt = candidate:FindFirstChild("HatchPrompt"),
				zone = candidate:GetAttribute("EggZoneId"),
			}
		end
	end
	return nil
end

describe("QOF-18 egg station authority", function()
	it("creates stable bounded IDs with unique per-server capabilities", function()
		local fixture = createFixture()
		expect(type(fixture.eggAuthority)):toBe("table")
		local basic = eggStationFixture(fixture, "BasicEgg")
		local premium = eggStationFixture(fixture, "PremiumEgg")
		expect(basic.stationId):toBe("EggStation-1-BasicEgg")
		expect(#basic.stationId <= 64):toBeTrue()
		expect(type(basic.token)):toBe("string")
		expect(type(premium.token)):toBe("string")
		expect(basic.token ~= premium.token):toBeTrue()
	end)

	it("requires exact station, token, zone, character, and start distance", function()
		local fixture = createFixture()
		local basic = eggStationFixture(fixture, "BasicEgg")
		local premium = eggStationFixture(fixture, "PremiumEgg")
		fixture.root.Position = basic.egg.Position
		local selected = fixture.eggAuthority.validateSelection(
			fixture.player, basic.stationId, basic.token, "BasicEgg", 1, true
		)
		expect(selected):toEqual({ stationId = basic.stationId, eggType = "BasicEgg", zone = 1 })
		expect(fixture.eggAuthority.validateSelection(
			fixture.player, basic.stationId, premium.token, "BasicEgg", 1, true
		)):toBeNil()
		expect(fixture.eggAuthority.validateSelection(
			fixture.player, basic.stationId, basic.token, "PremiumEgg", 1, true
		)):toBeNil()

		fixture.root.Position = basic.egg.Position + Vector3.new(10.001, 0, 0)
		expect(fixture.eggAuthority.validateSelection(
			fixture.player, basic.stationId, basic.token, "BasicEgg", 1, true
		)):toBeNil()
		-- Follow-up ticks use only the private server call; no client flag can grant it.
		expect(fixture.eggAuthority.validateSelection(
			fixture.player, basic.stationId, basic.token, "BasicEgg", 1, false
		).eggType):toBe("BasicEgg")
		profile.unlockedZones = { 2 }
		expect(fixture.eggAuthority.validateSelection(
			fixture.player, basic.stationId, basic.token, "BasicEgg", 1, false
		)):toBeNil()
	end)

	it("fails closed for clone, token-swap, prompt, property, and ancestry tampering", function()
		local fixture = createFixture()
		local basic = eggStationFixture(fixture, "BasicEgg")
		local premium = eggStationFixture(fixture, "PremiumEgg")
		fixture.root.Position = basic.egg.Position
		local function allowed()
			return fixture.eggAuthority.validateSelection(
				fixture.player, basic.stationId, basic.token, "BasicEgg", 1, true
			) ~= nil
		end
		expect(allowed()):toBeTrue()

		local oldPromptDistance = basic.prompt.MaxActivationDistance
		basic.prompt.MaxActivationDistance = 99
		expect(allowed()):toBeFalse()
		basic.prompt.MaxActivationDistance = oldPromptDistance
		expect(allowed()):toBeTrue()

		local oldSize = basic.egg.Size
		basic.egg.Size = Vector3.new(1, 1, 1)
		expect(allowed()):toBeFalse()
		basic.egg.Size = oldSize
		expect(allowed()):toBeTrue()

		local function expectEggStationTamperDenied(target, property, forgedValue)
			local original = target[property]
			target[property] = forgedValue
			expect(allowed()):toBeFalse()
			target[property] = original
			expect(allowed()):toBeTrue()
		end
		expectEggStationTamperDenied(basic.pedestal, "Color", Color3.fromRGB(1, 2, 3))
		expectEggStationTamperDenied(basic.pedestal, "Material", "ForgedMaterial")
		expectEggStationTamperDenied(basic.interactZone, "Shape", Enum.PartType.Ball)
		expectEggStationTamperDenied(basic.interactZone, "Color", Color3.fromRGB(4, 5, 6))
		expectEggStationTamperDenied(basic.interactZone, "Material", "ForgedMaterial")

		local oldToken = basic.egg:GetAttribute("EggStationIdentityToken")
		basic.egg:SetAttribute("EggStationIdentityToken", premium.token)
		expect(allowed()):toBeFalse()
		basic.egg:SetAttribute("EggStationIdentityToken", oldToken)

		local clone = Instance.new("Part")
		clone.Name = "EggModel"
		clone:SetAttribute("EggStationId", basic.stationId)
		clone:SetAttribute("EggStationIdentityToken", basic.token)
		clone.Parent = basic.folder
		expect(allowed()):toBeFalse()
		clone:Destroy()
		expect(allowed()):toBeTrue()

		basic.prompt.Parent = basic.folder
		expect(allowed()):toBeFalse()
		basic.prompt.Parent = basic.egg
		expect(allowed()):toBeTrue()
	end)
end)
