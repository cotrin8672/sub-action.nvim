-- Run: nvim --headless -u NONE -l tests/run.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:prepend(vim.env.SUB_ACTION_SUBMODE or root .. "/.deps/nvim-submode")
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")
vim.env.XDG_STATE_HOME = temporary .. "/state"
package.loaded["blink.cmp.config"] = setmetatable({}, {
	__index = function()
		error("sub-action must not access Blink")
	end,
})

local function equal(actual, expected)
	assert(vim.deep_equal(actual, expected), vim.inspect(actual) .. " != " .. vim.inspect(expected))
end
local function wait(predicate)
	assert(vim.wait(2000, predicate, 5), "timed out")
end
local function key(keys)
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "mtx", false)
	vim.wait(30, function()
		return false
	end, 5)
end
local function floats()
	local result = {}
	for _, window in ipairs(vim.api.nvim_list_wins()) do
		local filetype = vim.bo[vim.api.nvim_win_get_buf(window)].filetype
		if filetype == "sub-action" then
			result.menu = window
		end
		if filetype == "diff" then
			result.preview = window
		end
	end
	return result
end
local function text(window)
	return table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(window), 0, -1, false), "\n")
end
local function entries(titles)
	return vim.tbl_map(function(title)
		return { action = { title = title } }
	end, titles)
end

local checks = 0
local function check(name, fn)
	fn()
	checks = checks + 1
	io.stdout:write("ok " .. checks .. " - " .. name .. "\n")
end

local function run()
	check("setup preserves mappings and loads no session, UI, ranking, or submode modules", function()
		local plugin = require("sub_action")
		local mapping = function() end
		vim.keymap.set("n", "gra", mapping)
		plugin.setup()
		plugin.close()
		equal(vim.fn.maparg("gra", "n", false, true).callback, mapping)
		for name in pairs(package.loaded) do
			assert(not name:match("^sub_action%.") and not name:match("^nvim%-submode"), name .. " loaded during setup")
		end
	end)
	check("open uses defaults without setup and only accepts a local shortcut override", function()
		local plugin = package.loaded["sub_action"]
		package.loaded["sub_action"] = nil
		local fresh = require("sub_action")
		local captured
		package.loaded["sub_action.session"] = {
			open = function(config)
				captured = config
			end,
		}
		fresh.setup = function()
			error("open must not call setup")
		end
		fresh.open()
		equal(captured.ranking.frequency, false)
		equal(captured.color, "#E3A875")
		equal(captured.keymap["<Esc>"], "close")
		equal(captured.keymap["<C-c>"], nil)
		fresh.open({ shortcut = { mode = "off" } })
		equal(captured.shortcut.mode, "off")
		equal(captured.color, "#E3A875")
		fresh.open()
		equal(captured.shortcut.mode, "prefix")
		for _, options in ipairs({
			{ color = "#123456" },
			{ ranking = { frequency = true } },
			{ shortcut = { mode = "typo" } },
		}) do
			assert(not pcall(fresh.open, options))
		end
		package.loaded["sub_action.session"] = nil
		package.loaded["sub_action"] = plugin
	end)
	check("unknown options, wrong types, and invalid or conflicting mappings fail during setup", function()
		local plugin = require("sub_action")
		for _, options in ipairs({
			false,
			{ mapping = "gra" },
			{ shorcut = {} },
			{ shortcut = { mode = "typo" } },
			{ shortcut = { typo = true } },
			{ ranking = { frequency = "yes" } },
			{ preview = true },
			{ preview = {} },
			{ ui = { action = { padding = 2 } } },
			{ ui = { action = { max_height = 0 } } },
			{ ui = { preview = { scrollbar = 0 } } },
			{ ui = { action = { winblend = 101 } } },
			{ ui = { action = { winblend = true } } },
			{ ui = { preview = { winblend = "10" } } },
			{ ui = { action = { border = true } } },
			{ ui = { preview = { border = {} } } },
			{ ui = { action = { border = { "wide" } } } },
			{ client = { icons = { rust_analyzer = false } } },
			{ keymap = { ["<Tab>"] = "typo" } },
			{ keymap = { ["<Esc>"] = "next" } },
			{ keymap = { ["<Esc>"] = false } },
			{ keymap = { ["<C-i>"] = "next" } },
			{ keymap = { ["<any>"] = "apply" } },
		}) do
			assert(not pcall(plugin.setup, options), "accepted invalid options: " .. vim.inspect(options))
		end
	end)
	local shortcuts = require("sub_action.shortcut")
	check("shortcuts and collisions", function()
		local actions = entries({ "Import Foo", "Import Bar", "Implement members" })
		equal(shortcuts.labels(actions, "prefix"), { "if", "ib", "im" })
		equal(shortcuts.labels(actions, "mnemonic"), { "i", "b", "m" })
		equal(shortcuts.labels(actions, "off"), { "", "", "" })
		equal({ shortcuts.match({ "if", "ib", "im" }, "i") }, { 1, 3 })
		equal({ shortcuts.match({ "if", "ib", "im" }, "ib") }, { 2, 1 })
		local labels =
			shortcuts.labels(entries({ "Import Foo", "Import Foo", "I", "I1", "日本語", "a1", "a" }), "prefix")
		equal(#labels, 7)
		for i, label in ipairs(labels) do
			assert(#label > 0)
			for j, other in ipairs(labels) do
				if i ~= j then
					assert(other:sub(1, #label) ~= label)
				end
			end
		end
		local many = {}
		for _ = 1, 40 do
			many[#many + 1] = "Same"
		end
		equal(#shortcuts.labels(entries(many), "mnemonic"), 40)
	end)

	local source = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_name(source, temporary .. "/main.rs")
	vim.bo[source].filetype = "rust"
	local original = { "fn main() {", "    let foo = Foo::new();", "}" }
	vim.api.nvim_buf_set_lines(source, 0, -1, false, original)
	vim.api.nvim_win_set_cursor(0, { 2, 14 })
	vim.cmd.redraw()
	local uri = vim.uri_from_bufnr(source)
	local edit = {
		changes = {
			[uri] = {
				{
					range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
					newText = "use crate::Foo;\n",
				},
			},
		},
	}
	local bridge = require("sub_action.lsp")
	check("preview uses unsaved text and keeps edits and source intact", function()
		local copy = vim.deepcopy(edit)
		local before = vim.api.nvim_list_bufs()
		local lines = bridge.preview(edit, "utf-16")
		assert(table.concat(lines, "\n"):find("+use crate::Foo;", 1, true))
		equal(vim.api.nvim_buf_get_lines(source, 0, -1, false), original)
		equal(edit, copy)
		equal(vim.api.nvim_list_bufs(), before)
		equal(bridge.preview(nil, "utf-16"), { "Preview unavailable" })
		local annotated = {
			changes = {},
			documentChanges = {
				{
					textDocument = { uri = uri, version = 1 },
					edits = { vim.tbl_extend("force", copy.changes[uri][1], { annotationId = "confirm" }) },
				},
			},
			changeAnnotations = { confirm = { label = "Change", needsConfirmation = true } },
		}
		assert(table.concat(bridge.preview(annotated, "utf-16"), "\n"):find("+use crate::Foo;", 1, true))
		assert(annotated.documentChanges[1].edits[1].annotationId == "confirm")
		local operations = {
			documentChanges = {
				{ kind = "create", uri = vim.uri_from_fname(temporary .. "/new.rs") },
				{
					textDocument = { uri = vim.uri_from_fname(temporary .. "/new.rs") },
					edits = {
						{
							range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
							newText = "new content",
						},
					},
				},
				{ kind = "rename", oldUri = uri, newUri = vim.uri_from_fname(temporary .. "/renamed.rs") },
				{ kind = "delete", uri = uri },
			},
		}
		local preview = table.concat(bridge.preview(operations, "utf-16"), "\n")
		assert(preview:find("Create", 1, true) and preview:find("Rename", 1, true) and preview:find("Delete", 1, true))
		assert(vim.fn.filereadable(temporary .. "/new.rs") == 0)
		local unicode = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(unicode, temporary .. "/unicode.rs")
		vim.api.nvim_buf_set_lines(unicode, 0, -1, false, { "😀x" })
		local unicode_edit = {
			changes = {
				[vim.uri_from_bufnr(unicode)] = {
					{
						range = { start = { line = 0, character = 2 }, ["end"] = { line = 0, character = 3 } },
						newText = "y",
					},
				},
			},
		}
		assert(table.concat(bridge.preview(unicode_edit, "utf-16"), "\n"):find("+😀y", 1, true))
		vim.api.nvim_buf_delete(unicode, { force = true })
	end)

	local servers = {}
	local function server(name, encoding)
		local state = { actions = {}, requests = {}, commands = {}, resolvers = {}, cancelled = {}, sequence = 0 }
		servers[#servers + 1] = state
		state.id = vim.lsp.start({
			name = name,
			cmd = function(dispatchers)
				local closing = false
				return {
					request = function(method, params, callback)
						state.sequence = state.sequence + 1
						state.requests[#state.requests + 1] = { method = method, params = vim.deepcopy(params) }
						local id = state.sequence
						if method == "codeAction/resolve" and params.data == "defer" then
							state.resolvers[#state.resolvers + 1] = callback
						else
							vim.schedule(function()
								if method == "initialize" then
									callback(nil, {
										capabilities = {
											codeActionProvider = { resolveProvider = true },
											positionEncoding = encoding,
											executeCommandProvider = { commands = { "test.command" } },
										},
									})
								elseif method == "textDocument/codeAction" then
									callback(nil, vim.deepcopy(state.actions))
								elseif method == "codeAction/resolve" then
									callback(nil, params)
								elseif method == "workspace/executeCommand" then
									state.commands[#state.commands + 1] = params
									callback(state.command_error)
								elseif method == "shutdown" then
									callback(nil, nil)
								else
									callback(nil, nil)
								end
							end)
						end
						return true, id
					end,
					notify = function(method, params)
						if method == "$/cancelRequest" then
							state.cancelled[#state.cancelled + 1] = params.id
						end
						return true
					end,
					is_closing = function()
						return closing
					end,
					terminate = function()
						closing = true
						dispatchers.on_exit(0, 0)
					end,
				}
			end,
		})
		wait(function()
			return vim.lsp.get_client_by_id(state.id).initialized
		end)
		return state
	end
	local one, two = server("rust_analyzer", "utf-16"), server("other", "utf-8")
	local plugin = require("sub_action")
	local tab_count = 0
	vim.keymap.set("n", "<Tab>", function()
		tab_count = tab_count + 1
	end)
	local tab_mapping = vim.fn.maparg("<Tab>", "n", false, true)
	local function setup(options)
		plugin.setup(options)
	end
	local function open(options)
		vim.cmd.redraw()
		plugin.open(options)
		wait(function()
			return floats().menu ~= nil
		end)
		equal(vim.api.nvim_get_current_buf(), source)
	end
	local function command(title)
		return { title = title, command = "test.command", arguments = { title } }
	end
	setup()
	one.actions = {
		{ title = "Import Foo", edit = edit, kind = "quickfix" },
		command("Import Bar"),
		command("Implement members"),
	}
	two.actions = { command("Import Foo") }

	check("multiple clients, non-focusable Blink-shaped floats, Tab and Escape", function()
		local origin = vim.api.nvim_get_current_win()
		local border, blend, local_blend = vim.o.winborder, vim.go.winblend, vim.wo[origin].winblend
		vim.o.winborder, vim.go.winblend = "rounded", 17
		vim.api.nvim_set_option_value("winblend", 3, { scope = "local", win = origin })
		open()
		local windows = floats()
		equal(require("nvim-submode").get_submode_color(), "#E3A875")
		assert(text(windows.menu):find("rust_analyzer", 1, true) and text(windows.menu):find("other", 1, true))
		local marks = vim.api.nvim_buf_get_extmarks(
			vim.api.nvim_win_get_buf(windows.menu),
			vim.api.nvim_create_namespace("sub-action"),
			0,
			-1,
			{ details = true }
		)
		assert(vim.iter(marks):any(function(mark)
			return mark[4].hl_group == "SubActionClient"
		end))
		equal(vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(windows.menu)), 4)
		equal(vim.api.nvim_get_current_win(), origin)
		assert(not vim.api.nvim_win_get_config(windows.menu).focusable)
		assert(not vim.api.nvim_win_get_config(windows.preview).focusable)
		local rounded = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" }
		equal(vim.api.nvim_win_get_config(windows.menu).border, rounded)
		equal(vim.api.nvim_win_get_config(windows.preview).border, rounded)
		vim.api.nvim_exec_autocmds("CursorMoved", {})
		vim.api.nvim_exec_autocmds("TextChanged", { buffer = source })
		vim.wait(20, function()
			return false
		end)
		equal(floats().menu, windows.menu)
		local selection = vim.wo[windows.menu].winhighlight:match("CursorLine:([^,]+)")
		local original_selection = vim.api.nvim_get_hl(0, { name = selection, link = false })
		vim.api.nvim_set_hl(0, selection, { bg = 0x123456 })
		vim.api.nvim_exec_autocmds("ColorScheme", {})
		equal(vim.api.nvim_get_hl(0, { name = "SubActionSelection", link = false }).bg, 0x123456)
		vim.api.nvim_set_hl(0, selection, original_selection)
		vim.api.nvim_exec_autocmds("ColorScheme", {})
		equal(vim.wo[windows.menu].winblend, 17)
		equal(vim.wo[windows.preview].winblend, 17)
		assert(not package.loaded["blink.cmp.lib.window"] and not package.loaded["blink.lib"])
		key("<Tab>")
		equal(vim.api.nvim_win_get_cursor(windows.menu)[1], 2)
		equal(tab_count, 0)
		equal(text(windows.preview), "Preview unavailable")
		key("<S-Tab>")
		equal(vim.api.nvim_win_get_cursor(windows.menu)[1], 1)
		key("<Esc>")
		equal(floats(), {})
		equal(require("nvim-submode").get_submode_color(), nil)
		equal(vim.fn.maparg("<Tab>", "n", false, true).callback, tab_mapping.callback)
		key("<Tab>")
		equal(tab_count, 1)
		vim.o.winborder, vim.go.winblend, vim.wo[origin].winblend = border, blend, local_blend
	end)

	check("titles replace shortcut columns, typed letters highlight in place, and single clients are hidden", function()
		local previous, other = one.actions, two.actions
		one.actions, two.actions = { command("Import Foo Red"), command("Import Foo Rose"), command("Import Bar") }, {}
		open()
		local buffer = vim.api.nvim_win_get_buf(floats().menu)
		local namespace = vim.api.nvim_create_namespace("sub-action.input")
		local function positions()
			return vim.tbl_map(function(mark)
				return { mark[2], mark[3] }
			end, vim.api.nvim_buf_get_extmarks(buffer, namespace, 0, -1, {}))
		end
		assert(text(floats().menu):match("^ Import Foo Red") and not text(floats().menu):find("rust_analyzer", 1, true))
		key("i")
		equal(positions(), { { 0, 1 }, { 1, 1 }, { 2, 1 } })
		key("f")
		equal(positions(), { { 0, 1 }, { 0, 8 }, { 1, 1 }, { 1, 8 } })
		key("<BS>")
		equal(positions(), { { 0, 1 }, { 1, 1 }, { 2, 1 } })
		key("<Tab>")
		equal(positions(), {})
		key("<Esc>")
		setup({ client = { display = "name" } })
		open()
		assert(text(floats().menu):find("rust_analyzer", 1, true))
		key("<Esc>")
		one.actions, two.actions = previous, other
		setup()
	end)

	check("window overrides win over globals, and inherited values update on the next open", function()
		local border, blend = vim.o.winborder, vim.go.winblend
		vim.o.winborder, vim.go.winblend = "rounded", 35
		setup({ ui = { action = { border = "none", winblend = 0 } } })
		open()
		local windows = floats()
		local menu_border = vim.api.nvim_win_get_config(windows.menu).border
		assert(menu_border == nil or menu_border == "none")
		equal(
			vim.api.nvim_win_get_config(windows.preview).border,
			{ "╭", "─", "╮", "│", "╯", "─", "╰", "│" }
		)
		equal(vim.wo[windows.menu].winblend, 0)
		equal(vim.wo[windows.preview].winblend, 35)
		equal(vim.go.winblend, 35)
		plugin.close()
		setup()
		vim.o.winborder, vim.go.winblend = "double", 45
		open()
		for _, window in pairs(floats()) do
			equal(
				vim.api.nvim_win_get_config(window).border,
				{ "╔", "═", "╗", "║", "╝", "═", "╚", "║" }
			)
			equal(vim.wo[window].winblend, 45)
		end
		plugin.close()
		vim.o.winborder, vim.go.winblend = border, blend
	end)

	check("native scrollbars follow selection, reuse windows, and close with their parent", function()
		local previous = one.actions
		one.actions, two.actions = {}, {}
		for i = 1, 12 do
			one.actions[i] = command("Action " .. i)
		end
		one.actions[1].edit = edit
		setup({ ui = { action = { max_height = 3 }, preview = { max_height = 2 } } })
		open()
		local windows = floats()
		local menu_border = vim.api.nvim_win_get_config(windows.menu).border
		assert(menu_border == nil or menu_border == "none")
		equal(vim.api.nvim_win_get_config(windows.preview).border, { " ", "", "", " ", "", "", " ", " " })
		local function bar(parent)
			for _, window in ipairs(vim.api.nvim_list_wins()) do
				local c = vim.api.nvim_win_get_config(window)
				if c.relative == "win" and c.win == parent then
					assert(not c.focusable)
					assert(vim.wo[window].winhighlight:find("BlinkCmpScrollBar", 1, true))
					return window
				end
			end
		end
		local menu_bar, preview_bar = bar(windows.menu), bar(windows.preview)
		assert(menu_bar and preview_bar)
		local buffer = vim.api.nvim_win_get_buf(menu_bar)
		local namespace = vim.api.nvim_create_namespace("sub-action")
		local function thumb_row()
			return vim.api.nvim_buf_get_extmarks(buffer, namespace, 0, -1, {})[1][2]
		end
		equal(thumb_row(), 0)
		key("<S-Tab>")
		equal(vim.api.nvim_win_get_cursor(windows.menu)[1], 12)
		equal(bar(windows.menu), menu_bar)
		equal(thumb_row(), 2)
		assert(not vim.api.nvim_win_is_valid(preview_bar))
		plugin.close()
		assert(not vim.api.nvim_win_is_valid(menu_bar) and not vim.api.nvim_buf_is_valid(buffer))
		one.actions = previous
		setup()
	end)

	check("prefix remains ambiguous, Backspace resets, unique input executes", function()
		two.actions = {}
		open()
		key("i")
		assert(floats().menu)
		equal(#one.commands, 0)
		key("<BS>")
		key("ib")
		wait(function()
			return #one.commands == 1
		end)
		equal(one.commands[1].arguments, { "Import Bar" })
		equal(floats(), {})
		key("<Tab>")
		equal(tab_count, 2)
	end)

	check("Enter applies edits and mnemonic/off modes work", function()
		open()
		key("<CR>")
		wait(function()
			return vim.api.nvim_buf_get_lines(source, 0, 1, false)[1] == "use crate::Foo;"
		end)
		equal(floats(), {})
		vim.api.nvim_buf_set_lines(source, 0, -1, false, original)
		setup({ shortcut = { mode = "mnemonic" } })
		open()
		key("b")
		wait(function()
			return #one.commands == 2
		end)
		setup({ shortcut = { mode = "off" } })
		open()
		key("i")
		assert(floats().menu)
		key("<Tab><CR>")
		wait(function()
			return #one.commands == 3
		end)
		equal(floats(), {})
	end)
	check(
		"submode mappings are configurable, disabled keys stay inactive, and shortcut overrides do not persist",
		function()
			local previous, commands = one.actions, #one.commands
			one.actions = { command("Alpha"), command("Beta"), command("Gamma") }
			setup({
				color = false,
				keymap = {
					["<Tab>"] = false,
					["<S-Tab>"] = false,
					["<CR>"] = false,
					["<BS>"] = false,
					["<C-n>"] = "next",
					["<C-p>"] = "prev",
					["<C-y>"] = "apply",
					q = "close",
				},
			})
			open({ shortcut = { mode = "off" } })
			local window = floats().menu
			assert(text(window):match("^%s+Alpha"))
			equal(require("nvim-submode").get_submode_color(), nil)
			assert(not pcall(plugin.setup, { keymap = { ["<Tab>"] = "typo" } }))
			equal(floats().menu, window)
			key("<Tab><S-Tab><CR><C-c>")
			equal(vim.api.nvim_win_get_cursor(window)[1], 1)
			equal(#one.commands, commands)
			key("<C-n>")
			equal(vim.api.nvim_win_get_cursor(window)[1], 2)
			key("<C-p>")
			equal(vim.api.nvim_win_get_cursor(window)[1], 1)
			key("<C-n><C-y>")
			wait(function()
				return #one.commands == commands + 1
			end)
			equal(one.commands[#one.commands].arguments, { "Beta" })
			open()
			assert(text(floats().menu):match("^%s+Alpha"))
			key("q")
			equal(floats(), {})
			setup({ keymap = { ["<Esc>"] = "close" } })
			open()
			key("<C-c>")
			assert(floats().menu)
			key("<Esc>")
			equal(floats(), {})
			assert(not package.loaded["sub_action.ranking"])
			equal(vim.fn.filereadable(vim.fn.stdpath("state") .. "/sub-action.json"), 0)
			one.actions = previous
		end
	)

	check("lazy resolve is cached; stale responses and cancellation are harmless", function()
		setup()
		one.actions = { { title = "Delayed", data = "defer" }, command("Command") }
		open()
		wait(function()
			return #one.resolvers == 1
		end)
		key("<Tab>")
		local window = floats().preview
		equal(text(window), "Preview unavailable")
		one.resolvers[1](nil, { title = "Delayed", edit = edit })
		vim.wait(30, function()
			return false
		end)
		equal(text(window), "Preview unavailable")
		key("<S-Tab>")
		assert(text(window):find("+use crate::Foo;", 1, true))
		equal(#one.resolvers, 1)
		key("<Esc>")
		open()
		wait(function()
			return #one.resolvers == 2
		end)
		key("<CR>")
		equal(floats(), {})
		local tabs = tab_count
		key("<Tab>")
		equal(tab_count, tabs + 1)
		one.resolvers[2](nil, { title = "Delayed", edit = edit })
		wait(function()
			return vim.api.nvim_buf_get_lines(source, 0, 1, false)[1] == "use crate::Foo;"
		end)
		vim.api.nvim_buf_set_lines(source, 0, -1, false, original)
		open()
		wait(function()
			return #one.resolvers == 3
		end)
		key("<Esc>")
		open()
		wait(function()
			return #one.resolvers == 4
		end)
		local notify, messages = vim.notify, {}
		vim.notify = function(message)
			messages[#messages + 1] = message
		end
		key("<CR>iCHANGED<Esc>")
		local changed = vim.api.nvim_buf_get_lines(source, 0, -1, false)
		one.resolvers[4](nil, { title = "Delayed", edit = edit })
		wait(function()
			return #messages > 0
		end)
		equal(vim.api.nvim_buf_get_lines(source, 0, -1, false), changed)
		vim.notify = notify
		vim.api.nvim_buf_set_lines(source, 0, -1, false, original)
		one.resolvers[3](nil, { title = "Delayed", edit = edit })
		vim.wait(30, function()
			return false
		end)
		equal(floats(), {})
		equal(vim.api.nvim_buf_get_lines(source, 0, -1, false), original)
		assert(#one.cancelled > 0)
	end)

	check("batched keys keep their order, reuse the menu/diff, and release input immediately", function()
		setup({ shortcut = { mode = "off" } })
		one.actions = { { title = "Edit", edit = edit }, command("Command"), command("Other") }
		local ui, menu_calls, preview_calls = require("sub_action.ui"), 0, 0
		local menu, preview = ui.menu, bridge.preview
		ui.menu = function(...)
			menu_calls = menu_calls + 1
			return menu(...)
		end
		bridge.preview = function(...)
			preview_calls = preview_calls + 1
			return preview(...)
		end
		open()
		local window = floats().menu
		local tick = vim.api.nvim_buf_get_changedtick(vim.api.nvim_win_get_buf(window))
		key("<Tab><S-Tab>")
		equal(preview_calls, 1)
		equal(menu_calls, 1)
		equal(vim.api.nvim_buf_get_changedtick(vim.api.nvim_win_get_buf(window)), tick)
		key(string.rep("<Tab>", 101) .. string.rep("<S-Tab>", 100))
		equal(vim.api.nvim_win_get_cursor(window)[1], 2)
		equal(menu_calls, 1)
		local commands, tabs = #one.commands, tab_count
		key("<CR><Tab>")
		equal(tab_count, tabs + 1)
		wait(function()
			return #one.commands == commands + 1
		end)
		equal(one.commands[#one.commands].arguments, { "Command" })
		ui.menu, bridge.preview = menu, preview
		vim.lsp.commands["test.ready"] = function() end
		one.actions = { { title = "Ready edit", edit = edit, command = { command = "test.ready" } } }
		open()
		-- No sleeps between confirming, entering Insert mode, typing, and Escape.
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>iXYZ<Esc>", true, false, true), "mtx", false)
		equal(vim.api.nvim_buf_get_lines(source, 0, 1, false), { "use crate::Foo;" })
		assert(table.concat(vim.api.nvim_buf_get_lines(source, 0, -1, false), "\n"):find("XYZ", 1, true))
		equal(floats(), {})
		vim.lsp.commands["test.ready"] = nil
		vim.api.nvim_buf_set_lines(source, 0, -1, false, original)
		setup({ shortcut = { mode = "mnemonic" } })
		one.actions = { command("Unique") }
		open()
		tabs = tab_count
		key("u<Tab>")
		equal(tab_count, tabs + 1)
	end)

	check("preview callbacks receive resolved actions, cache results, fall back, and isolate errors", function()
		local previous, commands, resolves = one.actions, #one.commands, #one.resolvers
		local calls, native_calls = 0, 0
		local native = bridge.preview
		bridge.preview = function(...)
			native_calls = native_calls + 1
			return native(...)
		end
		one.actions = { { title = "External", data = "defer" }, { title = "Native", edit = edit }, command("Error") }
		setup({
			preview = function(action, context)
				calls = calls + 1
				equal(context.bufnr, source)
				equal(context.client.id, one.id)
				if action.title == "External" then
					equal(action.data, "resolved payload")
					return { "+ external preview" }
				elseif action.title == "Error" then
					error("expected preview failure")
				end
			end,
		})
		open()
		wait(function()
			return #one.resolvers == resolves + 1
		end)
		equal(calls, 0)
		one.resolvers[resolves + 1](nil, {
			title = "External",
			data = "resolved payload",
			command = { command = "test.command", arguments = { "original" } },
		})
		wait(function()
			return text(floats().preview) == "+ external preview"
		end)
		equal(#one.commands, commands)
		equal(vim.api.nvim_buf_get_lines(source, 0, -1, false), original)
		key("<Tab>")
		assert(text(floats().preview):find("+use crate::Foo;", 1, true))
		equal(native_calls, 1)
		key("<Tab>")
		assert(text(floats().preview):find("expected preview failure", 1, true))
		key("<Tab>")
		equal(text(floats().preview), "+ external preview")
		equal(calls, 3)
		key("<CR>")
		wait(function()
			return #one.commands == commands + 1
		end)
		equal(one.commands[#one.commands].arguments, { "original" })
		equal(#one.resolvers, resolves + 1)
		bridge.preview, one.actions = native, previous
		setup()
	end)

	check("frequency persists per filetype and ties keep server order", function()
		local ranking = require("sub_action.ranking")
		local actions = entries({ "A", "B", "C" })
		ranking.sort(actions, "rust")
		equal(
			vim.tbl_map(function(entry)
				return entry.action.title
			end, actions),
			{ "A", "B", "C" }
		)
		ranking.record(actions[2].action, "rust")
		local path = vim.fn.stdpath("state") .. "/sub-action.json"
		assert(vim.fn.filereadable(path) == 0, "record wrote synchronously")
		ranking.flush()
		ranking.record(actions[2].action, "rust")
		ranking.flush(true)
		local persisted = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
		equal(persisted.rust[vim.json.encode({ "", "B" })], 2)
		package.loaded["sub_action.ranking"] = nil
		ranking = require("sub_action.ranking")
		ranking.sort(actions, "rust")
		equal(
			vim.tbl_map(function(entry)
				return entry.action.title
			end, actions),
			{ "B", "A", "C" }
		)
		local other = entries({ "A", "B", "C" })
		ranking.sort(other, "lua")
		equal(
			vim.tbl_map(function(entry)
				return entry.action.title
			end, other),
			{ "A", "B", "C" }
		)
	end)

	check("client-side commands count once; failed and disabled actions do not count", function()
		local called, messages = 0, {}
		local notify = vim.notify
		vim.notify = function(message)
			messages[#messages + 1] = message
		end
		vim.lsp.commands["test.local"] = function(_, context)
			equal(context.bufnr, source)
			called = called + 1
		end
		setup({ ranking = { frequency = true } })
		one.actions = { { title = "Local command", command = "test.local" } }
		open()
		key("<CR>")
		equal(called, 1)
		require("sub_action.ranking").flush(true)
		local path = vim.fn.stdpath("state") .. "/sub-action.json"
		local state = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
		equal(state.rust[vim.json.encode({ "", "Local command" })], 1)
		one.actions = { command("Failed command") }
		one.command_error = { message = "expected failure" }
		open()
		key("<CR>")
		wait(function()
			return #messages > 0
		end)
		one.command_error = nil
		one.actions = { { title = "Disabled", disabled = { reason = "expected disabled" }, edit = edit } }
		open()
		key("<CR>")
		require("sub_action.ranking").flush(true)
		equal(vim.json.decode(table.concat(vim.fn.readfile(path), "\n")), state)
		equal(vim.api.nvim_buf_get_lines(source, 0, -1, false), original)
		vim.notify = notify
		vim.lsp.commands["test.local"] = nil
		setup()
	end)

	check("deferred saves, failed renames, exit flush, and damaged files preserve counts", function()
		local ranking = require("sub_action.ranking")
		local path = vim.fn.stdpath("state") .. "/sub-action.json"
		local function state()
			return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
		end
		local before = state()
		ranking.record({ title = "Deferred" }, "lua")
		equal(state(), before)
		wait(function()
			return state().lua ~= nil
		end)
		equal(state().lua[vim.json.encode({ "", "Deferred" })], 1)
		local rename, notify, messages = vim.uv.fs_rename, vim.notify, {}
		vim.notify = function(message)
			messages[#messages + 1] = message
		end
		vim.uv.fs_rename = function(_, _, callback)
			callback("expected rename failure")
		end
		before = state()
		ranking.record({ title = "Retry" }, "lua")
		ranking.flush()
		wait(function()
			return #messages > 0
		end)
		equal(state(), before)
		vim.uv.fs_rename = rename
		vim.api.nvim_exec_autocmds("VimLeavePre", {})
		equal(state().lua[vim.json.encode({ "", "Retry" })], 1)
		for _, invalid in ipairs({ "damaged JSON", '{"lua":{"invalid":-1}}' }) do
			vim.fn.writefile({ invalid }, path)
			package.loaded["sub_action.ranking"] = nil
			ranking = require("sub_action.ranking")
			ranking.record({ title = "Keep damaged file" }, "lua")
			ranking.flush(true)
			equal(vim.fn.readfile(path), { invalid })
		end
		vim.notify = notify
	end)

	check("movement and source edits close the session", function()
		one.actions = { command("Action") }
		open()
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		vim.api.nvim_exec_autocmds("CursorMoved", {})
		wait(function()
			return floats().menu == nil
		end)
		open()
		vim.api.nvim_buf_set_lines(source, 0, -1, false, { "changed" })
		vim.api.nvim_exec_autocmds("TextChanged", {})
		wait(function()
			return floats().menu == nil
		end)
	end)

	check("screen edges stay bounded and use the left preview", function()
		vim.o.columns, vim.o.lines = 100, 24
		vim.api.nvim_buf_set_lines(source, 0, -1, false, vim.fn["repeat"]({ string.rep("x", 99) }, 22))
		vim.wo.wrap = false
		vim.api.nvim_win_set_cursor(0, { 21, 90 })
		vim.cmd("normal! ze")
		setup({ ui = { action = { border = "rounded", max_width = 30 }, preview = { border = "rounded" } } })
		open()
		local windows = floats()
		local menu = vim.api.nvim_win_get_config(windows.menu)
		local preview = vim.api.nvim_win_get_config(windows.preview)
		assert(
			preview.col < menu.col,
			vim.inspect({ menu = menu, preview = preview, position = vim.fn.screenpos(0, 21, 91) })
		)
		for _, window in pairs(windows) do
			local c = vim.api.nvim_win_get_config(window)
			assert(c.col >= 0 and c.col + c.width + 2 <= vim.o.columns)
			assert(c.row >= 0 and c.row + c.height + 2 <= vim.o.lines - vim.o.cmdheight - 1)
		end
		plugin.close()
		vim.o.columns, vim.o.lines = 20, 12
		one.actions = { command(string.rep("😀日é", 16)) }
		setup({ client = { display = "none" }, ui = { action = { border = "rounded" } } })
		open()
		local c = vim.api.nvim_win_get_config(floats().menu)
		assert(c.width + 2 <= vim.o.columns)
		local line = text(floats().menu)
		assert(line:find("é", 1, true) and line:find("…", 1, true))
		assert(vim.fn.strdisplaywidth(line) <= c.width)
		plugin.close()
	end)
	for _, state in ipairs(servers) do
		vim.lsp.get_client_by_id(state.id):stop(true)
	end
	check("no clients or empty results leave no session behind", function()
		wait(function()
			return #vim.lsp.get_clients({ bufnr = source }) == 0
		end)
		plugin.open()
		equal(floats(), {})
		equal(require("nvim-submode.session").current(), nil)
	end)
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
	io.stderr:write(err .. "\n")
	vim.cmd("cquit 1")
end
io.stdout:write("Passed " .. checks .. " checks\n")
vim.cmd("qa!")
