return {
  "stevearc/overseer.nvim",
  version = "2.*",
  opts = {
    task_list = {
      direction = "bottom",
      min_height = 5,
      max_height = 5,
      default_detail = 1,
    },
    templates = {
      "vscode",
      "dap",
    },
  },
  config = function(_, opts)
    require("overseer").setup(opts)
  end
}
