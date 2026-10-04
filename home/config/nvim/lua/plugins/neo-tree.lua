-- Nicer filetree than NetRW
return {
	{
		"nvim-neo-tree/neo-tree.nvim",
		branch = "v3.x",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-tree/nvim-web-devicons",
			"MunifTanjim/nui.nvim",
		},
		config = function()
			local media_extensions = {
				png = true,
				jpg = true,
				jpeg = true,
				gif = true,
				webp = true,
				heic = true,
				tif = true,
				tiff = true,
				bmp = true,
				svg = true,
				mov = true,
				mp4 = true,
				m4v = true,
				mkv = true,
				avi = true,
				webm = true,
				mp3 = true,
				wav = true,
				m4a = true,
				flac = true,
				ogg = true,
			}

			local function system_default_opener()
				if vim.fn.has("mac") == 1 then
					return "open"
				end

				if vim.env.WSL_DISTRO_NAME or vim.env.WSL_INTEROP then
					return "wslview"
				end

				return "xdg-open"
			end

			local function open_media_or_file(state)
				local node = state.tree:get_node()
				if not node or node.type ~= "file" then
					return require("neo-tree.sources.filesystem.commands").open(state)
				end

				local extension = vim.fn.fnamemodify(node.path, ":e"):lower()
				if not media_extensions[extension] then
					return require("neo-tree.sources.filesystem.commands").open(state)
				end

				local opener = system_default_opener()
				if vim.fn.executable(opener) ~= 1 then
					vim.notify(("media opener is unavailable: %s"):format(opener), vim.log.levels.ERROR)
					return
				end

				vim.system({ opener, node.path }, { text = true }, function(result)
					if result.code ~= 0 then
						vim.schedule(function()
							vim.notify(
								("could not open %s: %s"):format(node.path, result.stderr),
								vim.log.levels.ERROR
							)
						end)
					end
				end)
			end

			local context_menu = require("core.context_menu")
			context_menu.register_provider({
				name = "neo-tree",
				priority = 100,
				match = function(context)
					return context.filetype == "neo-tree"
				end,
				build = function(context)
					local manager = require("neo-tree.sources.manager")
					local state = manager.get_state_for_window(context.winid)
					if not state or not state.tree then
						return nil
					end

					local node = state.tree:get_node()
					if not node then
						return nil
					end

					local commands = require("neo-tree.sources.filesystem.commands")
					local function command(name)
						return function()
							commands[name](state)
						end
					end
					local function copy_path(path, description)
						return function()
							vim.fn.setreg("+", path)
							vim.notify(description .. path, vim.log.levels.INFO)
						end
					end

					return {
						items = {
							{ label = "Open / Open Media", key = "o", action = function() open_media_or_file(state) end },
							{ label = "Open in Split", key = "s", action = command("open_split") },
							{ label = "Open in Vertical Split", key = "v", action = command("open_vsplit") },
							{ label = "Open in New Tab", key = "t", action = command("open_tabnew") },
							{ separator = true },
							{ label = "New File / Directory", key = "n", action = command("add") },
							{ label = "Rename", key = "r", action = command("rename") },
							{ label = "Delete", key = "d", action = command("delete") },
							{ label = "Copy", key = "c", action = command("copy_to_clipboard") },
							{ label = "Cut", key = "x", action = command("cut_to_clipboard") },
							{ label = "Paste", key = "p", action = command("paste_from_clipboard") },
							{ separator = true },
							{
								label = "Copy Absolute Path",
								key = "a",
								action = copy_path(node.path, "Copied path: "),
							},
							{
								label = "Copy Relative Path",
								key = "l",
								action = copy_path(vim.fn.fnamemodify(node.path, ":."), "Copied relative path: "),
							},
							{
								label = "Reveal in System Explorer",
								key = "e",
								action = function()
									local target = node.type == "directory" and node.path or vim.fn.fnamemodify(node.path, ":h")
									vim.system({ system_default_opener(), target })
								end,
							},
							{ label = "Toggle Hidden Files", key = "h", action = command("toggle_hidden") },
						},
					}
				end,
			})

			require("neo-tree").setup({
				filesystem = {
					follow_current_file = {
						enabled = true, -- track current file and reveal in tree
					},
					use_libuv_file_watcher = true, -- auto-refresh on file changes
					filtered_items = {
						visible = false,
						hide_dotfiles = true,
						hide_gitignored = true,
						always_show = {
							".github",
						},
					},
					commands = {
						open_media_or_file = open_media_or_file,
					},
					window = {
						mappings = {
							["<2-LeftMouse>"] = "open_media_or_file",
						},
					},
				},
			})
			require("helpers.keys").map(
				{ "n", "v" },
				"<leader>e",
				"<cmd>Neotree toggle<cr>",
				"Toggle file explorer"
			)
		end,
	},
}
