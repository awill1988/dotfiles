#!@BASH@
set -euo pipefail
export PATH="@PATH@:$PATH"

url="@GATEWAY_URL@"
uuid_file="@DATA_DIR@/virtual-server-id"
token_file="@DATA_DIR@/gateway-token"

# wait for gateway health (60s max, 2s intervals)
attempts=0
max_attempts=30
while ! curl -sf --max-time 5 "$url/health" >/dev/null 2>&1; do
  attempts=$((attempts + 1))
  if [[ $attempts -ge $max_attempts ]]; then
    echo "error: gateway not healthy after $((max_attempts * 2))s" >&2
    exit 1
  fi
  sleep 2
done
echo "gateway healthy"

# ensure virtual server exists — validate saved uuid against live gateway
first_run=1
needs_create=0
if [[ -f "$uuid_file" ]]; then
  saved_uuid="$(cat "$uuid_file")"
  if curl -sf --max-time 5 "$url/servers/$saved_uuid" >/dev/null 2>&1; then
    echo "virtual server verified: $saved_uuid"
    first_run=0
  else
    echo "virtual server stale (db recreated?), removing $uuid_file"
    rm -f "$uuid_file" "$token_file"
    needs_create=1
  fi
else
  needs_create=1
fi

if [[ "$needs_create" -eq 1 ]]; then
  response="$(curl -sf --max-time 10 -X POST \
    -H "Content-Type: application/json" \
    -d '{"server": {"name": "contextforge-all", "tools": "all"}}' \
    "$url/servers" 2>/dev/null)" || {
    # 409 means it already exists — fetch the existing uuid
    uuid="$(curl -sf --max-time 10 "$url/servers" 2>/dev/null \
      | jq -r '.[] | select(.name == "contextforge-all") | .id // empty')"
    if [[ -z "$uuid" ]]; then
      echo "error: failed to create or find virtual server" >&2
      exit 1
    fi
    echo "virtual server already exists: $uuid"
  }

  if [[ -z "${uuid:-}" ]]; then
    uuid="$(echo "$response" | jq -r '.id // .uuid // empty')"
    if [[ -z "$uuid" ]]; then
      echo "error: no uuid returned from server creation" >&2
      echo "response: $response" >&2
      exit 1
    fi
  fi

  # atomic write
  tmp="$(mktemp)"
  echo "$uuid" > "$tmp"
  mv "$tmp" "$uuid_file"
  echo "virtual server created: $uuid"

  # stale uuid means gateway registrations are also gone — trigger re-sync
  echo "gateway db may have been recreated, run contextforge-mcp-sync to re-register servers"
fi

# generate a non-expiring jwt for the wrapper
# the /mcp endpoint requires bearer auth even with AUTH_REQUIRED=false;
# since this is local dev with a known secret, we mint a static token
if [[ ! -f "$token_file" ]]; then
  token="$(uv run --with PyJWT python3 "@GENERATE_TOKEN_PY@" 2>/dev/null)" || {
    echo "warning: failed to generate jwt, wrapper may not authenticate" >&2
    exit 0
  }

  if [[ -n "$token" ]]; then
    tmp="$(mktemp)"
    echo "$token" > "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$token_file"
    echo "gateway token generated (saved to $token_file)"
  fi
else
  echo "gateway token already exists: $token_file"
fi

# source secrets so env var expansion in headers works (CONTEXT7_API_KEY, etc.)
# load ~/.env first (user-level secrets), then bridge env (overrides)
for env_file in "$HOME/.env" "@CONFIG_DIR@/mcpgw-bridge.env"; do
  if [[ -f "$env_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    . "$env_file"
    set +a
  fi
done

# sync mcp servers with gateway (registers http + bridged servers)
export PATH="@SYNC_PATH@:$PATH"

if [[ "$first_run" -eq 1 ]]; then
  # first run: wait for bridges to come up before full sync
  echo "waiting for bridges..."
  bridge_wait=0
  bridge_max=30
  while (( bridge_wait < bridge_max )); do
    if curl -sf --max-time 1 -X POST -H "Content-Type: application/json" \
        -d '{}' "http://127.0.0.1:4450/mcp" >/dev/null 2>&1 || \
       curl -sf --max-time 1 -X POST -H "Content-Type: application/json" \
        -d '{}' "http://127.0.0.1:4451/mcp" >/dev/null 2>&1; then
      break
    fi
    sleep 1
    (( bridge_wait++ )) || true
  done
  if (( bridge_wait >= bridge_max )); then
    echo "warning: no bridges reachable after ${bridge_max}s, syncing anyway"
  else
    echo "bridge detected after ${bridge_wait}s"
    # settle time for remaining bridges to finish starting
    sleep 3
  fi
  echo "syncing mcp servers..."
  @SYNC_BIN@ || echo "warning: sync failed" >&2
else
  # subsequent runs: lightweight reconcile (skips tool discovery when nothing new)
  echo "reconciling mcp servers..."
  @SYNC_BIN@ --reconcile || echo "warning: reconcile failed" >&2
fi
