local opts = {
	shiftwidth = 4,
	tabstop = 4,
	expandtab = true,
	wrap = false,
	termguicolors = true,
	number = true,
	relativenumber = true,
	cursorline = true,
	cursorlineopt = "number",
	shell = vim.fn.getenv("SHELL") ~= vim.NIL and vim.fn.getenv("SHELL") or "/bin/zsh",
	splitright = true,
	mouse = "a",
}

-- Set options from table
for opt, val in pairs(opts) do
	vim.o[opt] = val
end

-- Set other options
require("helpers.colorscheme").apply()
require("helpers.colorscheme").setup_auto_sync()

-- Ensure cursor line number matches the theme with high visibility when scrolling
local function setup_cursor_line_nr()
	local hl = vim.api.nvim_get_hl(0, { name = "CursorLineNr", link = false })
	local line_nr = vim.api.nvim_get_hl(0, { name = "LineNr", link = false })

	local fg = hl.fg
	if not fg or (line_nr.fg and fg == line_nr.fg) then
		local accent = vim.api.nvim_get_hl(0, { name = "Keyword", link = false }).fg
			or vim.api.nvim_get_hl(0, { name = "Statement", link = false }).fg
			or vim.api.nvim_get_hl(0, { name = "Special", link = false }).fg
			or vim.api.nvim_get_hl(0, { name = "WarningMsg", link = false }).fg
		if accent then
			fg = accent
		end
	end

	vim.api.nvim_set_hl(0, "CursorLineNr", vim.tbl_extend("force", hl, {
		fg = fg,
		bold = true,
	}))
end

setup_cursor_line_nr()

vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("ThemeCursorLineNr", { clear = true }),
	desc = "Ensure cursor line number is bold and styled with theme accent",
	callback = setup_cursor_line_nr,
})
