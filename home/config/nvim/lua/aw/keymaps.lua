local map = vim.keymap.set

map("n", "<leader>e", "<cmd>Neotree left reveal<CR>", { silent = true, desc = "file explorer" })
map("n", "<leader>ff", "<cmd>Telescope find_files<CR>", { silent = true, desc = "find files" })
map("n", "<leader>fg", "<cmd>Telescope live_grep<CR>", { silent = true, desc = "live grep" })

local function focus_neo_tree()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "neo-tree" then
      pcall(vim.api.nvim_set_current_win, win)
      return
    end
  end
end

local function bufremove(force)
  require("mini.bufremove").delete(0, force)
  focus_neo_tree()
end

map("n", "ZQ", function() bufremove(true) end, { silent = true, desc = "force close buffer, keep layout" })

-- dampen accidental drags: ignore drag motion, keep clicks/double-click intact
map({ "n", "v", "i" }, "<LeftDrag>", "<Nop>", { silent = true })
