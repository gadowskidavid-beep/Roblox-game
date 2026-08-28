-- MachineClient.spec.lua - QOF-17 station-bound generic client/UI contracts.

local originalRequire = require
local MachineClientSession = originalRequire("src/ReplicatedStorage/Shared/MachineClientSession")

local function readSource(path)
	if not io or not io.open then return nil end
	local file = assert(io.open(path, "rb"))
	local source = file:read("*a")
	file:close()
	return source
end

local function contains(source, value)
	return source and string.find(source, value, 1, true) ~= nil
end

describe("QOF-17 machine client contracts", function()
	it("routes only Gold and Rainbow prompts through the existing generic remote", function()
		local source = readSource("src/StarterPlayer/StarterPlayerScripts/Main.client.lua")
		if not source then return end
		expect(contains(source, 'WaitForChild("UseMachine")')):toBeTrue()
		expect(contains(source, 'WaitForChild("ConvertToGoldenPet")')):toBeFalse()
		expect(contains(source, 'prompt.Name ~= "UseMachinePrompt"')):toBeTrue()
		expect(contains(source, "GoldMachine = true")):toBeTrue()
		expect(contains(source, "RainbowMachine = true")):toBeTrue()
		expect(contains(source, "ACCEPTED_MACHINE_IDS[machineId] ~= true")):toBeTrue()
		expect(contains(source, "UseMachine:InvokeServer(machineId, identityToken, selectedIds)")):toBeTrue()
		expect(contains(source, "MachineClientSession.finishRequest(machineSession, operation)")):toBeTrue()
		expect(contains(source, "uiController:openMachineSelection(machineId)")):toBeTrue()
	end)

	it("keeps one station-bound action with exact dynamic source, target, price, and loss terms", function()
		local source = readSource("src/StarterPlayer/StarterPlayerScripts/UIController.lua")
		if not source then return end
		expect(contains(source, 'machineBtn.Name = "UseMachineBtn"')):toBeTrue()
		expect(contains(source, 'FindFirstChild("MakeGoldenBtn")')):toBeFalse()
		expect(contains(source, 'FindFirstChild("ConvertToGoldenPet")')):toBeFalse()
		expect(contains(source, 'FindFirstChild("UseRainbowMachineBtn")')):toBeFalse()
		expect(contains(source, "self._multiSelectMode and self._machineSessionActive")):toBeTrue()
		expect(contains(source, "presentation.baseVariant == machineInputVariant")):toBeTrue()
		expect(contains(source, "PetVariantPresentation.resolve(petData).baseVariant == machineInputVariant")):toBeTrue()
		expect(contains(source, "presentation.baseVariant ~= definition.inputVariant")):toBeTrue()
		expect(contains(source, "tostring(definition.cost.amount)")):toBeTrue()
		expect(contains(source, 'outputLabel = "Golden"')):toBeTrue()
		expect(contains(source, 'outputLabel = "Rainbow"')):toBeTrue()
		expect(contains(source, "BalanceConfig.Machines.SuccessChanceByInput[count]")):toBeTrue()
		expect(contains(source, 'warnLabel.Text = "WARNING: Pets and "')):toBeTrue()
		expect(contains(source, 'machineProtected and "Equipped"')):toBeTrue()
		expect(contains(source, 'isFavorite and "Favorite"')):toBeTrue()
		expect(contains(source, 'warnLabel.Text ..= " Shiny does not stack."')):toBeTrue()
		expect(contains(source, "self._machineOverlay ~= completedOverlay")):toBeTrue()
	end)

	it("keeps rolling-client compatibility fail-closed and creates both runtime stations generically", function()
		local main = readSource("src/ServerScriptService/Main.server.lua")
		local zone = readSource("src/ServerScriptService/Services/ZoneService.lua")
		if not main or not zone then return end
		expect(contains(main, '"UseMachine",')):toBeTrue()
		expect(contains(main, '"ConvertToGoldenPet",')):toBeTrue()
		expect(contains(main, 'getRemoteFunction("ConvertToGoldenPet").OnServerInvoke')):toBeTrue()
		expect(contains(main, "Legacy conversion unavailable")):toBeTrue()
		expect(contains(main, "PetService.convertToGoldenPet")):toBeFalse()
		expect(contains(main, "MachineAuthorityBootstrap.install")):toBeTrue()
		expect(contains(zone, "local function spawnMachineStation")):toBeTrue()
		expect(contains(zone, 'spawnMachineStation(zonesFolder, "Gold")')):toBeTrue()
		expect(contains(zone, 'spawnMachineStation(zonesFolder, "Rainbow")')):toBeTrue()
		expect(contains(zone, "spawnRainbowMachineStation")):toBeFalse()
	end)
end)

describe("QOF-17 machine client session generations", function()
	it("accepts exactly GoldMachine and RainbowMachine", function()
		for _, machineId in ipairs({ "GoldMachine", "RainbowMachine" }) do
			local state = MachineClientSession.new()
			expect(MachineClientSession.start(state, {}, machineId, "token")):toBeTrue()
			expect(state.machineId):toBe(machineId)
			expect(MachineClientSession.beginRequest(state) ~= nil):toBeTrue()
		end
		local state = MachineClientSession.new()
		expect(MachineClientSession.start(state, {}, "UnknownMachine", "token")):toBeFalse()
		expect(state.machineId):toBeNil()
	end)

	it("invalidates an in-flight response on close", function()
		local state = MachineClientSession.new()
		local prompt = {}
		expect(MachineClientSession.start(state, prompt, "GoldMachine", "token-a")):toBeTrue()
		local operation = MachineClientSession.beginRequest(state)
		expect(operation ~= nil):toBeTrue()
		expect(MachineClientSession.isCurrent(state, operation)):toBeTrue()
		MachineClientSession.close(state)
		expect(MachineClientSession.isCurrent(state, operation)):toBeFalse()
		expect(MachineClientSession.finishRequest(state, operation)):toBeFalse()
		expect(state.prompt):toBeNil()
		expect(state.inFlight):toBeFalse()
	end)

	it("prevents duplicate requests and permits retry only after the current request finishes", function()
		local state = MachineClientSession.new()
		expect(MachineClientSession.start(state, {}, "RainbowMachine", "token-a")):toBeTrue()
		local first = MachineClientSession.beginRequest(state)
		expect(first ~= nil):toBeTrue()
		expect(MachineClientSession.beginRequest(state)):toBeNil()
		expect(MachineClientSession.finishRequest(state, first)):toBeTrue()
		local retry = MachineClientSession.beginRequest(state)
		expect(retry ~= nil):toBeTrue()
		expect(retry.generation > first.generation):toBeTrue()
	end)

	it("makes a cross-machine replacement own a new generation", function()
		local state = MachineClientSession.new()
		local firstPrompt = {}
		local secondPrompt = {}
		MachineClientSession.start(state, firstPrompt, "GoldMachine", "token-a")
		local oldOperation = MachineClientSession.beginRequest(state)
		MachineClientSession.start(state, secondPrompt, "RainbowMachine", "token-b")
		expect(MachineClientSession.isCurrent(state, oldOperation)):toBeFalse()
		expect(state.prompt):toBe(secondPrompt)
		expect(state.machineId):toBe("RainbowMachine")
		expect(state.identityToken):toBe("token-b")
	end)

	it("clears prior authority on every malformed start", function()
		local invalidStarts = {
			{ nil, "GoldMachine", "token" },
			{ {}, "UnknownMachine", "token" },
			{ {}, "GoldMachine", "" },
			{ {}, "RainbowMachine", string.rep("x", 129) },
		}
		for _, invalid in ipairs(invalidStarts) do
			local state = MachineClientSession.new()
			MachineClientSession.start(state, {}, "GoldMachine", "old-token")
			expect(MachineClientSession.start(state, invalid[1], invalid[2], invalid[3])):toBeFalse()
			expect(state.prompt):toBeNil()
			expect(state.machineId):toBeNil()
			expect(state.identityToken):toBeNil()
			expect(state.inFlight):toBeFalse()
		end
	end)
end)
