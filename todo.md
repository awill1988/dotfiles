# todo

- add a mouse gutter click mapping to toggle dap breakpoints

```lua
vim.opt.mouse = "a"

vim.keymap.set("n", "<LeftMouse>", function()
	local mouse_pos = vim.fn.getmousepos()
	if mouse_pos.winid == 0 or mouse_pos.line <= 0 then
		return
	end

	local win_info = vim.fn.getwininfo(mouse_pos.winid)[1]
	if mouse_pos.wincol <= win_info.textoff then
		vim.api.nvim_set_current_win(mouse_pos.winid)
		vim.api.nvim_win_set_cursor(mouse_pos.winid, { mouse_pos.line, 0 })

		local ok, dap = pcall(require, "dap")
		if ok then
			dap.toggle_breakpoint()
		end
		return
	end

	vim.api.nvim_feedkeys(
		vim.api.nvim_replace_termcodes("<LeftMouse>", true, false, true),
		"n",
		true
	)
end, { silent = true, noremap = true })
```
