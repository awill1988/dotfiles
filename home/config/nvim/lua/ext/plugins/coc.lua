-- coc.nvim configuration
-- extensions to auto-install (coc will handle this on first run)
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

-- use <tab> for trigger completion and navigate to next complete item
function _G.check_back_space()
  local col = vim.fn.col(".") - 1
  return col == 0 or vim.fn.getline("."):sub(col, col):match("%s") ~= nil
end

local opts = { silent = true, noremap = true, expr = true, replace_keycodes = false }
vim.keymap.set("i", "<TAB>", 'coc#pum#visible() ? coc#pum#next(1) : v:lua.check_back_space() ? "<TAB>" : coc#refresh()', opts)
vim.keymap.set("i", "<S-TAB>", [[coc#pum#visible() ? coc#pum#prev(1) : "\<C-h>"]], opts)

-- make <CR> to accept selected completion item or notify coc.nvim to format
vim.keymap.set("i", "<cr>", [[coc#pum#visible() ? coc#pum#confirm() : "\<C-g>u\<CR>\<c-r>=coc#on_enter()\<CR>"]], opts)

-- use `[g` and `]g` to navigate diagnostics
vim.keymap.set("n", "[g", "<Plug>(coc-diagnostic-prev)", { silent = true })
vim.keymap.set("n", "]g", "<Plug>(coc-diagnostic-next)", { silent = true })

-- goto code navigation
vim.keymap.set("n", "gd", "<Plug>(coc-definition)", { silent = true })
vim.keymap.set("n", "gy", "<Plug>(coc-type-definition)", { silent = true })
vim.keymap.set("n", "gi", "<Plug>(coc-implementation)", { silent = true })
vim.keymap.set("n", "gr", "<Plug>(coc-references)", { silent = true })

-- use K to show documentation in preview window
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
vim.keymap.set("n", "K", "<CMD>lua _G.show_docs()<CR>", { silent = true })

-- highlight symbol under cursor on cursorhold
vim.api.nvim_create_augroup("CocGroup", {})
vim.api.nvim_create_autocmd("CursorHold", {
  group = "CocGroup",
  command = "silent call CocActionAsync('highlight')",
  desc = "Highlight symbol under cursor on CursorHold",
})

-- symbol renaming
vim.keymap.set("n", "<leader>rn", "<Plug>(coc-rename)", { silent = true })

-- formatting selected code
vim.keymap.set("x", "<leader>f", "<Plug>(coc-format-selected)", { silent = true })
vim.keymap.set("n", "<leader>f", "<Plug>(coc-format-selected)", { silent = true })

-- applying code actions to the selected region
vim.keymap.set("x", "<leader>a", "<Plug>(coc-codeaction-selected)", { silent = true })
vim.keymap.set("n", "<leader>a", "<Plug>(coc-codeaction-selected)", { silent = true })

-- remap keys for applying code actions at cursor position
vim.keymap.set("n", "<leader>ac", "<Plug>(coc-codeaction-cursor)", { silent = true })
-- remap keys for apply code actions affect whole buffer
vim.keymap.set("n", "<leader>as", "<Plug>(coc-codeaction-source)", { silent = true })
-- apply most preferred quickfix action on the current line
vim.keymap.set("n", "<leader>qf", "<Plug>(coc-fix-current)", { silent = true })

-- remap keys for applying refactor code actions
vim.keymap.set("n", "<leader>re", "<Plug>(coc-codeaction-refactor)", { silent = true })
vim.keymap.set("x", "<leader>r", "<Plug>(coc-codeaction-refactor-selected)", { silent = true })
vim.keymap.set("n", "<leader>r", "<Plug>(coc-codeaction-refactor-selected)", { silent = true })

-- run code lens action on the current line
vim.keymap.set("n", "<leader>cl", "<Plug>(coc-codelens-action)", { silent = true })

-- map function and class text objects
vim.keymap.set("x", "if", "<Plug>(coc-funcobj-i)", { silent = true })
vim.keymap.set("o", "if", "<Plug>(coc-funcobj-i)", { silent = true })
vim.keymap.set("x", "af", "<Plug>(coc-funcobj-a)", { silent = true })
vim.keymap.set("o", "af", "<Plug>(coc-funcobj-a)", { silent = true })
vim.keymap.set("x", "ic", "<Plug>(coc-classobj-i)", { silent = true })
vim.keymap.set("o", "ic", "<Plug>(coc-classobj-i)", { silent = true })
vim.keymap.set("x", "ac", "<Plug>(coc-classobj-a)", { silent = true })
vim.keymap.set("o", "ac", "<Plug>(coc-classobj-a)", { silent = true })

-- remap <C-f> and <C-b> to scroll float windows/popups
---@diagnostic disable-next-line: redefined-local
local opts_scroll = { silent = true, nowait = true, expr = true }
vim.keymap.set("n", "<C-f>", 'coc#float#has_scroll() ? coc#float#scroll(1) : "<C-f>"', opts_scroll)
vim.keymap.set("n", "<C-b>", 'coc#float#has_scroll() ? coc#float#scroll(0) : "<C-b>"', opts_scroll)
vim.keymap.set("i", "<C-f>", 'coc#float#has_scroll() ? "<c-r>=coc#float#scroll(1)<cr>" : "<Right>"', opts_scroll)
vim.keymap.set("i", "<C-b>", 'coc#float#has_scroll() ? "<c-r>=coc#float#scroll(0)<cr>" : "<Left>"', opts_scroll)
vim.keymap.set("v", "<C-f>", 'coc#float#has_scroll() ? coc#float#scroll(1) : "<C-f>"', opts_scroll)
vim.keymap.set("v", "<C-b>", 'coc#float#has_scroll() ? coc#float#scroll(0) : "<C-b>"', opts_scroll)

-- use CTRL-S for selections ranges
vim.keymap.set("n", "<C-s>", "<Plug>(coc-range-select)", { silent = true })
vim.keymap.set("x", "<C-s>", "<Plug>(coc-range-select)", { silent = true })

-- add `:Format` command to format current buffer
vim.api.nvim_create_user_command("Format", "call CocAction('format')", {})

-- add `:Fold` command to fold current buffer
vim.api.nvim_create_user_command("Fold", "call CocAction('fold', <f-args>)", { nargs = "?" })

-- add `:OR` command for organize imports of the current buffer
vim.api.nvim_create_user_command("OR", "call CocActionAsync('runCommand', 'editor.action.organizeImport')", {})

-- add (Neo)Vim's native statusline support
vim.opt.statusline:prepend("%{coc#status()}%{get(b:,'coc_current_function','')}")

-- namespace coc list/navigation under <leader>c*
vim.keymap.set("n", "<leader>cd", ":<C-u>CocList diagnostics<cr>", { silent = true, nowait = true })
vim.keymap.set("n", "<leader>ce", ":<C-u>CocList extensions<cr>", { silent = true, nowait = true })
vim.keymap.set("n", "<leader>cc", ":<C-u>CocList commands<cr>", { silent = true, nowait = true })
vim.keymap.set("n", "<leader>co", ":<C-u>CocList outline<cr>", { silent = true, nowait = true })
vim.keymap.set("n", "<leader>cs", ":<C-u>CocList -I symbols<cr>", { silent = true, nowait = true })
vim.keymap.set("n", "<leader>cj", ":<C-u>CocNext<cr>", { silent = true, nowait = true })
vim.keymap.set("n", "<leader>ck", ":<C-u>CocPrev<cr>", { silent = true, nowait = true })
vim.keymap.set("n", "<leader>cr", ":<C-u>CocListResume<cr>", { silent = true, nowait = true })
