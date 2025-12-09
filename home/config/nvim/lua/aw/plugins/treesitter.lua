local xdg_data = vim.env.XDG_DATA_HOME
local parser_install_dir = (xdg_data and #xdg_data > 0 and xdg_data or vim.fn.stdpath("data")) .. "/nvim/ts-parsers"
vim.fn.mkdir(parser_install_dir, "p")

require("nvim-treesitter.configs").setup({
  ensure_installed = {
    "lua",
    "vim",
    "vimdoc",
    "bash",
    "python",
    "javascript",
    "typescript",
    "go",
    "rust",
    "elixir",
    "ruby",
    "json",
    "yaml",
  },
  highlight = { enable = true },
  indent = { enable = true },
  parser_install_dir = parser_install_dir,
  auto_install = false,
})
