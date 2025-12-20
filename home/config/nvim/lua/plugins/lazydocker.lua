-- lazydocker terminal integration
return {
	{
		"akinsho/toggleterm.nvim",
		version = "*",
		opts = {
			direction = "float",
			float_opts = {
				border = "curved",
			},
		},
		config = function(_, opts)
			require("toggleterm").setup(opts)

			local Terminal = require("toggleterm.terminal").Terminal
			local lazydocker = Terminal:new({
				cmd = "lazydocker",
				hidden = true,
				direction = "float",
				float_opts = {
					border = "curved",
					width = function()
						return math.floor(vim.o.columns * 0.9)
					end,
					height = function()
						return math.floor(vim.o.lines * 0.9)
					end,
				},
			})

			local function toggle_lazydocker()
				lazydocker:toggle()
			end

			require("helpers.keys").map("n", "<leader>dc", toggle_lazydocker, "Docker: lazydocker")
		end,
	},
}
