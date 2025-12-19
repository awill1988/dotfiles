-- Nicer filetree than NetRW
return {
	{
		"nvim-neo-tree/neo-tree.nvim",
		branch = "v3.x",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-tree/nvim-web-devicons",
			"MunifTanjim/nui.nvim",
		},
		config = function()
			require("neo-tree").setup({
				filesystem = {
					follow_current_file = {
						enabled = true, -- track current file and reveal in tree
					},
					use_libuv_file_watcher = true, -- auto-refresh on file changes
				},
			})
			require("helpers.keys").map(
				{ "n", "v" },
				"<leader>e",
				"<cmd>Neotree toggle<cr>",
				"Toggle file explorer"
			)
		end,
	},
}
