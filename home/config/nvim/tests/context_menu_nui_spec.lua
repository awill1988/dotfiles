local context_menu = require("core.context_menu")

local target_window = vim.api.nvim_get_current_win()
local target_buffer = vim.api.nvim_get_current_buf()
local original_window_count = #vim.api.nvim_list_wins()
local original_mousemoveevent = vim.o.mousemoveevent

context_menu.open({
	context = {
		bufnr = target_buffer,
		mode = "n",
		mouse = { screenrow = 2, screencol = 2 },
		visual = false,
		winid = target_window,
	},
	items = {
		{ label = "Open", key = "o", action = function() end },
		{ separator = true },
		{ label = "Close", key = "c", action = function() end },
	},
})

assert(#vim.api.nvim_list_wins() > original_window_count, "popover should mount content and border windows")
assert(vim.o.mousemoveevent, "popover should enable mouse movement events")

context_menu.close()

assert(#vim.api.nvim_list_wins() == original_window_count, "popover should unmount every window")
assert(vim.o.mousemoveevent == original_mousemoveevent, "popover should restore mouse movement events")
print("context-menu-nui-tests-ok")
