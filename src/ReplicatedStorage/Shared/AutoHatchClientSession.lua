--[[
	AutoHatchClientSession.lua - Pure generation/revision ownership for QOF-18 UI.
	The station capability is local routing data only; the server revalidates the
	exact private registry before every start and tick.
]]

local AutoHatchClientSession = {}

local function validIdentifier(value, maximum)
	return type(value) == "string" and #value > 0 and #value <= maximum
end

function AutoHatchClientSession.new()
	return {
		generation = 0,
		prompt = nil,
		stationId = nil,
		stationToken = nil,
		eggType = nil,
		stateRevision = -1,
		inFlight = false,
	}
end

function AutoHatchClientSession.close(session)
	session.generation = session.generation + 1
	session.prompt = nil
	session.stationId = nil
	session.stationToken = nil
	session.eggType = nil
	session.inFlight = false
	return session.generation
end

function AutoHatchClientSession.start(session, prompt, stationId, stationToken, eggType)
	AutoHatchClientSession.close(session)
	if prompt == nil
		or not validIdentifier(stationId, 64)
		or not validIdentifier(stationToken, 128)
		or not validIdentifier(eggType, 64) then
		return false
	end
	session.prompt = prompt
	session.stationId = stationId
	session.stationToken = stationToken
	session.eggType = eggType
	return true
end

function AutoHatchClientSession.beginRequest(session, action)
	if session.inFlight or session.prompt == nil or type(action) ~= "string" then
		return nil
	end
	session.inFlight = true
	return {
		generation = session.generation,
		prompt = session.prompt,
		stationId = session.stationId,
		stationToken = session.stationToken,
		eggType = session.eggType,
		action = action,
	}
end

function AutoHatchClientSession.finishRequest(session, operation)
	if type(operation) ~= "table" or session.inFlight ~= true
		or operation.generation ~= session.generation
		or operation.prompt ~= session.prompt
		or operation.stationId ~= session.stationId
		or operation.stationToken ~= session.stationToken
		or operation.eggType ~= session.eggType then
		return false
	end
	session.inFlight = false
	return true
end

function AutoHatchClientSession.acceptState(session, payload)
	if type(payload) ~= "table" or payload.contractVersion ~= 1 then return false end
	local revision = payload.stateRevision
	if type(revision) ~= "number" or revision ~= revision or revision % 1 ~= 0
		or revision < 0 or revision <= session.stateRevision then
		return false
	end
	session.stateRevision = revision
	return true
end

return AutoHatchClientSession
