# Grafana MCP for Claude

This guide configures the Grafana MCP server for Claude sessions without Nix.

## Required Access

- VPN access to the monitoring network
- Claude Code installed and authenticated
- `uv` installed, which provides `uvx`
- A Grafana service account token from 1Password

The Grafana endpoint is:

```bash
export GRAFANA_URL="https://grafana.monitoring.arrofinance.io"
```

Store the service account token in your shell for the current terminal:

```bash
export GRAFANA_SERVICE_ACCOUNT_TOKEN="<token from 1Password>"
```

Do not commit the token, paste it into chat, or save it in a project file.

## Install `uv`

macOS with Homebrew:

```bash
brew install uv
```

Other platforms:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

Verify `uvx` is available:

```bash
uvx --version
```

## VPN and Token Test

Connect to VPN, then run:

```bash
curl -fsS \
  -H "Authorization: Bearer ${GRAFANA_SERVICE_ACCOUNT_TOKEN}" \
  "${GRAFANA_URL}/api/search?type=dash-db&limit=1"
```

Expected result: JSON output and exit code `0`.

Common failures:

- `could not resolve host`, timeout, or TLS connection failure: VPN or DNS is not connected to the monitoring network.
- `401` or `403`: the token is missing, expired, copied incorrectly, or lacks Grafana permissions.
- `404`: confirm `GRAFANA_URL` has no trailing path and is exactly `https://grafana.monitoring.arrofinance.io`.

Optional readable check with `jq`:

```bash
curl -fsS \
  -H "Authorization: Bearer ${GRAFANA_SERVICE_ACCOUNT_TOKEN}" \
  "${GRAFANA_URL}/api/search?type=dash-db&limit=1" | jq .
```

## Add Grafana MCP to Claude Code

Use user scope so the server is available in any Claude session:

```bash
claude mcp add --scope user \
  --env GRAFANA_URL="${GRAFANA_URL}" \
  --env GRAFANA_SERVICE_ACCOUNT_TOKEN="${GRAFANA_SERVICE_ACCOUNT_TOKEN}" \
  --transport stdio \
  grafana -- uvx mcp-grafana
```

Verify Claude registered it:

```bash
claude mcp get grafana
claude mcp list
```

Inside a Claude session, run:

```text
/mcp
```

The `grafana` server should show as connected.

## Manual JSON Fallback

If the `claude mcp add` command is unavailable, add this entry to the `mcpServers` object in `~/.claude.json`:

```json
{
  "mcpServers": {
    "grafana": {
      "command": "uvx",
      "args": ["mcp-grafana"],
      "env": {
        "GRAFANA_URL": "https://grafana.monitoring.arrofinance.io",
        "GRAFANA_SERVICE_ACCOUNT_TOKEN": "<token from 1Password>"
      }
    }
  }
}
```

If `~/.claude.json` already has other MCP servers, merge only the `grafana` object into the existing `mcpServers` object.

Restart Claude after editing `~/.claude.json`.

## Docker Fallback

Use this if installing `uv` is not an option:

```bash
claude mcp add --scope user \
  --env GRAFANA_URL="${GRAFANA_URL}" \
  --env GRAFANA_SERVICE_ACCOUNT_TOKEN="${GRAFANA_SERVICE_ACCOUNT_TOKEN}" \
  --transport stdio \
  grafana -- docker run --rm -i \
    -e GRAFANA_URL \
    -e GRAFANA_SERVICE_ACCOUNT_TOKEN \
    grafana/mcp-grafana -t stdio
```

## Usage Examples

After `/mcp` shows `grafana` as connected, ask Claude for read-only Grafana work, for example:

```text
list grafana dashboards related to payments
```

```text
show available grafana datasources
```

```text
find dashboards with panels querying loki for api errors
```

## Notes

- Use `GRAFANA_SERVICE_ACCOUNT_TOKEN`; `GRAFANA_API_KEY` is deprecated by upstream `mcp-grafana`.
- The token should come from 1Password and should not be stored in the repository.
- The curl test validates both VPN reachability and token authorization before debugging Claude.

## References

- Grafana MCP server: <https://github.com/grafana/mcp-grafana>
- Claude Code MCP configuration: <https://docs.anthropic.com/en/docs/claude-code/mcp>
