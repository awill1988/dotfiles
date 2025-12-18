return {
	{
		"folke/which-key.nvim",
		config = function()
			local wk = require("which-key")
			wk.setup()
			wk.add({
				{ "<leader>f", group = "file" },
				{ "<leader>d", group = "delete/close" },
				{ "<leader>q", group = "quit" },
				{ "<leader>s", group = "search" },
				{ "<leader>l", group = "lsp" },
				{ "<leader>u", group = "ui" },
				{ "<leader>b", group = "debugging" },
				{ "<leader>g", group = "git" },
			}, { mode = "n" })
		end
	}
}
