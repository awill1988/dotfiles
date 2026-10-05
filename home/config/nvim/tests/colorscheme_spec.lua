local colorscheme = require("helpers.colorscheme")

local palette = {
	"#282828",
	"#3c3836",
	"#504945",
	"#665c54",
	"#bdae93",
	"#d5c4a1",
	"#ebdbb2",
	"#fbf1c7",
	"#fb4934",
	"#fe8019",
	"#fabd2f",
	"#b8bb26",
	"#8ec07c",
	"#83a598",
	"#d3869b",
	"#d65d0e",
}

for index, color in ipairs(palette) do
	vim.env[string.format("NVIM_THEME_BASE%02X", index - 1)] = color
end
vim.env.ACTIVE_THEME = "gruvbox-dark"
vim.env.NVIM_THEME_POLARITY = "dark"

vim.g.colors_name = nil
colorscheme.apply()

local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
assert(vim.o.background == "dark", "configured polarity was not applied")
assert(vim.g.colors_name == "gruvbox-dark", "managed theme name was not applied")
assert(normal.bg == tonumber("282828", 16), "managed background color was not applied")

print("colorscheme-tests-ok")
