-- Fetch and setup colorscheme if available, otherwise just return 'default'
-- This should prevent Neovim from complaining about missing colorschemes on first boot
local function get_if_available(name, opts)
	local lua_ok, colorscheme = pcall(require, name)
	if lua_ok then
		colorscheme.setup(opts)
		return name
	end

	local vim_ok, _ = pcall(vim.cmd.colorscheme, name)
	if vim_ok then
		return name
	end

	return "default"
end

-- Colorscheme is driven by stylix (home/theme.nix). The plugin specs in
-- plugins/themes.lua still ship the implementations; stylix activates the
-- one matching the active base16 scheme. The fallback below only fires if
-- stylix hasn't initialised yet (e.g., running nvim outside the managed env).
local M = {}

local function get_managed_palette()
	local palette = {}
	for index = 0, 15 do
		local suffix = string.format("%02X", index)
		local color = os.getenv("NVIM_THEME_BASE" .. suffix)
		if not color then
			return nil
		end
		palette["base" .. suffix] = color
	end
	return palette
end

function M.apply()
	vim.opt.background = os.getenv("NVIM_THEME_POLARITY") or "dark"

	local palette = get_managed_palette()
	if palette then
		local active_theme = os.getenv("ACTIVE_THEME") or "stylix"
		local base16_path = os.getenv("NVIM_THEME_BASE16_PATH")
		if base16_path then
			vim.opt.runtimepath:prepend(base16_path)
		end
		require("mini.base16").setup({ palette = palette })
		vim.g.colors_name = active_theme
		vim.api.nvim_exec_autocmds("ColorScheme", { pattern = active_theme, modeline = false })
		return
	end

	local colorscheme = vim.g.colors_name or get_if_available("catppuccin")
	vim.cmd.colorscheme(colorscheme)
end

return M
