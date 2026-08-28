-- MachineClient.spec.lua - QOF-16 station-bound client/UI contracts.

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

describe("QOF-16 Gold machine client contracts", function()
	it("routes only the runtime Gold prompt through the generic remote", function()
		local source = readSource("src/StarterPlayer/StarterPlayerScripts/Main.client.lua")
		if not source then return end
		expect(contains(source, 'WaitForChild("UseMachine")')):toBeTrue()
		expect(contains(source, 'WaitForChild("ConvertToGoldenPet")')):toBeFalse()
		expect(contains(source, 'prompt.Name ~= "UseMachinePrompt"')):toBeTrue()
		expect(contains(source, 'machineId ~= "GoldMachine"')):toBeTrue()
		expect(contains(source, "UseMachine:InvokeServer(machineId, identityToken, selectedIds)")):toBeTrue()
		expect(contains(source, "prompt == machineSession.prompt")):toBeTrue()
		expect(contains(source, "MachineClientSession.finishRequest(machineSession, operation)")):toBeTrue()
	end)

	it("keeps the conversion action station-bound and presents exact loss terms", function()
		local source = readSource("src/StarterPlayer/StarterPlayerScripts/UIController.lua")
		if not source then return end
		expect(contains(source, 'goldenBtn.Name = "UseGoldMachineBtn"')):toBeTrue()
		expect(contains(source, 'FindFirstChild("MakeGoldenBtn")')):toBeFalse()
		expect(contains(source, 'FindFirstChild("ConvertToGoldenPet")')):toBeFalse()
		expect(contains(source, "self._multiSelectMode and self._goldMachineSessionActive")):toBeTrue()
		expect(contains(source, "BalanceConfig.Machines.SuccessChanceByInput[count]")):toBeTrue()
		expect(contains(source, "Pets and 750 Diamonds are consumed even on failure")):toBeTrue()
		expect(contains(source, 'presentation.baseVariant ~= "Normal"')):toBeTrue()
		expect(contains(source, "result.outputPet")):toBeTrue()
	end)

	it("removes the free legacy server route and keeps Rainbow world-dormant", function()
		local main = readSource("src/ServerScriptService/Main.server.lua")
		local zone = readSource("src/ServerScriptService/Services/ZoneService.lua")
		if not main or not zone then return end
		expect(contains(main, '"UseMachine",')):toBeTrue()
		expect(contains(main, '"ConvertToGoldenPet",')):toBeTrue()
		expect(contains(main, 'getRemoteFunction("ConvertToGoldenPet").OnServerInvoke')):toBeTrue()
		expect(contains(main, "Legacy conversion unavailable")):toBeTrue()
		expect(contains(main, "PetService.convertToGoldenPet")):toBeFalse()
		expect(contains(main, "MachineAuthorityBootstrap.install")):toBeTrue()
		expect(contains(zone, 'model.Name = definition.id')):toBeTrue()
		expect(contains(zone, 'Instance.new("ProximityPrompt")')):toBeTrue()
		expect(contains(zone, 'spawnGoldMachineStation(zonesFolder)')):toBeTrue()
		expect(contains(zone, 'spawnRainbowMachineStation')):toBeFalse()
	end)
end)



describe("QOF-16 machine client session generations", function()
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
		expect(MachineClientSession.start(state, {}, "GoldMachine", "token-a")):toBeTrue()
		local first = MachineClientSession.beginRequest(state)
		expect(first ~= nil):toBeTrue()
		expect(MachineClientSession.beginRequest(state)):toBeNil()
		expect(MachineClientSession.finishRequest(state, first)):toBeTrue()
		local retry = MachineClientSession.beginRequest(state)
		expect(retry ~= nil):toBeTrue()
		expect(retry.generation > first.generation):toBeTrue()
	end)

	it("makes a replacement prompt own a new generation", function()
		local state = MachineClientSession.new()
		local firstPrompt = {}
		local secondPrompt = {}
		MachineClientSession.start(state, firstPrompt, "GoldMachine", "token-a")
		local oldOperation = MachineClientSession.beginRequest(state)
		MachineClientSession.start(state, secondPrompt, "GoldMachine", "token-b")
		expect(MachineClientSession.isCurrent(state, oldOperation)):toBeFalse()
		expect(state.prompt):toBe(secondPrompt)
		expect(state.identityToken):toBe("token-b")
	end)

	it("rejects malformed or non-Gold session starts", function()
		local state = MachineClientSession.new()
		expect(MachineClientSession.start(state, {}, "RainbowMachine", "token")):toBeFalse()
		expect(MachineClientSession.start(state, nil, "GoldMachine", "token")):toBeFalse()
		expect(MachineClientSession.start(state, {}, "GoldMachine", "")):toBeFalse()
		expect(state.prompt):toBeNil()
	end)
end)
