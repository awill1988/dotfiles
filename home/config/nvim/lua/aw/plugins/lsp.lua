local function vale_root()
  local path = vim.fs.find({ ".vale.ini", ".git" }, { upward = true })[1]
  if path then
    return vim.fs.dirname(path)
  end
  local buf_path = vim.api.nvim_buf_get_name(0)
  return (buf_path ~= "" and vim.fs.dirname(buf_path)) or vim.loop.cwd()
end

local capabilities = require("cmp_nvim_lsp").default_capabilities()
vim.lsp.config("*", { capabilities = capabilities })

local bins = {
  bashls = "bash-language-server",
  ts_ls = "typescript-language-server",
  elixirls = "elixir-ls",
  kotlin_language_server = "kotlin-language-server",
  vale_ls = "vale-ls",
}

local overrides = {
  elixirls = { cmd = { "elixir-ls" } },
  ts_ls = { cmd = { "typescript-language-server", "--stdio" } },
  bashls = { cmd = { "bash-language-server", "start" } },
  vale_ls = {
    cmd = { "vale-ls" },
    filetypes = { "markdown", "text", "gitcommit" },
    root_dir = vale_root,
  },
}

local servers = {
  "gopls",
  "pyright",
  "ts_ls",
  "bashls",
  "elixirls",
  "rust_analyzer",
  "kotlin_language_server",
  "jdtls",
  "solargraph",
  "vale_ls",
}

for _, server in ipairs(servers) do
  local override = overrides[server] or {}
  local bin = bins[server] or override.cmd and override.cmd[1] or server
  if vim.fn.executable(bin) == 1 then
    vim.lsp.config(server, override)
    vim.lsp.enable(server)
  end
end
