--[[
	EnchantingClientContract.lua - Pure QOF-19 Contract V1 response validation.
	Only the exact canonical server DTO is accepted before client session/UI state
	can change. Every nested object must be a plain table with no extra keys.
]]

local EnchantingClientContract = {}

local CONTRACT_VERSION = 1
local REASON_CODES = {
	INVALID_REQUEST = true,
	RUNTIME_DISABLED = true,
	SERVICE_UNAVAILABLE = true,
	PROFILE_UNAVAILABLE = true,
	PET_NOT_FOUND = true,
	INVALID_PET_STATE = true,
	STALE_STATE = true,
	INSUFFICIENT_BALANCE = true,
	BUSY = true,
	RATE_LIMITED = true,
	TECHNICAL_FAILURE = true,
	ROLLBACK_FAILED = true,
}
local OUTCOMES = {
	{ id = "StrongI", weight = 35, stat = "damage", multiplier = 1.10 },
	{ id = "StrongII", weight = 15, stat = "damage", multiplier = 1.25 },
	{ id = "StrongIII", weight = 5, stat = "damage", multiplier = 1.50 },
	{ id = "AgileI", weight = 30, stat = "speed", multiplier = 1.10 },
	{ id = "AgileII", weight = 12, stat = "speed", multiplier = 1.20 },
	{ id = "AgileIII", weight = 3, stat = "speed", multiplier = 1.35 },
}
local OUTCOME_IDS = {}
for _, outcome in ipairs(OUTCOMES) do
	OUTCOME_IDS[outcome.id] = true
end

local function finiteInteger(value)
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
		and value % 1 == 0
end

local function exactPlainTable(value, allowedKeys, requiredKeys)
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return false
	end
	for key in next, value do
		if allowedKeys[key] ~= true then
			return false
		end
	end
	for key in pairs(requiredKeys or allowedKeys) do
		if rawget(value, key) == nil then
			return false
		end
	end
	return true
end

function EnchantingClientContract.isReasonCode(value)
	return REASON_CODES[value] == true
end

function EnchantingClientContract.validateState(state, petInstanceId)
	if not exactPlainTable(state, {
		contractVersion = true,
		stateRevision = true,
		runtimeEnabled = true,
		pet = true,
		economy = true,
		maxSlotsPerPet = true,
		outcomes = true,
		availability = true,
		isReroll = true,
	}) then
		return false
	end
	if rawget(state, "contractVersion") ~= CONTRACT_VERSION
		or not finiteInteger(rawget(state, "stateRevision"))
		or state.stateRevision < 0
		or type(rawget(state, "runtimeEnabled")) ~= "boolean"
		or rawget(state, "maxSlotsPerPet") ~= 1
		or type(rawget(state, "isReroll")) ~= "boolean" then
		return false
	end

	local pet = rawget(state, "pet")
	if not exactPlainTable(pet, { instanceId = true, enchantId = true })
		or rawget(pet, "instanceId") ~= petInstanceId
		or not (rawget(pet, "enchantId") == false
			or OUTCOME_IDS[rawget(pet, "enchantId")] == true)
		or state.isReroll ~= (pet.enchantId ~= false) then
		return false
	end

	local economy = rawget(state, "economy")
	if not exactPlainTable(economy, { currency = true, price = true })
		or rawget(economy, "currency") ~= "diamonds"
		or rawget(economy, "price") ~= 500 then
		return false
	end

	local availability = rawget(state, "availability")
	if not exactPlainTable(
		availability,
		{ canRoll = true, reason = true },
		{ canRoll = true }
	) or type(rawget(availability, "canRoll")) ~= "boolean" then
		return false
	end
	local reason = rawget(availability, "reason")
	if reason ~= nil and not EnchantingClientContract.isReasonCode(reason) then
		return false
	end
	if availability.canRoll then
		if reason ~= nil or state.runtimeEnabled ~= true then
			return false
		end
	elseif reason == nil then
		return false
	end

	local outcomes = rawget(state, "outcomes")
	if type(outcomes) ~= "table" or getmetatable(outcomes) ~= nil then
		return false
	end
	local count = 0
	for key in next, outcomes do
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #OUTCOMES then
			return false
		end
		count = count + 1
	end
	if count ~= #OUTCOMES or rawlen(outcomes) ~= #OUTCOMES then
		return false
	end
	for index, expected in ipairs(OUTCOMES) do
		local outcome = rawget(outcomes, index)
		if not exactPlainTable(outcome, {
			id = true,
			weight = true,
			stat = true,
			multiplier = true,
		}) or rawget(outcome, "id") ~= expected.id
			or rawget(outcome, "weight") ~= expected.weight
			or rawget(outcome, "stat") ~= expected.stat
			or rawget(outcome, "multiplier") ~= expected.multiplier then
			return false
		end
	end
	return true
end

return EnchantingClientContract
