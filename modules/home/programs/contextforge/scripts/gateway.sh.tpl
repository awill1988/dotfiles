#!@BASH@
set -euo pipefail
export PATH="@PATH@:$PATH"

# plugins on PYTHONPATH so `kind` imports resolve
export PYTHONPATH="@PLUGINS_DIR@:${PYTHONPATH:-}"

# load nix-managed env
set -a
# shellcheck disable=SC1091
. "@CONFIG_DIR@/gateway.env"
set +a

# ensure sqlite data dir exists
mkdir -p "@DATA_DIR@"

exec uvx --from mcp-contextforge-gateway mcpgateway \
  --host "$HOST" --port "$PORT"
