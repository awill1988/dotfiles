local ok, bufferline = pcall(require, "bufferline")
if not ok then
  return
end

-- smarter buffer close that doesn't quit vim
local function smart_close(bufnum)
  local buffers = vim.fn.getbufinfo({ buflisted = 1 })

  if #buffers <= 1 then
    -- last buffer - create new empty buffer first
    vim.cmd("enew")
  else
    -- multiple buffers - switch to another buffer first if closing current
    if vim.fn.bufnr() == bufnum then
      -- find another buffer to switch to
      for _, buf in ipairs(buffers) do
        if buf.bufnr ~= bufnum then
          vim.cmd("buffer " .. buf.bufnr)
          break
        end
      end
    end
  end

  -- safely delete the buffer
  pcall(vim.cmd, "bdelete! " .. bufnum)
end

bufferline.setup({
  options = {
    mode = "buffers",
    themable = true,
    numbers = "ordinal",
    close_command = function(bufnum) smart_close(bufnum) end,
    right_mouse_command = function(bufnum) smart_close(bufnum) end,
    left_mouse_command = "buffer %d",
    middle_mouse_command = nil,
    indicator = {
      icon = "▎",
      style = "icon",
    },
    buffer_close_icon = "×",
    modified_icon = "●",
    close_icon = "",
    left_trunc_marker = "",
    right_trunc_marker = "",
    max_name_length = 18,
    max_prefix_length = 15,
    truncate_names = true,
    tab_size = 18,
    diagnostics = "coc",
    diagnostics_update_in_insert = false,
    offsets = {
      {
        filetype = "neo-tree",
        text = "File Explorer",
        text_align = "left",
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
  },
})
