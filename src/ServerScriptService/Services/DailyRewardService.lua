--[[
	DailyRewardService.lua - Server-authoritative Daily Rewards system
	7-day reward cycle with UTC day boundary validation.
	Prevents double-claiming and resets streak after 2+ missed days.
]]

local DailyRewardService = {}

-- Service references (set during init)
DailyRewardService._dataService = nil
DailyRewardService._currencyService = nil
DailyRewardService._eggService = nil

-- Constants
local SECONDS_PER_DAY = 86400

-- 7-day reward cycle definition
local REWARDS = {
	[1] = { type = "Coins", amount = 500, description = "500 Coins" },
	[2] = { type = "Diamonds", amount = 50, description = "50 Diamonds" },
	[3] = { type = "Boost", boostType = "2xCoins", duration = 1800, description = "2x Coins Boost (30 min)" },
	[4] = { type = "Coins", amount = 1000, description = "1000 Coins" },
	[5] = { type = "FreeEgg", eggType = "PremiumEgg", description = "Free Egg Hatch" },
	[6] = { type = "Diamonds", amount = 100, description = "100 Diamonds" },
	[7] = { type = "Special", rewards = {
		{ type = "Coins", amount = 5000 },
		{ type = "Diamonds", amount = 500 },
	}, description = "5000 Coins + 500 Diamonds" },
}

-- Helper: get UTC day number from a timestamp
local function getUTCDay(timestamp)
	return math.floor(timestamp / SECONDS_PER_DAY)
end

-- Initialize with service references
function DailyRewardService.init(dataService, currencyService, eggService)
	DailyRewardService._dataService = dataService
	DailyRewardService._currencyService = currencyService
	DailyRewardService._eggService = eggService
end

-- Award a single reward to a player
local function awardReward(player, rewardDef)
	if not rewardDef then return end

	if rewardDef.type == "Coins" then
		if DailyRewardService._currencyService then
			DailyRewardService._currencyService.addCoins(player, rewardDef.amount)
		end
	elseif rewardDef.type == "Diamonds" then
		if DailyRewardService._currencyService then
			DailyRewardService._currencyService.addDiamonds(player, rewardDef.amount)
		end
	elseif rewardDef.type == "Boost" then
		-- Boost rewards are noted in the response; client can display a message.
		-- In a full implementation this would activate a timed buff via ShopService.
		-- For now, grant bonus coins as a placeholder for the boost value.
		if DailyRewardService._currencyService then
			DailyRewardService._currencyService.addCoins(player, 250)
		end
	elseif rewardDef.type == "FreeEgg" then
		if DailyRewardService._eggService then
			DailyRewardService._eggService.hatchFree(player, rewardDef.eggType)
		end
	elseif rewardDef.type == "Special" then
		-- Special rewards contain multiple sub-rewards
		if rewardDef.rewards then
			for _, subReward in ipairs(rewardDef.rewards) do
				awardReward(player, subReward)
			end
		end
	end
end

-- Claim the daily reward for a player
-- Returns { success, day, reward, nextClaimTime } or { success=false, reason }
function DailyRewardService.claimDailyReward(player)
	if not player or not player:IsA("Player") then
		return { success = false, reason = "Invalid player" }
	end

	local dataService = DailyRewardService._dataService
	if not dataService then
		return { success = false, reason = "Service not initialized" }
	end

	local data = dataService.getPlayerData(player)
	if not data then
		return { success = false, reason = "No player data" }
	end

	-- Ensure dailyRewards field exists (backward compat with old saves)
	if not data.dailyRewards then
		data.dailyRewards = { lastClaimTimestamp = 0, currentDay = 0 }
	end

	local now = os.time()
	local currentUTCDay = getUTCDay(now)
	local lastClaimUTCDay = getUTCDay(data.dailyRewards.lastClaimTimestamp)

	-- Check if already claimed today
	if data.dailyRewards.lastClaimTimestamp > 0 and currentUTCDay == lastClaimUTCDay then
		return { success = false, reason = "Already claimed today" }
	end

	-- Calculate streak: if more than 1 day was missed (gap of 2+ days), reset to day 1
	local daysSinceLastClaim = currentUTCDay - lastClaimUTCDay
	local currentDay = data.dailyRewards.currentDay

	if data.dailyRewards.lastClaimTimestamp == 0 then
		-- First time claiming ever
		currentDay = 1
	elseif daysSinceLastClaim >= 2 then
		-- Missed 2+ days, reset streak
		currentDay = 1
	else
		-- Normal progression (exactly 1 day passed)
		currentDay = currentDay + 1
		if currentDay > 7 then
			currentDay = 1
		end
	end

	-- Get the reward for this day
	local rewardDef = REWARDS[currentDay]
	if not rewardDef then
		return { success = false, reason = "Invalid reward day" }
	end

	-- Award the reward
	awardReward(player, rewardDef)

	-- Update player data
	data.dailyRewards.lastClaimTimestamp = now
	data.dailyRewards.currentDay = currentDay

	-- Calculate next claim time (start of next UTC day)
	local nextDayStart = (currentUTCDay + 1) * SECONDS_PER_DAY

	return {
		success = true,
		day = currentDay,
		reward = rewardDef,
		nextClaimTime = nextDayStart,
	}
end

-- Get the daily reward status for a player (used by client UI)
-- Returns { currentDay, canClaim, nextClaimTime, rewards }
function DailyRewardService.getDailyRewardStatus(player)
	if not player or not player:IsA("Player") then
		return { currentDay = 0, canClaim = false, nextClaimTime = 0, rewards = REWARDS }
	end

	local dataService = DailyRewardService._dataService
	if not dataService then
		return { currentDay = 0, canClaim = false, nextClaimTime = 0, rewards = REWARDS }
	end

	local data = dataService.getPlayerData(player)
	if not data then
		return { currentDay = 0, canClaim = false, nextClaimTime = 0, rewards = REWARDS }
	end

	-- Ensure dailyRewards field exists
	if not data.dailyRewards then
		data.dailyRewards = { lastClaimTimestamp = 0, currentDay = 0 }
	end

	local now = os.time()
	local currentUTCDay = getUTCDay(now)
	local lastClaimUTCDay = getUTCDay(data.dailyRewards.lastClaimTimestamp)

	-- Determine if player can claim
	local canClaim = false
	if data.dailyRewards.lastClaimTimestamp == 0 then
		-- Never claimed before
		canClaim = true
	elseif currentUTCDay > lastClaimUTCDay then
		-- A new UTC day has started since last claim
		canClaim = true
	end

	-- Determine the day that would be claimed next
	local nextDay = data.dailyRewards.currentDay
	if canClaim then
		local daysSinceLastClaim = currentUTCDay - lastClaimUTCDay
		if data.dailyRewards.lastClaimTimestamp == 0 then
			nextDay = 1
		elseif daysSinceLastClaim >= 2 then
			nextDay = 1
		else
			nextDay = data.dailyRewards.currentDay + 1
			if nextDay > 7 then
				nextDay = 1
			end
		end
	end

	-- Calculate next claim time
	local nextClaimTime = (currentUTCDay + 1) * SECONDS_PER_DAY

	return {
		currentDay = nextDay,
		canClaim = canClaim,
		nextClaimTime = nextClaimTime,
		rewards = REWARDS,
	}
end

return DailyRewardService
