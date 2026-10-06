return {
  {
    "awill1988/agent-stream.nvim",
    commit = "8e56fa0afbe50f7201df7173f6f57c4fe7d97e43",
    lazy = false,
    opts = function()
      return {
        manage_autoread = true,
        auto_reload_unmodified = false,
        rpc = { enabled = false },
        review = { mode = "optimistic", grace_period_ms = 3000 },
        task_control = "auto",
      }
    end,
  },
}
