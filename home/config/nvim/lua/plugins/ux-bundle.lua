-- Curated UX additions: signature hints, TODOs, motion, autopairs.
-- fidget.nvim and vim-illuminate are already declared as lspconfig
-- dependencies, so they live there.
return {
	{
		"ray-x/lsp_signature.nvim",
		event = "LspAttach",
		opts = {
			hint_enable = false,
			handler_opts = { border = "rounded" },
			toggle_key = "<C-s>",
		},
		config = function(_, opts)
			require("lsp_signature").setup(opts)
		end,
	},

	{
		"folke/todo-comments.nvim",
		event = "VimEnter",
		dependencies = { "nvim-lua/plenary.nvim" },
		opts = {},
		keys = {
			{ "<leader>st", "<cmd>TodoTelescope<cr>",                 desc = "TODOs" },
			{ "]t",         function() require("todo-comments").jump_next() end, desc = "Next TODO" },
			{ "[t",         function() require("todo-comments").jump_prev() end, desc = "Prev TODO" },
		},
	},

	{
		-- leap.nvim moved from GitHub (ggandor/leap.nvim) to Codeberg.
		-- lazy.nvim accepts a url= override that bypasses the github short form.
		url = "https://codeberg.org/andyg/leap.nvim",
		name = "leap.nvim",
		event = "VeryLazy",
		dependencies = { "tpope/vim-repeat" },
		config = function()
			require("leap").add_default_mappings()
		end,
	},

	{
		"windwp/nvim-autopairs",
		event = "InsertEnter",
		opts = {
			check_ts = true,
			fast_wrap = {},
		},
		config = function(_, opts)
			require("nvim-autopairs").setup(opts)
			-- bridge into nvim-cmp so completing a function adds parens
			local ok_cmp, cmp = pcall(require, "cmp")
			if ok_cmp then
				local cmp_autopairs = require("nvim-autopairs.completion.cmp")
				cmp.event:on("confirm_done", cmp_autopairs.on_confirm_done())
			end
		end,
	},
}
