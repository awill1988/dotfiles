#!@BASH@
set -eo pipefail
export PATH="@PATH@:$PATH"

# writable cache dirs for npx/uv package downloads
export HOME="@HOME@"
export NPM_CONFIG_CACHE="@CACHE_DIR@/npm"
export UV_CACHE_DIR="@CACHE_DIR@/uv"
mkdir -p "$NPM_CONFIG_CACHE" "$UV_CACHE_DIR"

# source secrets for bridge children (slack tokens, opnsense keys, etc.)
env_file="@CONFIG_DIR@/mcpgw-bridge.env"
if [[ -f "$env_file" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$env_file"
  set +a
  echo "bridge supervisor: loaded $env_file"
else
  echo "bridge supervisor: no $env_file found, bridges relying on env vars may fail"
fi

config_file="@CONFIG_DIR@/mcp-servers.toml"

# extract bridge configs: "name command arg1 arg2 ... |port|key1=val1 key2=val2"
readarray -t bridges < <(python3 "@PARSE_TOML_PY@" "$config_file")

if [[ ${#bridges[@]} -eq 0 ]]; then
  echo "bridge supervisor: no stdio bridges configured, idling"
  exec sleep infinity
fi

declare -A pids
declare -A bridge_names
declare -A bridge_cmds
declare -A bridge_ports
declare -A bridge_envs
declare -A fail_counts    # consecutive failures per bridge
declare -A backoff_secs   # current backoff per bridge
declare -A last_start     # epoch of last start attempt per bridge
declare -A stopped        # bridges that hit max failures

max_failures=5            # consecutive failures before giving up
initial_backoff=3         # seconds
max_backoff=300           # 5 minutes cap
readiness_timeout=15      # seconds to wait for bridge readiness
liveness_interval=60      # seconds between liveness checks per bridge
liveness_timeout=30       # seconds to wait for liveness response
liveness_restart_after=3  # consecutive failures before restarting (allows slow API calls)
max_liveness_fails=6      # consecutive failures before giving up entirely

declare -A liveness_fails
declare -A last_liveness

cleanup() {
  echo "bridge supervisor: shutting down"
  for pid in "${pids[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  sleep 2
  for pid in "${pids[@]}"; do
    kill -9 "$pid" 2>/dev/null || true
  done
  exit 0
}
trap cleanup SIGTERM SIGINT

start_bridge() {
  local name="$1"
  local cmd="$2"
  local port="$3"
  local env_vars="$4"

  # kill stale process on port (SIGTERM → SIGKILL escalation)
  local stale_pids
  stale_pids="$(lsof -ti :"$port" 2>/dev/null || true)"
  if [[ -n "$stale_pids" ]]; then
    echo "bridge supervisor: killing stale process(es) on port $port (pids: $(echo $stale_pids | tr '\n' ' '))"
    echo "$stale_pids" | xargs kill 2>/dev/null || true
    sleep 1
    # force-kill survivors
    stale_pids="$(lsof -ti :"$port" 2>/dev/null || true)"
    if [[ -n "$stale_pids" ]]; then
      echo "$stale_pids" | xargs kill -9 2>/dev/null || true
      sleep 1
    fi
  fi

  echo "bridge supervisor: starting $name on port $port"
  local bridge_cmd="uv run --with mcp-contextforge-gateway python -m mcpgateway.translate --stdio \"$cmd\" --expose-streamable-http --port $port --host 127.0.0.1 --stateless --jsonResponse"
  if [[ -n "$env_vars" ]]; then
    bridge_cmd="env $env_vars $bridge_cmd"
  fi
  eval "$bridge_cmd" &
  pids[$name]=$!
  last_start[$name]="$(date +%s)"
  last_liveness[$name]="$(date +%s)"
  liveness_fails[$name]=0
  echo "bridge supervisor: $name started (pid ${pids[$name]})"
}

# readiness check — POST to bridge /mcp endpoint, then perform MCP initialize
# handshake so the subprocess is ready for subsequent liveness pings.
check_ready() {
  local name="$1"
  local port="$2"
  local elapsed=0
  local base_url="http://127.0.0.1:$port/mcp"
  while (( elapsed < readiness_timeout )); do
    if curl -sf --max-time 2 -X POST -H "Content-Type: application/json" -d '{}' "$base_url" >/dev/null 2>&1; then
      # bridge http layer is up — send mcp initialize handshake so the stdio
      # subprocess is ready to respond to liveness pings.
      local init_body='{"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"bridge-supervisor","version":"1.0"}},"id":0}'
      local notif_body='{"jsonrpc":"2.0","method":"notifications/initialized"}'
      if curl -sf --max-time 10 -X POST -H "Content-Type: application/json" -d "$init_body" "$base_url" >/dev/null 2>&1; then
        curl -sf --max-time 3 -X POST -H "Content-Type: application/json" -d "$notif_body" "$base_url" >/dev/null 2>&1 || true
        return 0
      fi
      # initialize failed — subprocess may not be ready yet, keep trying
    fi
    sleep 1
    (( elapsed++ )) || true
  done
  return 1
}

# parse and start all bridges
for entry in "${bridges[@]}"; do
  IFS=$'\t' read -r name cmd port env_vars <<< "$entry"
  bridge_names[$name]="$name"
  bridge_cmds[$name]="$cmd"
  bridge_ports[$name]="$port"
  bridge_envs[$name]="$env_vars"
  fail_counts[$name]=0
  backoff_secs[$name]=$initial_backoff
  stopped[$name]=0
  start_bridge "$name" "$cmd" "$port" "$env_vars"
done

# initial readiness checks (non-blocking — don't hold up the monitor loop)
for name in "${!pids[@]}"; do
  port="${bridge_ports[$name]}"
  if check_ready "$name" "$port"; then
    echo "bridge supervisor: $name ready on port $port"
    fail_counts[$name]=0
    backoff_secs[$name]=$initial_backoff
  else
    echo "bridge supervisor: $name not ready after ${readiness_timeout}s (may still be starting)"
  fi
done

echo "bridge supervisor: monitoring ${#pids[@]} bridge(s)"

# monitor loop — check children, restart dead/hung ones
while true; do
  sleep 5
  for name in "${!pids[@]}"; do
    # skip bridges that hit max failures
    if (( ${stopped[$name]} )); then
      continue
    fi

    if kill -0 "${pids[$name]}" 2>/dev/null; then
      # process alive — periodic liveness check via MCP ping
      now="$(date +%s)"
      started="${last_start[$name]:-0}"

      # skip during startup grace period
      if (( now - started < readiness_timeout + 5 )); then
        continue
      fi

      last_check="${last_liveness[$name]:-0}"
      if (( now - last_check < liveness_interval )); then
        continue
      fi

      last_liveness[$name]="$now"
      port="${bridge_ports[$name]}"

      if ! curl -sf --max-time "$liveness_timeout" -X POST \
          -H "Content-Type: application/json" \
          -d '{"jsonrpc":"2.0","method":"ping","id":0}' \
          "http://127.0.0.1:$port/mcp" >/dev/null 2>&1; then
        lf="${liveness_fails[$name]:-0}"
        (( lf++ )) || true
        liveness_fails[$name]=$lf

        if (( lf >= max_liveness_fails )); then
          echo "bridge supervisor: $name unresponsive $lf consecutive checks, giving up"
          stopped[$name]=1
          kill "${pids[$name]}" 2>/dev/null || true
          sleep 1
          kill -9 "${pids[$name]}" 2>/dev/null || true
          continue
        fi

        if (( lf < liveness_restart_after )); then
          # might just be a slow API call — warn but don't restart yet
          echo "bridge supervisor: $name slow on port $port ($lf/$liveness_restart_after before restart)"
          continue
        fi

        echo "bridge supervisor: $name unresponsive on port $port ($lf/$max_liveness_fails), restarting"
        kill "${pids[$name]}" 2>/dev/null || true
        sleep 1
        kill -9 "${pids[$name]}" 2>/dev/null || true

        start_bridge "$name" "${bridge_cmds[$name]}" "${bridge_ports[$name]}" "${bridge_envs[$name]}"
        if check_ready "$name" "${bridge_ports[$name]}"; then
          echo "bridge supervisor: $name ready on port $port"
          liveness_fails[$name]=0
          fail_counts[$name]=0
          backoff_secs[$name]=$initial_backoff
        fi
      else
        liveness_fails[$name]=0
      fi
    else
      # process dead — restart with backoff
      fc="${fail_counts[$name]}"
      (( fc++ )) || true
      fail_counts[$name]=$fc
      bo="${backoff_secs[$name]}"

      if (( fc >= max_failures )); then
        echo "bridge supervisor: $name failed $fc times consecutively, giving up (check config/env)"
        stopped[$name]=1
        continue
      fi

      echo "bridge supervisor: $name (pid ${pids[$name]}) died (failure $fc/$max_failures), restarting in ${bo}s"
      sleep "$bo"

      # exponential backoff: double, capped at max_backoff
      new_bo=$(( bo * 2 ))
      if (( new_bo > max_backoff )); then
        new_bo=$max_backoff
      fi
      backoff_secs[$name]=$new_bo

      start_bridge "$name" "${bridge_cmds[$name]}" "${bridge_ports[$name]}" "${bridge_envs[$name]}"

      # readiness check — reset failure count on success
      if check_ready "$name" "${bridge_ports[$name]}"; then
        echo "bridge supervisor: $name ready on port ${bridge_ports[$name]}"
        fail_counts[$name]=0
        backoff_secs[$name]=$initial_backoff
      fi
    fi
  done
done
