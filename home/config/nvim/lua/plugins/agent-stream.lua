return {
  {
    "awill1988/agent-stream.nvim",
    commit = "66bf6356ab5cb4bd1783c67a62f11ad627dca32e",
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
