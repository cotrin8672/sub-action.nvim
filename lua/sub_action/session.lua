local M = {}
local api = vim.api
local events = api.nvim_create_augroup("sub-action", { clear = true })
local lsp = require("sub_action.lsp")
local ui = require("sub_action.ui")
local shortcut = require("sub_action.shortcut")
local current, runtime, pending
local loading = { "Loading…" }
local apply_keys = api.nvim_replace_termcodes("<Cmd>lua require('sub_action.session').apply()<CR>", true, false, true)

local function notify(message)
	vim.notify("sub-action: " .. tostring(message), vim.log.levels.ERROR)
end

local function valid(s)
	if
		current ~= s
		or not api.nvim_buf_is_valid(s.bufnr)
		or api.nvim_get_current_buf() ~= s.bufnr
		or api.nvim_get_current_win() ~= s.winid
		or api.nvim_get_mode().mode ~= "n"
		or api.nvim_buf_get_changedtick(s.bufnr) ~= s.changedtick
	then
		return false
	end
	local cursor = api.nvim_win_get_cursor(s.winid)
	return cursor[1] == s.cursor[1] and cursor[2] == s.cursor[2]
end

function M.close(keep)
	local s = current
	current = nil
	if runtime then
		runtime:stop()
	end
	if not s then
		return
	end
	if s.cancel then
		s.cancel()
	end
	for _, entry in ipairs(s.actions) do
		if entry ~= keep and entry.request_id then
			entry.client:cancel_request(entry.request_id)
		end
	end
	api.nvim_clear_autocmds({ group = events })
	ui.close(s)
end

local function preview(s)
	local entry = s.actions[s.selected]
	if s.preview_entry == entry then
		return
	end
	s.preview_entry = entry
	if entry.preview and (not entry.resolved or entry.preview_action == entry.resolved) then
		ui.preview(s, entry.preview, s.config)
		return
	end
	local finished = false
	local function draw(action, err, resolved)
		local data = resolved and s.config.preview and action or action.edit
		entry.preview_action = action
		if err then
			entry.preview = { "Preview unavailable", err.message or tostring(err) }
		elseif not entry.preview or not vim.deep_equal(entry.preview_data, data) then
			local ok, lines = pcall(function()
				local custom = resolved
						and s.config.preview
						and s.config.preview(action, { client = entry.client, bufnr = s.bufnr })
					or nil
				assert(custom == nil or vim.islist(custom), "preview must return a list of lines or nil")
				for _, line in ipairs(custom or {}) do
					assert(type(line) == "string", "preview lines must be strings")
				end
				if custom then
					return custom
				end
				if entry.preview and vim.deep_equal(entry.preview_data, action.edit) then
					return entry.preview
				end
				return lsp.preview(action.edit, entry.client.offset_encoding)
			end)
			entry.preview = ok and lines or { "Preview unavailable", tostring(lines) }
			entry.preview_data = data
		end
		ui.preview(s, entry.preview, s.config)
	end
	local action = entry.resolved or entry.action
	if action.edit then
		draw(action)
	end
	lsp.resolve(entry, s.bufnr, function(action, err)
		finished = true
		if not valid(s) or s.applying or s.actions[s.selected] ~= entry then
			return
		end
		draw(action, err, true)
	end)
	if not finished and not entry.preview then
		ui.preview(s, loading, s.config)
	end
end

local function render(s)
	if s.queued then
		return
	end
	s.queued = true
	vim.schedule(function()
		s.queued = false
		if not valid(s) or s.applying then
			return
		end
		ui.select(s)
		if not s.preview_queued then
			s.preview_queued = true
			-- Let the selection paint and newer input win before building a cold diff.
			vim.defer_fn(function()
				s.preview_queued = false
				if valid(s) and not s.applying then
					preview(s)
				end
			end, 0)
		end
	end)
end

local function select(s, index)
	s.selected = index
	render(s)
end

local function confirm(s)
	if current ~= s or s.applying then
		return
	end
	s.applying, pending = true, s
	-- Detach inside on_key, then run outside textlock before the next typed key.
	runtime:stop()
	api.nvim_feedkeys(apply_keys, "in", false)
end

function M.apply()
	local s = pending
	pending = nil
	if not s or not valid(s) then
		if current == s then
			M.close()
		end
		return
	end
	local entry = s.actions[s.selected]
	M.close(entry)
	lsp.resolve(entry, s.bufnr, function(action, err)
		if not api.nvim_buf_is_valid(s.bufnr) or api.nvim_buf_get_changedtick(s.bufnr) ~= s.changedtick then
			notify("Source changed while resolving; action cancelled")
			return
		end
		if err and not (action.edit or action.command) then
			notify(err.message or err)
			return
		end
		lsp.apply(entry, action, s.bufnr, function(apply_error)
			if apply_error then
				notify(apply_error.message or apply_error)
			elseif s.config.ranking.frequency then
				require("sub_action.ranking").record(entry.action, s.filetype, entry.frequency_key)
			end
		end)
	end)
end

local function typed(s, char)
	if s.config.shortcut.mode == "off" or not char:match("^%g$") then
		return
	end
	s.input = s.input .. char:lower()
	local first, count = shortcut.match(s.labels, s.input)
	if count == 0 then
		s.input = ""
		render(s)
	elseif count == 1 then
		s.selected = first
		confirm(s)
	elseif s.labels[s.selected]:sub(1, #s.input) ~= s.input then
		select(s, first)
	else
		render(s)
	end
end

local function enter(s)
	local handlers = {
		next = function()
			s.input = ""
			select(s, s.selected % #s.actions + 1)
		end,
		prev = function()
			s.input = ""
			select(s, (s.selected - 2) % #s.actions + 1)
		end,
		apply = function()
			confirm(s)
		end,
		backspace = function()
			s.input = s.input:sub(1, -2)
			render(s)
		end,
		close = function()
			runtime:stop()
		end,
	}
	local mappings = {
		{
			lhs = "<any>",
			action = function(context)
				typed(s, context.input)
			end,
		},
	}
	for lhs, action in pairs(s.config.keymap) do
		mappings[#mappings + 1] = { lhs = lhs, action = handlers[action] }
	end
	runtime = require("nvim-submode.runtime").create({
		id = "sub-action",
		display_name = "CODE ACTION",
		color = s.config.color or nil,
		options = { count = false, interrupt = "" },
		on_leave = function()
			if current == s and not s.applying then
				vim.schedule(function()
					if current == s then
						M.close()
					end
				end)
			end
		end,
		mappings = mappings,
	})
	runtime:start()
	ui.menu(s, s.config)
	preview(s)
end

function M.open(config)
	M.close()
	if api.nvim_get_mode().mode ~= "n" then
		return
	end
	local s = {
		config = config,
		bufnr = api.nvim_get_current_buf(),
		winid = api.nvim_get_current_win(),
		cursor = api.nvim_win_get_cursor(0),
		changedtick = api.nvim_buf_get_changedtick(0),
		filetype = vim.bo.filetype,
		actions = {},
		selected = 1,
		input = "",
	}
	current = s
	api.nvim_create_autocmd({ "CursorMoved", "TextChanged", "BufLeave", "WinLeave", "ModeChanged" }, {
		group = events,
		callback = function()
			vim.schedule(function()
				if current == s and not valid(s) then
					M.close()
				end
			end)
		end,
	})
	api.nvim_create_autocmd({ "VimResized", "ColorScheme" }, {
		group = events,
		callback = function()
			if valid(s) and #s.actions > 0 then
				ui.menu(s, config)
				s.preview_entry = nil
				preview(s)
			end
		end,
	})
	s.cancel = lsp.request(s, function(entries)
		if not valid(s) then
			if current == s then
				M.close()
			end
			return
		end
		if #entries == 0 then
			M.close()
			vim.notify("sub-action: No code actions available")
			return
		end
		if config.ranking.frequency then
			require("sub_action.ranking").sort(entries, s.filetype)
		end
		s.actions, s.labels = entries, shortcut.labels(entries, config.shortcut.mode)
		enter(s)
	end)
end

return M
