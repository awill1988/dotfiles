local map = vim.keymap.set

-- ============================================================================
-- basic operations (keep vim defaults)
-- ============================================================================

-- save file
map("n", "<c-s>", "<cmd>w<cr>", { silent = true, desc = "save file" })
map("i", "<c-s>", "<esc><cmd>w<cr>", { silent = true, desc = "save file" })

-- dampen accidental drags
map({ "n", "v", "i" }, "<LeftDrag>", "<Nop>", { silent = true })

-- better window navigation
map("n", "<c-h>", "<c-w>h", { desc = "focus left window" })
map("n", "<c-j>", "<c-w>j", { desc = "focus down window" })
map("n", "<c-k>", "<c-w>k", { desc = "focus up window" })
map("n", "<c-l>", "<c-w>l", { desc = "focus right window" })

-- ============================================================================
-- bracket navigation (prev/next)
-- ============================================================================

-- buffers
map("n", "[b", "<cmd>bprevious<cr>", { silent = true, desc = "previous buffer" })
map("n", "]b", "<cmd>bnext<cr>", { silent = true, desc = "next buffer" })

-- diagnostics (coc)
map("n", "[d", "<Plug>(coc-diagnostic-prev)", { silent = true, desc = "previous diagnostic" })
map("n", "]d", "<Plug>(coc-diagnostic-next)", { silent = true, desc = "next diagnostic" })

-- ale errors
map("n", "[a", "<Plug>(ale_previous_wrap)", { silent = true, desc = "previous ale error" })
map("n", "]a", "<Plug>(ale_next_wrap)", { silent = true, desc = "next ale error" })

-- git hunks
map("n", "[g", "<cmd>Gitsigns prev_hunk<cr>", { silent = true, desc = "previous git hunk" })
map("n", "]g", "<cmd>Gitsigns next_hunk<cr>", { silent = true, desc = "next git hunk" })

-- quickfix
map("n", "[q", "<cmd>cprev<cr>", { silent = true, desc = "previous quickfix" })
map("n", "]q", "<cmd>cnext<cr>", { silent = true, desc = "next quickfix" })

-- ============================================================================
-- leader f: find
-- ============================================================================

map("n", "<leader>ff", "<cmd>Telescope find_files<cr>", { silent = true, desc = "find files" })
map("n", "<leader>fg", "<cmd>Telescope live_grep<cr>", { silent = true, desc = "grep files" })
map("n", "<leader>fb", "<cmd>Telescope buffers<cr>", { silent = true, desc = "find buffers" })
map("n", "<leader>fr", "<cmd>Telescope oldfiles<cr>", { silent = true, desc = "recent files" })
map("n", "<leader>fh", "<cmd>Telescope help_tags<cr>", { silent = true, desc = "help tags" })

-- ============================================================================
-- leader g: git
-- ============================================================================

map("n", "<leader>gs", "<cmd>Gitsigns stage_hunk<cr>", { silent = true, desc = "stage hunk" })
map("n", "<leader>gr", "<cmd>Gitsigns reset_hunk<cr>", { silent = true, desc = "reset hunk" })
map("n", "<leader>gS", "<cmd>Gitsigns stage_buffer<cr>", { silent = true, desc = "stage buffer" })
map("n", "<leader>gu", "<cmd>Gitsigns undo_stage_hunk<cr>", { silent = true, desc = "undo stage hunk" })
map("n", "<leader>gp", "<cmd>Gitsigns preview_hunk<cr>", { silent = true, desc = "preview hunk" })
map("n", "<leader>gb", "<cmd>Gitsigns blame_line<cr>", { silent = true, desc = "blame line" })
map("n", "<leader>gd", "<cmd>Gitsigns diffthis<cr>", { silent = true, desc = "diff this" })

-- ============================================================================
-- leader c: code (lsp/coc)
-- ============================================================================

-- navigation
map("n", "<leader>cd", "<Plug>(coc-definition)", { silent = true, desc = "go to definition" })
map("n", "<leader>ct", "<Plug>(coc-type-definition)", { silent = true, desc = "go to type definition" })
map("n", "<leader>ci", "<Plug>(coc-implementation)", { silent = true, desc = "go to implementation" })
map("n", "<leader>cr", "<Plug>(coc-references)", { silent = true, desc = "find references" })

-- actions
map("n", "<leader>ca", "<Plug>(coc-codeaction-cursor)", { silent = true, desc = "code action" })
map("x", "<leader>ca", "<Plug>(coc-codeaction-selected)", { silent = true, desc = "code action" })
map("n", "<leader>cf", "<Plug>(coc-format-selected)", { silent = true, desc = "format" })
map("x", "<leader>cf", "<Plug>(coc-format-selected)", { silent = true, desc = "format" })
map("n", "<leader>cn", "<Plug>(coc-rename)", { silent = true, desc = "rename" })
map("n", "<leader>cq", "<Plug>(coc-fix-current)", { silent = true, desc = "quickfix" })
map("n", "<leader>cl", "<Plug>(coc-codelens-action)", { silent = true, desc = "code lens" })

-- lists
map("n", "<leader>cs", "<cmd>CocList symbols<cr>", { silent = true, desc = "symbols" })
map("n", "<leader>co", "<cmd>CocList outline<cr>", { silent = true, desc = "outline" })
map("n", "<leader>cc", "<cmd>CocList commands<cr>", { silent = true, desc = "commands" })

-- diagnostics
map("n", "<leader>cx", "<cmd>CocList diagnostics<cr>", { silent = true, desc = "diagnostics" })

-- hover documentation (keep K standard)
map("n", "K", "<cmd>lua _G.show_docs()<cr>", { silent = true, desc = "show documentation" })

-- ============================================================================
-- leader t: toggle
-- ============================================================================

map("n", "<leader>te", "<cmd>Neotree toggle left<cr>", { silent = true, desc = "toggle explorer" })
map("n", "<leader>tl", "<cmd>lua toggle_line_number()<cr>", { silent = true, desc = "cycle line number modes" })
map("n", "<leader>tn", "<cmd>set number!<cr>", { silent = true, desc = "toggle line numbers" })
map("n", "<leader>tr", "<cmd>set relativenumber!<cr>", { silent = true, desc = "toggle relative numbers" })
map("n", "<leader>tw", "<cmd>lua toggle_wrap()<cr>", { silent = true, desc = "toggle word wrap" })
map("n", "<leader>ts", "<cmd>set spell!<cr>", { silent = true, desc = "toggle spell check" })
map("n", "<leader>tb", "<cmd>Gitsigns toggle_current_line_blame<cr>", { silent = true, desc = "toggle git blame" })
map("n", "<leader>tv", "<cmd>lua cycle_virtualedit()<cr>", { silent = true, desc = "cycle virtualedit" })
map("n", "<leader>tc", "<cmd>lua toggle_comment()<cr>", { silent = true, desc = "toggle comment" })
map("n", "<leader>tm", "<cmd>lua show_mode_popup()<cr>", { silent = true, desc = "show mode popup" })

-- ============================================================================
-- leader w: window
-- ============================================================================

map("n", "<leader>ws", "<cmd>split<cr>", { silent = true, desc = "split horizontal" })
map("n", "<leader>wv", "<cmd>vsplit<cr>", { silent = true, desc = "split vertical" })
map("n", "<leader>wc", "<cmd>close<cr>", { silent = true, desc = "close window" })
map("n", "<leader>wo", "<cmd>only<cr>", { silent = true, desc = "close other windows" })
map("n", "<leader>w=", "<c-w>=", { desc = "equalize windows" })

-- ============================================================================
-- leader p: project/session
-- ============================================================================

map("n", "<leader>ps", "<cmd>Telescope persisted<cr>", { silent = true, desc = "sessions" })
map("n", "<leader>pl", "<cmd>SessionLoad<cr>", { silent = true, desc = "load session" })
map("n", "<leader>pw", "<cmd>SessionSave<cr>", { silent = true, desc = "save session" })
map("n", "<leader>pd", "<cmd>SessionDelete<cr>", { silent = true, desc = "delete session" })
map("n", "<leader>pt", "<cmd>SessionToggle<cr>", { silent = true, desc = "toggle auto-save" })

-- ============================================================================
-- buffer management
-- ============================================================================

local function focus_neo_tree()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "neo-tree" then
      pcall(vim.api.nvim_set_current_win, win)
      return
    end
  end
end

local function smart_bufremove()
  require("mini.bufremove").delete(0, false)
  focus_neo_tree()
end

map("n", "<leader>bd", smart_bufremove, { silent = true, desc = "delete buffer" })
map("n", "<leader>bD", "<cmd>bd!<cr>", { silent = true, desc = "force delete buffer" })

-- ============================================================================
-- coc completion (insert mode)
-- ============================================================================

local opts = { silent = true, noremap = true, expr = true, replace_keycodes = false }
map("i", "<tab>", 'coc#pum#visible() ? coc#pum#next(1) : v:lua.check_back_space() ? "<tab>" : coc#refresh()', opts)
map("i", "<s-tab>", [[coc#pum#visible() ? coc#pum#prev(1) : "\<c-h>"]], opts)
map("i", "<cr>", [[coc#pum#visible() ? coc#pum#confirm() : "\<c-g>u\<cr>\<c-r>=coc#on_enter()\<cr>"]], opts)

-- ============================================================================
-- text objects (coc)
-- ============================================================================

map("x", "if", "<Plug>(coc-funcobj-i)", { silent = true })
map("o", "if", "<Plug>(coc-funcobj-i)", { silent = true })
map("x", "af", "<Plug>(coc-funcobj-a)", { silent = true })
map("o", "af", "<Plug>(coc-funcobj-a)", { silent = true })
map("x", "ic", "<Plug>(coc-classobj-i)", { silent = true })
map("o", "ic", "<Plug>(coc-classobj-i)", { silent = true })
map("x", "ac", "<Plug>(coc-classobj-a)", { silent = true })
map("o", "ac", "<Plug>(coc-classobj-a)", { silent = true })

-- ============================================================================
-- coc float scrolling
-- ============================================================================

local opts_scroll = { silent = true, nowait = true, expr = true }
map("n", "<c-f>", 'coc#float#has_scroll() ? coc#float#scroll(1) : "<c-f>"', opts_scroll)
map("n", "<c-b>", 'coc#float#has_scroll() ? coc#float#scroll(0) : "<c-b>"', opts_scroll)
map("i", "<c-f>", 'coc#float#has_scroll() ? "<c-r>=coc#float#scroll(1)<cr>" : "<Right>"', opts_scroll)
map("i", "<c-b>", 'coc#float#has_scroll() ? "<c-r>=coc#float#scroll(0)<cr>" : "<Left>"', opts_scroll)
map("v", "<c-f>", 'coc#float#has_scroll() ? coc#float#scroll(1) : "<c-f>"', opts_scroll)
map("v", "<c-b>", 'coc#float#has_scroll() ? coc#float#scroll(0) : "<c-b>"', opts_scroll)

-- ============================================================================
-- additional productivity keymaps (inspired by kennypete)
-- ============================================================================

-- clear search highlighting (already have <c-l> for window navigation, use <leader>h)
map("n", "<leader>h", "<cmd>nohlsearch<cr>", { silent = true, desc = "clear search highlighting" })

-- better substitute command template (very magic mode with underscore delimiters)
map("n", "<c-s>", [[:%s_\v__g<left><left><left>]], { desc = "substitute (very magic)" })
map("v", "<c-s>", [[:s_\v__g<left><left><left>]], { desc = "substitute (very magic)" })

-- tab navigation
map("n", "<tab>", "<cmd>tabnext<cr>", { silent = true, desc = "next tab" })
map("n", "<s-tab>", "<cmd>tabprevious<cr>", { silent = true, desc = "previous tab" })

-- insert mode: undoable backspace (bram's recommendation)
map("i", "<c-u>", "<c-g>u<c-u>", { desc = "undoable backspace" })

-- screen-wise navigation (keeps cursor on screen line)
map("n", "<c-up>", "gk", { desc = "up (screen)" })
map("n", "<c-down>", "gj", { desc = "down (screen)" })
map("i", "<c-up>", "<c-o>gk", { desc = "up (screen)" })
map("i", "<c-down>", "<c-o>gj", { desc = "down (screen)" })

-- ============================================================================
-- digraphs (emoji support)
-- ============================================================================

-- add custom digraphs
vim.cmd([[
  digraph :) 128512
]])
