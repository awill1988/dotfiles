local M = {}

local function read_file(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local content = f:read("*a")
	f:close()
	return content
end

local function get_env_palette()
	local palette = {}
	for index = 0, 15 do
		local suffix = string.format("%02X", index)
		local color = vim.env["NVIM_THEME_BASE" .. suffix] or os.getenv("NVIM_THEME_BASE" .. suffix)
		if not color or color == "" then
			return nil
		end
		palette["base" .. suffix] = color
	end
	return palette
end

local function get_stylix_palette()
	local path = vim.fn.expand("~/.config/stylix/palette.json")
	local content = read_file(path)
	if not content or content == "" then
		return nil
	end
	local ok, data = pcall(vim.json.decode, content)
	if not ok or type(data) ~= "table" or not data.base00 then
		return nil
	end
	local palette = {}
	for index = 0, 15 do
		local suffix = string.format("%02X", index)
		local raw = data["base" .. suffix]
		if raw then
			palette["base" .. suffix] = raw:match("^#") and raw or ("#" .. raw)
		end
	end
	return {
		palette = palette,
		slug = data.slug,
		scheme = data.scheme,
	}
end

local function get_active_theme_file()
	local path = vim.fn.expand("~/projects/awill1988/dotfiles/home/active-theme.nix")
	local content = read_file(path)
	if not content then
		return nil
	end
	local theme = content:gsub('["\r\n%s]', "")
	return theme ~= "" and theme or nil
end

local function detect_polarity(base00, theme_name)
	if theme_name then
		local lower = theme_name:lower()
		if lower:find("light") or lower:find("latte") or lower:find("dawn") then
			return "light"
		elseif lower:find("dark") or lower:find("mocha") then
			return "dark"
		end
	end

	if base00 then
		local hex = base00:gsub("^#", "")
		if #hex == 6 then
			local r = tonumber(hex:sub(1, 2), 16) or 0
			local g = tonumber(hex:sub(3, 4), 16) or 0
			local b = tonumber(hex:sub(5, 6), 16) or 0
			local lum = 0.299 * r + 0.587 * g + 0.114 * b
			return lum > 128 and "light" or "dark"
		end
	end

	local env = vim.env.NVIM_THEME_POLARITY or os.getenv("NVIM_THEME_POLARITY")
	if env and env ~= "" then
		return env
	end

	return "dark"
end

local function apply_base16(palette)
	local ok_mini, mini = pcall(require, "mini.base16")
	if ok_mini and type(mini) == "table" and mini.setup then
		mini.setup({ palette = palette })
		return
	end

	local p = palette
	local highlights = {
		Normal = { fg = p.base05, bg = p.base00 },
		NormalFloat = { fg = p.base05, bg = p.base01 },
		Visual = { bg = p.base02 },
		Search = { fg = p.base01, bg = p.base0A },
		IncSearch = { fg = p.base01, bg = p.base09 },
		LineNr = { fg = p.base03, bg = p.base00 },
		CursorLine = { bg = p.base01 },
		CursorLineNr = { fg = p.base04, bold = true },
		StatusLine = { fg = p.base04, bg = p.base02 },
		StatusLineNC = { fg = p.base03, bg = p.base01 },
		Pmenu = { fg = p.base05, bg = p.base01 },
		PmenuSel = { fg = p.base01, bg = p.base05 },
		Comment = { fg = p.base03, italic = true },
		Constant = { fg = p.base09 },
		String = { fg = p.base0B },
		Identifier = { fg = p.base08 },
		Function = { fg = p.base0D },
		Statement = { fg = p.base0E },
		Keyword = { fg = p.base0E },
		PreProc = { fg = p.base0A },
		Type = { fg = p.base0A },
		Special = { fg = p.base0C },
		Error = { fg = p.base00, bg = p.base08 },
		Todo = { fg = p.base0A, bg = p.base01 },
	}
	for group, opts in pairs(highlights) do
		vim.api.nvim_set_hl(0, group, opts)
	end
end

local function apply_native_theme(theme_name, polarity)
	local lower = (theme_name or ""):lower()
	if lower:find("gruvbox") then
		local ok, gruvbox = pcall(require, "gruvbox")
		if ok and gruvbox.setup then
			gruvbox.setup({ contrast = "" })
		end
		return pcall(vim.cmd.colorscheme, "gruvbox")
	elseif lower:find("catppuccin") then
		local ok, catppuccin = pcall(require, "catppuccin")
		local variant = polarity == "light" and "catppuccin-latte" or "catppuccin-mocha"
		if ok and catppuccin.setup then
			catppuccin.setup({ flavour = polarity == "light" and "latte" or "mocha" })
		end
		return pcall(vim.cmd.colorscheme, variant)
	elseif lower:find("rose%-pine") or lower:find("rose_pine") then
		local variant = polarity == "light" and "rose-pine-dawn" or "rose-pine"
		return pcall(vim.cmd.colorscheme, variant)
	elseif lower:find("everforest") then
		return pcall(vim.cmd.colorscheme, "everforest")
	elseif lower:find("melange") then
		return pcall(vim.cmd.colorscheme, "melange")
	end
	return false
end

function M.apply()
	local env_palette = get_env_palette()
	local stylix_data = get_stylix_palette()
	local file_theme = get_active_theme_file()
	local env_theme = vim.env.ACTIVE_THEME

	local theme_name
	local polarity
	local palette

	if env_palette then
		palette = env_palette
		theme_name = env_theme or file_theme or "stylix"
		polarity = vim.env.NVIM_THEME_POLARITY or detect_polarity(env_palette.base00, theme_name)
	else
		palette = stylix_data and stylix_data.palette
		theme_name = env_theme or file_theme or (stylix_data and stylix_data.slug) or "gruvbox-dark"
		if theme_name then
			polarity = detect_polarity(palette and palette.base00, theme_name)
		elseif palette and palette.base00 then
			polarity = detect_polarity(palette.base00, theme_name)
		else
			polarity = detect_polarity(nil, theme_name)
		end
	end
	polarity = polarity or "dark"

	vim.opt.background = polarity

	local base16_path = vim.env.NVIM_THEME_BASE16_PATH or os.getenv("NVIM_THEME_BASE16_PATH")
	if base16_path and base16_path ~= "" then
		vim.opt.runtimepath:prepend(base16_path)
	end

	local applied_native = apply_native_theme(theme_name, polarity)
	if palette and (not applied_native or env_palette) then
		apply_base16(palette)
	end

	if palette and env_palette then
		vim.api.nvim_set_hl(0, "Normal", { bg = palette.base00, fg = palette.base05 })
	end

	vim.g.colors_name = theme_name
	pcall(vim.api.nvim_exec_autocmds, "ColorScheme", { pattern = theme_name, modeline = false })
end

function M.get_theme_pair(current_theme)
	local pairs_map = {
		["gruvbox-dark"] = "gruvbox-light",
		["gruvbox-light"] = "gruvbox-dark",
		["catppuccin-mocha"] = "catppuccin-latte",
		["catppuccin-latte"] = "catppuccin-mocha",
		["rose-pine"] = "rose-pine-dawn",
		["rose-pine-dawn"] = "rose-pine",
	}
	if pairs_map[current_theme] then
		return pairs_map[current_theme]
	end
	if current_theme:find("light") then
		return (current_theme:gsub("light", "dark"))
	elseif current_theme:find("dark") then
		return (current_theme:gsub("dark", "light"))
	end
	return current_theme
end

function M.toggle()
	local current = get_active_theme_file() or vim.g.colors_name or "gruvbox-dark"
	local pair = M.get_theme_pair(current)
	local theme_file = vim.fn.expand("~/projects/awill1988/dotfiles/home/active-theme.nix")
	local f = io.open(theme_file, "w")
	if f then
		f:write(string.format('"%s"\n', pair))
		f:close()
	end

	pcall(vim.fn.jobstart, { "theme-switch", "set", pair })
	M.apply()
end

function M.auto_sync()
	local file_theme = get_active_theme_file()
	local stylix_data = get_stylix_palette()
	local target_polarity = nil
	if stylix_data and stylix_data.palette then
		target_polarity = detect_polarity(stylix_data.palette.base00, file_theme or stylix_data.slug)
	elseif file_theme then
		target_polarity = detect_polarity(nil, file_theme)
	end

	if target_polarity and target_polarity ~= vim.o.background then
		M.apply()
	elseif file_theme and vim.g.colors_name and file_theme ~= vim.g.colors_name then
		M.apply()
	end
end

local active_watchers = {}

function M.setup_auto_sync()
	local watch_paths = {
		vim.fn.expand("~/.config/stylix/palette.json"),
		vim.fn.expand("~/projects/awill1988/dotfiles/home/active-theme.nix"),
	}

	for _, path in ipairs(watch_paths) do
		if vim.fn.filereadable(path) == 1 and not active_watchers[path] then
			local fs_event = vim.uv.new_fs_event()
			if fs_event then
				local ok = pcall(fs_event.start, fs_event, path, {}, vim.schedule_wrap(function(err, _, _)
					if not err then
						M.apply()
					end
				end))
				if ok then
					active_watchers[path] = fs_event
				end
			end
		end
	end

	local group = vim.api.nvim_create_augroup("AutoThemeSync", { clear = true })
	vim.api.nvim_create_autocmd({ "FocusGained", "VimResume" }, {
		group = group,
		desc = "Auto-update theme when gaining focus or resuming",
		callback = function()
			M.auto_sync()
		end,
	})

	if vim.fn.exists(":ThemeReload") == 0 then
		vim.api.nvim_create_user_command("ThemeReload", function()
			M.apply()
			vim.notify(
				string.format("Theme reloaded: %s (%s)", vim.g.colors_name or "default", vim.o.background),
				vim.log.levels.INFO
			)
		end, { desc = "Reload active theme from dotfiles / stylix" })
	end
end

return M
