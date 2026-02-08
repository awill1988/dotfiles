# contextforge

Home-manager module for the [ContextForge MCP gateway](https://github.com/IBM/mcp-context-forge) — a local MCP aggregation server that exposes multiple tool servers behind a single virtual-server endpoint.

## Architecture

```
  mcp-servers.toml          darwin-rebuild /
  (server definitions)     home-manager switch
         │                        │
         ▼                        ▼
  xdg.configFile ──► ~/.config/contextforge/mcp-servers.toml
                              │
              ┌───────────────┼────────────────────┐
              │               │                    │
   ┌──────────▼──────────┐   │   ┌────────────────▼──────────────┐
   │  gateway service    │   │   │  bridge supervisor service    │
   │  port 4444          │   │   │  spawns mcpgateway.translate  │
   │  launchd / systemd  │   │   │  per stdio server             │
   └──────────┬──────────┘   │   └───────┬────────────────────────┘
              │              │           │  ports 4450+
              │   ┌──────────▼────────┐  │
              │   │  setup (one-shot) │  │
              │   │  creates vserver  │  │
              │   │  acquires token   │  │
              │   └──────────┬────────┘  │
              │              │           │
              │    writes virtual-server-id
              │    writes gateway-token
              │              │           │
   ┌──────────▼──────────────▼───────────▼──┐
   │                mcpgw-wrapper            │
   │  (stdio bridge — AI clients spawn this) │
   └────────────────────────────────────────┘
              │
              ▼
   contextforge-mcp-sync
   (registers HTTP + bridged servers with gateway)
```

## Zero-touch setup

After enabling the module, a single `darwin-rebuild switch` or `home-manager switch` brings up the full stack with no manual steps:

1. **Activation** creates data and cache directories, rotates logs (darwin: truncates to last 5000 lines)
2. **Pre-agent bootout** (darwin) unloads existing launchd agents so new plists can be loaded cleanly
3. **Gateway service** starts and binds to the configured host/port
4. **Bridge supervisor** reads `mcp-servers.toml`, spawns `mcpgateway.translate` per stdio server with a `bridge.port`
5. **Setup service** (one-shot) waits for the gateway health endpoint, creates a virtual server, acquires a JWT token, and runs `contextforge-mcp-sync` (which registers gateways and associates all tools with the virtual server)
6. **Post-activation ensure** re-bootstraps any launchd agents that failed to load during the home-manager lifecycle

All stages are idempotent. Subsequent rebuilds skip directory creation and server creation if artifacts already exist.

## MCP server definitions

Servers are defined once in `modules/home/programs/contextforge/mcp-servers.toml` and deployed to `~/.config/contextforge/mcp-servers.toml` via `xdg.configFile`. After a rebuild, run:

```bash
contextforge-mcp-sync
```

This parses the TOML, resolves environment variable references in headers, auto-derives bridge URLs from bridge ports, writes `~/.config/contextforge/mcp-servers.json`, registers servers with the gateway, and associates all discovered tools with the virtual server so clients can use them via the `/mcp` endpoint.

### TOML schema

```toml
# HTTP servers — registered directly with the gateway
[[servers]]
name = "context7"
transport = "http"
url = "https://mcp.context7.com/mcp"
headers = { CONTEXT7_API_KEY = "$CONTEXT7_API_KEY" }

# stdio servers — bridged to HTTP via mcpgateway.translate
[[servers]]
name = "aws-docs"
transport = "stdio"
command = "uvx"
args = ["awslabs.aws-documentation-mcp-server@latest"]
bridge = { port = 4451 }
gateway_register = true
```

Field reference:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | string | required | unique server identifier |
| `transport` | `"http"` or `"stdio"` | `"http"` | transport type |
| `url` | string | — | upstream HTTP endpoint |
| `headers` | table | `{}` | headers with `$ENV_VAR` expansion |
| `command` | string | — | stdio command (e.g. `uvx`, `npx`) |
| `args` | list | `[]` | stdio command arguments |
| `env` | table | `{}` | extra env vars for stdio servers |
| `bridge.port` | int | — | HTTP bridge port (auto-derives URL as `http://127.0.0.1:{port}/mcp`) |
| `bridge.url` | string | — | explicit bridge URL (overrides port-derived URL) |
| `gateway_register` | bool | auto | register with gateway (true for http, bridge-dependent for stdio) |

Top-level (outside `[[servers]]`):

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `exclude_tools` | list of strings | `[]` | glob patterns for tools to hide from the virtual server |

Headers support env var expansion: `$VAR` and `${VAR}`. Servers with unresolvable env vars are skipped during gateway registration but still appear in the JSON inventory with a `missing_headers` list.

### Tool policy

The top-level `exclude_tools` list controls which tools are hidden from the virtual server. Patterns use glob syntax (`fnmatch`). Tools matching any pattern are discovered by the gateway but not associated with the virtual server, so clients never see them.

```toml
exclude_tools = [
  "*-delete-*",
  "*-create-repository",
  "*-fork-repository",
  "*-merge-pull-request",
]
```

The policy is applied every time `contextforge-mcp-sync` runs. The sync output shows excluded tools:

```
virtual server: 39 tools associated
  excluded: github-create-repository, github-delete-file, github-fork-repository, github-merge-pull-request
```

### Port convention

- Gateway: **4444**
- Reserved: 4445-4449
- Bridges: **4450+**, alpha-sorted by server name

Current assignments:

| Port | Server |
|------|--------|
| 4450 | aws |
| 4451 | aws-docs |
| 4452 | opnsense |
| 4453 | postgres |
| 4454 | slack |

### Bridge secrets

Env vars needed by bridged servers (slack tokens, opnsense keys, etc.) go in:

```
~/.config/contextforge/mcpgw-bridge.env
```

This file is sourced by the bridge supervisor at startup. It is **not** managed by nix (stays out of the nix store). Format is standard shell:

```bash
SLACK_BOT_TOKEN=xoxb-...
SLACK_TEAM_ID=T...
OPNSENSE_SSH_HOST=10.0.0.1
```

### Sync flags

| Flag | Behavior |
|------|----------|
| (none) | write JSON + register with gateway |
| `--dry-run` | write JSON, skip gateway registration |
| `--print` | write JSON, print it, exit |

## Files

| Path | Owner | Purpose |
|------|-------|---------|
| `~/.config/contextforge/gateway.env` | nix (xdg.configFile) | gateway runtime config |
| `~/.config/contextforge/plugins.yaml` | nix (xdg.configFile) | plugin definitions (caching layers) |
| `~/.config/contextforge/mcp-servers.toml` | nix (xdg.configFile) | server definitions |
| `~/.config/contextforge/mcp-servers.json` | contextforge-mcp-sync | resolved server inventory |
| `~/.config/contextforge/mcpgw-bridge.env` | user (manual) | secrets for bridged servers |
| `~/.local/share/contextforge/gateway.db` | gateway process | sqlite database |
| `~/.local/share/contextforge/virtual-server-id` | setup service | UUID of the virtual server |
| `~/.local/share/contextforge/gateway-token` | setup service | JWT token for wrapper auth |
| `~/.cache/contextforge/npm/` | bridge supervisor | npx package cache |
| `~/.cache/contextforge/uv/` | bridge supervisor | uv package cache |

## Services

### Gateway (long-running)

| Platform | Mechanism | Label/Unit |
|----------|-----------|------------|
| darwin | launchd agent | `com.contextforge.gateway` |
| linux | systemd user service | `contextforge-gateway.service` |

Sources `gateway.env`, then execs `uvx --from mcp-contextforge-gateway mcpgateway`. Auth is disabled for admin API (`AUTH_REQUIRED=false`) but the virtual server `/mcp` endpoint requires JWT authentication (handled automatically by the setup service and wrapper).

### Bridge supervisor (long-running)

| Platform | Mechanism | Label/Unit |
|----------|-----------|------------|
| darwin | launchd agent | `com.contextforge.bridge-supervisor` |
| linux | systemd user service | `contextforge-bridge-supervisor.service` |

Reads `mcp-servers.toml`, extracts stdio servers with `bridge.port`, spawns `mcpgateway.translate` per server. Sources `mcpgw-bridge.env` for secrets. If no bridges are configured, idles with `sleep infinity` to prevent launchd spin-restart.

Resilience features:

- **Readiness check**: after starting each bridge, POSTs to its `/mcp` endpoint for up to 15s; resets failure state on success
- **Exponential backoff**: restarts dead bridges with 3s initial delay, doubling each time up to a 5-minute cap
- **Crash loop detection**: after 5 consecutive failures (without a successful readiness check), stops restarting the bridge and logs a diagnostic message; other bridges are unaffected
- **Monitor loop**: checks child processes every 5s; only restarts bridges that haven't hit the failure limit

### Setup (one-shot)

| Platform | Mechanism | Label/Unit |
|----------|-----------|------------|
| darwin | launchd agent (`KeepAlive = false`) | `com.contextforge.setup` |
| linux | systemd user service (`Type = oneshot`) | `contextforge-setup.service` |

Waits for the gateway health endpoint (60s timeout), creates a virtual server if one doesn't exist, and generates a non-expiring JWT token for the wrapper. The token is minted locally using the gateway's known secret (`my-test-key` / HS256) — no login endpoint dependency and no expiry to manage.

## Shell commands

| Command | Purpose |
|---------|---------|
| `mcpgw-status` | check gateway health and print connection info |
| `mcpgw-setup` | manual repair — re-creates virtual server and acquires token |
| `mcpgw-bridges` | check bridge health (reads toml, curls each bridge port) |
| `mcpgw-wrapper` | stdio MCP bridge for AI clients (not called directly) |
| `contextforge-mcp-sync` | sync MCP servers from toml and register with gateway |

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `programs.contextforge.enable` | bool | `false` | enable the module |
| `programs.contextforge.host` | str | `"127.0.0.1"` | gateway bind address |
| `programs.contextforge.port` | port | `4444` | gateway bind port |
| `programs.contextforge.ui_enabled` | bool | `true` | enable admin web UI |
| `programs.contextforge.admin_api_enabled` | bool | `true` | enable admin REST API |
| `programs.contextforge.log_level` | enum | `"INFO"` | `DEBUG`, `INFO`, `WARNING`, `ERROR`, `CRITICAL` |
| `programs.contextforge.environment` | enum | `"development"` | `development`, `staging`, `production` |

## Caching

Four caching layers reduce redundant tool invocations, speed up registry lookups, and lower latency for repeated queries. All are enabled automatically via nix — `darwin-rebuild switch` activates them with no manual steps.

### Layer overview

| Layer | Scope | TTL | Config |
|-------|-------|-----|--------|
| **In-memory cache** | gateway-level request/response | — | `CACHE_TYPE=memory` in `gateway.env` |
| **Registry cache** | tool/prompt/resource/agent/server/gateway lookups | 15-20s | `REGISTRY_CACHE_*` env vars in `gateway.env` |
| **Admin stats cache** | system and observability stats | 30-60s | `ADMIN_STATS_CACHE_*` env vars in `gateway.env` |
| **Plugin caches** | tool invocation results | 300-900s | `plugins.yaml` (two plugins below) |

### Plugin caches

Defined in `~/.config/contextforge/plugins.yaml` (managed by nix, deployed via `xdg.configFile`). Plugin source files are from [IBM/mcp-context-forge](https://github.com/IBM/mcp-context-forge/tree/main/plugins) and assembled into a nix derivation that the gateway script adds to `PYTHONPATH`.

**ResponseCacheByPrompt** (priority 120, TTL 900s) — semantic similarity caching for search/query tools. Compares input fields using a 0.92 similarity threshold. Cached tools: `context7-query-docs`, `context7-resolve-library-id`, `aws-docs-*`, `github-search-*`.

**CachedToolResult** (priority 110, TTL 300s) — deterministic caching for idempotent read-only tools. Exact argument match. Cached tools: `context7-resolve-library-id`, `github-get-*`, `github-list-branches`, `github-list-tags`, `github-list-releases`, `github-list-issue-types`, `aws-docs-*`.

**Excluded from both caches**: all write/mutate tools, rapidly-changing list endpoints (issues, PRs, commits), and stateful servers (slack, postgres, opnsense).

### Disabling caches

Each layer can be disabled independently:

| Layer | How to disable |
|-------|----------------|
| Registry cache | `REGISTRY_CACHE_ENABLED=false` in `gateway.env` |
| Admin stats cache | `ADMIN_STATS_CACHE_ENABLED=false` in `gateway.env` |
| Plugin framework | `PLUGINS_ENABLED=false` in `gateway.env` |
| Individual plugin | `mode: "disabled"` in `plugins.yaml` |

After changing values, run `darwin-rebuild switch` to regenerate configs, then restart the gateway.

## Verification

After a rebuild:

```bash
# gateway running
mcpgw-status

# bridges running
mcpgw-bridges

# virtual server and token configured
cat ~/.local/share/contextforge/virtual-server-id
ls -la ~/.local/share/contextforge/gateway-token

# sync servers and register with gateway
contextforge-mcp-sync

# check registered gateways
curl -s http://127.0.0.1:4444/gateways | jq '.[].name'

# print resolved server inventory
contextforge-mcp-sync --print
```

Service logs (darwin) — rotated on each rebuild, kept to ~3 days of output:

```bash
tail ~/Library/Logs/contextforge-gateway.log
tail ~/Library/Logs/contextforge-setup.log
tail ~/Library/Logs/contextforge-bridge.log
```

Service logs (linux) — managed by journald:

```bash
journalctl --user -u contextforge-gateway
journalctl --user -u contextforge-setup
journalctl --user -u contextforge-bridge-supervisor
```

## Disaster recovery

The gateway stores all state in a single SQLite DB (`gateway.db`). If the DB is lost or corrupted (unclean shutdown, disk I/O error, version migration), three things go stale:

1. **Virtual server** — the saved UUID no longer exists in the new DB
2. **Gateway registrations** — all registered MCP servers are gone
3. **JWT token** — still valid (minted from a static secret, not stored in DB)

### Automatic recovery (on service restart)

The setup service validates the saved UUID on every run by querying `GET /servers/{uuid}` against the live gateway. If the server doesn't exist:

1. Removes stale `virtual-server-id` and `gateway-token`
2. Creates a new virtual server and mints a fresh token
3. Runs `contextforge-mcp-sync` to re-register gateways and associate tools with the virtual server

This handles the common case where `darwin-rebuild switch` or a crash cycles the gateway and the DB gets recreated. The setup service runs at boot (`RunAtLoad=true`), so recovery is automatic after a reboot.

### Manual recovery (mid-session)

If the DB is lost while the machine is running (no reboot), the setup service won't re-run automatically. Use:

```bash
mcpgw-setup
```

This unconditionally clears stale state, recreates the virtual server and token, and re-runs `contextforge-mcp-sync` to re-register all gateways and associate their tools with the virtual server. One command, full recovery.

### Clean slate

Wipe all state, caches, and logs, then let the next rebuild recreate everything from scratch.

darwin:

```bash
# stop all services
uid="$(id -u)"
launchctl bootout "gui/$uid/com.contextforge.gateway" 2>/dev/null
launchctl bootout "gui/$uid/com.contextforge.bridge-supervisor" 2>/dev/null
launchctl bootout "gui/$uid/com.contextforge.setup" 2>/dev/null
pkill -f mcpgateway 2>/dev/null

# remove state, cache, and logs
rm -rf ~/.local/share/contextforge
rm -rf ~/.cache/contextforge
rm -f ~/Library/Logs/contextforge-*.log

# rebuild — services come back automatically
darwin-rebuild switch --flake .
```

linux:

```bash
# stop all services
systemctl --user stop contextforge-gateway contextforge-bridge-supervisor contextforge-setup

# remove state, cache, and logs
rm -rf ~/.local/share/contextforge
rm -rf ~/.cache/contextforge
journalctl --user --unit='contextforge-*' --rotate && \
journalctl --user --unit='contextforge-*' --vacuum-time=0

# rebuild — services come back automatically
home-manager switch --flake .
```

After the rebuild, the setup service creates a new virtual server and token, and syncs all MCP servers. Verify with `mcpgw-status` and `mcpgw-bridges`.

## Troubleshooting

**`mcpgw-wrapper` stalls or exits with "authentication failed"**
The JWT token is missing or the gateway secret changed. Run `mcpgw-setup` to regenerate it. Check that `~/.local/share/contextforge/gateway-token` exists. The token does not expire.

**`mcpgw-wrapper` exits with "virtual server not configured"**
The setup service hasn't completed yet, or failed. Check setup logs. Run `mcpgw-setup` to repair manually.

**Gateway not reachable**
Check that the gateway service is running and that nothing else is bound to port 4444. On darwin: `launchctl list | grep contextforge`. On linux: `systemctl --user status contextforge-gateway`.

**Bridge not reachable / sync shows "bridge not reachable"**
Check bridge supervisor logs (`~/Library/Logs/contextforge-bridge.log`). Run `mcpgw-bridges` to see per-bridge status. Common causes: missing `mcpgw-bridge.env`, missing env vars, stale process on the bridge port.

**Sync skips a server with "missing env vars"**
The server's header values reference environment variables that aren't set. Export the required variables before running `contextforge-mcp-sync`.

**Sync fails with "gateway not healthy"**
The gateway must be running before sync can register servers. Check `mcpgw-status`.

**SQLite disk I/O error / corrupted gateway DB**
The setup service self-heals on restart: it validates the saved UUID against the live gateway and recreates the virtual server + token if the DB was lost. If you need to force a full reset: kill all mcpgateway processes, delete `~/.local/share/contextforge/gateway.db`, restart the gateway service, then run `mcpgw-setup` (which clears stale state, recreates everything, and re-syncs).

**Launchd agents not loading after rebuild**
The post-activation ensure hook handles most cases. If agents are still missing, check `launchctl list | grep contextforge` and manually bootstrap: `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.contextforge.gateway.plist`.

**UI shows login page**
The gateway bootstraps with a default admin password. If the DB was created before auth settings were configured, reset it: `sqlite3 ~/.local/share/contextforge/gateway.db "UPDATE email_users SET password_change_required = 0"`. Or delete the DB and restart.
