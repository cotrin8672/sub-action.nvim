local M = {}
local counts, damaged
local path = vim.fn.stdpath("state") .. "/sub-action.json"

local function load()
	if counts then
		return
	end
	counts = {}
	if vim.fn.filereadable(path) == 0 then
		return
	end
	local ok, data = pcall(function()
		return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
	end)
	if ok and type(data) == "table" then
		for ft, values in pairs(data) do
			if type(ft) == "string" and type(values) == "table" then
				counts[ft] = {}
				for key, count in pairs(values) do
					if type(key) == "string" and type(count) == "number" and count >= 0 then
						counts[ft][key] = count
					end
				end
			end
		end
	else
		damaged = true
		vim.notify("sub-action: unreadable frequency file; preserving " .. path, vim.log.levels.WARN)
	end
end

local function key(action)
	return vim.json.encode({ action.kind or "", action.title })
end

function M.sort(entries, filetype)
	load()
	local values = counts[filetype] or {}
	for i, entry in ipairs(entries) do
		entry.order = i
	end
	table.sort(entries, function(a, b)
		local left, right = values[key(a.action)] or 0, values[key(b.action)] or 0
		return left > right or (left == right and a.order < b.order)
	end)
end

function M.record(action, filetype)
	load()
	if damaged then
		return
	end
	counts[filetype] = counts[filetype] or {}
	local id = key(action)
	counts[filetype][id] = (counts[filetype][id] or 0) + 1
	-- ponytail: concurrent Neovim processes use last-writer-wins; add a lock if shared counts matter.
	local temporary = path .. "." .. vim.fn.getpid() .. ".tmp"
	local ok, err = pcall(function()
		vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
		assert(vim.fn.writefile({ vim.json.encode(counts) }, temporary) == 0)
		assert(vim.uv.fs_rename(temporary, path))
	end)
	if not ok then
		vim.fn.delete(temporary)
		vim.notify("sub-action: could not save frequency: " .. tostring(err), vim.log.levels.WARN)
	end
end

return M
