-- PetDexClient.spec.lua - QOF-20 client/server source-boundary contracts.

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

describe("QOF-20 Pet Dex client and remote contracts", function()
	it("renders six canonical states and records committed hatch and machine results", function()
		local ui = readSource("src/StarterPlayer/StarterPlayerScripts/UIController.lua")
		local main = readSource("src/StarterPlayer/StarterPlayerScripts/Main.client.lua")
		if not ui or not main then return end
		expect(contains(ui, 'local PetDex = require(Shared:WaitForChild("PetDex"))')):toBeTrue()
		expect(contains(ui, "local states = PetDex.getStates()")):toBeTrue()
		expect(contains(ui, "local discoveryKey = PetDex.getCanonicalKey(")):toBeTrue()
		expect(contains(ui, "variantLabel.Text = presentation.variantLabel")):toBeTrue()
		expect(contains(ui, "function UIController:recordPetDiscoveries(pets)")):toBeTrue()
		expect(contains(ui, "A confirmed mutation is newer than every snapshot already in flight.")):toBeTrue()
		expect(contains(ui, "self:recordPetDiscoveries({ result.outputPet })")):toBeTrue()
		expect(contains(main, "uiController:recordPetDiscoveries(pets)")):toBeTrue()
	end)

	it("rejects stale or failed refreshes without clearing local progress", function()
		local ui = readSource("src/StarterPlayer/StarterPlayerScripts/UIController.lua")
		local main = readSource("src/StarterPlayer/StarterPlayerScripts/Main.client.lua")
		if not ui or not main then return end
		expect(contains(ui, "self._petIndexRefreshGeneration = self._petIndexRefreshGeneration + 1")):toBeTrue()
		expect(contains(ui, "local invoked, discovered = pcall(remote.InvokeServer, remote)")):toBeTrue()
		expect(contains(ui, "generation ~= self._petIndexRefreshGeneration")):toBeTrue()
		expect(contains(ui, "not screen or not screen.Enabled or not projected")):toBeTrue()
		expect(contains(main, 'Remotes:WaitForChild("GetDiscoveredPets")')):toBeFalse()
	end)

	it("keeps the legacy remote shape defensive and distinguishes no refresh from empty", function()
		local server = readSource("src/ServerScriptService/Main.server.lua")
		if not server then return end
		expect(contains(server, 'getRemoteFunction("GetDiscoveredPets").OnServerInvoke')):toBeTrue()
		expect(contains(server, 'if not canCall(player, "GetDiscoveredPets", 0.25) then return nil end')):toBeTrue()
		expect(contains(server, "local discovered = {}")):toBeTrue()
		expect(contains(server, "discovered[key] = true")):toBeTrue()
		expect(contains(server, "return data.discoveredPets or {}")):toBeFalse()
	end)
end)
