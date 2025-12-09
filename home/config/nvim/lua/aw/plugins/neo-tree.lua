require("neo-tree").setup({
  close_if_last_window = true,
  filesystem = {
    follow_current_file = { enabled = true },
    bind_to_cwd = true,
    use_libuv_file_watcher = true,
    filtered_items = {
      hide_dotfiles = false,
      hide_gitignored = true,
      hide_by_name = { ".git" },
      never_show = { ".git" },
    },
  },
})

local function close_extra_neotree_windows()
  local tree_wins = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "neo-tree" then
      local position = vim.api.nvim_win_get_position(win)
      table.insert(tree_wins, { win = win, col = position[2] or 0 })
    end
  end

  if #tree_wins <= 1 then
    return
  end

  table.sort(tree_wins, function(a, b)
    return a.col < b.col
  end)

  for idx = 2, #tree_wins do
    pcall(vim.api.nvim_win_close, tree_wins[idx].win, true)
  end
  if vim.api.nvim_win_is_valid(tree_wins[1].win) then
    pcall(vim.api.nvim_set_current_win, tree_wins[1].win)
  end
end

vim.api.nvim_create_autocmd("BufWinEnter", {
  pattern = "neo-tree*",
  callback = close_extra_neotree_windows,
})
