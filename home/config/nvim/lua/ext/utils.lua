local M = {}

-- ============================================================================
-- toggle functions
-- ============================================================================

-- cycle through line number modes: number -> relative -> none -> number
function M.toggle_line_number()
  if vim.wo.number and not vim.wo.relativenumber then
    vim.wo.relativenumber = true
    print("line numbers: relative")
  elseif vim.wo.number and vim.wo.relativenumber then
    vim.wo.number = false
    vim.wo.relativenumber = false
    print("line numbers: disabled")
  else
    vim.wo.number = true
    vim.wo.relativenumber = false
    print("line numbers: absolute")
  end
end

-- toggle line wrapping
function M.toggle_wrap()
  vim.wo.wrap = not vim.wo.wrap
  if vim.wo.wrap then
    print("line wrap: enabled")
  else
    print("line wrap: disabled")
  end
end

-- cycle virtualedit modes: all -> block -> insert -> onemore -> none
function M.cycle_virtualedit()
  local current = vim.o.virtualedit
  local modes = { "", "all", "block", "insert", "onemore" }
  local labels = { "disabled", "all", "block", "insert", "onemore" }

  local idx = 1
  for i, mode in ipairs(modes) do
    if mode == current then
      idx = i
      break
    end
  end

  idx = (idx % #modes) + 1
  vim.o.virtualedit = modes[idx]
  print("virtualedit: " .. labels[idx])
end

-- toggle comment for current line or selection
-- supports: lua, python, sh, bash, vim, json, javascript, c, go
function M.toggle_comment()
  local ft = vim.bo.filetype
  local comment_chars = {
    lua = "--",
    python = "#",
    sh = "#",
    bash = "#",
    zsh = "#",
    vim = '"',
    json = "//",
    javascript = "//",
    typescript = "//",
    c = "//",
    cpp = "//",
    go = "//",
    rust = "//",
    nix = "#",
  }

  local comment = comment_chars[ft] or "#"
  local line = vim.api.nvim_get_current_line()
  local new_line

  -- check if line is already commented
  if line:match("^%s*" .. vim.pesc(comment)) then
    -- uncomment: remove comment chars and one following space if present
    new_line = line:gsub("^(%s*)" .. vim.pesc(comment) .. "%s?", "%1", 1)
  else
    -- comment: add comment chars after leading whitespace
    new_line = line:gsub("^(%s*)", "%1" .. comment .. " ", 1)
  end

  vim.api.nvim_set_current_line(new_line)
end

-- ============================================================================
-- utility functions
-- ============================================================================

-- jump to last editing position when opening a file
function M.last_cursor_pos()
  local mark = vim.api.nvim_buf_get_mark(0, '"')
  local line_count = vim.api.nvim_buf_line_count(0)

  if mark[1] > 0 and mark[1] <= line_count then
    vim.api.nvim_win_set_cursor(0, mark)
  end
end

-- auto-adjust line number column width based on buffer size
function M.set_number_width()
  if vim.wo.number or vim.wo.relativenumber then
    local line_count = vim.api.nvim_buf_line_count(0)
    local width = #tostring(line_count) + 1
    vim.wo.numberwidth = math.max(4, width)
  end
end

-- show current mode/state in a floating window
function M.show_mode_popup()
  local mode_map = {
    n = "NORMAL",
    i = "INSERT",
    v = "VISUAL",
    V = "V-LINE",
    ["\22"] = "V-BLOCK",
    c = "COMMAND",
    s = "SELECT",
    S = "S-LINE",
    ["\19"] = "S-BLOCK",
    R = "REPLACE",
    r = "PROMPT",
    ["!"] = "SHELL",
    t = "TERMINAL",
  }

  local mode = vim.api.nvim_get_mode().mode
  local mode_name = mode_map[mode] or "UNKNOWN"

  local info = {
    "mode: " .. mode_name,
    "paste: " .. (vim.o.paste and "on" or "off"),
    "wrap: " .. (vim.wo.wrap and "on" or "off"),
    "spell: " .. (vim.wo.spell and "on" or "off"),
  }

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, info)

  local width = 0
  for _, line in ipairs(info) do
    width = math.max(width, #line)
  end

  local opts = {
    relative = "cursor",
    width = width + 2,
    height = #info,
    row = 1,
    col = 0,
    style = "minimal",
    border = "rounded",
  }

  local win = vim.api.nvim_open_win(buf, false, opts)

  -- auto-close after 3 seconds
  vim.defer_fn(function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, 3000)
end

-- ============================================================================
-- autocommands setup
-- ============================================================================

function M.setup_autocommands()
  local augroup = vim.api.nvim_create_augroup("ext_utils", { clear = true })

  -- jump to last editing position
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = augroup,
    callback = M.last_cursor_pos,
  })

  -- auto-adjust number width
  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = M.set_number_width,
  })
end

-- ============================================================================
-- global functions for vim commands
-- ============================================================================

-- make toggle functions available globally for commands/keymaps
_G.toggle_line_number = M.toggle_line_number
_G.toggle_wrap = M.toggle_wrap
_G.cycle_virtualedit = M.cycle_virtualedit
_G.toggle_comment = M.toggle_comment
_G.show_mode_popup = M.show_mode_popup

return M
