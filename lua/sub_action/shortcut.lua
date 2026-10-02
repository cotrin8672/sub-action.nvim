local M = {}
local alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"

function M.labels(entries, mode)
	local labels, seeds, initials, counts = {}, {}, {}, {}
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
	if mode == "off" then
		for i = 1, #entries do
			labels[i] = ""
		end
	elseif mode == "mnemonic" then
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
		-- ponytail: quadratic comparison is enough for cursor-local actions; use a trie for huge lists.
		for i, seed in ipairs(seeds) do
			for length = 1, #seed do
				local prefix, unique = seed:sub(1, length), true
				for j, other in ipairs(seeds) do
					if i ~= j and other:sub(1, length) == prefix then
						unique = false
						break
					end
				end
				if unique then
					labels[i] = prefix
					break
				end
			end
		end
	end
	return labels
end

function M.match(labels, input)
	local matches = {}
	for i, label in ipairs(labels) do
		if label ~= "" and label:sub(1, #input) == input then
			matches[#matches + 1] = i
		end
	end
	return matches
end

return M
