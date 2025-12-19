-- Start screen with quick actions
return {
	{
		"nvimdev/dashboard-nvim",
		event = "VimEnter",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		config = function()
			local dashboard = require("dashboard")
			dashboard.setup({
				theme = "hyper",
				config = {
					week_header = {
						enable = true,
					},
					shortcut = {
						{ desc = " Find files", group = "Label", action = "Telescope find_files", key = "f" },
						{ desc = " Live grep", group = "DiagnosticHint", action = "Telescope live_grep", key = "g" },
						{ desc = " Recent files", group = "Number", action = "Telescope oldfiles", key = "r" },
						{ desc = " New file", group = "String", action = "ene | startinsert", key = "n" },
						{ desc = " Config", group = "@property", action = "e ~/.config/nvim/init.lua", key = "c" },
						{ desc = " Quit", group = "Error", action = "qa", key = "q" },
					},
				},
			})
		end,
	},
}
