local M = {}

local providers = {}
local active_menu

local function setup_highlights()
	vim.api.nvim_set_hl(0, "ContextMenuNormal", { link = "NormalFloat" })
	vim.api.nvim_set_hl(0, "ContextMenuBorder", { link = "FloatBorder" })
	vim.api.nvim_set_hl(0, "ContextMenuSelected", { link = "PmenuSel" })
	vim.api.nvim_set_hl(0, "ContextMenuShortcut", { link = "Special" })
	vim.api.nvim_set_hl(0, "ContextMenuDisabled", { link = "Comment" })
end

local function is_window_valid(winid)
	return winid and vim.api.nvim_win_is_valid(winid)
end

local function is_buffer_valid(bufnr)
	return bufnr and vim.api.nvim_buf_is_valid(bufnr)
end

local function visual_mode(mode)
	return mode == "v" or mode == "V" or mode == "\22"
end

local function point_in_visual_selection(mouse, mode, first, last)
	if not visual_mode(mode) or mouse.line <= 0 then
		return false
	end

	local start_line, start_col = first[2], first[3]
	local end_line, end_col = last[2], last[3]
	if start_line > end_line or (start_line == end_line and start_col > end_col) then
		start_line, end_line = end_line, start_line
		start_col, end_col = end_col, start_col
	end

	if mouse.line < start_line or mouse.line > end_line then
		return false
	end
	if mode == "V" then
		return true
	end
	if mode == "\22" then
		local minimum = math.min(start_col, end_col)
		local maximum = math.max(start_col, end_col)
		return mouse.column >= minimum and mouse.column <= maximum
	end
	if start_line == end_line then
		return mouse.column >= start_col and mouse.column <= end_col
	end
	if mouse.line == start_line then
		return mouse.column >= start_col
	end
	if mouse.line == end_line then
		return mouse.column <= end_col
	end
	return true
end

local function capture_context()
	local mouse = vim.fn.getmousepos()
	local winid = mouse.winid ~= 0 and mouse.winid or vim.api.nvim_get_current_win()
	if not is_window_valid(winid) then
		return nil
	end

	local bufnr = vim.api.nvim_win_get_buf(winid)
	local mode = vim.fn.mode(1):sub(1, 1)
	local first = vim.fn.getpos("'<")
	local last = vim.fn.getpos("'>")
	local keep_visual = point_in_visual_selection(mouse, mode, first, last)

	if mouse.winid == winid and mouse.line > 0 and not keep_visual then
		local line_count = vim.api.nvim_buf_line_count(bufnr)
		local line = math.min(math.max(mouse.line, 1), line_count)
		local text = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ""
		local column = math.min(math.max(mouse.column - 1, 0), #text)
		pcall(vim.api.nvim_win_set_cursor, winid, { line, column })
	end

	return {
		bufnr = bufnr,
		filetype = vim.bo[bufnr].filetype,
		buftype = vim.bo[bufnr].buftype,
		modifiable = vim.bo[bufnr].modifiable,
		mode = mode,
		mouse = mouse,
		visual = keep_visual,
		visual_start = first,
		visual_end = last,
		winid = winid,
	}
end

local function restore_context(context, resume_mode)
	if not context or not is_window_valid(context.winid) or not is_buffer_valid(context.bufnr) then
		return
	end

	vim.api.nvim_set_current_win(context.winid)
	if context.visual then
		pcall(vim.cmd, "normal! gv")
	elseif resume_mode and context.mode == "i" then
		vim.cmd("startinsert")
	elseif resume_mode and context.mode == "t" then
		vim.cmd("startinsert")
	end
end

local function close_active(resume_mode)
	if not active_menu then
		return
	end

	local state = active_menu
	active_menu = nil
	vim.o.mousemoveevent = state.mousemoveevent
	if state.menu and state.menu._ and state.menu._.mounted then
		state.menu:unmount()
	end
	if resume_mode then
		restore_context(state.context, true)
	end
end

local function calculate_geometry(mouse, content_width, item_count, columns, lines)
	local outer_width = content_width + 4
	local outer_height = item_count + 2
	local row = math.max((mouse.screenrow or 1) - 1, 0)
	local col = math.max((mouse.screencol or 1) - 1, 0)
	local anchor = "NW"

	if col + outer_width > columns then
		anchor = "NE"
		col = math.min(math.max(col, outer_width - 1), columns - 1)
	end
	if row + outer_height > lines - 1 then
		anchor = anchor == "NE" and "SE" or "SW"
		row = math.min(math.max(row, outer_height - 1), math.max(lines - 2, 0))
	end

	return {
		anchor = anchor,
		position = { row = row, col = col },
		width = content_width,
	}
end

local function normalized_items(items)
	local result = {}
	local shortcuts = {}
	for _, item in ipairs(items or {}) do
		if item.separator then
			if #result > 0 and not result[#result].separator then
				table.insert(result, { separator = true })
			end
		elseif item.enabled ~= false then
			assert(type(item.label) == "string" and item.label ~= "", "context menu item requires a label")
			assert(type(item.action) == "function", "context menu item requires an action")
			assert(type(item.key) == "string" and item.key ~= "", "context menu item requires a shortcut")
			assert(not shortcuts[item.key], "duplicate context menu shortcut: " .. item.key)
			shortcuts[item.key] = true
			table.insert(result, item)
		end
	end
	if result[#result] and result[#result].separator then
		table.remove(result)
	end
	return result
end

local function truncate_label(label, maximum_width)
	if vim.api.nvim_strwidth(label) <= maximum_width then
		return label
	end
	if maximum_width <= 1 then
		return "…"
	end

	local character_count = vim.fn.strchars(label)
	while character_count > 0 do
		local candidate = vim.fn.strcharpart(label, 0, character_count) .. "…"
		if vim.api.nvim_strwidth(candidate) <= maximum_width then
			return candidate
		end
		character_count = character_count - 1
	end
	return "…"
end

function M.register_provider(provider)
	assert(type(provider) == "table", "context menu provider must be a table")
	assert(type(provider.name) == "string", "context menu provider requires a name")
	assert(type(provider.match) == "function", "context menu provider requires match(context)")
	assert(type(provider.build) == "function", "context menu provider requires build(context)")

	for index, existing in ipairs(providers) do
		if existing.name == provider.name then
			providers[index] = provider
			table.sort(providers, function(left, right)
				return (left.priority or 0) > (right.priority or 0)
			end)
			return
		end
	end
	table.insert(providers, provider)
	table.sort(providers, function(left, right)
		return (left.priority or 0) > (right.priority or 0)
	end)
end

function M.open(spec)
	local Menu = require("nui.menu")
	local Line = require("nui.line")
	local Text = require("nui.text")
	local event = require("nui.utils.autocmd").event
	local context = assert(spec.context, "context menu requires a captured context")
	local items = normalized_items(spec.items)
	if #items == 0 then
		return
	end

	close_active(false)

	local label_width = 0
	for _, item in ipairs(items) do
		if not item.separator then
			label_width = math.max(label_width, vim.api.nvim_strwidth(item.label))
		end
	end
	local available_width = math.max(vim.o.columns - 4, 4)
	local content_width = math.min(math.max(label_width + 5, 12), available_width)
	local lines = {}
	local item_lines = {}
	for _, item in ipairs(items) do
		if item.separator then
			table.insert(lines, Menu.separator("", { char = "─" }))
		else
			local line = Line()
			local shortcut = "(" .. item.key .. ")"
			local shortcut_width = vim.api.nvim_strwidth(shortcut)
			local label = truncate_label(item.label, math.max(content_width - shortcut_width - 1, 1))
			local gap = content_width - vim.api.nvim_strwidth(label) - shortcut_width
			line:append(Text(label, "ContextMenuNormal"))
			line:append(Text(string.rep(" ", math.max(gap, 1))))
			line:append(Text(shortcut, "ContextMenuShortcut"))
			local menu_item = Menu.item(line, { action = item.action, shortcut = item.key })
			table.insert(lines, menu_item)
			item_lines[item.key] = #lines
		end
	end

	local visible_height = math.min(#lines, math.max(vim.o.lines - 2, 1))
	local geometry = calculate_geometry(context.mouse, content_width, visible_height, vim.o.columns, vim.o.lines)
	local state
	local function finish(resume_mode)
		if active_menu ~= state then
			return
		end
		active_menu = nil
		vim.o.mousemoveevent = state.mousemoveevent
		if resume_mode then
			restore_context(context, true)
		end
	end
	local function run_action(item)
		finish(false)
		restore_context(context, false)
		local ok, error_message = pcall(item.action, context)
		if not ok then
			vim.notify("context menu action failed: " .. error_message, vim.log.levels.ERROR)
		end
	end

	local menu = Menu({
		anchor = geometry.anchor,
		border = {
			padding = { top = 0, right = 1, bottom = 0, left = 1 },
			style = "single",
		},
		position = geometry.position,
		relative = "editor",
		size = { width = geometry.width, height = visible_height },
		win_options = {
			cursorline = true,
			winblend = 0,
			winhighlight = table.concat({
				"Normal:ContextMenuNormal",
				"FloatBorder:ContextMenuBorder",
				"CursorLine:ContextMenuSelected",
			}, ","),
		},
		zindex = 200,
	}, {
		lines = lines,
		keymap = {
			close = { "<Esc>", "q" },
			focus_next = { "j", "<Down>", "<Tab>" },
			focus_prev = { "k", "<Up>", "<S-Tab>" },
			submit = { "<CR>", "<Space>" },
		},
		on_close = function()
			finish(true)
		end,
		on_submit = run_action,
	})

	state = {
		context = context,
		menu = menu,
		mousemoveevent = vim.o.mousemoveevent,
	}
	active_menu = state
	vim.o.mousemoveevent = true
	menu:mount()

	for shortcut, line_number in pairs(item_lines) do
		menu:map("n", shortcut, function()
			if not active_menu or active_menu.menu ~= menu then
				return
			end
			vim.api.nvim_win_set_cursor(menu.winid, { line_number, 0 })
			menu.menu_props.on_submit()
		end, { noremap = true, nowait = true })
	end

	menu:map("n", "<MouseMove>", function()
		local mouse = vim.fn.getmousepos()
		if mouse.winid ~= menu.winid then
			return
		end
		local node = menu.tree:get_node(mouse.line)
		if node and node._type == "item" then
			vim.api.nvim_win_set_cursor(menu.winid, { mouse.line, 0 })
		end
	end, { noremap = true, nowait = true })

	menu:map("n", "<LeftMouse>", function()
		local mouse = vim.fn.getmousepos()
		if mouse.winid ~= menu.winid then
			close_active(true)
			return
		end
		local node = menu.tree:get_node(mouse.line)
		if node and node._type == "item" then
			vim.api.nvim_win_set_cursor(menu.winid, { mouse.line, 0 })
			menu.menu_props.on_submit()
		end
	end, { noremap = true, nowait = true })
	menu:map("n", "<RightMouse>", function()
		close_active(true)
	end, { noremap = true, nowait = true })

	menu:on(event.VimResized, function()
		close_active(true)
	end, { once = true })
	menu:on(event.WinLeave, function()
		vim.schedule(function()
			if active_menu == state then
				close_active(false)
			end
		end)
	end, { once = true })
end

function M.open_for_buffer()
	local context = capture_context()
	if not context then
		return
	end

	for _, provider in ipairs(providers) do
		if provider.match(context) then
			local spec = provider.build(context)
			if spec and spec.items then
				M.open({ context = context, items = spec.items })
			end
			return
		end
	end
end

function M.close()
	close_active(true)
end

function M.setup()
	setup_highlights()
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("ContextMenuHighlights", { clear = true }),
		callback = setup_highlights,
	})
	local modes = { "n", "x", "i", "t" }
	local function map_buffer(bufnr)
		vim.keymap.set(modes, "<RightMouse>", M.open_for_buffer, {
			buffer = bufnr,
			desc = "Open context menu",
			noremap = true,
			silent = true,
		})
	end

	vim.keymap.set(modes, "<RightMouse>", M.open_for_buffer, {
		desc = "Open context menu",
		noremap = true,
		silent = true,
	})
	local mapping_group = vim.api.nvim_create_augroup("ContextMenuMappings", { clear = true })
	vim.api.nvim_create_autocmd("BufWinEnter", {
		group = mapping_group,
		callback = function(args)
			map_buffer(args.buf)
		end,
	})
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(bufnr) then
			map_buffer(bufnr)
		end
	end
end

M._test = {
	calculate_geometry = calculate_geometry,
	normalized_items = normalized_items,
	point_in_visual_selection = point_in_visual_selection,
	truncate_label = truncate_label,
}

return M
