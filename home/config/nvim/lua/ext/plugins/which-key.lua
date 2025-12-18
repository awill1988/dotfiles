local ok, wk = pcall(require, "which-key")
if not ok then
  return
end

wk.setup({})

-- register group labels
wk.add({
  { "<leader>f", group = "find" },
  { "<leader>g", group = "git" },
  { "<leader>c", group = "code" },
  { "<leader>t", group = "toggle" },
  { "<leader>w", group = "window" },
  { "<leader>b", group = "buffer" },
  { "<leader>p", group = "project" },
})
