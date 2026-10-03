local M = {}

function M.enter(color)
	local lualine = package.loaded.lualine
	if not color or not lualine then
		return
	end
	local original = lualine.get_config().options.theme
	local function theme()
		local base = type(original) == "function" and original() or original
		if type(base) == "string" then
			base = require("lualine.utils.loader").load_theme(base)
		end
		local tinted = {}
		for mode, sections in pairs(base) do
			sections = vim.deepcopy(sections)
			tinted[mode] = sections
			if mode ~= "inactive" then
				for section, attr in pairs({ a = "bg", b = "fg", y = "fg", z = "bg" }) do
					local colors = sections[section]
					if colors then
						sections[section] = function(context)
							local resolved = type(colors) == "function" and colors(context) or colors
							if type(resolved) == "string" then
								resolved = require("lualine.utils.utils").extract_highlight_colors(resolved)
							end
							return vim.tbl_extend("force", resolved or {}, { [attr] = color })
						end
					end
				end
			end
		end
		return tinted
	end
	lualine.setup({ options = { theme = theme } })
	return function()
		lualine.setup({ options = { theme = original } })
		lualine.refresh({ force = true })
	end
end

return M
