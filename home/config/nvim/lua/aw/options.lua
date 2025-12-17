vim.g.mapleader = " "

local o = vim.o
local shell = vim.env.SHELL
if shell == nil or shell == "" or vim.fn.executable(shell) == 0 then
  shell = "/bin/zsh"
end
o.shell = shell
o.termguicolors = true
o.number = true
o.relativenumber = true
o.signcolumn = "yes"
o.clipboard = "unnamedplus"
o.mouse = "a"
o.splitright = true
o.splitbelow = true
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.g.have_nerd_font = true

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
