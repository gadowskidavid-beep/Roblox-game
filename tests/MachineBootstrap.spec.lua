-- MachineBootstrap.spec.lua - Executable QOF-16 world-init fail-closed contracts.

local MachineAuthorityBootstrap = require("src/ServerScriptService/Services/MachineAuthorityBootstrap")

local function runBootstrap(initializer)
	local installed = nil
	local machineService = {}
	function machineService.setActivationValidator(candidate)
		installed = candidate
	end
	local succeeded, candidate = xpcall(initializer, debug.traceback)
	local wired = MachineAuthorityBootstrap.install(machineService, succeeded, candidate)
	return wired, installed, succeeded
end

describe("QOF-16 machine world authority bootstrap", function()
	it("installs exactly the validator returned by successful world initialization", function()
		local validator = function() return true end
		local wired, installed, succeeded = runBootstrap(function()
			return validator
		end)
		expect(succeeded):toBeTrue()
		expect(wired):toBeTrue()
		expect(installed):toBe(validator)
	end)

	it("leaves authority absent when world initialization throws", function()
		local wired, installed, succeeded = runBootstrap(function()
			error("world build failed")
		end)
		expect(succeeded):toBeFalse()
		expect(wired):toBeFalse()
		expect(installed):toBeNil()
	end)

	it("leaves authority absent when initialization returns no callable validator", function()
		for _, candidate in ipairs({ false, true, "validator", {}, 42 }) do
			local wired, installed = runBootstrap(function()
				return candidate
			end)
			expect(wired):toBeFalse()
			expect(installed):toBeNil()
		end
		local wired, installed = runBootstrap(function() return nil end)
		expect(wired):toBeFalse()
		expect(installed):toBeNil()
	end)
end)
