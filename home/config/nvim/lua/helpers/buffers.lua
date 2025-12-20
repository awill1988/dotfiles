local M = {}
local function delete_buffer(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	if vim.bo[bufnr].buflisted then
		pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
	end
end

local function delete_buffers(filter)
	local current = vim.api.nvim_get_current_buf()
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if filter(bufnr, current) then
			delete_buffer(bufnr)
		end
	end
end

local function delete_this_buffer()
	delete_buffer(vim.api.nvim_get_current_buf())
end

local function delete_other_buffers()
	delete_buffers(function(bufnr, current)
		return bufnr ~= current
	end)
end

local function delete_all_buffers()
	delete_buffers(function()
		return true
	end)
end

local ok, close_buffers = pcall(require, "close_buffers")
if ok then
	M.delete_this = function()
		local deleted = pcall(close_buffers.delete, { type = "this", force = true })
		if not deleted then
			delete_this_buffer()
		end
	end
	M.delete_all = function()
		local deleted = pcall(close_buffers.delete, { type = "all", force = true })
		if not deleted then
			delete_all_buffers()
		end
	end
	M.delete_others = function()
		local deleted = pcall(close_buffers.delete, { type = "other", force = true })
		if not deleted then
			delete_other_buffers()
		end
	end
else
	M.delete_this = delete_this_buffer
	M.delete_all = delete_all_buffers
	M.delete_others = delete_other_buffers
end

return M
