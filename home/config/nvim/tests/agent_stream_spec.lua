local spec = require("plugins.agent-stream")[1]
assert(spec.lazy == false)
local opts = type(spec.opts) == "function" and spec.opts() or spec.opts
assert(opts.manage_autoread == true)
assert(opts.auto_reload_unmodified == false)
assert(opts.rpc.enabled == false)

local stream = require("agent-stream")
stream.setup(opts)
vim.cmd("runtime plugin/agent-stream.lua")
require("core.keymaps")
assert(vim.fn.maparg(" aa", "n"):find("AgentStreamAccept", 1, true))
assert(vim.fn.maparg(" ar", "n"):find("AgentStreamResume", 1, true))
assert(vim.fn.maparg(" ax", "n"):find("AgentStreamReject", 1, true))
assert(vim.fn.maparg("]a", "n"):find("AgentStreamNextHunk", 1, true))

local captured
local original_tree = package.loaded["neo-tree"]
local original_menu = package.loaded["core.context_menu"]
package.loaded["neo-tree"] = {
  setup = function(opts)
    captured = opts
  end,
}
package.loaded["core.context_menu"] = { register_provider = function() end }
require("plugins.neo-tree")[1].config()
local defaults = require("neo-tree.defaults").renderers.file
local actual = captured.filesystem.renderers.file
assert(#actual == #defaults + 1)
for index, component in ipairs(defaults) do
  assert(vim.deep_equal(component, actual[index]), "existing renderer changed")
end
assert(actual[#actual][1] == "agent_stream_badge")
assert(type(captured.filesystem.commands.open_media_or_file) == "function")
assert(captured.filesystem.window.mappings["<2-LeftMouse>"] == "open_media_or_file")
package.loaded["neo-tree"] = original_tree
package.loaded["core.context_menu"] = original_menu

local path = vim.fn.tempname()
vim.fn.writefile({ "original" }, path)
vim.cmd.edit(path)
local buf = vim.api.nvim_get_current_buf()
assert(vim.bo[buf].autoread == false)
vim.fn.writefile({ "external", "edit" }, path)
vim.cmd.checktime()
assert(vim.wait(3000, function()
  return stream.renderer.active_state[buf] ~= nil
end))
assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "original")
vim.cmd.AgentStreamAccept()
assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "external")
stream.watcher.stop_all()
vim.api.nvim_buf_delete(buf, { force = true })
vim.fn.delete(path)
print("agent-stream-tests-ok")
