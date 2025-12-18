-- ============================================================================
-- custom commands inspired by kennypete's .vimrc
-- ============================================================================

-- DiffOrig: compare buffer against original file
vim.api.nvim_create_user_command("DiffOrig", function()
  local filetype = vim.bo.filetype
  vim.cmd("vert new")
  vim.bo.buftype = "nofile"
  vim.cmd("read ++edit #")
  vim.cmd("0d_")
  vim.bo.filetype = filetype
  vim.cmd("diffthis")
  vim.cmd("wincmd p")
  vim.cmd("diffthis")
end, { desc = "compare buffer against original file" })

-- Bod: delete all buffers except current or specified
vim.api.nvim_create_user_command("Bod", function(opts)
  local target = tonumber(opts.args) or vim.api.nvim_get_current_buf()
  local buffers = vim.api.nvim_list_bufs()

  for _, buf in ipairs(buffers) do
    if buf ~= target and vim.api.nvim_buf_is_loaded(buf) then
      vim.api.nvim_buf_delete(buf, { force = false })
    end
  end
end, { nargs = "?", desc = "delete all buffers except current or specified" })

-- Bow: wipe all buffers except current or specified
vim.api.nvim_create_user_command("Bow", function(opts)
  local target = tonumber(opts.args) or vim.api.nvim_get_current_buf()
  local buffers = vim.api.nvim_list_bufs()

  for _, buf in ipairs(buffers) do
    if buf ~= target and vim.api.nvim_buf_is_loaded(buf) then
      vim.api.nvim_buf_delete(buf, { force = true, unload = false })
    end
  end
end, { nargs = "?", desc = "wipe all buffers except current or specified" })

-- B: navigate to buffer by number in any tab
vim.api.nvim_create_user_command("B", function(opts)
  local bufnr = tonumber(opts.args)
  if not bufnr then
    print("error: buffer number required")
    return
  end

  if not vim.api.nvim_buf_is_valid(bufnr) then
    print("error: invalid buffer number")
    return
  end

  -- check if buffer is already visible in a window
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      vim.api.nvim_set_current_win(win)
      return
    end
  end

  -- otherwise switch to it in current window
  vim.api.nvim_set_current_buf(bufnr)
end, { nargs = 1, desc = "navigate to buffer in any tab" })

-- LLP: populate location list with pattern matches
vim.api.nvim_create_user_command("LLP", function(opts)
  local pattern = opts.args
  if pattern == "" then
    print("error: pattern required")
    return
  end

  vim.fn.setloclist(0, {})
  vim.cmd("lvimgrep /" .. vim.fn.escape(pattern, "/") .. "/gj %")
  vim.cmd("lwindow")
end, { nargs = 1, desc = "populate location list for pattern matches" })

-- SetTextWidth: set textwidth and matching colorcolumn
vim.api.nvim_create_user_command("SetTextWidth", function(opts)
  local width = tonumber(opts.args)
  if not width or width < 0 then
    print("error: invalid width")
    return
  end

  vim.bo.textwidth = width
  if width > 0 then
    vim.wo.colorcolumn = tostring(width + 2)
    print("textwidth=" .. width .. ", colorcolumn=" .. (width + 2))
  else
    vim.wo.colorcolumn = ""
    print("textwidth disabled")
  end
end, { nargs = 1, desc = "set textwidth and colorcolumn" })

-- ClearTextWidth: clear textwidth and colorcolumn
vim.api.nvim_create_user_command("ClearTextWidth", function()
  vim.bo.textwidth = 0
  vim.wo.colorcolumn = ""
  print("textwidth and colorcolumn cleared")
end, { desc = "clear textwidth and colorcolumn" })

-- Redirr: redirect command output to register p
vim.api.nvim_create_user_command("Redirr", function(opts)
  local cmd = opts.args
  if cmd == "" then
    print("error: command required")
    return
  end

  local output = vim.fn.execute(cmd)
  vim.fn.setreg("p", output)
  print("output saved to register p")
end, { nargs = "+", desc = "redirect command output to register p" })

-- ReloadConfig: reload neovim configuration
vim.api.nvim_create_user_command("ReloadConfig", function()
  for name, _ in pairs(package.loaded) do
    if name:match("^ext") then
      package.loaded[name] = nil
    end
  end
  dofile(vim.env.MYVIMRC)
  print("configuration reloaded")
end, { desc = "reload neovim configuration" })
