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

-- Set background polarity matching Stylix / environment baseline
local polarity = os.getenv("NVIM_THEME_POLARITY") or "dark"
vim.opt.background = polarity

-- Colorscheme is driven by stylix (home/theme.nix). The plugin specs in
-- plugins/themes.lua still ship the implementations; stylix activates the
-- one matching the active base16 scheme. The fallback below only fires if
-- stylix hasn't initialised yet (e.g., running nvim outside the managed env).
local colorscheme = vim.g.colors_name or get_if_available("catppuccin")

return colorscheme
