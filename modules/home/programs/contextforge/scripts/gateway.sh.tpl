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

# --- watchdog configuration ---
health_url="http://${HOST}:${PORT}/health"
health_interval=30       # seconds between health checks
health_timeout=5         # seconds per health check request
max_failures=5           # consecutive failures before restart
startup_grace=10         # seconds after start before first health check

gw_pid=""
consecutive_failures=0

kill_gateway() {
  if [[ -z "${gw_pid:-}" ]]; then
    return
  fi
  if ! kill -0 "$gw_pid" 2>/dev/null; then
    gw_pid=""
    return
  fi
  kill "$gw_pid" 2>/dev/null || true
  local i=0
  while kill -0 "$gw_pid" 2>/dev/null && (( i < 5 )); do
    sleep 1
    (( i++ )) || true
  done
  if kill -0 "$gw_pid" 2>/dev/null; then
    kill -9 "$gw_pid" 2>/dev/null || true
  fi
  wait "$gw_pid" 2>/dev/null || true
  gw_pid=""
}

start_gateway() {
  # clear anything still holding the port
  local stale
  stale="$(lsof -ti :"$PORT" 2>/dev/null || true)"
  if [[ -n "$stale" ]]; then
    echo "gateway watchdog: killing stale process(es) on port $PORT"
    echo "$stale" | xargs kill -9 2>/dev/null || true
    sleep 1
  fi

  @MCPGATEWAY_BIN@ \
    --host "$HOST" --port "$PORT" &
  gw_pid=$!
  consecutive_failures=0
  echo "gateway watchdog: started (pid $gw_pid)"
}

cleanup() {
  echo "gateway watchdog: shutting down"
  pkill -P "${gw_pid:-0}" 2>/dev/null || true
  kill_gateway
  exit 0
}
trap cleanup SIGTERM SIGINT

start_gateway
sleep "$startup_grace"

while true; do
  sleep "$health_interval"

  # check if process is still alive
  if ! kill -0 "$gw_pid" 2>/dev/null; then
    echo "gateway watchdog: process died, restarting"
    gw_pid=""
    start_gateway
    sleep "$startup_grace"
    continue
  fi

  # health check
  if curl -sf --max-time "$health_timeout" "$health_url" >/dev/null 2>&1; then
    consecutive_failures=0
  else
    (( consecutive_failures++ )) || true
    echo "gateway watchdog: health check failed ($consecutive_failures/$max_failures)"
    if (( consecutive_failures >= max_failures )); then
      echo "gateway watchdog: unresponsive, killing and restarting"
      kill_gateway
      sleep 2
      start_gateway
      sleep "$startup_grace"
    fi
  fi
done
