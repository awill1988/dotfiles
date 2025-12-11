vim.g.db_ui_use_nerd_fonts = 1
vim.g.db_ui_show_database_icon = 1

local env = vim.env
local function add_dsn(map, name, value)
  if value and value ~= "" then
    map[name] = value
  end
end

local dbs = {}
add_dsn(dbs, "main", env.DATABASE_URL)
add_dsn(dbs, "staging", env.DB_STAGING_URL)
add_dsn(dbs, "prod", env.DB_PROD_URL)
if env.DB_SQLITE_PATH and env.DB_SQLITE_PATH ~= "" then
  add_dsn(dbs, "sqlite", "sqlite:" .. env.DB_SQLITE_PATH)
end

if next(dbs) ~= nil then
  vim.g.dbs = dbs
end
