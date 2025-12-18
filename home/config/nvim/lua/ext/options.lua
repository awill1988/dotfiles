vim.g.mapleader = " "

local o = vim.o
local opt = vim.opt

-- ============================================================================
-- shell configuration
-- ============================================================================

local shell = vim.env.SHELL
if shell == nil or shell == "" or vim.fn.executable(shell) == 0 then
  shell = "/bin/zsh"
end
o.shell = shell

-- ============================================================================
-- display & visual settings
-- ============================================================================

o.termguicolors = true
o.number = true
o.relativenumber = true
o.signcolumn = "yes"
o.cursorline = true
opt.cursorlineopt = "number"  -- highlight line number only

-- colorcolumn: show margin guide one column after textwidth
opt.colorcolumn = "+1"

-- custom fillchars for splits, folds, and end-of-buffer
opt.fillchars = {
  vert = "│",
  fold = "-",
  eob = "~",
  foldopen = "┏",
  foldsep = "│",
  foldclose = "╋",
}

-- visual whitespace indicators
o.list = true
opt.listchars = {
  nbsp = "°",
  trail = "·",
  tab = "——►",
  eol = "¶",
}

-- wrapped line indicator
opt.showbreak = "↪"

-- line wrapping
o.wrap = false  -- start with wrap disabled

-- scrolling
o.scrolloff = 0
o.sidescrolloff = 2

-- command line
o.cmdheight = 2
o.showcmd = true  -- show partial commands

-- popup menu
o.pumheight = 9

-- show truncated lines with @@@
opt.display = "truncate"

-- ============================================================================
-- editing behavior
-- ============================================================================

-- clipboard
o.clipboard = "unnamedplus"

-- mouse
o.mouse = "a"
o.mousetime = 500

-- backspace behavior
opt.backspace = { "indent", "eol", "start" }

-- buffer management
o.hidden = true

-- disable bell for various events
opt.belloff = { "backspace", "cursor", "error", "esc", "insertmode", "showmatch" }

-- ============================================================================
-- tabs & indentation
-- ============================================================================

o.expandtab = true  -- use spaces instead of tabs
o.shiftwidth = 2    -- auto-indent width
o.smarttab = true   -- smart tab at line start
o.tabstop = 8       -- visual tab width (standard)

-- ============================================================================
-- search & matching
-- ============================================================================

o.hlsearch = true     -- highlight search matches
o.incsearch = true    -- show matches while typing
o.ignorecase = true   -- case-insensitive by default
o.smartcase = true    -- case-sensitive if uppercase present
o.showmatch = true    -- flash matching brackets

-- bracket pairs for % matching
opt.matchpairs = { "(:)", "{:}", "[:]", '":"', "':'" }

-- ============================================================================
-- file handling
-- ============================================================================

-- file encoding detection order
opt.fileencodings = { "ucs-bom", "utf-8", "default", "latin1" }

-- end-of-line format preference
opt.fileformats = { "unix", "dos" }

-- internal encoding (neovim is always utf-8, this option is ignored but kept for documentation)
-- o.encoding = "utf-8"  -- not settable in neovim

-- ============================================================================
-- completion
-- ============================================================================

opt.completeopt = { "menu", "menuone", "preview", "noinsert" }

-- command-line completion
opt.wildoptions = { "pum", "fuzzy" }

-- ============================================================================
-- history & persistence
-- ============================================================================

o.history = 5000  -- extended command history

-- viminfo/shada settings (neovim uses shada)
opt.shada = { "'100", "<9999", "s1000", "h" }

-- ============================================================================
-- window behavior
-- ============================================================================

o.splitright = true
o.splitbelow = true
o.laststatus = 2  -- always show statusline

-- ============================================================================
-- timeout settings
-- ============================================================================

o.timeout = true
o.timeoutlen = 1500   -- mapping timeout
o.ttimeoutlen = 150   -- key code timeout

-- ============================================================================
-- misc settings
-- ============================================================================

-- change working directory to buffer's directory
-- o.autochdir = true  -- commented out: can interfere with project workflows

-- window title shows buffer name
o.title = true

-- shorten messages (no intro, truncate file messages, etc.)
opt.shortmess:append("I")  -- no intro message on startup

-- report all line changes
o.report = 0

-- syntax column limit (performance)
o.synmaxcol = 9999

-- shift+arrows select text
opt.keymodel = { "startsel" }

-- neovim-specific: disable netrw (using neo-tree)
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.g.have_nerd_font = true

-- ============================================================================
-- gui font configuration
-- ============================================================================

local guifont = os.getenv("NVIM_GUI_FONT")
local guifont_family = os.getenv("NVIM_GUI_FONT_FAMILY")
local guifont_size = os.getenv("NVIM_GUI_FONT_SIZE")

if guifont ~= nil and guifont ~= "" then
  vim.o.guifont = guifont
elseif guifont_family ~= nil and guifont_family ~= "" then
  if guifont_size ~= nil and guifont_size ~= "" then
    vim.o.guifont = guifont_family .. ":h" .. guifont_size
  else
    vim.o.guifont = guifont_family
  end
end
