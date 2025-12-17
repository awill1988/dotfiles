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
