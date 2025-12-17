local ok, bufferline = pcall(require, "bufferline")
if not ok then
  return
end

-- close buffer without closing window
local function close_buffer(bufnum)
  bufnum = bufnum or vim.api.nvim_get_current_buf()

  -- get list of windows showing this buffer
  local windows = vim.fn.win_findbuf(bufnum)

  -- get list of all listed buffers
  local buffers = vim.fn.getbufinfo({ buflisted = 1 })

  -- find alternative buffer to show
  local alt_buf = nil
  for _, buf in ipairs(buffers) do
    if buf.bufnr ~= bufnum then
      alt_buf = buf.bufnr
      break
    end
  end

  -- switch to alternative buffer in all windows showing this buffer
  if alt_buf then
    for _, win in ipairs(windows) do
      vim.api.nvim_win_set_buf(win, alt_buf)
    end
  end

  -- delete the buffer
  vim.api.nvim_buf_delete(bufnum, { force = false })
end

vim.api.nvim_create_user_command("BufClose", function(opts)
  close_buffer(tonumber(opts.args))
end, { nargs = "?" })

bufferline.setup({
  options = {
    mode = "buffers",
    themable = true,
    numbers = "none",
    close_command = function(bufnum)
      close_buffer(bufnum)
    end,
    right_mouse_command = function(bufnum)
      close_buffer(bufnum)
    end,
    left_mouse_command = "buffer %d",
    middle_mouse_command = nil,
    indicator = {
      icon = "▎",
      style = "icon",
    },
    buffer_close_icon = "󰅖",
    modified_icon = "●",
    close_icon = "",
    left_trunc_marker = "",
    right_trunc_marker = "",
    max_name_length = 18,
    max_prefix_length = 15,
    truncate_names = true,
    tab_size = 18,
    diagnostics = "nvim_lsp",
    diagnostics_update_in_insert = false,
    diagnostics_indicator = function(count, level, diagnostics_dict, context)
      local icon = level:match("error") and " " or " "
      return " " .. icon .. count
    end,
    offsets = {
      {
        filetype = "neo-tree",
        text = "File Explorer",
        text_align = "center",
        separator = true,
      },
    },
    color_icons = true,
    show_buffer_icons = true,
    show_buffer_close_icons = true,
    show_close_icon = true,
    show_tab_indicators = true,
    show_duplicate_prefix = true,
    persist_buffer_sort = true,
    separator_style = "thin",
    enforce_regular_tabs = false,
    always_show_bufferline = true,
    hover = {
      enabled = true,
      delay = 200,
      reveal = { "close" },
    },
    sort_by = "insert_after_current",
  },
})
