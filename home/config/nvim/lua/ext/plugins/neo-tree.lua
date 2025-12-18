require("neo-tree").setup({
  close_if_last_window = true,
  filesystem = {
    follow_current_file = { enabled = true },
    bind_to_cwd = false, -- allow multiple project roots
    use_libuv_file_watcher = true,
    filtered_items = {
      hide_dotfiles = false,
      hide_gitignored = true,
      hide_by_name = { ".git" },
      never_show = { ".git" },
    },
    commands = {
      -- add current directory to workspace
      add_directory = function(state)
        local node = state.tree:get_node()
        local path = node.type == "directory" and node.path or vim.fn.fnamemodify(node.path, ":h")
        vim.ui.input({ prompt = "Add directory: ", default = path }, function(input)
          if input then
            vim.cmd("tcd " .. input)
            require("neo-tree.sources.filesystem").navigate(state, state.path, input)
          end
        end)
      end,
      -- change root to selected directory
      set_root = function(state)
        local node = state.tree:get_node()
        if node.type == "directory" then
          require("neo-tree.sources.filesystem").navigate(state, state.path, node.path)
        end
      end,
    },
    window = {
      mappings = {
        ["<c-a>"] = "add_directory",
        ["<c-r>"] = "set_root",
        ["."] = "set_root",
        ["<bs>"] = "navigate_up",
        ["u"] = "navigate_up",
      },
    },
  },
})
