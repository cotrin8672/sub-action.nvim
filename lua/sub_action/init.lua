local M = {}
local defaults = {
	color = "#E3A875",
	shortcut = { mode = "prefix" },
	keymap = {
		["<Tab>"] = "next",
		["<S-Tab>"] = "prev",
		["<CR>"] = "apply",
		["<BS>"] = "backspace",
		["<Esc>"] = "close",
	},
	ui = {
		action = {
			max_width = 50,
			max_height = 8,
			scrollbar = true,
			winhighlight = "Normal:BlinkCmpMenu,FloatBorder:BlinkCmpMenuBorder,CursorLine:BlinkCmpMenuSelection,Search:None,CurSearch:None",
		},
		preview = {
			max_width = 70,
			max_height = 15,
			scrollbar = true,
			winhighlight = "Normal:BlinkCmpDoc,FloatBorder:BlinkCmpDocBorder,EndOfBuffer:BlinkCmpDoc",
		},
	},
	ranking = { frequency = false },
	client = { display = "name", icons = {} },
}
local config

local function check_options(opts, template, path)
	assert(type(opts) == "table", path .. " must be a table")
	for name, value in pairs(opts) do
		local default = template[name]
		if default == nil and template.max_width then
			default = name == "border" and "" or name == "winblend" and 0 or nil
		end
		local field = path .. "." .. tostring(name)
		assert(default ~= nil, "unknown option: " .. field)
		local kind = type(value)
		assert(
			kind == type(default) or (name == "border" and kind == "table") or (name == "color" and value == false),
			field .. " has an invalid type"
		)
		if kind == "table" and name ~= "keymap" and name ~= "icons" and name ~= "border" then
			check_options(value, default, field)
		end
	end
end

local function check_shortcut(shortcut)
	local mode = shortcut.mode
	assert(mode == "prefix" or mode == "mnemonic" or mode == "off", "invalid shortcut.mode")
end

function M.close()
	local session = package.loaded["sub_action.session"]
	if session then
		session.close()
	end
end

function M.open(opts)
	assert(vim.fn.has("nvim-0.11") == 1, "sub-action requires Neovim 0.11+")
	local options = config or defaults
	if opts ~= nil then
		check_options(opts, { shortcut = defaults.shortcut }, "open")
		if opts.shortcut then
			local shortcut = vim.tbl_extend("force", options.shortcut, opts.shortcut)
			check_shortcut(shortcut)
			options = vim.tbl_extend("force", options, { shortcut = shortcut })
		end
	end
	require("sub_action.session").open(options)
end

function M.setup(opts)
	opts = opts == nil and {} or opts
	check_options(opts, defaults, "setup")
	if next(opts) == nil then
		M.close()
		config = defaults
		return
	end
	local next_config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
	check_shortcut(next_config.shortcut)
	assert(vim.tbl_contains({ "name", "icon", "none" }, next_config.client.display), "invalid client display")
	for name, icon in pairs(next_config.client.icons) do
		assert(type(name) == "string" and type(icon) == "string", "client.icons must map names to strings")
	end
	assert(
		next_config.color == false
			or (type(next_config.color) == "string" and next_config.color:match("^#%x%x%x%x%x%x$")),
		"color must be a #RRGGBB string or false"
	)
	local seen = {}
	for lhs, action in pairs(next_config.keymap) do
		assert(type(lhs) == "string" and lhs ~= "" and not lhs:find("<any>", 1, true), "invalid keymap key")
		local key = vim.fn.keytrans(vim.api.nvim_replace_termcodes(lhs, true, false, true))
		assert(key ~= "<Esc>" or action == "close", "Esc can only be mapped to close")
		assert(
			action == false or vim.tbl_contains({ "next", "prev", "apply", "backspace", "close" }, action),
			"invalid keymap action for " .. lhs
		)
		if action ~= false then
			assert(not seen[key], "duplicate keymap key: " .. lhs)
			seen[key] = true
		end
	end
	for _, window in pairs(next_config.ui) do
		for _, dimension in ipairs({ "max_width", "max_height" }) do
			local value = window[dimension]
			assert(
				type(value) == "number" and value >= 1 and value == math.floor(value),
				dimension .. " must be a positive integer"
			)
		end
		local blend = window.winblend or 0
		assert(blend >= 0 and blend <= 100 and blend % 1 == 0, "invalid winblend")
		local border = window.border
		if type(border) == "string" then
			assert(
				vim.tbl_contains({ "none", "single", "double", "rounded", "solid", "shadow", "padded" }, border),
				"invalid border"
			)
		elseif border then
			assert(vim.tbl_contains({ 1, 2, 4, 8 }, #border), "border must have 1, 2, 4, or 8 entries")
			for _, char in ipairs(border) do
				if type(char) == "table" then
					assert(#char == 2 and type(char[2]) == "string", "invalid border highlight")
					char = char[1]
				end
				assert(type(char) == "string" and vim.fn.strdisplaywidth(char) <= 1, "invalid border character")
			end
		end
	end
	M.close()
	config = next_config
end

return M
