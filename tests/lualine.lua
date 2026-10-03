-- Run with SUB_ACTION_LUALINE and SUB_ACTION_SUBMODE pointing to checkouts.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(vim.env.SUB_ACTION_SUBMODE or root .. "/.deps/nvim-submode")
vim.opt.rtp:append(vim.env.SUB_ACTION_LUALINE or root .. "/.deps/lualine.nvim")
local reply
package.loaded["sub_action.lsp"] = {
	request = function(_, callback)
		reply = callback
		return function() end
	end,
	resolve = function(entry, _, callback) callback(entry.action) end,
	preview = function() return {} end,
	apply = function(_, _, _, callback) callback() end,
}
local plugin, lualine = require("sub_action"), require("lualine")
local sm = require("nvim-submode")
local function label()
	return sm.get_submode_name() or "NORMAL"
end
local function frame(text, attr, active)
	local result = vim.api.nvim_eval_statusline(lualine.statusline(active ~= false), { maxwidth = 200, highlights = true })
	local start = assert(result.str:find(text, 1, true), result.str) - 1
	local highlight
	for _, item in ipairs(result.highlights) do
		if item.start <= start then highlight = item end
	end
	return vim.api.nvim_get_hl(0, { name = highlight.groups[#highlight.groups], link = false })[attr]
end
local function colors(active)
	return {
		frame(label(), "bg", active),
		frame("repository", "fg", active),
		frame("filetype", "fg", active),
		frame("location", "bg", active),
	}
end
local function key(keys)
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "mtx", false)
	vim.wait(30, function() return false end, 5)
end
local function equal(a, b)
	assert(vim.deep_equal(a, b), vim.inspect(a) .. " != " .. vim.inspect(b))
end
local sections = {
	lualine_a = { label },
	lualine_b = { function() return "repository" end },
	lualine_c = {}, lualine_x = {},
	lualine_y = { function() return "filetype" end },
	lualine_z = { function() return "location" end },
}
for _, theme in ipairs({
	"auto",
	function() return "gruvbox" end,
	{
		normal = { a = { fg = "#16181A", bg = "#5EA1FF" }, b = { fg = "#5EA1FF", bg = "#222222" }, c = { fg = "#FFFFFF", bg = "#16181A" } },
		inactive = { a = { fg = "#FFFFFF", bg = "#16181A" }, b = { fg = "#FFFFFF", bg = "#16181A" }, c = { fg = "#FFFFFF", bg = "#16181A" } },
	},
}) do
	lualine.setup({ options = { theme = theme, icons_enabled = false }, sections = sections, inactive_sections = sections })
	local normal, inactive = colors(), colors(false)
	local original = lualine.get_config()
	plugin.setup()
	plugin.open()
	equal(colors(), { 0xE3A875, 0xE3A875, 0xE3A875, 0xE3A875 })
	equal(colors(false), inactive)
	vim.api.nvim_exec_autocmds("ColorScheme", {})
	equal(colors(), { 0xE3A875, 0xE3A875, 0xE3A875, 0xE3A875 })
	key("<Esc>")
	equal(colors(), normal)
	equal(lualine.get_config(), original)
	plugin.open()
	reply({ { action = { title = "Apply action", command = "test" }, client = { name = "test", id = 1 } } })
	key("<CR>")
	equal(colors(), normal)
	equal(lualine.get_config(), original)
	plugin.setup({ color = false })
	plugin.open()
	equal(colors(), normal)
	plugin.close()
	equal(lualine.get_config(), original)
end
print("PASS: lualine accents during loading and selection, inactive colors, theme changes, cancellation, apply and disabled accents")
