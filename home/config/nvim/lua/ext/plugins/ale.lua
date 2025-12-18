-- ale configuration
-- fixers for various filetypes
vim.g.ale_fixers = {
  ["*"] = { "remove_trailing_lines", "trim_whitespace" },
  python = { "black", "isort" },
  go = { "gofmt", "goimports" },
  javascript = { "prettier" },
  typescript = { "prettier" },
  json = { "prettier" },
  yaml = { "prettier" },
  markdown = { "prettier" },
  sh = { "shfmt" },
  nix = { "nixfmt" },
  elixir = { "mix_format" },
  rust = { "rustfmt" },
}

-- linters for various filetypes (supplement LSP diagnostics)
vim.g.ale_linters = {
  python = { "flake8", "mypy" },
  sh = { "shellcheck" },
  yaml = { "yamllint" },
  dockerfile = { "hadolint" },
  powershell = { "psscriptanalyzer" },
}

-- only run linters named in ale_linters settings
vim.g.ale_linters_explicit = 1

-- fix files on save
vim.g.ale_fix_on_save = 1

-- integrate with coc.nvim - disable ale lsp features since coc handles that
vim.g.ale_disable_lsp = 1

-- sign column symbols
vim.g.ale_sign_error = "✘"
vim.g.ale_sign_warning = "⚠"

-- error message format
vim.g.ale_echo_msg_format = "[%linter%] %s [%severity%]"

-- navigate between errors
vim.keymap.set("n", "[a", "<Plug>(ale_previous_wrap)", { silent = true })
vim.keymap.set("n", "]a", "<Plug>(ale_next_wrap)", { silent = true })
