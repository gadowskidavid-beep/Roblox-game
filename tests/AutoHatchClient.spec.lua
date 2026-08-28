local Session = require("src/ReplicatedStorage/Shared/AutoHatchClientSession")

describe("QOF-18 Auto-Hatch client generations", function()
	it("binds one exact station and rejects malformed capabilities", function()
		local session = Session.new()
		expect(Session.start(session, {}, "EggStation-1-BasicEgg", "guid", "BasicEgg")):toBeTrue()
		expect(session.stationId):toBe("EggStation-1-BasicEgg")
		expect(Session.start(session, {}, "", "guid", "BasicEgg")):toBeFalse()
		expect(session.prompt):toBeNil()
	end)

	it("invalidates stale A to B responses and close callbacks", function()
		local session = Session.new()
		local promptA = {}
		local promptB = {}
		Session.start(session, promptA, "EggStation-1-BasicEgg", "guid-a", "BasicEgg")
		local operationA = Session.beginRequest(session, "START")
		expect(operationA ~= nil):toBeTrue()
		Session.start(session, promptB, "EggStation-2-PremiumEgg", "guid-b", "PremiumEgg")
		expect(Session.finishRequest(session, operationA)):toBeFalse()
		local operationB = Session.beginRequest(session, "START")
		Session.close(session)
		expect(Session.finishRequest(session, operationB)):toBeFalse()
		-- Cancel/navigation close followed by the same prompt reopening has the
		-- same generation guarantee as a cross-station replacement.
		Session.start(session, promptB, "EggStation-2-PremiumEgg", "guid-b", "PremiumEgg")
		local operationBeforeCancel = Session.beginRequest(session, "START")
		Session.close(session)
		Session.start(session, promptB, "EggStation-2-PremiumEgg", "guid-b", "PremiumEgg")
		expect(Session.finishRequest(session, operationBeforeCancel)):toBeFalse()
		expect(Session.beginRequest(session, "START") ~= nil):toBeTrue()
	end)

	it("permits one request in flight and accepts only monotone V1 state", function()
		local session = Session.new()
		Session.start(session, {}, "EggStation-1-BasicEgg", "guid", "BasicEgg")
		local operation = Session.beginRequest(session, "SET_BATCH")
		expect(operation ~= nil):toBeTrue()
		expect(Session.beginRequest(session, "STOP")):toBeNil()
		expect(Session.finishRequest(session, operation)):toBeTrue()
		expect(Session.acceptState(session, { contractVersion = 1, stateRevision = 5 })):toBeTrue()
		expect(Session.acceptState(session, { contractVersion = 1, stateRevision = 5 })):toBeFalse()
		expect(Session.acceptState(session, { contractVersion = 1, stateRevision = 4 })):toBeFalse()
		expect(Session.acceptState(session, { contractVersion = 2, stateRevision = 6 })):toBeFalse()
		expect(Session.acceptState(session, { contractVersion = 1, stateRevision = 6 })):toBeTrue()
	end)
end)


local function readSource(path)
	if not io or not io.open then return nil end
	local file = assert(io.open(path, "rb"))
	local source = file:read("*a")
	file:close()
	return source
end

local function contains(source, needle)
	return string.find(source, needle, 1, true) ~= nil
end

describe("QOF-18 client and UI source contracts", function()
	it("discovers new remotes optionally and binds controls to exact station capabilities", function()
		local main = readSource("src/StarterPlayer/StarterPlayerScripts/Main.client.lua")
		local ui = readSource("src/StarterPlayer/StarterPlayerScripts/UIController.lua")
		if not main or not ui then return end
		for _, required in ipairs({
			'FindFirstChild("AutoHatchStateUpdated")',
			'FindFirstChild("PurchaseAutoHatch")',
			'FindFirstChild("StartAutoHatch")',
			'FindFirstChild("StopAutoHatch")',
			'GetAttribute("EggStationId")',
			'GetAttribute("EggStationIdentityToken")',
			'AutoHatchClientSession.finishRequest',
			'Direct A-to-B prompt switches revoke both request and busy UI ownership.',
			'Cancel/navigation owns the same invalidation boundary as PromptHidden:',
			're-triggering must reinstall it before controls reopen.',
			'if autoHatchSession.prompt ~= prompt then',
			'autoHatchGlobalToken += 1',
			'local applied = applyAutoHatchState(state)',
			'Valid semantic failures carry revisioned authoritative actionFeedback',
			'uiController:clearAutoHatchLocalStation()',
			'not uiController:isAutoHatchRuntimeEnabled()',
			'action = "PURCHASE"',
			'action = "START"',
		}) do
			expect(contains(main, required)):toBeTrue()
		end
		expect(contains(main, 'WaitForChild("PurchaseAutoHatch")')):toBeFalse()
		expect(contains(main, 'WaitForChild("AutoHatchStateUpdated")')):toBeFalse()
		for _, required in ipairs({
			'autoPanel.Name = "AutoHatchControls"',
			'"AutoHatchTier" .. tostring(count)',
			'AUTO_HATCH_REASON_TEXT',
			'ACCESS_REQUIRED = "Buy Auto-Hatch Access before starting."',
			'TOO_FAR = "Move closer to this exact egg station to start."',
			'ZONE_LOCKED = "Paused: the station zone is no longer unlocked."',
			'STATION_INVALID = "Paused: the selected egg station failed integrity checks."',
			'CHARACTER_UNAVAILABLE = "Character is unavailable; try again after spawning."',
			'actionFeedback = type(payload.actionFeedback) == "table"',
			'actionFeedback.stationId == station.stationId',
			'revision <= self._autoHatchStateRevision',
			'generation ~= self._autoHatchUiGeneration',
			'autoRuntimeUnavailable',
			'card.button.Text = "UNAVAILABLE"',
			'function UIController:isAutoHatchRuntimeEnabled()',
			'start.Active = runtimeEnabled and remaining > 0',
			'self._autoHatchUiGeneration += 1',
			'item.itemType == "autoHatch"',
		}) do
			expect(contains(ui, required)):toBeTrue()
		end
	end)
end)
