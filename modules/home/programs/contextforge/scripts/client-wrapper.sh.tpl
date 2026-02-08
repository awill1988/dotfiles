#!@BASH@
set -euo pipefail
export PATH="@PATH@:$PATH"

# read virtual server uuid — fail fast, no polling
uuid_file="@DATA_DIR@/virtual-server-id"
if [[ ! -f "$uuid_file" ]]; then
  echo "error: virtual server not configured." >&2
  echo "the contextforge-setup service should create it automatically." >&2
  echo "check service logs or run mcpgw-setup to repair manually." >&2
  exit 1
fi
uuid="$(cat "$uuid_file")"

export MCP_SERVER_URL="http://@GATEWAY_HOST@:@GATEWAY_PORT@/servers/$uuid/mcp"

# load jwt token for virtual server auth (acquired by setup service)
token_file="@DATA_DIR@/gateway-token"
if [[ -f "$token_file" ]]; then
  export MCP_AUTH="Bearer $(cat "$token_file")"
fi

exec uv run --with mcp-contextforge-gateway python -m mcpgateway.wrapper
