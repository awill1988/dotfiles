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

export MCP_SERVER_URL="http://@GATEWAY_HOST@:@GATEWAY_PORT@/servers/$uuid/mcp/"

# load jwt token for virtual server auth (acquired by setup service)
token_file="@DATA_DIR@/gateway-token"
if [[ -f "$token_file" ]]; then
  export MCP_AUTH="Bearer $(cat "$token_file")"
else
  echo "error: gateway token missing; run mcpgw-setup" >&2
  exit 1
fi

# Resolve profile-scoped DRIVE_ACCOUNT (falls back to CWD routing for GUI clients)
if [[ -z "${DRIVE_ACCOUNT:-}" ]]; then
  if [[ -x "@PROFILE_ROUTER@" ]]; then
    DRIVE_ACCOUNT="$("@PROFILE_ROUTER@" --show-drive-account 2>/dev/null || true)"
  elif command -v profile-router >/dev/null 2>&1; then
    DRIVE_ACCOUNT="$(profile-router --show-drive-account 2>/dev/null || true)"
  fi
fi

extra_args=()
if [[ -n "${DRIVE_ACCOUNT:-}" ]]; then
  export DRIVE_ACCOUNT
  extra_args+=(--header 'X-Drive-Account: ${DRIVE_ACCOUNT}')
fi

exec @REMOTE_BIN@ "$MCP_SERVER_URL" --auth none --header 'Authorization: ${MCP_AUTH}' "${extra_args[@]}"
