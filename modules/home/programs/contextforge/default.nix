{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.contextforge;
  is_darwin = pkgs.stdenv.isDarwin;

  config_dir = "${config.xdg.configHome}/contextforge";
  data_dir = "${config.xdg.dataHome}/contextforge";
  cache_dir = "${config.xdg.cacheHome}/contextforge";

  db_path = "${data_dir}/gateway.db";

  gateway_env = pkgs.writeText "gateway.env" (
    lib.concatStringsSep "\n" [
      "HOST=${cfg.host}"
      "PORT=${toString cfg.port}"
      "DATABASE_URL=sqlite:///${db_path}"
      "MCPGATEWAY_UI_ENABLED=${lib.boolToString cfg.ui_enabled}"
      "MCPGATEWAY_ADMIN_API_ENABLED=${lib.boolToString cfg.admin_api_enabled}"
      "LOG_LEVEL=${cfg.log_level}"
      "LOG_FORMAT=json"
      "CACHE_TYPE=memory"

      # plugin framework
      "PLUGINS_ENABLED=true"
      "PLUGIN_CONFIG_FILE=${config_dir}/plugins.yaml"

      # registry cache
      "REGISTRY_CACHE_ENABLED=true"
      "REGISTRY_CACHE_TOOLS_TTL=20"
      "REGISTRY_CACHE_PROMPTS_TTL=15"
      "REGISTRY_CACHE_RESOURCES_TTL=15"
      "REGISTRY_CACHE_AGENTS_TTL=20"
      "REGISTRY_CACHE_SERVERS_TTL=20"
      "REGISTRY_CACHE_GATEWAYS_TTL=20"

      # admin stats cache
      "ADMIN_STATS_CACHE_ENABLED=true"
      "ADMIN_STATS_CACHE_SYSTEM_TTL=60"
      "ADMIN_STATS_CACHE_OBSERVABILITY_TTL=30"

      "ENVIRONMENT=${cfg.environment}"
      "AUTH_REQUIRED=false"
      "SECURE_COOKIES=false"
      "PLATFORM_ADMIN_PASSWORD=Local!Dev#2026"
      "DEFAULT_USER_PASSWORD=Local!Dev#2026"
      "PASSWORD_CHANGE_ENFORCEMENT_ENABLED=false"
      "ADMIN_REQUIRE_PASSWORD_CHANGE_ON_BOOTSTRAP=false"
      "DETECT_DEFAULT_PASSWORD_ON_LOGIN=false"
      ""
    ]
  );

  # external plugins from IBM/mcp-context-forge — not bundled with the pip package.
  # assembled into a plugins/ package tree so `kind` import paths resolve.
  plugins_dir = let
    cached_src = ./plugins/cached_tool_result.py;
    prompt_src = ./plugins/response_cache_by_prompt.py;
  in pkgs.runCommand "contextforge-plugins" {} ''
    mkdir -p $out/plugins/cached_tool_result
    mkdir -p $out/plugins/response_cache_by_prompt

    touch $out/plugins/__init__.py
    touch $out/plugins/cached_tool_result/__init__.py
    touch $out/plugins/response_cache_by_prompt/__init__.py

    cp ${cached_src} $out/plugins/cached_tool_result/cached_tool_result.py
    cp ${prompt_src} $out/plugins/response_cache_by_prompt/response_cache_by_prompt.py
  '';

  plugins_yaml = pkgs.writeText "plugins.yaml" ''
    plugin_settings: {}
    plugins:
      - name: "ResponseCacheByPrompt"
        kind: "plugins.response_cache_by_prompt.response_cache_by_prompt.ResponseCacheByPromptPlugin"
        hooks: ["tool_pre_invoke", "tool_post_invoke"]
        mode: "permissive"
        priority: 120
        config:
          cacheable_tools:
            - "context7-query-docs"
            - "context7-resolve-library-id"
            - "aws-docs-read-documentation"
            - "aws-docs-recommend"
            - "github-search-code"
            - "github-search-repositories"
            - "github-search-issues"
            - "github-search-pull-requests"
            - "github-search-users"
          fields: ["prompt", "input", "query", "url", "libraryName"]
          ttl: 900
          threshold: 0.92
          max_entries: 1000

      - name: "CachedToolResult"
        kind: "plugins.cached_tool_result.cached_tool_result.CachedToolResultPlugin"
        hooks: ["tool_pre_invoke", "tool_post_invoke"]
        mode: "permissive"
        priority: 110
        config:
          cacheable_tools:
            - "context7-resolve-library-id"
            - "github-get-me"
            - "github-get-file-contents"
            - "github-get-label"
            - "github-get-tag"
            - "github-get-latest-release"
            - "github-get-release-by-tag"
            - "github-get-teams"
            - "github-get-team-members"
            - "github-list-branches"
            - "github-list-tags"
            - "github-list-releases"
            - "github-list-issue-types"
            - "aws-docs-read-documentation"
            - "aws-docs-recommend"
          ttl: 300
          max_entries: 5000
  '';

  mcp_servers_source = ../../../../mcp-servers.toml;

  # gateway daemon wrapper — sources env files, execs uvx
  gateway_script = pkgs.writeShellScript "contextforge-gateway" ''
    set -euo pipefail
    export PATH="${lib.makeBinPath [ pkgs.uv pkgs.coreutils ]}:$PATH"

    # plugins on PYTHONPATH so `kind` imports resolve
    export PYTHONPATH="${plugins_dir}:''${PYTHONPATH:-}"

    # load nix-managed env
    set -a
    # shellcheck disable=SC1091
    . "${config_dir}/gateway.env"
    set +a

    # ensure sqlite data dir exists
    mkdir -p "${data_dir}"

    exec uvx --from mcp-contextforge-gateway mcpgateway \
      --host "$HOST" --port "$PORT"
  '';

  # bridge supervisor — spawns mcpgateway.translate per stdio server with bridge.port
  bridge_supervisor_script = pkgs.writeShellScript "contextforge-bridge-supervisor" ''
    set -eo pipefail
    export PATH="${lib.makeBinPath [ pkgs.uv pkgs.python3 pkgs.nodejs pkgs.coreutils ]}:$PATH"

    # writable cache dirs for npx/uv package downloads
    export HOME="${config.home.homeDirectory}"
    export NPM_CONFIG_CACHE="${cache_dir}/npm"
    export UV_CACHE_DIR="${cache_dir}/uv"
    mkdir -p "$NPM_CONFIG_CACHE" "$UV_CACHE_DIR"

    # source secrets for bridge children (slack tokens, opnsense keys, etc.)
    env_file="${config_dir}/mcpgw-bridge.env"
    if [[ -f "$env_file" ]]; then
      set -a
      # shellcheck disable=SC1090
      . "$env_file"
      set +a
      echo "bridge supervisor: loaded $env_file"
    else
      echo "bridge supervisor: no $env_file found, bridges relying on env vars may fail"
    fi

    config_file="${config_dir}/mcp-servers.toml"

    # extract bridge configs: "name command arg1 arg2 ... |port|key1=val1 key2=val2"
    readarray -t bridges < <(python3 - "$config_file" <<'PY'
import sys

try:
    import tomllib
except ModuleNotFoundError:
    print("error: python3 lacks tomllib", file=sys.stderr)
    sys.exit(1)

config_path = sys.argv[1]
with open(config_path, "rb") as f:
    data = tomllib.load(f)

for server in data.get("servers", []):
    if not isinstance(server, dict):
        continue
    transport = (server.get("transport") or "").lower()
    if transport != "stdio":
        continue
    bridge = server.get("bridge") or {}
    port = bridge.get("port")
    if not port:
        continue
    name = server.get("name", "unknown")
    command = server.get("command", "")
    args = server.get("args") or []
    env = server.get("env") or {}
    cmd_parts = [command] + args
    env_pairs = " ".join(f"{k}={v}" for k, v in env.items())
    print(f"{name}\t{' '.join(cmd_parts)}\t{port}\t{env_pairs}")
PY
    )

    if [[ ''${#bridges[@]} -eq 0 ]]; then
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

    cleanup() {
      echo "bridge supervisor: shutting down"
      for pid in "''${pids[@]}"; do
        kill "$pid" 2>/dev/null || true
      done
      sleep 2
      for pid in "''${pids[@]}"; do
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

      # kill stale process on port
      local stale_pid
      stale_pid="$(lsof -ti :"$port" 2>/dev/null || true)"
      if [[ -n "$stale_pid" ]]; then
        echo "bridge supervisor: killing stale process on port $port (pid $stale_pid)"
        kill "$stale_pid" 2>/dev/null || true
        sleep 1
      fi

      echo "bridge supervisor: starting $name on port $port"
      local bridge_cmd="uv run --with mcp-contextforge-gateway python -m mcpgateway.translate --stdio \"$cmd\" --expose-streamable-http --port $port --host 127.0.0.1 --stateless --jsonResponse"
      if [[ -n "$env_vars" ]]; then
        bridge_cmd="env $env_vars $bridge_cmd"
      fi
      eval "$bridge_cmd" &
      pids[$name]=$!
      last_start[$name]="$(date +%s)"
      echo "bridge supervisor: $name started (pid ''${pids[$name]})"
    }

    # readiness check — POST to bridge /mcp endpoint
    check_ready() {
      local name="$1"
      local port="$2"
      local elapsed=0
      while (( elapsed < readiness_timeout )); do
        if curl -sf --max-time 2 -X POST -H "Content-Type: application/json" -d '{}' "http://127.0.0.1:$port/mcp" >/dev/null 2>&1; then
          return 0
        fi
        sleep 1
        (( elapsed++ )) || true
      done
      return 1
    }

    # parse and start all bridges
    for entry in "''${bridges[@]}"; do
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
    for name in "''${!pids[@]}"; do
      port="''${bridge_ports[$name]}"
      if check_ready "$name" "$port"; then
        echo "bridge supervisor: $name ready on port $port"
        fail_counts[$name]=0
        backoff_secs[$name]=$initial_backoff
      else
        echo "bridge supervisor: $name not ready after ''${readiness_timeout}s (may still be starting)"
      fi
    done

    echo "bridge supervisor: monitoring ''${#pids[@]} bridge(s)"

    # monitor loop — check children, restart dead ones with backoff
    while true; do
      sleep 5
      for name in "''${!pids[@]}"; do
        # skip bridges that hit max failures
        if (( ''${stopped[$name]} )); then
          continue
        fi

        if ! kill -0 "''${pids[$name]}" 2>/dev/null; then
          fc="''${fail_counts[$name]}"
          (( fc++ )) || true
          fail_counts[$name]=$fc
          bo="''${backoff_secs[$name]}"

          if (( fc >= max_failures )); then
            echo "bridge supervisor: $name failed $fc times consecutively, giving up (check config/env)"
            stopped[$name]=1
            continue
          fi

          echo "bridge supervisor: $name (pid ''${pids[$name]}) died (failure $fc/$max_failures), restarting in ''${bo}s"
          sleep "$bo"

          # exponential backoff: double, capped at max_backoff
          new_bo=$(( bo * 2 ))
          if (( new_bo > max_backoff )); then
            new_bo=$max_backoff
          fi
          backoff_secs[$name]=$new_bo

          start_bridge "$name" "''${bridge_cmds[$name]}" "''${bridge_ports[$name]}" "''${bridge_envs[$name]}"

          # readiness check — reset failure count on success
          if check_ready "$name" "''${bridge_ports[$name]}"; then
            echo "bridge supervisor: $name ready on port ''${bridge_ports[$name]}"
            fail_counts[$name]=0
            backoff_secs[$name]=$initial_backoff
          fi
        fi
      done
    done
  '';

  # one-shot setup script — waits for gateway, creates virtual server, acquires jwt token
  setup_script = pkgs.writeShellScript "contextforge-auto-setup" ''
    set -euo pipefail
    export PATH="${lib.makeBinPath [ pkgs.uv pkgs.python3 pkgs.curl pkgs.jq pkgs.coreutils ]}:$PATH"

    url="http://${cfg.host}:${toString cfg.port}"
    uuid_file="${data_dir}/virtual-server-id"
    token_file="${data_dir}/gateway-token"

    # wait for gateway health (60s max, 2s intervals)
    attempts=0
    max_attempts=30
    while ! curl -sf "$url/health" >/dev/null 2>&1; do
      attempts=$((attempts + 1))
      if [[ $attempts -ge $max_attempts ]]; then
        echo "error: gateway not healthy after $((max_attempts * 2))s" >&2
        exit 1
      fi
      sleep 2
    done
    echo "gateway healthy"

    # ensure virtual server exists — validate saved uuid against live gateway
    needs_create=0
    if [[ -f "$uuid_file" ]]; then
      saved_uuid="$(cat "$uuid_file")"
      if curl -sf "$url/servers/$saved_uuid" >/dev/null 2>&1; then
        echo "virtual server verified: $saved_uuid"
      else
        echo "virtual server stale (db recreated?), removing $uuid_file"
        rm -f "$uuid_file" "$token_file"
        needs_create=1
      fi
    else
      needs_create=1
    fi

    if [[ "$needs_create" -eq 1 ]]; then
      response="$(curl -sf -X POST \
        -H "Content-Type: application/json" \
        -d '{"server": {"name": "contextforge-all", "tools": "all"}}' \
        "$url/servers" 2>/dev/null)" || {
        # 409 means it already exists — fetch the existing uuid
        uuid="$(curl -sf "$url/servers" 2>/dev/null \
          | jq -r '.[] | select(.name == "contextforge-all") | .id // empty')"
        if [[ -z "$uuid" ]]; then
          echo "error: failed to create or find virtual server" >&2
          exit 1
        fi
        echo "virtual server already exists: $uuid"
      }

      if [[ -z "''${uuid:-}" ]]; then
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
      token="$(uv run --with PyJWT python3 -c "
import jwt, warnings
warnings.filterwarnings('ignore')
print(jwt.encode(
    {'sub': 'admin@example.com', 'iss': 'mcpgateway', 'aud': 'mcpgateway-api',
     'user': {'email': 'admin@example.com', 'full_name': 'Local Admin',
              'is_admin': True, 'auth_provider': 'local'}},
    'my-test-key', algorithm='HS256'))
" 2>/dev/null)" || {
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
    for env_file in "$HOME/.env" "${config_dir}/mcpgw-bridge.env"; do
      if [[ -f "$env_file" ]]; then
        set -a
        # shellcheck disable=SC1090
        . "$env_file"
        set +a
      fi
    done

    # wait for at least one bridge to become reachable before syncing;
    # the bridge supervisor starts in parallel, so give it time.
    # probe the first expected bridge port with curl (lsof may not be in PATH)
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
      echo "warning: no bridges reachable after ''${bridge_max}s, syncing anyway"
    else
      echo "bridge detected after ''${bridge_wait}s"
      # settle time for remaining bridges to finish starting
      sleep 3
    fi

    # sync mcp servers with gateway (registers http + bridged servers)
    export PATH="${lib.makeBinPath [ pkgs.coreutils pkgs.curl pkgs.jq pkgs.python3 ]}:$PATH"
    echo "syncing mcp servers..."
    ${sync_script}/bin/contextforge-mcp-sync || echo "warning: sync failed" >&2
  '';

  sync_script = pkgs.writeShellScriptBin "contextforge-mcp-sync" ''
    set -euo pipefail
    umask 077
    export PATH="${lib.makeBinPath [ pkgs.coreutils pkgs.curl pkgs.jq pkgs.python3 ]}:$PATH"

    config_file="${config_dir}/mcp-servers.toml"
    output_file="${config_dir}/mcp-servers.json"
    dry_run=0
    print_only=0

    usage() {
      echo "usage: contextforge-mcp-sync [--dry-run] [--print]"
    }

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --dry-run)
          dry_run=1
          ;;
        --print)
          print_only=1
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

    mkdir -p "${config_dir}"

    temp_file="$(mktemp)"
    python3 - "$config_file" "$temp_file" <<'PY'
import json
import os
import re
import sys

try:
    import tomllib
except ModuleNotFoundError:
    print("error: python3 lacks tomllib", file=sys.stderr)
    sys.exit(1)

config_path = sys.argv[1]
output_path = sys.argv[2]

def read_toml(path):
    try:
        with open(path, "rb") as handle:
            return tomllib.load(handle)
    except FileNotFoundError:
        return {}
    except tomllib.TOMLDecodeError as exc:
        print(f"error: invalid toml: {exc}", file=sys.stderr)
        sys.exit(1)

pattern = re.compile(r"\$(\w+)|\''${([^}]+)}")

def expand_value(value, missing):
    if isinstance(value, str):
        for match in pattern.findall(value):
            env_name = match[0] or match[1]
            if os.environ.get(env_name) is None:
                missing.add(env_name)
        return os.path.expandvars(value)
    if isinstance(value, dict):
        return {key: expand_value(val, missing) for key, val in value.items()}
    if isinstance(value, list):
        return [expand_value(val, missing) for val in value]
    return value

def expand_headers(headers, missing):
    if not isinstance(headers, dict):
        return {}, missing
    resolved = {}
    for key, value in headers.items():
        resolved[key] = expand_value(value, missing)
    return resolved, missing

data = read_toml(config_path)
servers = data.get("servers", [])
if not isinstance(servers, list):
    servers = []

inventory = []
for item in servers:
    if not isinstance(item, dict):
        continue
    name = item.get("name")
    if not name:
        continue
    transport = (item.get("transport") or "http").lower()
    url = item.get("url")
    missing = set()
    headers, _ = expand_headers(item.get("headers", {}), missing)
    auth_headers = []
    auth_headers_raw = item.get("auth_headers")
    if isinstance(auth_headers_raw, list):
        for entry in auth_headers_raw:
            if not isinstance(entry, dict):
                continue
            key = entry.get("key")
            if key is None:
                continue
            value = expand_value(entry.get("value", ""), missing)
            auth_headers.append(
                {
                    "key": str(key),
                    "value": "" if value is None else str(value),
                }
            )
    elif headers:
        for key in sorted(headers.keys()):
            value = headers[key]
            auth_headers.append(
                {
                    "key": str(key),
                    "value": "" if value is None else str(value),
                }
            )

    oauth_config = item.get("oauth_config") or {}
    if isinstance(oauth_config, dict):
        oauth_config = expand_value(oauth_config, missing)
    else:
        oauth_config = {}

    auth_type = item.get("auth_type")
    if not auth_type:
        if oauth_config:
            auth_type = "oauth"
        elif auth_headers:
            auth_type = "authheaders"
    command = item.get("command")
    args = item.get("args") or []
    env = item.get("env") or {}
    bridge = item.get("bridge") or {}
    bridge_port = bridge.get("port")
    bridge_url = bridge.get("url")
    if bridge_port and not bridge_url:
        bridge_url = f"http://127.0.0.1:{bridge_port}/mcp"
    gateway_register = item.get("gateway_register")
    if gateway_register is None:
        if transport == "http":
            gateway_register = True
        else:
            gateway_register = bool(bridge_url)

    gateway_transport = None
    if transport in ("http", "streamablehttp", "streamable_http"):
        gateway_transport = "STREAMABLEHTTP"
    elif transport == "sse":
        gateway_transport = "SSE"
    elif transport == "stdio" and bridge_url:
        # stdio servers can register via their http bridge
        gateway_transport = "STREAMABLEHTTP"

    inventory.append(
        {
            "name": name,
            "transport": transport,
            "gateway_transport": gateway_transport,
            "url": url,
            "headers": headers,
            "missing_headers": sorted(missing),
            "auth_type": auth_type,
            "auth_headers": auth_headers,
            "oauth_config": oauth_config,
            "command": command,
            "args": args,
            "env": env,
            "bridge_url": bridge_url,
            "gateway_register": bool(gateway_register),
        }
    )

inventory = sorted(inventory, key=lambda item: item["name"])
with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(inventory, handle, indent=2, sort_keys=True)
PY

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

    gateway_url="http://${cfg.host}:${toString cfg.port}"

    if ! curl -sf "$gateway_url/health" >/dev/null 2>&1; then
      echo "gateway sync: gateway not healthy"
      exit 1
    fi

    gateways_json="$(curl -sf --max-time 10 "$gateway_url/gateways" 2>/dev/null || true)"
    if [[ -z "$gateways_json" ]]; then
      echo "gateway sync: failed to fetch gateways"
      exit 1
    fi

    bridge_fail_marker="$(mktemp)"
    rm -f "$bridge_fail_marker"

    ${pkgs.jq}/bin/jq -c '.[]' "$output_file" | while read -r server; do
      name="$(echo "$server" | ${pkgs.jq}/bin/jq -r '.name')"
      transport="$(echo "$server" | ${pkgs.jq}/bin/jq -r '.transport')"
      gateway_transport="$(echo "$server" | ${pkgs.jq}/bin/jq -r '.gateway_transport // empty')"
      url="$(echo "$server" | ${pkgs.jq}/bin/jq -r '.url // empty')"
      bridge_url="$(echo "$server" | ${pkgs.jq}/bin/jq -r '.bridge_url // empty')"
      register="$(echo "$server" | ${pkgs.jq}/bin/jq -r '.gateway_register')"
      missing_count="$(echo "$server" | ${pkgs.jq}/bin/jq -r '.missing_headers | length')"
      auth_type="$(echo "$server" | ${pkgs.jq}/bin/jq -r '.auth_type // empty')"
      auth_headers="$(echo "$server" | ${pkgs.jq}/bin/jq -c '.auth_headers // []')"
      oauth_config="$(echo "$server" | ${pkgs.jq}/bin/jq -c '.oauth_config // {}')"

      if [[ "$register" != "true" ]]; then
        echo "  $name: skip (register=false)"
        continue
      fi

      if [[ "$missing_count" -gt 0 ]]; then
        missing_names="$(echo "$server" | ${pkgs.jq}/bin/jq -r '.missing_headers | join(", ")')"
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

      if echo "$gateways_json" | ${pkgs.jq}/bin/jq -e --arg name "$name" '.gateways // . // [] | any(.name == $name)' >/dev/null 2>&1; then
        echo "  $name: ok (registered)"
        continue
      fi

      # pre-check: verify bridge is reachable for stdio servers (POST — bridges reject GET)
      if [[ "$transport" == "stdio" && -n "$bridge_url" ]]; then
        if ! curl -sf --max-time 3 -X POST -H "Content-Type: application/json" -d '{}' "$bridge_url" >/dev/null 2>&1; then
          echo "  $name: bridge down ($bridge_url)"
          touch "$bridge_fail_marker"
          continue
        fi
      fi

      body="$(echo "$server" | ${pkgs.jq}/bin/jq -c \
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
      elif [[ "$http_code" == "409" ]]; then
        echo "  $name: ok (registered)"
      elif [[ "$http_code" == "503" ]]; then
        reason="$(echo "$resp_body" | ${pkgs.jq}/bin/jq -r '.message // empty' 2>/dev/null)"
        echo "  $name: unreachable''${reason:+ — $reason}"
      else
        reason="$(echo "$resp_body" | ${pkgs.jq}/bin/jq -r '.message // .detail // empty' 2>/dev/null)"
        echo "  $name: failed (http $http_code)''${reason:+ — $reason}"
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

    # associate discovered tools with the virtual server, applying exclude_tools policy.
    # waits for tool discovery to stabilize after registering new gateways.
    uuid_file="${data_dir}/virtual-server-id"
    if [[ -f "$uuid_file" ]]; then
      uuid="$(cat "$uuid_file")"

      # poll until tool count stabilizes (gateway is still discovering)
      prev_count=0
      stable_rounds=0
      for _ in $(seq 1 15); do
        cur_count="$(curl -sf --max-time 5 "$gateway_url/tools" 2>/dev/null \
          | ${pkgs.jq}/bin/jq 'length' 2>/dev/null || echo 0)"
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

      # fetch tools, apply exclude_tools policy from config, output filtered ids + summary
      tool_output="$(curl -sf --max-time 10 "$gateway_url/tools" 2>/dev/null \
        | python3 - "$config_file" <<'PYEOF'
import json, sys, fnmatch
try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib

tools = json.load(sys.stdin)
with open(sys.argv[1], "rb") as f:
    config = tomllib.load(f)

patterns = config.get("exclude_tools", [])
included, excluded = [], []
for t in tools:
    name = t.get("name", "")
    if any(fnmatch.fnmatch(name, p) for p in patterns):
        excluded.append(name)
    else:
        included.append(t.get("id", ""))

result = {"ids": included, "excluded": sorted(excluded)}
print(json.dumps(result))
PYEOF
      )" || tool_output='{"ids":[],"excluded":[]}'

      tool_ids="$(echo "$tool_output" | ${pkgs.jq}/bin/jq -c '.ids')"
      tool_count="$(echo "$tool_output" | ${pkgs.jq}/bin/jq '.ids | length')"
      excluded_list="$(echo "$tool_output" | ${pkgs.jq}/bin/jq -r '.excluded | join(", ")')"

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
  '';

  # client wrapper — AI agents spawn this as a stdio MCP server
  client_wrapper = pkgs.writeShellScriptBin "mcpgw-wrapper" ''
    set -euo pipefail
    export PATH="${lib.makeBinPath [ pkgs.uv pkgs.coreutils ]}:$PATH"

    # read virtual server uuid — fail fast, no polling
    uuid_file="${data_dir}/virtual-server-id"
    if [[ ! -f "$uuid_file" ]]; then
      echo "error: virtual server not configured." >&2
      echo "the contextforge-setup service should create it automatically." >&2
      echo "check service logs or run mcpgw-setup to repair manually." >&2
      exit 1
    fi
    uuid="$(cat "$uuid_file")"

    export MCP_SERVER_URL="http://${cfg.host}:${toString cfg.port}/servers/$uuid/mcp"

    # load jwt token for virtual server auth (acquired by setup service)
    token_file="${data_dir}/gateway-token"
    if [[ -f "$token_file" ]]; then
      export MCP_AUTH="Bearer $(cat "$token_file")"
    fi

    exec uv run --with mcp-contextforge-gateway python -m mcpgateway.wrapper
  '';

  log_level_type = lib.types.enum [
    "DEBUG"
    "INFO"
    "WARNING"
    "ERROR"
    "CRITICAL"
  ];

  environment_type = lib.types.enum [
    "development"
    "staging"
    "production"
  ];
in
{
  options.programs.contextforge = {
    enable = lib.mkEnableOption "ContextForge MCP gateway";

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Bind address for the gateway.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 4444;
      description = "Bind port for the gateway.";
    };

    ui_enabled = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the admin web UI.";
    };

    admin_api_enabled = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the admin REST API.";
    };

    log_level = lib.mkOption {
      type = log_level_type;
      default = "INFO";
      description = "Log verbosity for the gateway.";
    };

    environment = lib.mkOption {
      type = environment_type;
      default = "development";
      description = "Runtime environment hint.";
    };
  };

  config = lib.mkIf cfg.enable {
    # 1. client wrapper on PATH
    home.packages = [
      client_wrapper
      sync_script
    ];

    # 2. nix-managed gateway env file
    xdg.configFile."contextforge/gateway.env" = {
      source = gateway_env;
      force = true;
    };

    xdg.configFile."contextforge/mcp-servers.toml" = {
      source = mcp_servers_source;
      force = true;
    };

    xdg.configFile."contextforge/plugins.yaml" = {
      source = plugins_yaml;
      force = true;
    };

    # 3. activation: create dirs + prune old logs (darwin only — linux uses journald)
    home.activation.contextforge_setup = lib.hm.dag.entryAfter [ "writeBoundary" ] (''
      mkdir -p "${data_dir}"
      mkdir -p "${cache_dir}"
    '' + lib.optionalString is_darwin ''
      # rotate contextforge logs — keep last 5000 lines (~3 days of output)
      log_dir="$HOME/Library/Logs"
      for f in "$log_dir"/contextforge-*.log; do
        [[ -f "$f" ]] || continue
        lines="$(wc -l < "$f" 2>/dev/null || echo 0)"
        if (( lines > 5000 )); then
          tmp="$(mktemp)"
          tail -n 5000 "$f" > "$tmp" && mv "$tmp" "$f"
        fi
      done
    '');

    # 3b. post-activation (darwin): ensure all contextforge agents are loaded and running.
    # unconditionally bootstraps any agent that isn't loaded (catches setupLaunchAgents
    # failures and first installs). does NOT cycle already-running agents — the setup
    # service handles re-syncing state, and launchd KeepAlive handles gateway restarts.
    home.activation.contextforge_ensure_agents = lib.mkIf is_darwin (
      lib.hm.dag.entryAfter [ "setupLaunchAgents" ] ''
        uid="$(id -u)"
        domain="gui/$uid"
        agent_dir="$HOME/Library/LaunchAgents"
        for label in com.contextforge.gateway com.contextforge.bridge-supervisor com.contextforge.setup; do
          plist="$agent_dir/$label.plist"
          [[ -f "$plist" ]] || continue
          if ! /bin/launchctl print "$domain/$label" >/dev/null 2>&1; then
            /bin/launchctl bootstrap "$domain" "$plist" 2>/dev/null || true
          fi
        done

        # kick setup to re-validate state and sync (runs in background)
        /bin/launchctl kickstart "gui/$uid/com.contextforge.setup" 2>/dev/null &
      ''
    );

    # 3d. post-activation (linux): re-trigger setup service to validate state and re-sync
    home.activation.contextforge_resync = lib.mkIf (!is_darwin) (
      lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
        # restart the oneshot so it re-validates uuid and re-syncs gateways;
        # runs in background to avoid blocking activation
        ${pkgs.systemd}/bin/systemctl --user restart contextforge-setup.service 2>/dev/null &
      ''
    );

    # 4. platform service — darwin launchd agent
    launchd.agents.contextforge-gateway = lib.mkIf is_darwin (
      let
        log_path = "${config.home.homeDirectory}/Library/Logs/contextforge-gateway.log";
      in
      {
        enable = true;
        config = {
          Label = "com.contextforge.gateway";
          ProgramArguments = [ "${gateway_script}" ];
          RunAtLoad = true;
          KeepAlive = true;
          StandardOutPath = log_path;
          StandardErrorPath = log_path;
          EnvironmentVariables = {
            PATH = lib.makeBinPath [
              pkgs.uv
              pkgs.coreutils
            ];
          };
        };
      }
    );

    # 4b. platform service — linux systemd user service
    systemd.user.services.contextforge-gateway = lib.mkIf (!is_darwin) {
      Unit = {
        Description = "ContextForge MCP gateway";
        After = [ "default.target" ];
      };
      Service = {
        ExecStart = "${gateway_script}";
        Restart = "always";
        RestartSec = 5;
        Environment = [
          "PATH=${lib.makeBinPath [ pkgs.uv pkgs.coreutils ]}"
        ];
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };

    # 5a. one-shot setup service — darwin launchd agent
    launchd.agents.contextforge-setup = lib.mkIf is_darwin (
      let
        setup_log_path = "${config.home.homeDirectory}/Library/Logs/contextforge-setup.log";
      in
      {
        enable = true;
        config = {
          Label = "com.contextforge.setup";
          ProgramArguments = [ "${setup_script}" ];
          RunAtLoad = true;
          KeepAlive = false;
          StandardOutPath = setup_log_path;
          StandardErrorPath = setup_log_path;
          EnvironmentVariables = {
            PATH = lib.makeBinPath [
              pkgs.uv
              pkgs.python3
              pkgs.curl
              pkgs.jq
              pkgs.coreutils
            ];
          };
        };
      }
    );

    # 5c. bridge supervisor service — darwin launchd agent
    launchd.agents.contextforge-bridge-supervisor = lib.mkIf is_darwin (
      let
        bridge_log_path = "${config.home.homeDirectory}/Library/Logs/contextforge-bridge.log";
      in
      {
        enable = true;
        config = {
          Label = "com.contextforge.bridge-supervisor";
          ProgramArguments = [ "${bridge_supervisor_script}" ];
          RunAtLoad = true;
          KeepAlive = true;
          StandardOutPath = bridge_log_path;
          StandardErrorPath = bridge_log_path;
          EnvironmentVariables = {
            PATH = lib.makeBinPath [
              pkgs.uv
              pkgs.python3
              pkgs.nodejs
              pkgs.curl
              pkgs.jq
              pkgs.coreutils
            ];
          };
        };
      }
    );

    # 5d. bridge supervisor service — linux systemd user service
    systemd.user.services.contextforge-bridge-supervisor = lib.mkIf (!is_darwin) {
      Unit = {
        Description = "ContextForge MCP bridge supervisor";
        After = [ "contextforge-gateway.service" ];
      };
      Service = {
        ExecStart = "${bridge_supervisor_script}";
        Restart = "always";
        RestartSec = 5;
        Environment = [
          "PATH=${lib.makeBinPath [ pkgs.uv pkgs.python3 pkgs.nodejs pkgs.curl pkgs.jq pkgs.coreutils ]}"
        ];
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };

    # 5b. one-shot setup service — linux systemd user service
    systemd.user.services.contextforge-setup = lib.mkIf (!is_darwin) {
      Unit = {
        Description = "ContextForge MCP gateway auto-setup";
        After = [ "contextforge-gateway.service" ];
        Requires = [ "contextforge-gateway.service" ];
      };
      Service = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${setup_script}";
        Environment = [
          "PATH=${lib.makeBinPath [ pkgs.uv pkgs.python3 pkgs.curl pkgs.jq pkgs.coreutils ]}"
        ];
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };

    # 6. shell integration
    programs.zsh.initContent = lib.mkAfter ''
      # contextforge gateway status
      function mcpgw-status() {
        local url="http://${cfg.host}:${toString cfg.port}"
        local health
        health="$(curl -sf "$url/health" 2>/dev/null)" || {
          echo "contextforge gateway: not reachable at $url"
          return 1
        }
        echo "contextforge gateway: healthy"
        echo "url: $url"
        echo "health: $health"
      }

      # contextforge manual repair/re-setup tool
      # cleans stale state, re-creates virtual server + token, re-syncs gateways
      function mcpgw-setup() {
        local url="http://${cfg.host}:${toString cfg.port}"
        local data_dir="${data_dir}"
        local uuid_file="$data_dir/virtual-server-id"
        local token_file="$data_dir/gateway-token"

        echo "==> manual repair/re-setup for contextforge"
        echo ""

        # clean stale state so everything is recreated fresh
        rm -f "$uuid_file" "$token_file"
        echo "==> cleared stale uuid and token"

        echo ""
        echo "==> waiting for gateway health..."
        local attempts=0
        while ! curl -sf "$url/health" >/dev/null 2>&1; do
          attempts=$((attempts + 1))
          if [[ $attempts -ge 30 ]]; then
            echo "error: gateway not healthy after 30 attempts" >&2
            return 1
          fi
          sleep 1
        done
        echo "gateway is healthy"

        echo ""
        echo "==> creating virtual server with all tools..."
        local response uuid
        response="$(curl -sf -X POST \
          -H "Content-Type: application/json" \
          -d '{"server": {"name": "contextforge-all", "tools": "all"}}' \
          "$url/servers" 2>/dev/null)" || {
          # 409 means it already exists — fetch the existing uuid
          uuid="$(curl -sf "$url/servers" 2>/dev/null \
            | ${pkgs.jq}/bin/jq -r '.[] | select(.name == "contextforge-all") | .id // empty')"
          if [[ -z "$uuid" ]]; then
            echo "error: failed to create or find virtual server" >&2
            return 1
          fi
          echo "virtual server already exists: $uuid"
        }

        if [[ -z "''${uuid:-}" ]]; then
          uuid="$(echo "$response" | ${pkgs.jq}/bin/jq -r '.id // .uuid // empty')"
          if [[ -z "$uuid" ]]; then
            echo "error: no uuid returned from server creation" >&2
            echo "response: $response"
            return 1
          fi
        fi

        local tmp
        tmp="$(mktemp)"
        echo "$uuid" > "$tmp"
        mv "$tmp" "$uuid_file"
        echo "virtual server uuid: $uuid"
        echo "saved to $uuid_file"

        echo ""
        echo "==> generating gateway token..."
        local token
        token="$(uv run --with PyJWT python3 -c "
import jwt, warnings
warnings.filterwarnings('ignore')
print(jwt.encode(
    {'sub': 'admin@example.com', 'iss': 'mcpgateway', 'aud': 'mcpgateway-api',
     'user': {'email': 'admin@example.com', 'full_name': 'Local Admin',
              'is_admin': True, 'auth_provider': 'local'}},
    'my-test-key', algorithm='HS256'))
" 2>/dev/null)" || {
          echo "warning: failed to generate token" >&2
        }

        if [[ -n "''${token:-}" ]]; then
          tmp="$(mktemp)"
          echo "$token" > "$tmp"
          chmod 600 "$tmp"
          mv "$tmp" "$token_file"
          echo "gateway token saved to $token_file"
        fi

        echo ""
        echo "==> re-registering mcp servers with gateway..."
        contextforge-mcp-sync || echo "warning: sync failed, run contextforge-mcp-sync manually" >&2

        echo ""
        echo "==> done! verify with: mcpgw-status"
      }

      # contextforge bridge status checker
      function mcpgw-bridges() {
        local config_file="${config_dir}/mcp-servers.toml"
        python3 - "$config_file" <<'PYBRIDGE'
import sys

try:
    import tomllib
except ModuleNotFoundError:
    print("error: python3 lacks tomllib", file=sys.stderr)
    sys.exit(1)

import subprocess

config_path = sys.argv[1]
with open(config_path, "rb") as f:
    data = tomllib.load(f)

bridges = []
for server in data.get("servers", []):
    if not isinstance(server, dict):
        continue
    transport = (server.get("transport") or "").lower()
    if transport != "stdio":
        continue
    bridge = server.get("bridge") or {}
    port = bridge.get("port")
    if not port:
        continue
    name = server.get("name", "unknown")
    bridges.append((name, port))

if not bridges:
    print("no stdio bridges configured")
    sys.exit(0)

print(f"{'name':<20} {'port':<8} {'status'}")
print("-" * 40)
for name, port in bridges:
    try:
        result = subprocess.run(
            ["curl", "-sf", "--max-time", "2", "-X", "POST", "-H", "Content-Type: application/json", "-d", "{}", f"http://127.0.0.1:{port}/mcp"],
            capture_output=True, timeout=5
        )
        status = "healthy" if result.returncode == 0 else "unreachable"
    except Exception:
        status = "unreachable"
    print(f"{name:<20} {port:<8} {status}")
PYBRIDGE
      }
    '';
  };
}
