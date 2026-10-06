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
							local ok, stream = pcall(require, "agent-stream")
							if ok and type(stream.statusline) == "function" then
								return stream.statusline()
							end
							return ""
						end,
						cond = function()
							local ok, stream = pcall(require, "agent-stream")
							return ok and type(stream.statusline) == "function" and stream.statusline() ~= ""
						end,
					},
				},
			},
		})
	end,
}
