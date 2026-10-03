local M = {}
local api = vim.api
local ns = api.nvim_create_namespace("sub-action")
local input_ns = api.nvim_create_namespace("sub-action.input")
local width = vim.fn.strdisplaywidth
local shortcut = require("sub_action.shortcut")

local links = {
	BlinkCmpMenu = "Pmenu",
	BlinkCmpMenuBorder = "Pmenu",
	BlinkCmpMenuSelection = "PmenuSel",
	BlinkCmpLabel = "Pmenu",
	BlinkCmpLabelMatch = "Special",
	BlinkCmpLabelDeprecated = "PmenuExtra",
	SubActionClient = "Comment",
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
	options = vim.tbl_extend("force", { winblend = vim.go.winblend }, options)
	if options.border == nil then
		local global = vim.opt.winborder:get()
		options.border = #global > 1 and global or global[1] or (kind == "action" and "none" or "padded")
	end
	return options
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
	local result = vim.fn.strcharpart(text, 0, limit - 1, true)
	while width(result) > limit - 1 do
		result = vim.fn.strcharpart(result, 0, vim.fn.strchars(result, true) - 1, true)
	end
	return result .. "…"
end

local function dimensions(longest, height, options)
	local left, right, top, bottom = borders(options.border)
	local columns, rows = vim.o.columns, vim.o.lines - vim.o.cmdheight - 1
	return math.max(1, math.min(longest, options.max_width, columns - left - right)),
		math.max(1, math.min(height, options.max_height, rows - top - bottom)),
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
		vim.bo[float.buf].filetype = kind == "action" and "sub-action" or "diff"
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
		vim.wo[float.id].wrap = kind == "preview"
		vim.wo[float.id].linebreak = kind == "preview"
		vim.wo[float.id].scrolloff = kind == "action" and 2 or 0
		vim.wo[float.id].cursorlineopt = "line"
		vim.wo[float.id].foldenable = false
	end
	return float, changed
end

local function stop_loading(float)
	if float.loading_timer then
		float.loading_timer:stop()
		float.loading_timer:close()
		float.loading_timer = nil
	end
end

local function close_float(float)
	stop_loading(float)
	if float.scrollbar then
		close_float(float.scrollbar)
	end
	if float.id and api.nvim_win_is_valid(float.id) then
		api.nvim_win_close(float.id, true)
	end
	if api.nvim_buf_is_valid(float.buf) then
		api.nvim_buf_delete(float.buf, { force = true })
	end
end

local function scrollbar(float)
	local geometry, options = float.geometry, float.config
	local height, total = geometry.height, float.content_height
	if not options.scrollbar or total <= height then
		if float.scrollbar then
			close_float(float.scrollbar)
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
	if top > 0 and vim.wo[float.id].wrap then
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

local function spin(float)
	local frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
	local timer, frame, id = vim.uv.new_timer(), 0, nil
	float.loading_timer = timer
	local function draw()
		if float.loading_timer ~= timer then
			return
		end
		if not api.nvim_win_is_valid(float.id) or not api.nvim_buf_is_valid(float.buf) then
			stop_loading(float)
			return
		end
		frame = frame % #frames + 1
		id = api.nvim_buf_set_extmark(float.buf, ns, math.floor((float.geometry.height - 1) / 2), 0, {
			id = id,
			virt_text = { { frames[frame], "BlinkCmpLabelMatch" } },
			virt_text_win_col = math.max(0, math.floor((float.geometry.width - width(frames[frame])) / 2)),
		})
	end
	draw()
	timer:start(80, 80, vim.schedule_wrap(draw))
end

function M.menu(s, config)
	local options = s.menu_options or style("action", config.ui.action)
	s.menu_options, s.marked_input = options, nil
	local display = config.client.display
	if display == "auto" then
		display = "none"
		local first = s.actions[1] and s.actions[1].client
		for _, entry in ipairs(s.actions) do
			if (entry.client.id or entry.client.name) ~= (first.id or first.name) then
				display = "name"
				break
			end
		end
	end
	local names, titles, name_width, title_width = {}, {}, 0, 0
	for i, entry in ipairs(s.actions) do
		titles[i] = entry.action.title:gsub("[\r\n\t]", " ")
		names[i] = display == "name" and entry.client.name
			or display == "icon" and (config.client.icons[entry.client.name] or "")
			or ""
		name_width, title_width = math.max(name_width, width(names[i])), math.max(title_width, width(titles[i]))
	end
	local longest = title_width + (name_width > 0 and 1 + name_width or 0) + 2
	local loading = #s.actions == 0
	local menu_width, height, horizontal, vertical = dimensions(
		loading and options.max_width or math.max(15, longest),
		loading and options.max_height or #s.actions,
		options
	)
	-- Keep the action readable when a client name is unusually long.
	local minimum_title = math.min(title_width, math.max(1, math.floor((menu_width - 1) / 2)))
	name_width = math.min(name_width, math.max(0, menu_width - 3 - minimum_title))
	local title_space = math.max(0, menu_width - 2 - (name_width > 0 and 1 + name_width or 0))
	local lines, ranges = {}, {}
	if loading then
		lines = vim.fn["repeat"]({ "" }, height)
	end
	for i, entry in ipairs(s.actions) do
		local title, name = clip(titles[i], title_space), clip(names[i], name_width)
		titles[i] = title:lower()
		local line = " "
		local start = #line
		line = line .. title .. string.rep(" ", title_space - width(title))
		local source_start = #line + 1
		if name_width > 0 then
			line = line .. " " .. name .. string.rep(" ", name_width - width(name))
		end
		lines[i], ranges[i] = line .. " ", { start, start + #title, source_start, source_start + #name }
	end
	local position = vim.fn.screenpos(s.winid, s.cursor[1], s.cursor[2] + 1)
	local cursor_row, cursor_col = math.max(0, position.row - 1), math.max(0, position.col - 1)
	local rows = vim.o.lines - vim.o.cmdheight - 1
	local below = cursor_row + 1 + height + vertical <= rows
	local row = below and cursor_row + 1 or math.max(0, cursor_row - height - vertical)
	local col = math.max(0, math.min(cursor_col - 1, vim.o.columns - menu_width - horizontal))
	local geometry = { row = row, col = col, width = menu_width, height = height }
	s.geometry = { row = row, col = col, width = menu_width + horizontal, height = height + vertical }
	local float = show(s, "action", lines, options, geometry)
	stop_loading(float)
	if #s.actions == 0 then
		spin(float)
	end
	float.content_height = #lines
	float.titles = titles
	float.selection = nil
	api.nvim_buf_clear_namespace(float.buf, input_ns, 0, -1)
	vim.wo[float.id].cursorline = #s.actions > 0
	for i, entry in ipairs(s.actions) do
		local range = ranges[i]
		mark(
			float.buf,
			i - 1,
			range[1],
			range[2],
			entry.action.disabled and "BlinkCmpLabelDeprecated" or "BlinkCmpLabel"
		)
		mark(float.buf, i - 1, range[3], range[4], "SubActionClient")
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
	if #s.actions == 0 then
		return
	end
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
		local title = s.actions[i].action.title:lower()
		local positions = shortcut.positions(label, s.input, title, s.config.shortcut.mode, s.label_positions[i])
		for _, position in ipairs(positions or {}) do
			-- ponytail: synthetic suffixes have no glyph; only mark visible title characters.
			if float.titles[i]:sub(position, position) == title:sub(position, position) then
				api.nvim_buf_set_extmark(float.buf, input_ns, i - 1, position, {
					end_col = position + 1,
					hl_group = "BlinkCmpLabelMatch",
					priority = 20000,
				})
			end
		end
	end
end

local function preview_lines(lines)
	local headers, paths, counts = {}, {}, {}
	local old_left, new_left = 0, 0
	for i, line in ipairs(lines) do
		local old_start, old_count, new_start, new_count = line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
		if old_start then
			old_left, new_left = tonumber(old_count) or 1, tonumber(new_count) or 1
		elseif old_left > 0 or new_left > 0 then
			local prefix = line:sub(1, 1)
			old_left = old_left - ((prefix == " " or prefix == "-") and 1 or 0)
			new_left = new_left - ((prefix == " " or prefix == "+") and 1 or 0)
		else
			local old = line:match("^--- (.+)$")
			local new = (lines[i + 1] or ""):match("^%+%+%+ (.+)$")
			if old and new then
				old, new = old:gsub("\\", "/"), new:gsub("\\", "/")
				if (old:sub(1, 2) == "a/" or old == "/dev/null") and (new:sub(1, 2) == "b/" or new == "/dev/null") then
					old, new = old:gsub("^a/", ""), new:gsub("^b/", "")
				end
				headers[i], headers[i + 1] = old, new
				for _, path in ipairs({ old, new }) do
					if path ~= "/dev/null" then
						paths[path] = vim.split(path, "/", { plain = true })
					end
				end
			end
		end
	end
	if not next(headers) then
		return lines
	end
	for _, parts in pairs(paths) do
		for start = #parts, 1, -1 do
			local suffix = table.concat(parts, "/", start)
			counts[suffix] = (counts[suffix] or 0) + 1
		end
	end
	local short = { ["/dev/null"] = "/dev/null" }
	for path, parts in pairs(paths) do
		for start = #parts, 1, -1 do
			local suffix = table.concat(parts, "/", start)
			short[path] = suffix
			if counts[suffix] == 1 then
				break
			end
		end
	end
	local result = vim.list_extend({}, lines)
	for row, path in pairs(headers) do
		result[row] = lines[row]:sub(1, 4) .. short[path]
	end
	return result
end

function M.preview(s, lines, config)
	s.preview_options = s.preview_options or style("preview", config.ui.preview)
	local options, anchor = s.preview_options, s.geometry
	if s.preview and s.preview.source_lines == lines and s.preview.anchor == anchor then
		return
	end
	local source_lines = lines
	lines = s.preview and s.preview.source_lines == lines and s.preview.lines or preview_lines(lines)
	local longest = 1
	for _, line in ipairs(lines) do
		longest = math.max(longest, width(line))
	end
	local preview_width, height, horizontal, vertical = dimensions(longest, #lines, options)
	local east, west = vim.o.columns - anchor.col - anchor.width - 1, anchor.col - 1
	local right = east >= preview_width + horizontal or east >= west
	local available = right and east or west
	if available <= horizontal then
		if s.preview then
			close_float(s.preview)
			s.preview = nil
		end
		return
	end
	preview_width = math.max(1, math.min(preview_width, available - horizontal))
	local col = right and anchor.col + anchor.width + 1 or anchor.col - preview_width - horizontal - 1
	local row = math.max(0, math.min(anchor.row, vim.o.lines - vim.o.cmdheight - 1 - height - vertical))
	local float, changed =
		show(s, "preview", lines, options, { row = row, col = col, width = preview_width, height = height })
	float.source_lines = source_lines
	float.anchor = anchor
	float.content_height = api.nvim_win_text_height(float.id, {}).all
	height =
		math.max(1, math.min(float.content_height, options.max_height, vim.o.lines - vim.o.cmdheight - 1 - vertical))
	row = math.max(0, math.min(anchor.row, vim.o.lines - vim.o.cmdheight - 1 - height - vertical))
	if height ~= float.geometry.height or row ~= float.geometry.row then
		api.nvim_win_set_config(float.id, { relative = "editor", row = row, col = col, height = height })
		float.geometry.height, float.geometry.row = height, row
	end
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

function M.close(s)
	for _, kind in ipairs({ "action", "preview" }) do
		if s[kind] then
			close_float(s[kind])
		end
	end
end

return M
