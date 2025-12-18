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

return {}
