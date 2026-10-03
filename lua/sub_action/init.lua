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
	client = { display = "auto", icons = {} },
	preview = false,
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
		if name == "preview" and default == false then
			assert(value == false or kind == "function", field .. " must be a function or false")
		elseif name ~= "color" or value ~= false then
			vim.validate(field, value, name == "border" and { "string", "table" } or type(default))
		end
		if name == "mode" then
			assert(vim.tbl_contains({ "prefix", "mnemonic", "off" }, value), "invalid " .. field)
		elseif name == "display" then
			assert(vim.tbl_contains({ "auto", "name", "icon", "none" }, value), "invalid " .. field)
		elseif name == "color" then
			assert(value == false or value:match("^#%x%x%x%x%x%x$"), "color must be a #RRGGBB string or false")
		elseif name == "max_width" or name == "max_height" or name == "winblend" then
			assert(
				value % 1 == 0 and value >= (name == "winblend" and 0 or 1) and (name ~= "winblend" or value <= 100),
				"invalid " .. field
			)
		elseif name == "icons" then
			for client, icon in pairs(value) do
				vim.validate("client name", client, "string")
				vim.validate("client icon", icon, "string")
			end
		elseif name == "border" then
			if kind == "string" then
				assert(
					vim.tbl_contains({ "none", "single", "double", "rounded", "solid", "shadow", "padded" }, value),
					"invalid border"
				)
			else
				assert(vim.tbl_contains({ 1, 2, 4, 8 }, #value), "border must have 1, 2, 4, or 8 entries")
				for _, char in ipairs(value) do
					if type(char) == "table" then
						assert(#char == 2 and type(char[2]) == "string", "invalid border highlight")
						char = char[1]
					end
					assert(type(char) == "string" and vim.fn.strdisplaywidth(char) <= 1, "invalid border character")
				end
			end
		elseif kind == "table" and name ~= "keymap" then
			check_options(value, default, field)
		end
	end
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
			options = vim.tbl_extend("force", options, { shortcut = shortcut })
		end
	end
	require("sub_action.session").open(options)
end

function M.setup(opts)
	opts = opts == nil and {} or opts
	check_options(opts, defaults, "setup")
	local next_config = next(opts) and vim.tbl_deep_extend("force", defaults, opts) or defaults
	if opts.keymap then
		local keys = {}
		for lhs, action in pairs(next_config.keymap) do
			assert(type(lhs) == "string" and lhs ~= "" and not lhs:find("<any>", 1, true), "invalid keymap key")
			local key = vim.fn.keytrans(vim.api.nvim_replace_termcodes(lhs, true, false, true))
			assert(key ~= "<Esc>" or action == "close", "Esc can only be mapped to close")
			assert(
				action == false or vim.tbl_contains({ "next", "prev", "apply", "backspace", "close" }, action),
				"invalid keymap action for " .. lhs
			)
			if action ~= false then
				assert(not keys[key], "duplicate keymap key: " .. lhs)
				keys[key] = action
			end
		end
		next_config.keymap = keys
	end
	M.close()
	config = next_config
end

return M
