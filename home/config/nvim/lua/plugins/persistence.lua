-- Per-cwd session restore. Sessions key off the working directory, so
-- re-attaching to a code-{proj} tmux session pulls back the prior buffer
-- and split layout.
return {
	{
		"folke/persistence.nvim",
		event = "BufReadPre",
		opts = {
			dir = vim.fn.stdpath("state") .. "/sessions/",
			options = { "buffers", "curdir", "tabpages", "winsize", "help" },
		},
		keys = {
			{
				"<leader>qs",
				function() require("persistence").load() end,
				desc = "Restore session (cwd)",
			},
			{
				"<leader>ql",
				function() require("persistence").load({ last = true }) end,
				desc = "Restore last session",
			},
			{
				"<leader>qd",
				function() require("persistence").stop() end,
				desc = "Stop session save",
			},
		},
	},
}
