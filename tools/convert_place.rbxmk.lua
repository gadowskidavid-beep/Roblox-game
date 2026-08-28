-- Convert one Roblox place between XML (.rbxlx) and binary (.rbxl).
-- Paths are supplied by the caller; filesystem access is constrained by rbxmk.

local inputPath, outputPath = ...

if type(inputPath) ~= "string" or type(outputPath) ~= "string" then
	error("usage: rbxmk run convert_place.rbxmk.lua INPUT OUTPUT", 0)
end

local function extension(path)
	return string.lower(string.match(path, "(%.[^./\\]+)$") or "")
end

local inputFormat = extension(inputPath)
local outputFormat = extension(outputPath)
local conversions = {
	[".rbxlx"] = { format = "rbxlx", output = ".rbxl" },
	[".rbxl"] = { format = "rbxl", output = ".rbxlx" },
}

local conversion = conversions[inputFormat]
if conversion == nil or outputFormat ~= conversion.output then
	error("supported conversions are .rbxlx -> .rbxl and .rbxl -> .rbxlx", 0)
end

local place = fs.read(inputPath, conversion.format)
fs.write(outputPath, place, conversions[outputFormat].format)
