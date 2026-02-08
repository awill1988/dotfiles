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
      "ENVIRONMENT=${cfg.environment}"
      ""
    ]
  );

  # gateway daemon wrapper — sources env files, execs uvx
  gateway_script = pkgs.writeShellScript "contextforge-gateway" ''
    set -euo pipefail
    export PATH="${lib.makeBinPath [ pkgs.uv pkgs.coreutils ]}:$PATH"

    # load nix-managed env
    set -a
    # shellcheck disable=SC1091
    . "${config_dir}/gateway.env"
    set +a

    # load user-managed secrets (jwt, basic auth)
    if [[ -f "${config_dir}/secrets.env" ]]; then
      set -a
      # shellcheck disable=SC1091
      . "${config_dir}/secrets.env"
      set +a
    fi

    # ensure sqlite data dir exists
    mkdir -p "${data_dir}"

    exec uvx --from mcp-contextforge-gateway mcpgateway \
      --host "$HOST" --port "$PORT"
  '';

  # one-shot setup script — waits for gateway, creates virtual server
  setup_script = pkgs.writeShellScript "contextforge-auto-setup" ''
    set -euo pipefail
    export PATH="${lib.makeBinPath [ pkgs.uv pkgs.curl pkgs.jq pkgs.coreutils ]}:$PATH"

    url="http://${cfg.host}:${toString cfg.port}"
    secrets="${config_dir}/secrets.env"
    uuid_file="${data_dir}/virtual-server-id"

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

    # load secrets for jwt token
    if [[ ! -f "$secrets" ]]; then
      echo "error: secrets.env not found at $secrets" >&2
      exit 1
    fi
    set -a
    # shellcheck disable=SC1090
    . "$secrets"
    set +a

    if [[ -z "''${JWT_TOKEN:-}" ]]; then
      echo "error: JWT_TOKEN not set in $secrets" >&2
      exit 1
    fi

    # create virtual server if not already done
    if [[ -f "$uuid_file" ]]; then
      echo "virtual server already configured: $(cat "$uuid_file")"
      exit 0
    fi

    response="$(curl -sf -X POST \
      -H "Authorization: Bearer $JWT_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{"name": "contextforge-all", "tools": "all"}' \
      "$url/servers" 2>/dev/null)" || {
      echo "error: failed to create virtual server" >&2
      exit 1
    }

    uuid="$(echo "$response" | jq -r '.id // .uuid // empty')"
    if [[ -z "$uuid" ]]; then
      echo "error: no uuid returned from server creation" >&2
      echo "response: $response" >&2
      exit 1
    fi

    # atomic write
    tmp="$(mktemp)"
    echo "$uuid" > "$tmp"
    mv "$tmp" "$uuid_file"
    echo "virtual server created: $uuid"
  '';

  sync_script = pkgs.writeShellScriptBin "contextforge-mcp-sync" ''
    set -euo pipefail
    umask 077
    export PATH="${lib.makeBinPath [ pkgs.coreutils pkgs.curl pkgs.jq pkgs.python3 ]}:$PATH"

    config_home="${config.xdg.configHome}"
    contextforge_dir="${config_dir}"
    output_file="${config_dir}/mcp-sync.json"
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

    mkdir -p "$contextforge_dir"

    temp_file="$(mktemp)"
    python3 - "$config_home" "${config.home.homeDirectory}" "$temp_file" <<'PY'
import json
import os
import re
import sys

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover
    import tomli as tomllib

config_home = sys.argv[1]
home_dir = sys.argv[2]
output_path = sys.argv[3]

def read_json(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        return {}
    except json.JSONDecodeError:
        return {}

def read_toml(path):
    try:
        with open(path, "rb") as handle:
            return tomllib.load(handle)
    except FileNotFoundError:
        return {}
    except tomllib.TOMLDecodeError:
        return {}

def expand_headers(headers, env_header_map, bearer_token_env_var):
    resolved = {}
    missing = []
    pattern = re.compile(r"\$(\w+)|\''${([^}]+)}")

    for key, value in headers.items():
        text = str(value)
        for match in pattern.findall(text):
            env_name = match[0] or match[1]
            if os.environ.get(env_name) is None:
                missing.append(env_name)
        resolved[key] = os.path.expandvars(text)

    for header, env_name in env_header_map.items():
        env_value = os.environ.get(env_name)
        if env_value is None:
            missing.append(env_name)
        else:
            resolved[header] = env_value

    if bearer_token_env_var:
        token = os.environ.get(bearer_token_env_var)
        if token is None:
            missing.append(bearer_token_env_var)
        elif "Authorization" not in resolved:
            resolved["Authorization"] = f"Bearer {token}"

    return resolved, sorted(set(missing))

def add_server(servers, name, record):
    existing = servers.get(name)
    if existing is None:
        servers[name] = record
        return

    if existing["kind"] != "http" and record["kind"] == "http":
        record["sources"] = sorted(set(existing["sources"] + record["sources"]))
        servers[name] = record
        return

    if existing["kind"] == "http" and record["kind"] == "http":
        existing["sources"] = sorted(set(existing["sources"] + record["sources"]))
        if not existing.get("headers") and record.get("headers"):
            existing["headers"] = record["headers"]
        if not existing.get("missing_headers") and record.get("missing_headers"):
            existing["missing_headers"] = record["missing_headers"]
        return

    existing["sources"] = sorted(set(existing["sources"] + record["sources"]))

servers = {}

codex_path = os.path.join(config_home, "codex", "config.toml")
codex_data = read_toml(codex_path)
for name, cfg in codex_data.get("mcp_servers", {}).items():
    url = cfg.get("url")
    command = cfg.get("command")
    headers, missing = expand_headers(
        cfg.get("env_http_headers", {}),
        {},
        cfg.get("bearer_token_env_var"),
    )
    record = {
        "name": name,
        "kind": "http" if url else "stdio",
        "url": url,
        "command": command,
        "args": cfg.get("args", []),
        "headers": headers,
        "missing_headers": missing,
        "sources": [f"codex:{codex_path}"],
    }
    add_server(servers, name, record)

gemini_path = os.path.join(config_home, "gemini", "settings.json")
gemini_data = read_json(gemini_path)
for name, cfg in gemini_data.get("mcpServers", {}).items():
    url = cfg.get("httpUrl")
    command = cfg.get("command")
    headers, missing = expand_headers(cfg.get("headers", {}), {}, None)
    record = {
        "name": name,
        "kind": "http" if url else "stdio",
        "url": url,
        "command": command,
        "args": cfg.get("args", []),
        "headers": headers,
        "missing_headers": missing,
        "sources": [f"gemini:{gemini_path}"],
    }
    add_server(servers, name, record)

claude_paths = [
    os.path.join(config_home, "claude", ".claude.json"),
    os.path.join(config_home, "claude-secondary", ".claude.json"),
    os.path.join(home_dir, ".claude.json"),
]
for path in claude_paths:
    claude_data = read_json(path)
    for name, cfg in claude_data.get("mcpServers", {}).items():
        command = cfg.get("command")
        args = cfg.get("args", [])
        url = None
        if "mcp-remote" in args:
            idx = args.index("mcp-remote")
            if idx + 1 < len(args):
                candidate = args[idx + 1]
                if isinstance(candidate, str) and candidate.startswith("http"):
                    url = candidate
        record = {
            "name": name,
            "kind": "http" if url else "stdio",
            "url": url,
            "command": command,
            "args": args,
            "headers": {},
            "missing_headers": [],
            "sources": [f"claude:{path}"],
        }
        add_server(servers, name, record)

output = sorted(servers.values(), key=lambda item: item["name"])
with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(output, handle, indent=2, sort_keys=True)
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
    secrets_file="${config_dir}/secrets.env"

    if ! curl -sf "$gateway_url/health" >/dev/null 2>&1; then
      echo "gateway sync: gateway not healthy"
      exit 1
    fi

    if [[ ! -f "$secrets_file" ]]; then
      echo "gateway sync: secrets file missing"
      exit 1
    fi

    set -a
    # shellcheck disable=SC1090
    . "$secrets_file"
    set +a

    if [[ -z "''${JWT_TOKEN:-}" ]]; then
      echo "gateway sync: jwt token missing"
      exit 1
    fi

    gateways_json="$(curl -sf -H "Authorization: Bearer $JWT_TOKEN" "$gateway_url/gateways" 2>/dev/null || true)"
    if [[ -z "$gateways_json" ]]; then
      echo "gateway sync: failed to fetch gateways"
      exit 1
    fi

    ${pkgs.jq}/bin/jq -c '.[] | select(.kind == "http" and .url != null)' "$output_file" | while read -r server; do
      name="$(echo "$server" | ${pkgs.jq}/bin/jq -r '.name')"
      url="$(echo "$server" | ${pkgs.jq}/bin/jq -r '.url')"
      missing="$(echo "$server" | ${pkgs.jq}/bin/jq -r '.missing_headers[]?' || true)"

      if [[ -n "$missing" ]]; then
        echo "gateway sync: skipping $name (missing env)"
        continue
      fi

      if echo "$gateways_json" | ${pkgs.jq}/bin/jq -e --arg name "$name" '.gateways // . // [] | any(.name == $name)' >/dev/null 2>&1; then
        echo "gateway sync: already registered $name"
        continue
      fi

      headers="$(echo "$server" | ${pkgs.jq}/bin/jq -c '.headers // {}')"
      if [[ "$headers" == "{}" ]]; then
        body="$( ${pkgs.jq}/bin/jq -n --arg name "$name" --arg url "$url" '{name: $name, url: $url}' )"
      else
        body="$( ${pkgs.jq}/bin/jq -n --arg name "$name" --arg url "$url" --argjson headers "$headers" '{name: $name, url: $url, headers: $headers}' )"
      fi

      if curl -sf -X POST \
        -H "Authorization: Bearer $JWT_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$body" \
        "$gateway_url/gateways" >/dev/null 2>&1; then
        echo "gateway sync: registered $name"
      else
        echo "gateway sync: failed to register $name"
      fi
    done
  '';

  # client wrapper — AI agents spawn this as a stdio MCP server
  client_wrapper = pkgs.writeShellScriptBin "mcpgw-wrapper" ''
    set -euo pipefail
    export PATH="${lib.makeBinPath [ pkgs.uv pkgs.coreutils ]}:$PATH"

    # load secrets for auth token
    if [[ -f "${config_dir}/secrets.env" ]]; then
      set -a
      # shellcheck disable=SC1091
      . "${config_dir}/secrets.env"
      set +a
    fi

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
    export MCP_AUTH="Bearer ''${JWT_TOKEN:-}"

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

    # 3. activation: create dirs, auto-generate all secrets
    home.activation.contextforge_setup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "${data_dir}"
      mkdir -p "${cache_dir}"

      secrets="${config_dir}/secrets.env"
      if [[ ! -e "$secrets" ]] || ! grep -q '^JWT_SECRET_KEY=.\+' "$secrets"; then
        jwt_key="$(${pkgs.openssl}/bin/openssl rand -hex 32)"
        basic_pw="$(${pkgs.openssl}/bin/openssl rand -hex 16)"

        export JWT_SECRET_KEY="$jwt_key"
        jwt_token="$(${pkgs.uv}/bin/uv run --with mcp-contextforge-gateway \
          python -m mcpgateway.utils.create_jwt_token)"

        tmp="$(mktemp)"
        cat > "$tmp" <<EOF
JWT_SECRET_KEY=$jwt_key
BASIC_AUTH_USER=admin
BASIC_AUTH_PASSWORD=$basic_pw
JWT_TOKEN=$jwt_token
EOF
        chmod 600 "$tmp"
        mv "$tmp" "$secrets"
      fi
    '';

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
              pkgs.curl
              pkgs.jq
              pkgs.coreutils
            ];
          };
        };
      }
    );

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
          "PATH=${lib.makeBinPath [ pkgs.uv pkgs.curl pkgs.jq pkgs.coreutils ]}"
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
      # not required for first-time setup — activation and the
      # contextforge-setup service handle that automatically.
      function mcpgw-setup() {
        local url="http://${cfg.host}:${toString cfg.port}"
        local config_dir="${config_dir}"
        local data_dir="${data_dir}"
        local secrets="$config_dir/secrets.env"
        local uuid_file="$data_dir/virtual-server-id"

        echo "==> manual repair/re-setup for contextforge"
        echo "(first-time setup runs automatically during rebuild)"
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
        echo "==> regenerating secrets..."
        local jwt_key basic_pw jwt_token
        jwt_key="$(openssl rand -hex 32)"
        basic_pw="$(openssl rand -hex 16)"

        export JWT_SECRET_KEY="$jwt_key"
        jwt_token="$(uv run --with mcp-contextforge-gateway \
          python -m mcpgateway.utils.create_jwt_token 2>/dev/null)" || {
          echo "error: failed to generate jwt token" >&2
          return 1
        }

        local tmp
        tmp="$(mktemp)"
        cat > "$tmp" <<EOF
JWT_SECRET_KEY=$jwt_key
BASIC_AUTH_USER=admin
BASIC_AUTH_PASSWORD=$basic_pw
JWT_TOKEN=$jwt_token
EOF
        chmod 600 "$tmp"
        mv "$tmp" "$secrets"
        echo "secrets regenerated at $secrets"

        echo ""
        echo "==> creating virtual server with all tools..."
        local response
        response="$(curl -sf -X POST \
          -H "Authorization: Bearer $jwt_token" \
          -H "Content-Type: application/json" \
          -d '{"name": "contextforge-all", "tools": "all"}' \
          "$url/servers" 2>/dev/null)" || {
          echo "error: failed to create virtual server" >&2
          return 1
        }

        local uuid
        uuid="$(echo "$response" | ${pkgs.jq}/bin/jq -r '.id // .uuid // empty')"
        if [[ -z "$uuid" ]]; then
          echo "error: no uuid returned from server creation" >&2
          echo "response: $response"
          return 1
        fi

        tmp="$(mktemp)"
        echo "$uuid" > "$tmp"
        mv "$tmp" "$uuid_file"
        echo "virtual server uuid: $uuid"
        echo "saved to $uuid_file"

        echo ""
        echo "==> done! verify with: mcpgw-status"
      }
    '';
  };
}
