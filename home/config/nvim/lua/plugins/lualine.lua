-- Fancier statusline
return {
	"nvim-lualine/lualine.nvim",
	config = function()
		require("lualine").setup({
			options = {
				icons_enabled = true,
				theme = "auto",
				component_separators = "|",
				section_separators = "",
			},
			sections = {
				lualine_x = {
					{
						function()
							return require("agent-stream").statusline()
						end,
						cond = function()
							return require("agent-stream").statusline() ~= ""
						end,
					},
				},
			},
		})
	end,
}
