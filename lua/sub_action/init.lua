local M = {}
local lsp = require("sub_action.lsp")
local ui = require("sub_action.ui")
local shortcut = require("sub_action.shortcut")
local ranking = require("sub_action.ranking")
local defaults = {
	mapping = "gra",
	shortcut = { mode = "prefix" },
	ui = { action = { max_width = 50, max_height = 8 }, preview = { max_width = 70, max_height = 15 } },
	ranking = { frequency = true },
	client = { display = "name", icons = {} },
}
local config, current, runtime

local function notify(message, level)
	vim.notify("sub-action: " .. message, level or vim.log.levels.INFO)
end

local function valid(s)
	return current == s
		and vim.api.nvim_buf_is_valid(s.bufnr)
		and vim.api.nvim_get_current_buf() == s.bufnr
		and vim.api.nvim_get_current_win() == s.winid
		and vim.api.nvim_get_mode().mode == "n"
		and vim.deep_equal(vim.api.nvim_win_get_cursor(s.winid), s.cursor)
		and vim.api.nvim_buf_get_changedtick(s.bufnr) == s.changedtick
end

function M.close()
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
		if entry.request_id then
			entry.client:cancel_request(entry.request_id)
		end
	end
	for _, id in ipairs(s.events or {}) do
		pcall(vim.api.nvim_del_autocmd, id)
	end
	ui.close(s)
end

local function select(s, index)
	if not valid(s) or s.applying then
		return
	end
	s.selected = index
	s.generation = s.generation + 1
	local generation, entry = s.generation, s.actions[index]
	ui.menu(s, config)
	ui.preview(s, { "Loading…" }, config)
	lsp.resolve(entry, s.bufnr, function(action, err)
		if not valid(s) or generation ~= s.generation then
			return
		end
		local ok, lines = pcall(lsp.preview, action.edit, entry.client.offset_encoding)
		ui.preview(s, ok and lines or { "Preview unavailable", tostring(lines) }, config)
		if err then
			ui.preview(s, { "Preview unavailable", err.message or tostring(err) }, config)
		end
	end)
end

local function apply(s)
	if not valid(s) or s.applying then
		return
	end
	s.applying = true
	local entry = s.actions[s.selected]
	lsp.resolve(entry, s.bufnr, function(action, err)
		if not valid(s) then
			return
		end
		if err and not (action.edit or action.command) then
			s.applying = false
			notify(err.message or tostring(err), vim.log.levels.ERROR)
			return
		end
		M.close()
		lsp.apply(entry, action, s.bufnr, function(apply_error)
			if apply_error then
				notify(tostring(apply_error.message or apply_error), vim.log.levels.ERROR)
			elseif config.ranking.frequency then
				ranking.record(entry.action, s.filetype)
			end
		end)
	end, true)
end

local function typed(s, char)
	if s.applying or config.shortcut.mode == "off" or not char:match("^%g$") then
		return
	end
	s.input = s.input .. char:lower()
	local matches = shortcut.match(s.labels, s.input)
	if #matches == 0 then
		s.input = ""
		ui.menu(s, config)
		return
	end
	if #matches == 1 then
		s.selected = matches[1]
		apply(s)
		return
	end
	if not vim.tbl_contains(matches, s.selected) then
		select(s, matches[1])
	else
		ui.menu(s, config)
	end
end

local function enter(s)
	local function scheduled(fn)
		return function(context)
			vim.schedule(function()
				if valid(s) then
					fn(context)
				end
			end)
		end
	end
	runtime = require("nvim-submode.runtime").create({
		id = "sub-action",
		display_name = "CODE ACTION",
		color = config.color,
		options = { count = false, interrupt = "<C-c>" },
		on_leave = function()
			if current == s then
				M.close()
			end
		end,
		mappings = {
			{
				lhs = "<Tab>",
				action = scheduled(function()
					s.input = ""
					select(s, s.selected % #s.actions + 1)
				end),
			},
			{
				lhs = "<S-Tab>",
				action = scheduled(function()
					s.input = ""
					select(s, (s.selected - 2) % #s.actions + 1)
				end),
			},
			{ lhs = "<CR>", action = scheduled(function()
				apply(s)
			end) },
			{
				lhs = "<BS>",
				action = scheduled(function()
					s.input = s.input:sub(1, -2)
					ui.menu(s, config)
				end),
			},
			{ lhs = "<any>", action = scheduled(function(context)
				typed(s, context.input)
			end) },
		},
	})
	runtime:start()
	select(s, 1)
end

function M.open()
	if not config then
		M.setup()
	end
	M.close()
	if vim.api.nvim_get_mode().mode ~= "n" then
		return
	end
	local s = {
		bufnr = vim.api.nvim_get_current_buf(),
		winid = vim.api.nvim_get_current_win(),
		cursor = vim.api.nvim_win_get_cursor(0),
		changedtick = vim.api.nvim_buf_get_changedtick(0),
		filetype = vim.bo.filetype,
		actions = {},
		selected = 1,
		input = "",
		generation = 0,
		events = {},
	}
	current = s
	s.events[1] = vim.api.nvim_create_autocmd({ "CursorMoved", "TextChanged", "BufLeave", "WinLeave", "ModeChanged" }, {
		callback = function()
			vim.schedule(function()
				if current == s and not valid(s) then
					M.close()
				end
			end)
		end,
	})
	s.events[2] = vim.api.nvim_create_autocmd("VimResized", {
		callback = function()
			if valid(s) and #s.actions > 0 then
				select(s, s.selected)
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
			notify("No code actions available")
			return
		end
		if config.ranking.frequency then
			ranking.sort(entries, s.filetype)
		end
		s.actions, s.labels = entries, shortcut.labels(entries, config.shortcut.mode)
		enter(s)
	end)
end

function M.setup(opts)
	M.close()
	local next_config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
	assert(vim.fn.has("nvim-0.11") == 1, "sub-action requires Neovim 0.11+")
	assert(type(next_config.mapping) == "string" or next_config.mapping == false, "mapping must be a string or false")
	assert(vim.tbl_contains({ "prefix", "mnemonic", "off" }, next_config.shortcut.mode), "invalid shortcut mode")
	assert(vim.tbl_contains({ "name", "icon", "none" }, next_config.client.display), "invalid client display")
	assert(type(next_config.client.icons) == "table", "client.icons must be a table")
	assert(type(next_config.ranking.frequency) == "boolean", "ranking.frequency must be a boolean")
	assert(
		next_config.color == nil or (type(next_config.color) == "string" and next_config.color:match("^#%x%x%x%x%x%x$")),
		"color must be a #RRGGBB string"
	)
	for _, window in pairs(next_config.ui) do
		for _, dimension in ipairs({ "max_width", "max_height" }) do
			local value = window[dimension]
			assert(
				type(value) == "number" and value >= 1 and value == math.floor(value),
				dimension .. " must be a positive integer"
			)
		end
	end
	require("nvim-submode.runtime")
	if config and config.mapping and vim.fn.maparg(config.mapping, "n", false, true).callback == M.open then
		vim.keymap.del("n", config.mapping)
	end
	config = next_config
	if config.mapping then
		vim.keymap.set("n", config.mapping, M.open, { desc = "Code actions (sub-action)" })
	end
end

return M
