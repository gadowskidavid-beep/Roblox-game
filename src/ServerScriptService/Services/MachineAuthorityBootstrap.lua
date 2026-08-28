-- MachineAuthorityBootstrap.lua - Fail-closed installation of QOF-16 world authority.

local MachineAuthorityBootstrap = {}

function MachineAuthorityBootstrap.install(machineService, initSucceeded, candidate)
	if type(machineService) ~= "table"
		or type(machineService.setActivationValidator) ~= "function"
		or initSucceeded ~= true
		or type(candidate) ~= "function" then
		return false
	end
	machineService.setActivationValidator(candidate)
	return true
end

return MachineAuthorityBootstrap
