--[[
	EnchantingClientSession.lua - Pure QOF-19 pet/revision request ownership.
	The server remains authoritative for every state field and mutation. This
	module only prevents responses from an old pet, generation, or revision from
	owning the current client UI.
]]

local EnchantingClientSession = {}

local CONTRACT_VERSION = 1
local ACTIONS = {
	GET_STATE = true,
	ROLL = true,
}
local ENCHANT_IDS = {
	StrongI = true,
	StrongII = true,
	StrongIII = true,
	AgileI = true,
	AgileII = true,
	AgileIII = true,
}

local function validPetInstanceId(value)
	return type(value) == "string" and value ~= "" and #value <= 128
end

local function validEnchantId(value)
	return value == false or ENCHANT_IDS[value] == true
end

local function validRevision(value)
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
		and value >= 0
		and value % 1 == 0
end

local function clearSelection(session)
	session.petInstanceId = nil
	session.inFlight = false
	session.hasState = false
	session.stateRevision = nil
	session.enchantId = nil
end

function EnchantingClientSession.new()
	return {
		generation = 0,
		petInstanceId = nil,
		inFlight = false,
		hasState = false,
		stateRevision = nil,
		enchantId = nil,
		revisionsByPet = {},
	}
end

function EnchantingClientSession.selectPet(session, petInstanceId)
	if type(session) ~= "table" then return false end
	session.generation = (session.generation or 0) + 1
	clearSelection(session)
	if not validPetInstanceId(petInstanceId) then
		return false
	end
	session.petInstanceId = petInstanceId
	return true
end

function EnchantingClientSession.close(session)
	if type(session) ~= "table" then return end
	session.generation = (session.generation or 0) + 1
	clearSelection(session)
end

function EnchantingClientSession.beginRequest(session, action)
	if type(session) ~= "table" or session.inFlight
		or not validPetInstanceId(session.petInstanceId)
		or ACTIONS[action] ~= true then
		return nil
	end
	if action == "ROLL" and (session.hasState ~= true
		or not validRevision(session.stateRevision)
		or not validEnchantId(session.enchantId)) then
		return nil
	end

	session.generation = (session.generation or 0) + 1
	session.inFlight = true
	local operation = {
		generation = session.generation,
		petInstanceId = session.petInstanceId,
		action = action,
	}
	if action == "ROLL" then
		operation.expectedStateRevision = session.stateRevision
		operation.expectedEnchantId = session.enchantId
	end
	return operation
end

function EnchantingClientSession.isCurrent(session, operation)
	return type(session) == "table" and type(operation) == "table"
		and session.inFlight == true
		and session.generation == operation.generation
		and session.petInstanceId == operation.petInstanceId
		and ACTIONS[operation.action] == true
end

function EnchantingClientSession.finishRequest(session, operation)
	if not EnchantingClientSession.isCurrent(session, operation) then
		return false
	end
	session.inFlight = false
	return true
end

function EnchantingClientSession.acceptState(session, operation, state, mutationSucceeded)
	if not EnchantingClientSession.isCurrent(session, operation)
		or type(state) ~= "table" or state.contractVersion ~= CONTRACT_VERSION
		or type(state.pet) ~= "table"
		or state.pet.instanceId ~= operation.petInstanceId
		or not validRevision(state.stateRevision) then
		return false
	end
	local enchantId = state.pet.enchantId
	if not validEnchantId(enchantId) then
		return false
	end
	local knownRevision = type(session.revisionsByPet) == "table"
		and session.revisionsByPet[operation.petInstanceId] or nil
	if validRevision(knownRevision) and state.stateRevision < knownRevision then
		return false
	end
	if operation.action == "ROLL" and state.stateRevision < operation.expectedStateRevision then
		return false
	end
	-- A successful paid mutation must advance beyond its optimistic revision.
	-- Semantic failures may legitimately return the same authoritative state.
	if operation.action == "ROLL" and mutationSucceeded == true
		and state.stateRevision <= operation.expectedStateRevision then
		return false
	end

	session.revisionsByPet[operation.petInstanceId] = state.stateRevision
	session.stateRevision = state.stateRevision
	session.enchantId = enchantId
	session.hasState = true
	session.inFlight = false
	return true
end

return EnchantingClientSession
