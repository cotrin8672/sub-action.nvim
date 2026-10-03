local M = {}
local alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"

function M.labels(entries, mode)
	local labels, seeds, initials, counts = {}, {}, {}, {}
	if mode == "off" then
		for i = 1, #entries do
			labels[i] = ""
		end
		return labels
	end
	for i, entry in ipairs(entries) do
		local words = {}
		for word in entry.action.title:lower():gmatch("[a-z0-9]+") do
			words[#words + 1] = word
		end
		local first = words[1] or "a"
		local initial = first:sub(1, 1)
		local tail = ""
		for j = 2, #words do
			initial = initial .. words[j]:sub(1, 1)
			tail = tail .. words[j]
		end
		initials[i] = initial
		seeds[i] = tail == "" and first or first:sub(1, 1) .. tail .. first:sub(2)
		counts[seeds[i]] = (counts[seeds[i]] or 0) + 1
	end
	if mode == "mnemonic" then
		local used = {}
		for i, entry in ipairs(entries) do
			local candidates = initials[i] .. entry.action.title:lower() .. alphabet
			labels[i] = ""
			for char in candidates:gmatch("[a-z0-9]") do
				if not used[char] then
					labels[i], used[char] = char, true
					break
				end
			end
		end
	else
		for i, seed in ipairs(seeds) do
			local suffix = string.format("%0" .. #tostring(#entries) .. "d", i)
			seeds[i] = (counts[seed] > 1 and initials[i] .. suffix or seed) .. ":" .. suffix
		end
		local order = {}
		for i = 1, #seeds do
			order[i] = i
		end
		table.sort(order, function(a, b)
			return seeds[a] < seeds[b]
		end)
		local function shared(a, b)
			local length = 0
			if b then
				while length < math.min(#a, #b) and a:byte(length + 1) == b:byte(length + 1) do
					length = length + 1
				end
			end
			return length
		end
		-- In lexical order, only the two neighbours can share the longest prefix.
		for position, i in ipairs(order) do
			labels[i] = seeds[i]:sub(
				1,
				1 + math.max(shared(seeds[i], seeds[order[position - 1]]), shared(seeds[i], seeds[order[position + 1]]))
			)
		end
	end
	return labels
end

function M.match(labels, input)
	local first, count = nil, 0
	for i, label in ipairs(labels) do
		if label ~= "" and label:sub(1, #input) == input then
			first, count = first or i, count + 1
		end
	end
	return first, count
end

return M
