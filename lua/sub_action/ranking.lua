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
	timer:start(
		1000,
		0,
		vim.schedule_wrap(function()
			M.flush()
		end)
	)
end

function M.flush(synchronous)
	if timer then
		timer:stop()
	end
	if saving then
		if not synchronous then
			return
		end
		assert(
			vim.wait(5000, function()
				return not saving
			end, 1),
			"sub-action: frequency save still pending"
		)
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
	if synchronous then
		local written, err = pcall(function()
			assert(vim.fn.writefile({ data:sub(1, -2) }, temporary) == 0)
			assert(uv.fs_rename(temporary, path))
		end)
		if written then
			dirty = false
		else
			vim.fn.delete(temporary)
			failure(err)
		end
		return
	end
	dirty, saving = false, true
	local function finish(err)
		local function complete()
			vim.schedule(function()
				saving = false
				if err then
					failure(err)
				elseif dirty then
					schedule_save()
				end
			end)
		end
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
