-- MachineClientSession.lua - Pure generation ownership for QOF-16 prompt sessions.

local MachineClientSession = {}

function MachineClientSession.new()
	return {
		generation = 0,
		prompt = nil,
		machineId = nil,
		identityToken = nil,
		inFlight = false,
	}
end

function MachineClientSession.start(state, prompt, machineId, identityToken)
	if type(state) ~= "table" or prompt == nil
		or machineId ~= "GoldMachine"
		or type(identityToken) ~= "string" or identityToken == "" then
		return false
	end
	state.generation = (state.generation or 0) + 1
	state.prompt = prompt
	state.machineId = machineId
	state.identityToken = identityToken
	state.inFlight = false
	return true
end

function MachineClientSession.close(state)
	if type(state) ~= "table" then return end
	state.generation = (state.generation or 0) + 1
	state.prompt = nil
	state.machineId = nil
	state.identityToken = nil
	state.inFlight = false
end

function MachineClientSession.beginRequest(state)
	if type(state) ~= "table" or state.inFlight
		or state.prompt == nil or state.machineId ~= "GoldMachine"
		or type(state.identityToken) ~= "string" or state.identityToken == "" then
		return nil
	end
	state.generation = (state.generation or 0) + 1
	state.inFlight = true
	return {
		generation = state.generation,
		prompt = state.prompt,
		machineId = state.machineId,
		identityToken = state.identityToken,
	}
end

function MachineClientSession.isCurrent(state, operation)
	return type(state) == "table" and type(operation) == "table"
		and state.generation == operation.generation
		and state.inFlight == true
		and state.prompt == operation.prompt
		and state.machineId == operation.machineId
		and state.identityToken == operation.identityToken
end

function MachineClientSession.finishRequest(state, operation)
	if not MachineClientSession.isCurrent(state, operation) then
		return false
	end
	state.inFlight = false
	return true
end

return MachineClientSession
