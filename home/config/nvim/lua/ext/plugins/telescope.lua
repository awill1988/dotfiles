local telescope = require("telescope")
local actions = require("telescope.actions")

local function select_vertical(open_right)
  return function(prompt_bufnr)
    local previous = vim.o.splitright
    vim.o.splitright = open_right
    actions.select_vertical(prompt_bufnr)
    vim.o.splitright = previous
  end
end

telescope.setup({
  defaults = {
    mappings = {
      i = {
        ["<C-l>"] = select_vertical(true),
        ["<C-h>"] = select_vertical(false),
      },
      n = {
        ["<C-l>"] = select_vertical(true),
        ["<C-h>"] = select_vertical(false),
      },
    },
  },
})
