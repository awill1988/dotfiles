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
