local M = {}
local defaults = {
	mapping = "gra",
	shortcut = { mode = "prefix" },
	ui = { action = { max_width = 50, max_height = 8 }, preview = { max_width = 70, max_height = 15 } },
	ranking = { frequency = true },
	client = { display = "name", icons = {} },
}
local config

function M.close()
	local session = package.loaded["sub_action.session"]
	if session then
		session.close()
	end
end

function M.open()
	if not config then
		M.setup()
	end
	require("sub_action.session").open(config)
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
	if config and config.mapping and vim.fn.maparg(config.mapping, "n", false, true).callback == M.open then
		vim.keymap.del("n", config.mapping)
	end
	config = next_config
	if config.mapping then
		vim.keymap.set("n", config.mapping, M.open, { desc = "Code actions (sub-action)" })
	end
end

return M
