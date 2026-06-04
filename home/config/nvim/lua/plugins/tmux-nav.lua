-- Seamless Ctrl-h/j/k/l navigation between nvim splits and tmux panes.
-- Default mappings (<C-h/j/k/l>) replace the manual <C-w> mappings in
-- core/keymaps.lua. Paired tmux bindings live in programs.tmux.extraConfig.
return {
	{
		"christoomey/vim-tmux-navigator",
		lazy = false,
	},
}
