--[[
	run_tests.lua - Minimal test runner for Luau spec files.
	Discovers all *spec* files in tests/ and provides describe/it/expect helpers.
	Prints results to stdout. Exits with code 1 on any failure.
	Usage: luau tests/run_tests.lua
]]

-- Minimal shims so spec files can reference game.ReplicatedStorage etc.
-- We intercept require() calls inside specs to provide stubs.

local totalPassed = 0
local totalFailed = 0
local currentDescribe = ""

local function expect(value)
	local assertion = {}

	function assertion.toBe(_, expected)
		if value ~= expected then
			error(string.format("Expected %s to be %s", tostring(value), tostring(expected)), 2)
		end
	end

	function assertion.toEqual(_, expected)
		-- Deep equality for tables
		local function deepEqual(a, b)
			if type(a) ~= type(b) then return false end
			if type(a) ~= "table" then return a == b end
			for k, v in pairs(a) do
				if not deepEqual(v, b[k]) then return false end
			end
			for k, _ in pairs(b) do
				if a[k] == nil then return false end
			end
			return true
		end
		if not deepEqual(value, expected) then
			error(string.format("Expected tables to be deeply equal"), 2)
		end
	end

	function assertion.toBeGreaterThan(_, expected)
		if not (value > expected) then
			error(string.format("Expected %s > %s", tostring(value), tostring(expected)), 2)
		end
	end

	function assertion.toBeLessThanOrEqual(_, expected)
		if not (value <= expected) then
			error(string.format("Expected %s <= %s", tostring(value), tostring(expected)), 2)
		end
	end

	function assertion.toBeNil(_)
		if value ~= nil then
			error(string.format("Expected nil but got %s", tostring(value)), 2)
		end
	end

	function assertion.toBeTrue(_)
		if value ~= true then
			error(string.format("Expected true but got %s", tostring(value)), 2)
		end
	end

	function assertion.toBeFalse(_)
		if value ~= false then
			error(string.format("Expected false but got %s", tostring(value)), 2)
		end
	end

	function assertion.toContain(_, item)
		if type(value) ~= "table" then
			error("Expected a table for toContain", 2)
		end
		for _, v in ipairs(value) do
			if v == item then return end
		end
		error(string.format("Expected table to contain %s", tostring(item)), 2)
	end

	function assertion.toHaveLength(_, expected)
		if #value ~= expected then
			error(string.format("Expected length %d but got %d", expected, #value), 2)
		end
	end

	return assertion
end

local function it(name, fn)
	local ok, err = pcall(fn)
	if ok then
		totalPassed = totalPassed + 1
		print(string.format("    PASS: %s", name))
	else
		totalFailed = totalFailed + 1
		print(string.format("    FAIL: %s", name))
		print(string.format("          %s", tostring(err)))
	end
end

local function describe(name, fn)
	currentDescribe = name
	print(string.format("\n  %s", name))
	fn()
	currentDescribe = ""
end

-- Export globals for spec files
_G.describe = describe
_G.it = it
_G.expect = expect

-- Load and run spec files
-- In pure Luau CLI context we use a simple require approach
local specFiles = {
	"tests/BalanceConfig.spec",
	"tests/PetHatchMath.spec",
	"tests/PetVariantMath.spec",
	"tests/PetVariantPresentation.spec",
	"tests/HatchCinematicPolicy.spec",
	"tests/DataSchema.spec",
	"tests/DataService.spec",
	"tests/CurrencyService.spec",
	"tests/UpgradeTreeService.spec",
	"tests/PetService.spec",
	"tests/EggService.spec",
}

local function loadSpec(specPath)
	-- Standard Lua treats the dot in `*.spec` as a path separator, so load the
	-- exact filename when loadfile is available. Luau keeps its native require.
	if loadfile then
		local chunk, loadError = loadfile(specPath .. ".lua")
		if not chunk then
			error(loadError)
		end
		return chunk()
	end
	return require(specPath)
end

for _, specPath in ipairs(specFiles) do
	print(string.format("\nRunning: %s", specPath))
	local ok, err = pcall(function()
		loadSpec(specPath)
	end)
	if not ok then
		print(string.format("  ERROR loading spec: %s", tostring(err)))
		totalFailed = totalFailed + 1
	end
end

-- Summary
print(string.format("\n========================================"))
print(string.format("Results: %d passed, %d failed", totalPassed, totalFailed))
print(string.format("========================================\n"))

if totalFailed > 0 then
	-- Use os.exit if available (standard Lua), otherwise error to signal failure
	if os and os.exit then
		os.exit(1)
	else
		error("Tests failed")
	end
end
