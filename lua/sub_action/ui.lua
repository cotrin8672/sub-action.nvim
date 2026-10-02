local M = {}
local api = vim.api
local ns = api.nvim_create_namespace("sub-action")
local width = vim.fn.strdisplaywidth

local links = {
	BlinkCmpMenu = "Pmenu",
	BlinkCmpMenuBorder = "Pmenu",
	BlinkCmpMenuSelection = "PmenuSel",
	BlinkCmpLabel = "Pmenu",
	BlinkCmpLabelMatch = "Pmenu",
	BlinkCmpLabelDeprecated = "PmenuExtra",
	BlinkCmpSource = "PmenuExtra",
	BlinkCmpKind = "PmenuKind",
	BlinkCmpDoc = "NormalFloat",
	BlinkCmpDocBorder = "NormalFloat",
}
local function highlights()
	for group, link in pairs(links) do
		api.nvim_set_hl(0, group, { default = true, link = link })
	end
end
highlights()
api.nvim_create_autocmd("ColorScheme", { callback = highlights })

local function style(kind, options)
	local blink = package.loaded["blink.cmp.config"]
	local inherited = blink and (kind == "action" and blink.completion.menu or blink.completion.documentation.window)
		or {}
	local border = options.border or inherited.border
	if not border then
		local global = vim.opt.winborder:get()
		border = #global == 1 and global[1] or global
		if border == "" or #global == 0 then
			border = kind == "preview" and "padded" or "none"
		end
	end
	local draw = blink and blink.completion.menu.draw or {}
	return {
		border = border,
		winblend = options.winblend or inherited.winblend or 0,
		winhighlight = options.winhighlight
			or inherited.winhighlight
			or (
				kind == "action"
					and "Normal:BlinkCmpMenu,FloatBorder:BlinkCmpMenuBorder,CursorLine:BlinkCmpMenuSelection,Search:None"
				or "Normal:BlinkCmpDoc,FloatBorder:BlinkCmpDocBorder,EndOfBuffer:BlinkCmpDoc"
			),
		min_width = kind == "action" and (inherited.min_width or 15) or 1,
		max_height = options.max_height,
		max_width = options.max_width,
		scrolloff = kind == "action" and (inherited.scrolloff or 2) or 0,
		scrollbar = inherited.scrollbar ~= false,
		cursorline_priority = draw.cursorline_priority or 10000,
		padding = draw.padding or 1,
		gap = draw.gap or 1,
		wrap = kind == "preview",
		linebreak = kind == "preview",
		filetype = kind == "action" and "sub-action" or "diff",
	}
end

local function borders(border)
	if border == "none" then
		return 0, 0, 0, 0
	end
	if border == "padded" then
		return 1, 1, 0, 0
	end
	if border == "shadow" then
		return 0, 1, 0, 1
	end
	if type(border) == "table" then
		local function side(index)
			local char = border[(index - 1) % #border + 1]
			if type(char) == "table" then
				char = char[1]
			end
			return char == "" and 0 or 1
		end
		return side(8), side(4), side(2), side(6)
	end
	return 1, 1, 1, 1
end

local function clip(text, limit)
	if width(text) <= limit then
		return text
	end
	if limit <= 0 then
		return ""
	end
	local result = ""
	for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		if width(result .. char .. "…") > limit then
			break
		end
		result = result .. char
	end
	return result .. "…"
end

local function dimensions(lines, options)
	local longest = options.min_width
	for _, line in ipairs(lines) do
		longest = math.max(longest, width(line))
	end
	local left, right, top, bottom = borders(options.border)
	local columns, rows = vim.o.columns, vim.o.lines - vim.o.cmdheight - 1
	return math.max(1, math.min(longest, options.max_width, columns - left - right)),
		math.max(1, math.min(#lines, options.max_height, rows - top - bottom)),
		left + right,
		top + bottom
end

local function show(s, kind, lines, options, geometry)
	local float = s[kind]
	if not float then
		local blink = package.loaded["blink.cmp.config"] and require("blink.cmp.lib.window")
		if blink then
			float = blink.new("sub_action_" .. kind, options)
			float.buf = float:get_buf()
		else
			float = { buf = api.nvim_create_buf(false, true), config = options }
		end
		s[kind] = float
		vim.bo[float.buf].bufhidden = "wipe"
		vim.bo[float.buf].filetype = options.filetype
	end
	vim.bo[float.buf].modifiable = true
	api.nvim_buf_set_lines(float.buf, 0, -1, false, lines)
	vim.bo[float.buf].modifiable = false
	api.nvim_buf_clear_namespace(float.buf, ns, 0, -1)
	local border = options.border == "padded" and { " ", "", "", " ", "", "", " ", " " } or options.border
	local win_config = vim.tbl_extend("force", {
		relative = "editor",
		style = "minimal",
		focusable = false,
		border = border,
		zindex = 1001,
	}, geometry)
	if float.open then
		float:open()
		float:set_win_config(win_config)
	elseif float.id and api.nvim_win_is_valid(float.id) then
		api.nvim_win_set_config(float.id, win_config)
	else
		float.id = api.nvim_open_win(float.buf, false, win_config)
	end
	vim.wo[float.id].winblend = options.winblend
	vim.wo[float.id].winhighlight = options.winhighlight
	vim.wo[float.id].wrap = options.wrap
	vim.wo[float.id].linebreak = options.linebreak
	vim.wo[float.id].scrolloff = options.scrolloff
	vim.wo[float.id].cursorlineopt = "line"
	return float
end

local function mark(buffer, row, start, finish, group, priority)
	if finish > start then
		api.nvim_buf_set_extmark(buffer, ns, row, start, {
			end_col = finish,
			hl_group = group,
			priority = priority or 100,
		})
	end
end

function M.menu(s, config)
	local options = style("action", config.ui.action)
	local padding = type(options.padding) == "table" and options.padding or { options.padding, options.padding }
	local names, titles, label_width, name_width, title_width = {}, {}, 0, 0, 0
	for i, entry in ipairs(s.actions) do
		titles[i] = entry.action.title:gsub("[\r\n\t]", " ")
		names[i] = config.client.display == "name" and entry.client.name
			or config.client.display == "icon" and (config.client.icons[entry.client.name] or entry.client.name)
			or ""
		label_width, name_width, title_width =
			math.max(label_width, width(s.labels[i])),
			math.max(name_width, width(names[i])),
			math.max(title_width, width(titles[i]))
	end
	local gap = string.rep(" ", options.gap)
	local prefix_size = padding[1] + label_width + (label_width > 0 and options.gap or 0)
	local longest = prefix_size + title_width + (name_width > 0 and options.gap + name_width or 0) + padding[2]
	local menu_width, height, horizontal, vertical = dimensions({ string.rep(" ", longest) }, options)
	height = math.min(#s.actions, config.ui.action.max_height, vim.o.lines - vim.o.cmdheight - 1 - vertical)
	height = math.max(1, height)
	-- Keep the action readable when a client name is unusually long.
	local minimum_title = math.min(title_width, math.max(1, math.floor((menu_width - prefix_size) / 2)))
	name_width = math.min(name_width, math.max(0, menu_width - prefix_size - padding[2] - options.gap - minimum_title))
	local title_space =
		math.max(0, menu_width - prefix_size - padding[2] - (name_width > 0 and options.gap + name_width or 0))
	local lines, ranges = {}, {}
	for i, entry in ipairs(s.actions) do
		local label, title, name = s.labels[i], clip(titles[i], title_space), clip(names[i], name_width)
		local line = string.rep(" ", padding[1])
			.. label
			.. string.rep(" ", label_width - width(label))
			.. (label_width > 0 and gap or "")
		local start = #line
		line = line .. title .. string.rep(" ", title_space - width(title))
		local source_start = #line + #gap
		if name_width > 0 then
			line = line .. gap .. name .. string.rep(" ", name_width - width(name))
		end
		lines[i], ranges[i] =
			line .. string.rep(" ", padding[2]), { start, start + #title, source_start, source_start + #name }
	end
	local position = vim.fn.screenpos(s.winid, s.cursor[1], s.cursor[2] + 1)
	local cursor_row, cursor_col = math.max(0, position.row - 1), math.max(0, position.col - 1)
	local rows = vim.o.lines - vim.o.cmdheight - 1
	local below = cursor_row + 1 + height + vertical <= rows
	local row = below and cursor_row + 1 or math.max(0, cursor_row - height - vertical)
	local col = math.max(0, math.min(cursor_col - prefix_size, vim.o.columns - menu_width - horizontal))
	local geometry = { row = row, col = col, width = menu_width, height = height }
	s.geometry = { row = row, col = col, width = menu_width + horizontal, height = height + vertical }
	local float = show(s, "action", lines, options, geometry)
	vim.wo[float.id].cursorline = true
	if float.set_cursor then
		float:set_cursor({ s.selected, 0 })
	else
		api.nvim_win_set_cursor(float.id, { s.selected, 0 })
	end
	for i, entry in ipairs(s.actions) do
		local range = ranges[i]
		mark(float.buf, i - 1, padding[1], padding[1] + #s.labels[i], "BlinkCmpKind")
		if s.input ~= "" and s.labels[i]:sub(1, #s.input) == s.input then
			mark(float.buf, i - 1, padding[1], padding[1] + #s.input, "BlinkCmpLabelMatch", 20000)
		end
		mark(
			float.buf,
			i - 1,
			range[1],
			range[2],
			entry.action.disabled and "BlinkCmpLabelDeprecated" or "BlinkCmpLabel"
		)
		mark(float.buf, i - 1, range[3], range[4], "BlinkCmpSource")
	end
	if not float.open then
		local group = options.winhighlight:match("CursorLine:([^,]+)") or "BlinkCmpMenuSelection"
		local background = api.nvim_get_hl(0, { name = group, link = false }).bg
		if background then
			api.nvim_set_hl(0, "SubActionSelection", { bg = background })
			api.nvim_buf_set_extmark(float.buf, ns, s.selected - 1, 0, {
				line_hl_group = "SubActionSelection",
				priority = options.cursorline_priority,
			})
		end
	end
end

function M.preview(s, lines, config)
	local options, anchor = style("preview", config.ui.preview), s.geometry
	local preview_width, height, horizontal, vertical = dimensions(lines, options)
	local east, west = vim.o.columns - anchor.col - anchor.width - 1, anchor.col - 1
	local right = east >= preview_width + horizontal or east >= west
	local available = right and east or west
	if available <= horizontal then
		if s.preview then
			M.close_float(s.preview)
			s.preview = nil
		end
		return
	end
	preview_width = math.max(1, math.min(preview_width, available - horizontal))
	local col = right and anchor.col + anchor.width + 1 or anchor.col - preview_width - horizontal - 1
	local row = math.max(0, math.min(anchor.row, vim.o.lines - vim.o.cmdheight - 1 - height - vertical))
	local float = show(s, "preview", lines, options, { row = row, col = col, width = preview_width, height = height })
	height = math.max(
		1,
		math.min(
			api.nvim_win_text_height(float.id, {}).all,
			options.max_height,
			vim.o.lines - vim.o.cmdheight - 1 - vertical
		)
	)
	row = math.max(0, math.min(anchor.row, vim.o.lines - vim.o.cmdheight - 1 - height - vertical))
	local geometry = { relative = "editor", row = row, col = col, width = preview_width, height = height }
	if float.set_win_config then
		float:set_win_config(geometry)
	else
		api.nvim_win_set_config(float.id, geometry)
	end
	for i, line in ipairs(lines) do
		local group = line:match("^@@") and "DiffChange"
			or line:match("^[+-][+-]") and "Comment"
			or line:sub(1, 1) == "+" and "DiffAdd"
			or line:sub(1, 1) == "-" and "DiffDelete"
		if group then
			mark(float.buf, i - 1, 0, #line, group)
		end
	end
end

function M.close_float(float)
	if float.close then
		float:close()
	elseif float.id and api.nvim_win_is_valid(float.id) then
		api.nvim_win_close(float.id, true)
	end
	if api.nvim_buf_is_valid(float.buf) then
		api.nvim_buf_delete(float.buf, { force = true })
	end
end

function M.close(s)
	for _, kind in ipairs({ "action", "preview" }) do
		if s[kind] then
			M.close_float(s[kind])
		end
	end
end

return M
