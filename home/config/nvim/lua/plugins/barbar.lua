-- Buffer bar to show all open files as tabs
return {
	"romgrk/barbar.nvim",
	dependencies = {
		"lewis6991/gitsigns.nvim",
		"nvim-tree/nvim-web-devicons",
	},
	init = function()
		vim.g.barbar_auto_setup = false
	end,
	config = function()
		require("barbar").setup({
			animation = false,
			auto_hide = false,
			tabpages = true,
			clickable = true,
			icons = {
				buffer_index = false,
				buffer_number = false,
				button = "",
				diagnostics = {
					[vim.diagnostic.severity.ERROR] = { enabled = true, icon = " " },
					[vim.diagnostic.severity.WARN] = { enabled = true, icon = " " },
					[vim.diagnostic.severity.INFO] = { enabled = false },
					[vim.diagnostic.severity.HINT] = { enabled = false },
				},
				gitsigns = {
					added = { enabled = true, icon = "+" },
					changed = { enabled = true, icon = "~" },
					deleted = { enabled = true, icon = "-" },
				},
				filetype = {
					enabled = true,
				},
				separator = { left = "▎", right = "" },
				modified = { button = "●" },
				pinned = { button = "", filename = true },
			},
		})

		-- recommended keymaps
		local map = vim.keymap.set
		local opts = { noremap = true, silent = true }

		-- navigate buffers
		map("n", "<A-,>", "<cmd>BufferPrevious<cr>", opts)
		map("n", "<A-.>", "<cmd>BufferNext<cr>", opts)

		-- reorder buffers
		map("n", "<A-<>", "<cmd>BufferMovePrevious<cr>", opts)
		map("n", "<A->>", "<cmd>BufferMoveNext<cr>", opts)

		-- goto buffer by position
		map("n", "<A-1>", "<cmd>BufferGoto 1<cr>", opts)
		map("n", "<A-2>", "<cmd>BufferGoto 2<cr>", opts)
		map("n", "<A-3>", "<cmd>BufferGoto 3<cr>", opts)
		map("n", "<A-4>", "<cmd>BufferGoto 4<cr>", opts)
		map("n", "<A-5>", "<cmd>BufferGoto 5<cr>", opts)
		map("n", "<A-6>", "<cmd>BufferGoto 6<cr>", opts)
		map("n", "<A-7>", "<cmd>BufferGoto 7<cr>", opts)
		map("n", "<A-8>", "<cmd>BufferGoto 8<cr>", opts)
		map("n", "<A-9>", "<cmd>BufferGoto 9<cr>", opts)
		map("n", "<A-0>", "<cmd>BufferLast<cr>", opts)

		-- pin/unpin buffer
		map("n", "<A-p>", "<cmd>BufferPin<cr>", opts)

		-- close buffer
		map("n", "<A-c>", "<cmd>BufferClose<cr>", opts)
		map("n", "<A-C>", "<cmd>BufferCloseAllButCurrentOrPinned<cr>", opts)

		-- patch barbar's move_buffer to handle nil buffer_number (fixes middle-click error)
		local api = require("barbar.api")
		local original_move_buffer = api.move_buffer
		api.move_buffer = function(buffer_number, direction)
			if buffer_number == nil then
				return
			end
			return original_move_buffer(buffer_number, direction)
		end
	end,
}
