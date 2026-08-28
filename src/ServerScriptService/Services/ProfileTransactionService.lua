--[[
	ProfileTransactionService.lua - QOF-25 central per-profile mutation owner.
	One opaque owner serializes composite profile/economy work, blocks persistence
	until commit or exact rollback, and remains strongly retained for lifecycle retry.
]]

local ProfileTransactionService = {}

ProfileTransactionService._dataService = nil
ProfileTransactionService._owners = {}
ProfileTransactionService._admissionClosed = {}

local function userIdOf(playerOrUserId)
	if type(playerOrUserId) == "number" and playerOrUserId % 1 == 0 then
		return playerOrUserId
	end
	-- Roblox Player values are Instances/userdata, while tests use plain tables.
	-- Read UserId defensively instead of restricting the container's Lua type.
	local ok, userId = pcall(function()
		return playerOrUserId.UserId
	end)
	if not ok then return nil end
	return type(userId) == "number" and userId % 1 == 0 and userId or nil
end

local function currentOwner(handle)
	local userId = type(handle) == "table" and handle.userId or nil
	return userId and ProfileTransactionService._owners[userId] == handle
end

function ProfileTransactionService.init(dataService)
	ProfileTransactionService._dataService = dataService
	ProfileTransactionService._owners = {}
	ProfileTransactionService._admissionClosed = {}
end

function ProfileTransactionService.begin(player, ownerName)
	local userId = userIdOf(player)
	if not userId or type(ownerName) ~= "string" or ownerName == "" then
		return nil, "INVALID_OWNER"
	end
	if ProfileTransactionService._admissionClosed[userId] ~= nil
		or ProfileTransactionService._owners[userId] ~= nil then
		return nil, "BUSY"
	end
	local dataService = ProfileTransactionService._dataService
	if type(dataService) ~= "table"
		or type(dataService.getPlayerData) ~= "function"
		or type(dataService.isMutationAdmissionOpen) ~= "function"
		or dataService.isMutationAdmissionOpen(player) ~= true then
		return nil, "ADMISSION_CLOSED"
	end
	if type(dataService.isProfileSaveInProgress) == "function"
		and dataService.isProfileSaveInProgress(player) == true then
		return nil, "SAVE_IN_PROGRESS"
	end
	local profile = dataService.getPlayerData(player)
	if type(profile) ~= "table" then
		return nil, "NO_PROFILE"
	end
	local owner = {
		userId = userId,
		player = player,
		profile = profile,
		ownerName = ownerName,
		settler = nil,
		settling = false,
	}
	ProfileTransactionService._owners[userId] = owner
	return owner, nil
end

function ProfileTransactionService.isCurrent(handle)
	return currentOwner(handle)
end

function ProfileTransactionService.setSettler(handle, settler)
	if not currentOwner(handle) or type(settler) ~= "function" then
		return false
	end
	handle.settler = settler
	return true
end

function ProfileTransactionService.commit(handle)
	if not currentOwner(handle) then return false end
	ProfileTransactionService._owners[handle.userId] = nil
	return true
end

function ProfileTransactionService.rollback(handle)
	if not currentOwner(handle) or handle.settling then return false end
	if type(handle.settler) ~= "function" then
		ProfileTransactionService._owners[handle.userId] = nil
		return true
	end
	handle.settling = true
	local ok, restored = pcall(handle.settler, handle)
	handle.settling = false
	if not currentOwner(handle) then
		return ok and restored == true
	end
	if ok and restored == true then
		ProfileTransactionService._owners[handle.userId] = nil
		return true
	end
	return false
end

function ProfileTransactionService.closeAdmission(player)
	local userId = userIdOf(player)
	if not userId then return false end
	local owner = ProfileTransactionService._owners[userId]
	if owner and owner.player ~= player then return false end
	ProfileTransactionService._admissionClosed[userId] = player
	return true
end

function ProfileTransactionService.isAdmissionOpen(player)
	local userId = userIdOf(player)
	return userId ~= nil and ProfileTransactionService._admissionClosed[userId] == nil
end

function ProfileTransactionService.hasPending(playerOrUserId)
	local userId = userIdOf(playerOrUserId)
	return userId ~= nil and ProfileTransactionService._owners[userId] ~= nil
end

function ProfileTransactionService.settlePlayer(player)
	local userId = userIdOf(player)
	if not userId then return false end
	local owner = ProfileTransactionService._owners[userId]
	if not owner then return true end
	if owner.player ~= player then return false end
	return ProfileTransactionService.rollback(owner)
end

function ProfileTransactionService.clearProfile(playerOrUserId)
	local userId = userIdOf(playerOrUserId)
	if not userId or ProfileTransactionService._owners[userId] ~= nil then
		return false
	end
	ProfileTransactionService._admissionClosed[userId] = nil
	return true
end

function ProfileTransactionService.getOwnerName(playerOrUserId)
	local userId = userIdOf(playerOrUserId)
	local owner = userId and ProfileTransactionService._owners[userId] or nil
	return owner and owner.ownerName or nil
end

return ProfileTransactionService
