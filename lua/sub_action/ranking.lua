local M = {}
local counts, damaged, dirty, saving, timer
local uv = vim.uv
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
		local data = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
		vim.validate("frequency file", data, "table")
		for ft, values in pairs(data) do
			vim.validate("filetype", ft, "string")
			vim.validate("frequencies", values, "table")
			for key, count in pairs(values) do
				vim.validate("frequency key", key, "string")
				vim.validate("frequency count", count, "number")
				assert(count >= 0 and count % 1 == 0, "invalid frequency count")
			end
		end
		return data
	end)
	if ok then
		counts = data
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
	local values = counts[filetype]
	if not values or not next(values) then
		return
	end
	local used = false
	for i, entry in ipairs(entries) do
		entry.order = i
		entry.frequency_key = entry.frequency_key or key(entry.action)
		entry.frequency = values[entry.frequency_key] or 0
		used = used or entry.frequency > 0
	end
	if not used then
		return
	end
	table.sort(entries, function(a, b)
		return a.frequency > b.frequency or (a.frequency == b.frequency and a.order < b.order)
	end)
end

local function schedule_save()
	timer = timer or uv.new_timer()
	timer:start(1000, 0, vim.schedule_wrap(M.flush))
end

local function wait_for_save()
	assert(
		vim.wait(5000, function()
			return not saving
		end, 1),
		"sub-action: frequency save still pending"
	)
end

function M.flush(wait)
	if timer then
		timer:stop()
	end
	if saving then
		if not wait then
			return
		end
		wait_for_save()
	end
	if not dirty or damaged then
		return
	end
	-- ponytail: concurrent Neovim processes use last-writer-wins; add a lock if shared counts matter.
	local temporary = path .. "." .. vim.fn.getpid() .. ".tmp"
	local ok, data = pcall(function()
		vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
		return vim.json.encode(counts) .. "\n"
	end)
	local function failure(err)
		dirty = true
		vim.notify("sub-action: could not save frequency: " .. tostring(err), vim.log.levels.WARN)
	end
	if not ok then
		failure(data)
		return
	end
	dirty, saving = false, true
	local function finish(err)
		local complete = vim.schedule_wrap(function()
			saving = false
			if err then
				failure(err)
			elseif dirty then
				schedule_save()
			end
		end)
		-- Finish cleanup before another save can reuse this temporary filename.
		if err then
			uv.fs_unlink(temporary, complete)
		else
			complete()
		end
	end
	uv.fs_open(temporary, "w", 384, function(open_error, fd)
		if open_error then
			finish(open_error)
			return
		end
		uv.fs_write(fd, data, 0, function(write_error, bytes)
			uv.fs_close(fd, function(close_error)
				local err = write_error or close_error or (bytes ~= #data and "incomplete write" or nil)
				if err then
					finish(err)
					return
				end
				uv.fs_rename(temporary, path, finish)
			end)
		end)
	end)
	if wait then
		wait_for_save()
	end
end

function M.record(action, filetype, id)
	load()
	if damaged then
		return
	end
	counts[filetype] = counts[filetype] or {}
	id = id or key(action)
	counts[filetype][id] = (counts[filetype][id] or 0) + 1
	dirty = true
	schedule_save()
end

vim.api.nvim_create_autocmd("VimLeavePre", {
	callback = function()
		M.flush(true)
		if timer then
			timer:close()
			timer = nil
		end
	end,
})

return M
