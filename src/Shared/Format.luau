--!strict
-- Turns big numbers into short text: 1500 -> "1.5K", 2500000 -> "2.5M"
local Format = {}
local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }
function Format.Short(n: number): string
	n = math.floor(n)
	if n < 1000 then return tostring(n) end
	local i = 1
	local v = n
	while v >= 1000 and i < #SUFFIXES do v /= 1000; i += 1 end
	local s = if v >= 100 then string.format("%d", v) elseif v >= 10 then string.format("%.1f", v) else string.format("%.2f", v)
	if s:find("%.") then s = s:gsub("0+$", ""):gsub("%.$", "") end
	return s .. SUFFIXES[i]
end
return Format
