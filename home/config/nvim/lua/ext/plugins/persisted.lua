local ok, persisted = pcall(require, "persisted")
if not ok then
  return
end

persisted.setup({
  save_dir = vim.fn.expand(vim.fn.stdpath("data") .. "/sessions/"),
  silent = false,
  use_git_branch = true, -- separate sessions per git branch
  autosave = true, -- auto-save session on exit
  autoload = false, -- don't auto-load session on startup (manual control)
  on_autoload_no_session = function()
    vim.notify("no session found for this directory")
  end,
  follow_cwd = true, -- change session when changing working directory
  allowed_dirs = nil, -- allow all directories
  ignored_dirs = nil,
  telescope = {
    reset_prompt = true,
    mappings = {
      change_branch = "<c-b>",
      copy_session = "<c-c>",
      delete_session = "<c-d>",
    },
  },
})

-- telescope integration
local telescope_ok, telescope = pcall(require, "telescope")
if telescope_ok then
  telescope.load_extension("persisted")
end
