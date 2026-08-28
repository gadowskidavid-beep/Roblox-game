local formatNumber = {}

local suffixes = {
	"", "K", "M", "B", "T",
	"Qa", "Qi", "Sx", "Sp", "Oc",
	"No", "Dc", "Ud", "Dd", "Td",
	"Qad", "Qid", "Sxd", "Spd", "Ocd",
	"Nod", "Vg", "Uvg", "Dvg", "Tvg",
	"Qavg", "Qivg", "Sxvg", "Spvg", "Ocvg",
	"Novg", "Dcv", "Udvg", "Ddvg", "Tdvg",
	"Qadvg", "Qidvg", "Sxdvg", "Spdvg", "Ocdvg",
	"Nodvg", "Vgg", "Uvgg", "Dvgg", "Tvgg",
	"QaVg", "QiVg", "SxVg", "SpVg", "OcVg",
	"NoVg", "DcVg", "UdVg", "DdVg", "TdVg"
}

local function removeTrailingZeros(str:string)
	str = string.gsub(str, "%.0+$", "")
	str = string.gsub(str, "%.(%d-)0+$", ".%1")
	return str
end

function formatNumber.format(n)
	n = tonumber(n) or 0

	if n < 1000 then
		local str = string.format("%.2f", n)
		return removeTrailingZeros(str)
	end

	local i = math.floor(math.log10(n) / 3)

	if i <= #suffixes - 1 then
		local scaled = n / (10^(i * 3))

		local num = removeTrailingZeros(string.format("%.2f", scaled))

		return num .. suffixes[i + 1]
	else
		return string.format("%.2e", n)
	end
end


return formatNumber
