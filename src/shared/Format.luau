--!strict
-- Number formatting for big incremental numbers: 1234 -> "1.23K", 5.2e6 -> "5.2M"

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local Format = {}

function Format.Number(n: number): string
	if n ~= n then
		return "0"
	end
	local negative = n < 0
	n = math.abs(n)
	if n < 1000 then
		local s = if n == math.floor(n) then tostring(n) else string.format("%.1f", n)
		return (negative and "-" or "") .. s
	end
	local i = 1
	while n >= 1000 and i < #SUFFIXES do
		n /= 1000
		i += 1
	end
	local s = if n >= 100
		then string.format("%.0f", n)
		elseif n >= 10 then string.format("%.1f", n)
		else string.format("%.2f", n)
	if string.find(s, ".", 1, true) then
		s = (string.gsub(s, "0+$", ""))
		s = (string.gsub(s, "%.$", ""))
	end
	return (negative and "-" or "") .. s .. SUFFIXES[i]
end

function Format.Cash(n: number): string
	return "$" .. Format.Number(n)
end

function Format.Time(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

return Format
