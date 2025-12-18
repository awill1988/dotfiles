-- Polyfills and shims that need to load before plugins
require("core.shims")

-- Handle plugins with lazy.nvim
require("core.lazy")

-- General Neovim keymaps
require("core.keymaps")

-- Other options
require("core.options")
