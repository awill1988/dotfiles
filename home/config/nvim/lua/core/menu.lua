-- Context Menu (PopUp) & Tmux AI Agent Prompt Integration
local M = {}

-- 1. Helper to extract visual selection
function M.get_visual_selection()
	local s_start = vim.fn.getpos("'<")
	local s_end = vim.fn.getpos("'>")
	local lines = vim.api.nvim_buf_get_lines(0, s_start[2] - 1, s_end[2], false)
	if #lines == 0 then
		return ""
	end
	local mode = vim.fn.visualmode()
	if mode == "v" then
		if #lines == 1 then
			lines[1] = string.sub(lines[1], s_start[3], s_end[3])
		else
			lines[1] = string.sub(lines[1], s_start[3])
			lines[#lines] = string.sub(lines[#lines], 1, s_end[3])
		end
	elseif mode == "\22" then -- Block visual mode (<C-v>)
		for i = 1, #lines do
			lines[i] = string.sub(lines[i], s_start[3], s_end[3])
		end
	end
	return table.concat(lines, "\n")
end

-- 2. Helper to target active tmux pane
function M.get_target_tmux_pane()
	local tmux_env = vim.fn.getenv("TMUX")
	if tmux_env == vim.NIL or tmux_env == "" then
		return nil
	end

	local handle = io.popen("tmux list-panes -F '#{pane_id}|#{pane_current_command}|#{pane_active}' 2>/dev/null")
	if not handle then
		return nil
	end

	local panes = {}
	for line in handle:lines() do
		local id, cmd, active = line:match("([^|]+)|([^|]+)|([^|]+)")
		if id then
			table.insert(panes, { id = id, cmd = cmd, active = (active == "1") })
		end
	end
	handle:close()

	if #panes == 0 then
		return nil
	end

	-- If only 1 pane (Neovim alone in window), split a new right pane for agent/shell
	if #panes == 1 then
		local p = io.popen("tmux split-window -h -l 40% -P -F '#{pane_id}' 2>/dev/null")
		if p then
			local new_id = p:read("*l")
			p:close()
			return new_id
		end
	end

	-- Look for an agent pane first (claude, gemini, agy, etc.)
	for _, pane in ipairs(panes) do
		if not pane.active and (pane.cmd:match("claude") or pane.cmd:match("gemini") or pane.cmd:match("agy") or pane.cmd:match("agent")) then
			return pane.id
		end
	end

	-- Fall back to any non-active pane in the window
	for _, pane in ipairs(panes) do
		if not pane.active then
			return pane.id
		end
	end

	return nil
end

-- 3. Core function to prompt for question and send code selection to tmux agent
function M.ai_chat_selection()
	local selection = M.get_visual_selection()
	local filetype = vim.bo.filetype ~= "" and vim.bo.filetype or "text"
	local filename = vim.fn.expand("%:t")

	vim.ui.input({ prompt = "AI Agent Prompt (Selected Code): " }, function(user_prompt)
		if not user_prompt or user_prompt:gsub("%s+", "") == "" then
			return
		end

		local full_text
		if selection and selection ~= "" then
			full_text = string.format("%s\n\nContext from `%s` (%s):\n```%s\n%s\n```",
				user_prompt,
				filename,
				filetype,
				filetype,
				selection
			)
		else
			full_text = user_prompt
		end

		local pane_id = M.get_target_tmux_pane()
		if not pane_id then
			-- Fall back to copying prompt to system clipboard if not in tmux
			vim.fn.setreg("+", full_text)
			vim.notify("Copied AI prompt & selection to clipboard (not running in tmux).", vim.log.levels.INFO)
			return
		end

		-- Write prompt to a temp file and send to tmux buffer cleanly
		local tmp = vim.fn.tempname()
		local f = io.open(tmp, "w")
		if f then
			f:write(full_text .. "\n")
			f:close()
			local cmd = string.format(
				"tmux load-buffer %s && tmux paste-buffer -t %s && tmux send-keys -t %s Enter",
				vim.fn.shellescape(tmp),
				vim.fn.shellescape(pane_id),
				vim.fn.shellescape(pane_id)
			)
			vim.fn.system(cmd)
			os.remove(tmp)
			vim.notify("Sent selection & prompt to tmux pane (" .. pane_id .. ").", vim.log.levels.INFO)
		end
	end)
end

local function has_lsp_method(bufnr, method)
	return #vim.lsp.get_clients({ bufnr = bufnr, method = method }) > 0
end

local function copy_selection()
	local selection = M.get_visual_selection()
	if selection ~= "" then
		vim.fn.setreg("+", selection)
	end
end

local function paste_clipboard(context)
	if context.visual then
		vim.cmd([[normal! "+P]])
	else
		vim.cmd([[normal! "+gP]])
	end
end

local function editable_buffer_items(context)
	local items = {}
	if context.visual then
		table.insert(items, { label = "AI Chat Selection", key = "a", action = M.ai_chat_selection })
		table.insert(items, { label = "Cut", key = "x", action = function() vim.cmd([[normal! "+x]]) end })
		table.insert(items, { label = "Copy", key = "y", action = copy_selection })
		table.insert(items, { label = "Paste", key = "p", action = paste_clipboard })
		table.insert(items, { label = "Delete", key = "d", action = function() vim.cmd([[normal! "_x]]) end })
		table.insert(items, { separator = true })
	else
		table.insert(items, {
			label = "Open Target",
			key = "o",
			action = function()
				local target = vim.fn.expand("<cfile>")
				if target ~= "" then
					vim.ui.open(target)
				end
			end,
		})
		if vim.treesitter.highlighter.active[context.bufnr] then
			table.insert(items, { label = "Inspect Syntax", key = "i", action = function() vim.cmd("Inspect") end })
		end
	end

	if has_lsp_method(context.bufnr, "textDocument/definition") then
		table.insert(items, { label = "Go to Definition", key = "g", action = vim.lsp.buf.definition })
	end
	if has_lsp_method(context.bufnr, "textDocument/references") then
		table.insert(items, { label = "Find References", key = "r", action = vim.lsp.buf.references })
	end
	if has_lsp_method(context.bufnr, "textDocument/hover") then
		table.insert(items, { label = "Hover Information", key = "h", action = vim.lsp.buf.hover })
	end
	if has_lsp_method(context.bufnr, "textDocument/codeAction") then
		table.insert(items, { label = "Code Actions", key = "c", action = vim.lsp.buf.code_action })
	end
	if not context.visual and has_lsp_method(context.bufnr, "textDocument/rename") then
		table.insert(items, { label = "Rename Symbol", key = "n", action = vim.lsp.buf.rename })
	end
	if has_lsp_method(context.bufnr, "textDocument/formatting") then
		table.insert(items, { label = "Format Document", key = "f", action = vim.lsp.buf.format })
	end

	if not context.visual then
		table.insert(items, { label = "Show Diagnostics", key = "d", action = vim.diagnostic.open_float })
		table.insert(items, { separator = true })
		table.insert(items, { label = "Paste", key = "p", action = paste_clipboard })
		table.insert(items, { label = "Select All", key = "s", action = function() vim.cmd("normal! ggVG") end })
	end
	return items
end

local function terminal_buffer_items(context)
	local items = {}
	if context.visual then
		table.insert(items, { label = "Copy", key = "y", action = copy_selection })
	end
	table.insert(items, {
		label = "Paste",
		key = "p",
		action = function()
			local channel = vim.bo[context.bufnr].channel
			if channel and channel > 0 then
				vim.api.nvim_chan_send(channel, vim.fn.getreg("+"))
			end
		end,
	})
	table.insert(items, { label = "Close Window", key = "w", action = function() vim.cmd("close") end })
	return items
end

local function generic_buffer_items(context)
	local items = {}
	if context.visual then
		table.insert(items, { label = "Copy", key = "y", action = copy_selection })
	end
	if context.modifiable then
		table.insert(items, { label = "Paste", key = "p", action = paste_clipboard })
		table.insert(items, { label = "Select All", key = "s", action = function() vim.cmd("normal! ggVG") end })
	end
	table.insert(items, { label = "Close Window", key = "w", action = function() vim.cmd("close") end })
	return items
end

function M.setup()
	pcall(vim.cmd, "silent! aunmenu PopUp")

	local context_menu = require("core.context_menu")
	context_menu.register_provider({
		name = "terminal",
		priority = 80,
		match = function(context) return context.buftype == "terminal" end,
		build = function(context) return { items = terminal_buffer_items(context) } end,
	})
	context_menu.register_provider({
		name = "editable-buffer",
		priority = 50,
		match = function(context) return context.buftype == "" and context.modifiable end,
		build = function(context) return { items = editable_buffer_items(context) } end,
	})
	context_menu.register_provider({
		name = "generic-buffer",
		priority = -100,
		match = function() return true end,
		build = function(context) return { items = generic_buffer_items(context) } end,
	})
	context_menu.setup()

	vim.keymap.set("v", "<leader>ai", function()
		M.ai_chat_selection()
	end, { desc = "AI Chat with selection" })
end

M.setup()

return M
