#!@BASH@
set -euo pipefail
umask 077
export PATH="@PATH@:$PATH"

config_file="@CONFIG_DIR@/mcp-servers.toml"
output_file="@CONFIG_DIR@/mcp-servers.json"
dry_run=0
print_only=0
reconcile=0

usage() {
  echo "usage: contextforge-mcp-sync [--dry-run] [--print] [--reconcile]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      dry_run=1
      ;;
    --print)
      print_only=1
      ;;
    --reconcile)
      reconcile=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [[ ! -f "$config_file" ]]; then
  echo "sync: config file missing at $config_file" >&2
  exit 1
fi

mkdir -p "@CONFIG_DIR@"

temp_file="$(mktemp)"
python3 "@PARSE_TOML_PY@" "$config_file" "$temp_file"

chmod 600 "$temp_file"
mv "$temp_file" "$output_file"
echo "sync: wrote $output_file"

if [[ "$print_only" -eq 1 ]]; then
  cat "$output_file"
  exit 0
fi

if [[ "$dry_run" -eq 1 ]]; then
  echo "sync: dry-run enabled, skipping gateway registration"
  exit 0
fi

gateway_url="@GATEWAY_URL@"

if ! curl -sf "$gateway_url/health" >/dev/null 2>&1; then
  echo "gateway sync: gateway not healthy"
  exit 1
fi

# poll until total tool count stabilizes (gateway discovers tools async after registration)
wait_for_stable_tools() {
  local max_polls="${1:-15}"
  local prev_count=0 stable_rounds=0
  for _ in $(seq 1 "$max_polls"); do
    cur_count="$(curl -sf --max-time 5 "$gateway_url/tools" 2>/dev/null \
      | @JQ@ 'length' 2>/dev/null || echo 0)"
    if (( cur_count > 0 && cur_count == prev_count )); then
      (( stable_rounds++ )) || true
      if (( stable_rounds >= 2 )); then
        break
      fi
    else
      stable_rounds=0
    fi
    prev_count="$cur_count"
    sleep 2
  done
}

gateways_json="$(curl -sf --max-time 10 "$gateway_url/gateways" 2>/dev/null || true)"
if [[ -z "$gateways_json" ]]; then
  echo "gateway sync: failed to fetch gateways"
  exit 1
fi

all_tools_json="$(curl -sf --max-time 10 "$gateway_url/tools" 2>/dev/null || echo '[]')"

bridge_fail_marker="$(mktemp)"
rm -f "$bridge_fail_marker"

new_reg_marker="$(mktemp)"
rm -f "$new_reg_marker"

@JQ@ -c '.[]' "$output_file" | while read -r server; do
  name="$(echo "$server" | @JQ@ -r '.name')"
  transport="$(echo "$server" | @JQ@ -r '.transport')"
  gateway_transport="$(echo "$server" | @JQ@ -r '.gateway_transport // empty')"
  url="$(echo "$server" | @JQ@ -r '.url // empty')"
  bridge_url="$(echo "$server" | @JQ@ -r '.bridge_url // empty')"
  register="$(echo "$server" | @JQ@ -r '.gateway_register')"
  missing_count="$(echo "$server" | @JQ@ -r '.missing_headers | length')"
  auth_type="$(echo "$server" | @JQ@ -r '.auth_type // empty')"
  auth_headers="$(echo "$server" | @JQ@ -c '.auth_headers // []')"
  oauth_config="$(echo "$server" | @JQ@ -c '.oauth_config // {}')"

  if [[ "$register" != "true" ]]; then
    echo "  $name: skip (register=false)"
    continue
  fi

  if [[ "$missing_count" -gt 0 ]]; then
    missing_names="$(echo "$server" | @JQ@ -r '.missing_headers | join(", ")')"
    echo "  $name: skip (missing: $missing_names)"
    continue
  fi

  register_url="$url"
  if [[ "$transport" != "http" ]]; then
    register_url="$bridge_url"
  fi

  if [[ -z "$register_url" ]]; then
    echo "  $name: skip (no url)"
    continue
  fi

  if echo "$gateways_json" | @JQ@ -e --arg name "$name" \
      '(if type == "object" then .gateways // [] else . end) | any(.name == $name)' >/dev/null 2>&1; then

    gw_id="$(echo "$gateways_json" | @JQ@ -r --arg name "$name" \
      '(if type == "object" then .gateways // [] else . end)[] | select(.name == $name) | .id')"
    gw_tool_count="$(echo "$all_tools_json" | @JQ@ \
      --arg gid "$gw_id" '[.[] | select(.gatewayId == $gid)] | length')"

    if (( gw_tool_count > 0 )); then
      echo "  $name: ok ($gw_tool_count tools)"
      continue
    fi

    # 0 tools — check if bridge is healthy before re-registering
    check_url="$register_url"
    if [[ "$transport" == "stdio" && -n "$bridge_url" ]]; then
      check_url="$bridge_url"
    fi

    if [[ -n "$check_url" ]] && curl -sf --max-time 3 -X POST \
        -H "Content-Type: application/json" -d '{}' "$check_url" >/dev/null 2>&1; then
      curl -sf --max-time 5 -X DELETE "$gateway_url/gateways/$gw_id" >/dev/null 2>&1 || true
      # refresh gateways list so subsequent iterations don't see stale data
      gateways_json="$(curl -sf --max-time 10 "$gateway_url/gateways" 2>/dev/null || echo '[]')"
      echo "  $name: stale (0 tools), re-registering"
      # fall through to registration
    else
      echo "  $name: ok (0 tools, bridge down)"
      continue
    fi
  fi

  # pre-check: verify bridge is reachable for stdio servers (POST — bridges reject GET)
  if [[ "$transport" == "stdio" && -n "$bridge_url" ]]; then
    if ! curl -sf --max-time 3 -X POST -H "Content-Type: application/json" -d '{}' "$bridge_url" >/dev/null 2>&1; then
      echo "  $name: bridge down ($bridge_url)"
      touch "$bridge_fail_marker"
      continue
    fi
  fi

  body="$(echo "$server" | @JQ@ -c \
    --arg name "$name" \
    --arg url "$register_url" \
    --arg auth_type "$auth_type" \
    --arg transport "$gateway_transport" \
    --argjson auth_headers "$auth_headers" \
    --argjson oauth_config "$oauth_config" \
    '{
      name: $name,
      url: $url,
      initialize_timeout: null
    }
    + (if $transport != "" then {transport: $transport} else {} end)
    + (if $auth_type != "" then {auth_type: $auth_type} else {} end)
    + (if ($auth_headers | length) > 0 then {auth_headers: $auth_headers} else {} end)
    + (if ($oauth_config | type) == "object" and ($oauth_config | length) > 0 then {oauth_config: $oauth_config} else {} end)
    ' )"

  resp_file="$(mktemp)"
  http_code="$(curl -s --max-time 30 -o "$resp_file" -w '%{http_code}' \
    -X POST \
    -H "Content-Type: application/json" \
    -d "$body" \
    "$gateway_url/gateways" 2>&1)" || http_code="000"
  resp_body="$(cat "$resp_file" 2>/dev/null || true)"
  rm -f "$resp_file"

  if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
    echo "  $name: ok (registered)"
    touch "$new_reg_marker"
  elif [[ "$http_code" == "409" ]]; then
    echo "  $name: ok (already exists)"
  elif [[ "$http_code" == "503" ]]; then
    reason="$(echo "$resp_body" | @JQ@ -r '.message // empty' 2>/dev/null)"
    echo "  $name: unreachable${reason:+ — $reason}"
  else
    reason="$(echo "$resp_body" | @JQ@ -r '.message // .detail // empty' 2>/dev/null)"
    echo "  $name: failed (http $http_code)${reason:+ — $reason}"
  fi
done

# single hint block for bridge failures
if [[ -f "$bridge_fail_marker" ]]; then
  rm -f "$bridge_fail_marker"
  echo ""
  echo "some bridges are down. check:"
  echo "  mcpgw-bridges"
  echo "  tail ~/Library/Logs/contextforge-bridge.log"
fi

# in reconcile mode, skip tool discovery when no new servers were registered
if [[ "$reconcile" -eq 1 && ! -f "$new_reg_marker" ]]; then
  echo "reconcile: all servers registered, skipping tool discovery"
  rm -f "$new_reg_marker"
  exit 0
fi
rm -f "$new_reg_marker"

# associate discovered tools with the virtual server, applying exclude_tools policy.
# waits for tool discovery to stabilize after registering new gateways.
uuid_file="@DATA_DIR@/virtual-server-id"
if [[ -f "$uuid_file" ]]; then
  uuid="$(cat "$uuid_file")"

  wait_for_stable_tools 15

  # retry gateways that ended up with 0 tools — bridge subprocess may have been
  # initializing when the gateway tried async discovery during registration.
  # deleting and re-registering triggers a fresh discovery attempt.
  retry_gateways_json="$(curl -sf --max-time 10 "$gateway_url/gateways" 2>/dev/null || echo '[]')"
  retry_tools_json="$(curl -sf --max-time 10 "$gateway_url/tools" 2>/dev/null || echo '[]')"
  retry_marker="$(mktemp)"
  rm -f "$retry_marker"

  @JQ@ -c '.[]' "$output_file" | while read -r server; do
    name="$(echo "$server" | @JQ@ -r '.name')"
    bridge_url="$(echo "$server" | @JQ@ -r '.bridge_url // empty')"
    [[ -n "$bridge_url" ]] || continue

    gw_id="$(echo "$retry_gateways_json" | @JQ@ -r --arg name "$name" \
      '(if type == "object" then .gateways // [] else . end)[] | select(.name == $name) | .id // empty')"
    [[ -n "$gw_id" ]] || continue

    gw_tools="$(echo "$retry_tools_json" | @JQ@ \
      --arg gid "$gw_id" '[.[] | select(.gatewayId == $gid)] | length')"

    if (( gw_tools == 0 )); then
      # only retry if bridge is actually reachable now
      if curl -sf --max-time 3 -X POST -H "Content-Type: application/json" -d '{}' \
          "$bridge_url" >/dev/null 2>&1; then
        echo "  $name: retry (0 tools, bridge healthy)"
        curl -sf --max-time 5 -X DELETE "$gateway_url/gateways/$gw_id" >/dev/null 2>&1 || true

        register_url="$bridge_url"
        gateway_transport="$(echo "$server" | @JQ@ -r '.gateway_transport // empty')"
        auth_type="$(echo "$server" | @JQ@ -r '.auth_type // empty')"
        auth_headers="$(echo "$server" | @JQ@ -c '.auth_headers // []')"

        body="$(echo "$server" | @JQ@ -c \
          --arg name "$name" \
          --arg url "$register_url" \
          --arg auth_type "$auth_type" \
          --arg transport "$gateway_transport" \
          --argjson auth_headers "$auth_headers" \
          '{name: $name, url: $url, initialize_timeout: null}
          + (if $transport != "" then {transport: $transport} else {} end)
          + (if $auth_type != "" then {auth_type: $auth_type} else {} end)
          + (if ($auth_headers | length) > 0 then {auth_headers: $auth_headers} else {} end)')"

        http_code="$(curl -s --max-time 30 -o /dev/null -w '%{http_code}' \
          -X POST -H "Content-Type: application/json" -d "$body" \
          "$gateway_url/gateways" 2>&1)" || http_code="000"

        if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
          echo "  $name: re-registered"
          touch "$retry_marker"
        fi
      fi
    fi
  done

  if [[ -f "$retry_marker" ]]; then
    rm -f "$retry_marker"
    sleep 3
    wait_for_stable_tools 10
  fi

  # fetch tools, apply exclude_tools policy from config, output filtered ids + summary
  tool_output="$(curl -sf --max-time 10 "$gateway_url/tools" 2>/dev/null \
    | python3 "@FILTER_TOOLS_PY@" "$config_file")" || tool_output='{"ids":[],"excluded":[]}'

  tool_ids="$(echo "$tool_output" | @JQ@ -c '.ids')"
  tool_count="$(echo "$tool_output" | @JQ@ '.ids | length')"
  excluded_list="$(echo "$tool_output" | @JQ@ -r '.excluded | join(", ")')"

  if (( tool_count > 0 )); then
    http_code="$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' \
      -X PUT -H "Content-Type: application/json" \
      -d "{\"associatedTools\": $tool_ids}" \
      "$gateway_url/servers/$uuid" 2>/dev/null)" || http_code="000"
    if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
      echo ""
      echo "virtual server: $tool_count tools associated"
      if [[ -n "$excluded_list" ]]; then
        echo "  excluded: $excluded_list"
      fi
    else
      echo ""
      echo "virtual server: failed to associate tools (http $http_code)"
    fi
  fi
fi
