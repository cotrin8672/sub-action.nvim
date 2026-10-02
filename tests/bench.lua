-- Run with the same dependency paths as tests/run.lua. Times are microseconds.
-- SUB_ACTION_BENCH_PHASE=setup: fresh-process require + setup only.
-- SUB_ACTION_BENCH_LOADER=1: enable Neovim's native bytecode cache.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:prepend(vim.env.SUB_ACTION_SUBMODE or root .. "/.deps/nvim-submode")
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")
vim.env.XDG_STATE_HOME = temporary .. "/state"
local clock = vim.uv.hrtime
if vim.env.SUB_ACTION_BENCH_LOADER then
	vim.loader.enable()
end
local started = clock()
local plugin = require("sub_action")
local require_us = (clock() - started) / 1000
plugin.setup()
local setup_us = (clock() - started) / 1000
local dependencies = 0
for name in pairs(package.loaded) do
	if name:match("^sub_action%.") or name:match("^nvim%-submode") then
		dependencies = dependencies + 1
	end
end
local results = { setup_us = setup_us, require_us = require_us, setup_modules = dependencies }
if vim.env.SUB_ACTION_BENCH_PHASE ~= "setup" then
	if vim.env.SUB_ACTION_BLINK then
		vim.opt.runtimepath:prepend(vim.env.SUB_ACTION_BLINK)
		vim.opt.runtimepath:prepend(vim.env.SUB_ACTION_BLINK_LIB or root .. "/.deps/blink.lib")
		require("blink.cmp.config").set({})
	end
	local function measure(name, count, fn, warmup)
		for _ = 1, warmup or 20 do
			fn()
		end
		local samples = {}
		for i = 1, count do
			local before = clock()
			fn()
			samples[i] = (clock() - before) / 1000
		end
		table.sort(samples)
		results[name] = { median_us = samples[math.ceil(count / 2)], p95_us = samples[math.ceil(count * 0.95)] }
	end
	local function actions(count)
		local entries = {}
		for i = 1, count do
			entries[i] = { action = { title = "Import Type" .. i, kind = "quickfix" } }
		end
		return entries
	end
	local rank = require("sub_action.ranking")
	local path = vim.fn.stdpath("state") .. "/sub-action.json"
	local counts = { rust = {} }
	for i = 1, 10000 do
		counts.rust[vim.json.encode({ "quickfix", "Import Type" .. i })] = i % 17
	end
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
	vim.fn.writefile({ vim.json.encode(counts) }, path)
	local ranked = actions(1000)
	rank.sort(ranked, "rust")
	measure("rank_1000", 100, function()
		rank.sort(ranked, "rust")
	end)
	measure("rank_1000_fresh", 100, function()
		rank.sort(actions(1000), "rust")
	end)
	measure("record_10000_history", 30, function()
		rank.record(ranked[1].action, "rust")
	end)
	local shortcuts = require("sub_action.shortcut")
	local labelled = actions(1000)
	measure("shortcuts_1000", 30, function()
		shortcuts.labels(labelled, "prefix")
	end)
	vim.o.columns, vim.o.lines = 120, 40
	local api = vim.api
	local buf = api.nvim_get_current_buf()
	api.nvim_buf_set_name(buf, temporary .. "/source.rs")
	vim.bo[buf].filetype = "rust"
	local source = {}
	for i = 1, 4000 do
		source[i] = "let value" .. i .. " = " .. i .. ";"
	end
	api.nvim_buf_set_lines(buf, 0, -1, false, source)
	api.nvim_win_set_cursor(0, { 1, 10 })
	vim.cmd.redraw()
	local entries = actions(40)
	for i, entry in ipairs(entries) do
		entry.action.edit = {
			changes = {
				[vim.uri_from_bufnr(buf)] = {
					{
						range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
						newText = "// action " .. i .. "\n",
					},
				},
			},
		}
		entry.client = {
			name = "benchmark",
			offset_encoding = "utf-16",
			supports_method = function()
				return false
			end,
		}
	end
	local lsp = require("sub_action.lsp")
	-- Isolate local UI/input work from language-server and transport latency.
	lsp.request = function(_, callback)
		callback(vim.deepcopy(entries))
		return function() end
	end
	plugin.setup({ ranking = { frequency = false } })
	plugin.open()
	local window
	for _, win in ipairs(api.nvim_list_wins()) do
		if vim.bo[api.nvim_win_get_buf(win)].filetype == "sub-action" then
			window = win
		end
	end
	assert(window)
	local function key(keys)
		api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, false, true), "mtx", false)
	end
	local preview
	for _, win in ipairs(api.nvim_list_wins()) do
		if vim.bo[api.nvim_win_get_buf(win)].filetype == "diff" then
			preview = win
		end
	end
	assert(preview)
	local function with_preview(keys, delta)
		local selected = (api.nvim_win_get_cursor(window)[1] - 1 + delta) % #entries + 1
		key(keys)
		assert(vim.wait(1000, function()
			local lines = api.nvim_buf_get_lines(api.nvim_win_get_buf(preview), 0, -1, false)
			return api.nvim_win_get_cursor(window)[1] == selected and vim.tbl_contains(lines, "+// action " .. selected)
		end, 1))
	end
	measure("cold_tab_preview_40_actions_4000_lines", 39, function()
		with_preview("<Tab>", 1)
	end, 0)
	measure("tab_selection_40_actions_4000_lines", 200, function()
		local selected = api.nvim_win_get_cursor(window)[1]
		key("<Tab>")
		assert(vim.wait(1000, function()
			return api.nvim_win_get_cursor(window)[1] == selected % #entries + 1
		end, 1))
	end)
	measure("tab_preview_40_actions_4000_lines", 200, function()
		with_preview("<Tab>", 1)
	end)
	measure("shift_tab_preview_40_actions_4000_lines", 200, function()
		with_preview("<S-Tab>", -1)
	end)
	measure("shift_tab_selection_40_actions_4000_lines", 200, function()
		local selected = api.nvim_win_get_cursor(window)[1]
		key("<S-Tab>")
		assert(vim.wait(1000, function()
			return api.nvim_win_get_cursor(window)[1] == (selected - 2) % #entries + 1
		end, 1))
	end)
	plugin.close()
	entries = {
		{
			action = { title = "Command", command = "benchmark.local" },
			client = {
				name = "benchmark",
				offset_encoding = "utf-16",
				commands = {},
				supports_method = function()
					return false
				end,
				exec_cmd = function() end,
			},
		},
	}
	vim.lsp.commands["benchmark.local"] = function() end
	local samples = {}
	plugin.setup({ ranking = { frequency = true } })
	for i = 1, 30 do
		plugin.open()
		local before = clock()
		key("<CR>")
		assert(vim.wait(1000, function()
			return require("nvim-submode.session").current() == nil
		end, 1))
		samples[i] = (clock() - before) / 1000
	end
	table.sort(samples)
	results.confirm_local_command = { median_us = samples[15], p95_us = samples[29] }
end
io.stdout:write(vim.json.encode(results) .. "\n")
vim.cmd("qa!")
