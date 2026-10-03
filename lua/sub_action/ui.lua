local M = {}
local api = vim.api
local ns = api.nvim_create_namespace("sub-action")
local input_ns = api.nvim_create_namespace("sub-action.input")
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
	BlinkCmpScrollBarThumb = "PmenuThumb",
	BlinkCmpScrollBarGutter = "PmenuSbar",
}
local function highlights()
	for group, link in pairs(links) do
		api.nvim_set_hl(0, group, { default = true, link = link })
	end
end
highlights()
api.nvim_create_autocmd("ColorScheme", { callback = highlights })

local function style(kind, options)
	local border = options.border
	if border == false then
		if vim.o.winborder ~= "" then
			border = vim.opt.winborder:get()
			border = #border == 1 and border[1] or border
		else
			border = kind == "action" and "none" or "padded"
		end
	end
	return {
		border = border,
		winblend = options.winblend == false and vim.go.winblend or options.winblend,
		winhighlight = options.winhighlight,
		min_width = kind == "action" and 15 or 1,
		max_height = options.max_height,
		max_width = options.max_width,
		scrolloff = kind == "action" and 2 or 0,
		scrollbar = options.scrollbar,
		padding = 1,
		gap = 1,
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
	local created = not float
	if not float then
		float = { buf = api.nvim_create_buf(false, true) }
		s[kind] = float
		vim.bo[float.buf].bufhidden = "wipe"
		vim.bo[float.buf].filetype = options.filetype
		vim.bo[float.buf].tabstop = 1
	end
	float.config = options
	local changed = float.lines ~= lines
	if changed then
		vim.bo[float.buf].modifiable = true
		api.nvim_buf_set_lines(float.buf, 0, -1, false, lines)
		vim.bo[float.buf].modifiable = false
		api.nvim_buf_clear_namespace(float.buf, ns, 0, -1)
		float.lines = lines
	end
	local border = options.border == "padded" and { " ", "", "", " ", "", "", " ", " " } or options.border
	local win_config = vim.tbl_extend("force", {
		relative = "editor",
		focusable = false,
		border = border,
		zindex = 1001,
	}, geometry)
	if created or not vim.deep_equal(float.geometry, geometry) then
		if float.id and api.nvim_win_is_valid(float.id) then
			api.nvim_win_set_config(float.id, win_config)
		else
			win_config.style = "minimal"
			float.id = api.nvim_open_win(float.buf, false, win_config)
		end
		float.geometry = geometry
	end
	if created then
		vim.wo[float.id].winblend = options.winblend
		vim.wo[float.id].winhighlight = options.winhighlight
		vim.wo[float.id].wrap = options.wrap
		vim.wo[float.id].linebreak = options.linebreak
		vim.wo[float.id].scrolloff = options.scrolloff
		vim.wo[float.id].cursorlineopt = "line"
		vim.wo[float.id].foldenable = false
	end
	return float, changed
end

local function scrollbar(float)
	local geometry, options = float.geometry, float.config
	local height, total = geometry.height, float.content_height
	if not options.scrollbar or total <= height then
		if float.scrollbar then
			M.close_float(float.scrollbar)
			float.scrollbar = nil
		end
		return
	end
	local border = options.border
	local gutter = border == "none" or border == "padded"
	if type(border) == "table" then
		local right = border[3 % #border + 1]
		right = type(right) == "table" and right[1] or right
		gutter = right == "" or right == " "
	end
	local thumb = math.max(1, math.floor(height * height / total + 0.5) - 1)
	local top = math.max(0, vim.fn.line("w0", float.id) - 1)
	if options.wrap and top > 0 then
		top = api.nvim_win_text_height(float.id, { start_row = 0, end_row = top - 1 }).all
	end
	local offset = math.min(height - thumb, math.floor(top / (total - height) * (height - thumb) + 0.5))
	local position = {
		relative = "win",
		win = float.id,
		row = gutter and 0 or offset,
		col = geometry.width + (border == "padded" and 1 or 0),
		width = 1,
		height = gutter and height or thumb,
		focusable = false,
		border = "none",
		zindex = 1002,
	}
	local bar = float.scrollbar
	if not bar then
		bar = { buf = api.nvim_create_buf(false, true) }
		float.scrollbar = bar
		vim.bo[bar.buf].bufhidden = "wipe"
		position.style, position.noautocmd = "minimal", true
		bar.id = api.nvim_open_win(bar.buf, false, position)
		vim.wo[bar.id].winblend = options.winblend
		position.style, position.noautocmd = nil, nil
	end
	if bar.height ~= height then
		api.nvim_buf_set_lines(bar.buf, 0, -1, false, vim.fn["repeat"]({ " " }, height))
		bar.height = height
		bar.offset = nil
	end
	if not vim.deep_equal(bar.geometry, position) then
		api.nvim_win_set_config(bar.id, position)
		bar.geometry = position
	end
	if bar.gutter ~= gutter then
		local group = gutter and "BlinkCmpScrollBarGutter" or "BlinkCmpScrollBarThumb"
		vim.wo[bar.id].winhighlight = "Normal:" .. group .. ",EndOfBuffer:" .. group
	end
	if bar.offset ~= offset or bar.thumb ~= thumb or bar.gutter ~= gutter then
		api.nvim_buf_clear_namespace(bar.buf, ns, 0, -1)
		if gutter then
			api.nvim_buf_set_extmark(bar.buf, ns, offset, 0, {
				end_row = offset + thumb,
				line_hl_group = "BlinkCmpScrollBarThumb",
			})
		end
		bar.offset, bar.thumb, bar.gutter = offset, thumb, gutter
	end
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
	local options = s.menu_options or style("action", config.ui.action)
	local padding = type(options.padding) == "table" and options.padding or { options.padding, options.padding }
	s.menu_options, s.label_start, s.marked_input = options, padding[1], nil
	local names, titles, label_width, name_width, title_width = {}, {}, 0, 0, 0
	for i, entry in ipairs(s.actions) do
		titles[i] = entry.action.title:gsub("[\r\n\t]", " ")
		names[i] = config.client.display == "name" and entry.client.name
			or config.client.display == "icon" and (config.client.icons[entry.client.name] or "")
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
	float.content_height = #lines
	float.selection = nil
	api.nvim_buf_clear_namespace(float.buf, input_ns, 0, -1)
	vim.wo[float.id].cursorline = true
	for i, entry in ipairs(s.actions) do
		local range = ranges[i]
		mark(float.buf, i - 1, padding[1], padding[1] + #s.labels[i], "BlinkCmpKind")
		mark(
			float.buf,
			i - 1,
			range[1],
			range[2],
			entry.action.disabled and "BlinkCmpLabelDeprecated" or "BlinkCmpLabel"
		)
		mark(float.buf, i - 1, range[3], range[4], "BlinkCmpSource")
	end
	local group = options.winhighlight:match("CursorLine:([^,]+)") or "CursorLine"
	local background = api.nvim_get_hl(0, { name = group, link = false }).bg
	float.selection_group = nil
	if background then
		api.nvim_set_hl(0, "SubActionSelection", { bg = background })
		float.selection_group = "SubActionSelection"
	end
	M.select(s)
end

function M.select(s)
	local float = s.action
	api.nvim_win_set_cursor(float.id, { s.selected, 0 })
	if float.selection_group then
		float.selection = api.nvim_buf_set_extmark(float.buf, ns, s.selected - 1, 0, {
			id = float.selection,
			line_hl_group = float.selection_group,
			priority = 10000,
		})
	end
	scrollbar(float)
	if s.marked_input == s.input then
		return
	end
	s.marked_input = s.input
	api.nvim_buf_clear_namespace(float.buf, input_ns, 0, -1)
	if s.input == "" then
		return
	end
	for i, label in ipairs(s.labels) do
		if label:sub(1, #s.input) == s.input then
			api.nvim_buf_set_extmark(float.buf, input_ns, i - 1, s.label_start, {
				end_col = s.label_start + #s.input,
				hl_group = "BlinkCmpLabelMatch",
				priority = 20000,
			})
		end
	end
end

function M.preview(s, lines, config)
	s.preview_options = s.preview_options or style("preview", config.ui.preview)
	local options, anchor = s.preview_options, s.geometry
	if s.preview and s.preview.lines == lines and s.preview.anchor == anchor then
		return
	end
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
	local float, changed =
		show(s, "preview", lines, options, { row = row, col = col, width = preview_width, height = height })
	float.anchor = anchor
	float.content_height = api.nvim_win_text_height(float.id, {}).all
	height =
		math.max(1, math.min(float.content_height, options.max_height, vim.o.lines - vim.o.cmdheight - 1 - vertical))
	row = math.max(0, math.min(anchor.row, vim.o.lines - vim.o.cmdheight - 1 - height - vertical))
	local geometry = { relative = "editor", row = row, col = col, width = preview_width, height = height }
	api.nvim_win_set_config(float.id, geometry)
	float.geometry = geometry
	scrollbar(float)
	if not changed then
		return
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
	if float.scrollbar then
		M.close_float(float.scrollbar)
	end
	if float.id and api.nvim_win_is_valid(float.id) then
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
