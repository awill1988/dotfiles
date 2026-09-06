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

			local function open_context_menu(state)
				local mousepos = vim.fn.getmousepos()
				if mousepos.winid == state.winid and mousepos.line > 0 then
					pcall(vim.api.nvim_win_set_cursor, state.winid, { mousepos.line, 0 })
				end

				local node = state.tree:get_node()
				if not node then
					return
				end

				local is_dir = node.type == "directory"
				local options = {
					{ label = "󰏋 Open / Open Media", action = "open_media_or_file" },
					{ label = " Open in Split", action = "open_split" },
					{ label = " Open in VSplit", action = "open_vsplit" },
					{ label = "󰓩 Open in New Tab", action = "open_tabnew" },
					{ label = "󰏔 New File / Directory", action = "add" },
					{ label = "󰑕 Rename", action = "rename" },
					{ label = "󰆴 Delete", action = "delete" },
					{ label = "󰆏 Copy", action = "copy_to_clipboard" },
					{ label = "󰆐 Cut", action = "cut_to_clipboard" },
					{ label = "󰆒 Paste", action = "paste_from_clipboard" },
					{ label = "󰅍 Copy Absolute Path", action = "copy_path" },
					{ label = "󰅍 Copy Relative Path", action = "copy_relpath" },
					{ label = "󰋜 Reveal in System Explorer", action = "reveal_in_os" },
					{ label = "󰈈 Toggle Hidden Files", action = "toggle_hidden" },
				}

				local labels = {}
				for _, item in ipairs(options) do
					table.insert(labels, item.label)
				end

				vim.ui.select(labels, {
					prompt = "Right-Click Action (" .. node.name .. "):",
				}, function(choice, idx)
					if not choice or not idx then
						return
					end
					local selected = options[idx]
					local cc = require("neo-tree.sources.filesystem.commands")

					if selected.action == "copy_path" then
						vim.fn.setreg("+", node.path)
						vim.notify("Copied path: " .. node.path, vim.log.levels.INFO)
					elseif selected.action == "copy_relpath" then
						local relpath = vim.fn.fnamemodify(node.path, ":.")
						vim.fn.setreg("+", relpath)
						vim.notify("Copied relative path: " .. relpath, vim.log.levels.INFO)
					elseif selected.action == "reveal_in_os" then
						local opener = system_default_opener()
						local target = is_dir and node.path or vim.fn.fnamemodify(node.path, ":h")
						vim.system({ opener, target })
					elseif selected.action == "open_media_or_file" then
						open_media_or_file(state)
					elseif cc[selected.action] then
						cc[selected.action](state)
					end
				end)
			end

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
						open_context_menu = open_context_menu,
					},
					window = {
						mappings = {
							["<2-LeftMouse>"] = "open_media_or_file",
							["<RightMouse>"] = "open_context_menu",
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
