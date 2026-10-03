local M = {}
local alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"

function M.labels(entries, mode)
	local labels, seeds, initials, counts = {}, {}, {}, {}
	local locations, seed_locations, initial_locations = {}, {}, {}
	if mode == "off" then
		for i = 1, #entries do
			labels[i] = ""
		end
		return labels, locations
	end
	for i, entry in ipairs(entries) do
		local words, starts = {}, {}
		for start, word in entry.action.title:lower():gmatch("()([a-z0-9]+)") do
			words[#words + 1] = word
			starts[#words] = start
		end
		seed_locations[i], initial_locations[i] = {}, {}
		if starts[1] then
			seed_locations[i][1], initial_locations[i][1] = starts[1], starts[1]
		end
		local first = words[1] or "a"
		local initial = first:sub(1, 1)
		local tail = ""
		for j = 2, #words do
			initial = initial .. words[j]:sub(1, 1)
			tail = tail .. words[j]
			initial_locations[i][j] = starts[j]
			for position = starts[j], starts[j] + #words[j] - 1 do
				seed_locations[i][#seed_locations[i] + 1] = position
			end
		end
		for position = (starts[1] or 0) + 1, (starts[1] or 0) + #first - 1 do
			seed_locations[i][#seed_locations[i] + 1] = position
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
			for position, char in candidates:gmatch("()([a-z0-9])") do
				if not used[char] then
					labels[i], used[char] = char, true
					locations[i] = {
						position <= #initials[i] and initial_locations[i][position]
							or entry.action.title:lower():find(char, 1, true),
					}
					break
				end
			end
		end
	else
		for i, seed in ipairs(seeds) do
			local suffix = string.format("%0" .. #tostring(#entries) .. "d", i)
			seeds[i] = (counts[seed] > 1 and initials[i] .. suffix or seed) .. ":" .. suffix
			locations[i] = counts[seed] > 1 and initial_locations[i] or seed_locations[i]
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
	return labels, locations
end

function M.positions(label, input, title, mode, locations)
	if label == "" then
		return
	end
	input = input:lower():gsub("%s", "")
	if mode == "prefix" and title and title:lower():gsub("%s", ""):sub(1, #input) == input then
		local positions = {}
		for position, char in title:gmatch("()(.)") do
			if not char:match("%s") and #positions < #input then
				positions[#positions + 1] = position
			end
			if #positions == #input then
				break
			end
		end
		return positions
	end
	if label:sub(1, #input) == input then
		return { unpack(locations or {}, 1, #input) }
	end
end

function M.match(labels, input, entries, mode, locations)
	local first, count = nil, 0
	for i, label in ipairs(labels) do
		if M.positions(label, input, entries and entries[i].action.title, mode, locations and locations[i]) then
			first, count = first or i, count + 1
		end
	end
	return first, count
end

return M
