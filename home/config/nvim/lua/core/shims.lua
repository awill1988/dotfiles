-- Compatibility shims for deprecated/removed Neovim helpers
local function add_reverse_lookup(tbl)
	for key, value in pairs(tbl) do
		if tbl[value] == nil then
			tbl[value] = key
		end
	end
	return tbl
end

-- nvim 0.11 deprecates vim.tbl_add_reverse_lookup; replace with a no-warning version
vim.tbl_add_reverse_lookup = add_reverse_lookup

-- Safeguard for plugins (such as bg.nvim) querying the Normal highlight group when fg/bg may be incomplete during colorscheme transitions
local orig_get_hl = vim.api.nvim_get_hl
vim.api.nvim_get_hl = function(ns_id, opts)
	local hl = orig_get_hl(ns_id, opts)
	if opts and opts.name == "Normal" and type(hl) == "table" then
		if hl.bg ~= nil and hl.fg == nil then
			local resolved = orig_get_hl(ns_id or 0, { name = "Normal" })
			if resolved and resolved.fg ~= nil then
				hl.fg = resolved.fg
			end
		end
	end
	return hl
end

return {}
