-- coc.nvim configuration
-- keybindings are centralized in keymaps.lua

-- extensions to auto-install
vim.g.coc_global_extensions = {
  "coc-json",
  "coc-tsserver",
  "coc-pyright",
  "coc-go",
  "coc-rust-analyzer",
  "coc-elixir",
  "coc-solargraph",
  "coc-sh",
  "coc-snippets",
  "coc-powershell",
}

-- helper function for tab completion (used in keymaps.lua)
function _G.check_back_space()
  local col = vim.fn.col(".") - 1
  return col == 0 or vim.fn.getline("."):sub(col, col):match("%s") ~= nil
end

-- helper function for K hover (used in keymaps.lua)
function _G.show_docs()
  local cw = vim.fn.expand("<cword>")
  if vim.fn.index({ "vim", "help" }, vim.bo.filetype) >= 0 then
    vim.api.nvim_command("h " .. cw)
  elseif vim.api.nvim_eval("coc#rpc#ready()") then
    vim.fn.CocActionAsync("doHover")
  else
    vim.api.nvim_command("!" .. vim.o.keywordprg .. " " .. cw)
  end
end

-- highlight symbol under cursor on cursorhold
vim.api.nvim_create_augroup("CocGroup", {})
vim.api.nvim_create_autocmd("CursorHold", {
  group = "CocGroup",
  command = "silent call CocActionAsync('highlight')",
  desc = "highlight symbol under cursor on cursorhold",
})

-- commands
vim.api.nvim_create_user_command("Format", "call CocAction('format')", {})
vim.api.nvim_create_user_command("Fold", "call CocAction('fold', <f-args>)", { nargs = "?" })
vim.api.nvim_create_user_command("OR", "call CocActionAsync('runCommand', 'editor.action.organizeImport')", {})

-- statusline integration
vim.opt.statusline:prepend("%{coc#status()}%{get(b:,'coc_current_function','')}")
