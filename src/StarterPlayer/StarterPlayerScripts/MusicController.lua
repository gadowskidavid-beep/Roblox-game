--[[
	MusicController.lua - Per-zone background music with crossfade
	Creates Sound instances in SoundService. Detects which zone the player is in
	based on their X position and crossfades to the appropriate track.
	Music loops and plays at low volume (0.3-0.5).
]]

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MusicController = {}
MusicController.__index = MusicController

-- Zone boundaries: zones are 250 studs apart, each 200 studs wide
local ZONE_SPACING = 250

-- Crossfade duration in seconds
local CROSSFADE_DURATION = 1.5

function MusicController.new()
	local self = setmetatable({}, MusicController)
	self._currentZone = nil
	self._currentSound = nil
	self._nextSound = nil
	self._sounds = {} -- [zoneId] = Sound instance
	self._initialized = false
	self._zoneMusic = nil
	self._checkConnection = nil
	return self
end

function MusicController:init()
	self._player = Players.LocalPlayer

	-- Load zone music data
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	local ZoneData = require(Shared:WaitForChild("ZoneData"))
	self._zoneMusic = ZoneData.ZoneMusic

	if not self._zoneMusic then
		return
	end

	-- Pre-create Sound instances in SoundService for each zone
	for zoneId, musicDef in pairs(self._zoneMusic) do
		local sound = Instance.new("Sound")
		sound.Name = "ZoneMusic_" .. tostring(zoneId)
		sound.SoundId = musicDef.assetId
		sound.Volume = 0
		sound.Looped = true
		sound.Parent = SoundService
		self._sounds[zoneId] = sound
	end

	self._initialized = true

	-- Start zone detection loop
	self:_startZoneDetection()
end

--------------------------------------------------------------------------------
-- Determine which zone the player is in based on X position
-- Zone centers: zone 1 at X=0, zone 2 at X=250, etc.
-- Zone boundaries are halfway between centers (at X=125, X=375, etc.)
--------------------------------------------------------------------------------
function MusicController:_getPlayerZone()
	local character = self._player.Character
	if not character then return nil end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return nil end

	local playerX = rootPart.Position.X

	-- Each zone center is at (zoneId - 1) * ZONE_SPACING
	-- Find which zone center is closest
	local bestZone = 1
	local bestDist = math.huge

	for zoneId, _ in pairs(self._zoneMusic) do
		local zoneCenter = (zoneId - 1) * ZONE_SPACING
		local dist = math.abs(playerX - zoneCenter)
		if dist < bestDist then
			bestDist = dist
			bestZone = zoneId
		end
	end

	return bestZone
end

--------------------------------------------------------------------------------
-- Crossfade from the current zone track to a new one
--------------------------------------------------------------------------------
function MusicController:_crossfadeTo(newZoneId)
	if not self._zoneMusic[newZoneId] then return end

	local targetVolume = self._zoneMusic[newZoneId].volume or 0.4
	local newSound = self._sounds[newZoneId]
	if not newSound then return end

	-- Fade out old sound
	if self._currentSound and self._currentSound ~= newSound then
		local oldSound = self._currentSound
		local fadeOutInfo = TweenInfo.new(CROSSFADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local fadeOut = TweenService:Create(oldSound, fadeOutInfo, { Volume = 0 })
		fadeOut:Play()
		fadeOut.Completed:Connect(function()
			oldSound:Stop()
		end)
	end

	-- Fade in new sound
	if not newSound.IsPlaying then
		newSound.Volume = 0
		newSound:Play()
	end

	local fadeInInfo = TweenInfo.new(CROSSFADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local fadeIn = TweenService:Create(newSound, fadeInInfo, { Volume = targetVolume })
	fadeIn:Play()

	self._currentSound = newSound
	self._currentZone = newZoneId
end

--------------------------------------------------------------------------------
-- Zone detection: check every 0.5s which zone the player is in
--------------------------------------------------------------------------------
function MusicController:_startZoneDetection()
	if self._checkConnection then return end

	-- Initial check
	task.delay(1, function()
		local zone = self:_getPlayerZone()
		if zone then
			self:_crossfadeTo(zone)
		end
	end)

	-- Periodic check
	self._checkConnection = RunService.Heartbeat:Connect(function()
		-- Only check every ~0.5 seconds (throttle)
		if not self._lastCheck then
			self._lastCheck = 0
		end
		self._lastCheck = self._lastCheck + 1
		if self._lastCheck < 30 then return end -- ~0.5s at 60fps
		self._lastCheck = 0

		local zone = self:_getPlayerZone()
		if zone and zone ~= self._currentZone then
			self:_crossfadeTo(zone)
		end
	end)
end

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------
function MusicController:cleanup()
	if self._checkConnection then
		self._checkConnection:Disconnect()
		self._checkConnection = nil
	end
	for _, sound in pairs(self._sounds) do
		sound:Stop()
		sound:Destroy()
	end
	self._sounds = {}
end

return MusicController
