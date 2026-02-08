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
          ttl: 0
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
          ttl: 0
          max_entries: 5000
  '';

  mcp_servers_source = ../../../../mcp-servers.toml;

  # --- python helper derivations ---

  bridge_supervisor_parse_toml_py = pkgs.writeText
    "bridge-supervisor-parse-toml.py"
    (builtins.readFile ./scripts/bridge-supervisor-parse-toml.py);

  setup_generate_token_py = pkgs.writeText
    "setup-generate-token.py"
    (builtins.readFile ./scripts/setup-generate-token.py);

  sync_parse_toml_py = pkgs.writeText
    "sync-parse-toml.py"
    (builtins.readFile ./scripts/sync-parse-toml.py);

  sync_filter_tools_py = pkgs.writeText
    "sync-filter-tools.py"
    (builtins.readFile ./scripts/sync-filter-tools.py);

  # --- bash script derivations (template substitution) ---

  # gateway daemon wrapper — sources env files, execs uvx
  gateway_script = pkgs.writeTextFile {
    name = "contextforge-gateway";
    text = builtins.replaceStrings
      [ "@BASH@" "@PATH@" "@PLUGINS_DIR@" "@CONFIG_DIR@" "@DATA_DIR@" ]
      [ "${pkgs.bash}/bin/bash"
        (lib.makeBinPath [ pkgs.uv pkgs.coreutils ])
        "${plugins_dir}" config_dir data_dir ]
      (builtins.readFile ./scripts/gateway.sh.tpl);
    executable = true;
  };

  # bridge supervisor — spawns mcpgateway.translate per stdio server with bridge.port
  bridge_supervisor_script = pkgs.writeTextFile {
    name = "contextforge-bridge-supervisor";
    text = builtins.replaceStrings
      [ "@BASH@" "@PATH@" "@HOME@" "@CACHE_DIR@" "@CONFIG_DIR@" "@PARSE_TOML_PY@" ]
      [ "${pkgs.bash}/bin/bash"
        (lib.makeBinPath [ pkgs.uv pkgs.python3 pkgs.nodejs pkgs.coreutils ])
        "${config.home.homeDirectory}" cache_dir config_dir
        "${bridge_supervisor_parse_toml_py}" ]
      (builtins.readFile ./scripts/bridge-supervisor.sh.tpl);
    executable = true;
  };

  # sync script — server registration (writeShellScriptBin equivalent)
  sync_script = pkgs.writeTextFile {
    name = "contextforge-mcp-sync";
    text = builtins.replaceStrings
      [ "@BASH@" "@PATH@" "@CONFIG_DIR@" "@GATEWAY_URL@" "@JQ@"
        "@DATA_DIR@" "@PARSE_TOML_PY@" "@FILTER_TOOLS_PY@" ]
      [ "${pkgs.bash}/bin/bash"
        (lib.makeBinPath [ pkgs.coreutils pkgs.curl pkgs.jq pkgs.python3 ])
        config_dir "http://${cfg.host}:${toString cfg.port}"
        "${pkgs.jq}/bin/jq" data_dir
        "${sync_parse_toml_py}" "${sync_filter_tools_py}" ]
      (builtins.readFile ./scripts/sync.sh.tpl);
    executable = true;
    destination = "/bin/contextforge-mcp-sync";
  };

  # one-shot setup script — waits for gateway, creates virtual server, acquires jwt token
  setup_script = pkgs.writeTextFile {
    name = "contextforge-auto-setup";
    text = builtins.replaceStrings
      [ "@BASH@" "@PATH@" "@GATEWAY_URL@" "@DATA_DIR@" "@CONFIG_DIR@"
        "@SYNC_PATH@" "@SYNC_BIN@" "@GENERATE_TOKEN_PY@" ]
      [ "${pkgs.bash}/bin/bash"
        (lib.makeBinPath [ pkgs.uv pkgs.python3 pkgs.curl pkgs.jq pkgs.coreutils ])
        "http://${cfg.host}:${toString cfg.port}" data_dir config_dir
        (lib.makeBinPath [ pkgs.coreutils pkgs.curl pkgs.jq pkgs.python3 ])
        "${sync_script}/bin/contextforge-mcp-sync"
        "${setup_generate_token_py}" ]
      (builtins.readFile ./scripts/setup.sh.tpl);
    executable = true;
  };

  # client wrapper — AI agents spawn this as a stdio MCP server
  client_wrapper = pkgs.writeTextFile {
    name = "mcpgw-wrapper";
    text = builtins.replaceStrings
      [ "@BASH@" "@PATH@" "@DATA_DIR@" "@GATEWAY_HOST@" "@GATEWAY_PORT@" ]
      [ "${pkgs.bash}/bin/bash"
        (lib.makeBinPath [ pkgs.uv pkgs.coreutils ])
        data_dir cfg.host (toString cfg.port) ]
      (builtins.readFile ./scripts/client-wrapper.sh.tpl);
    executable = true;
    destination = "/bin/mcpgw-wrapper";
  };

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
    # failures and first installs). retries transient launchctl bootstrap failures.
    # does NOT cycle already-running agents — the setup service handles re-syncing
    # state, and launchd KeepAlive handles gateway restarts.
    home.activation.contextforge_ensure_agents = lib.mkIf is_darwin (
      lib.hm.dag.entryAfter [ "setupLaunchAgents" ] ''
        uid="$(id -u)"
        domain="gui/$uid"
        agent_dir="$HOME/Library/LaunchAgents"
        for label in com.contextforge.gateway com.contextforge.bridge-supervisor com.contextforge.setup; do
          plist="$agent_dir/$label.plist"
          [[ -f "$plist" ]] || continue
          if ! /bin/launchctl print "$domain/$label" >/dev/null 2>&1; then
            loaded=0
            for attempt in 1 2 3; do
              if /bin/launchctl bootstrap "$domain" "$plist" 2>/dev/null; then
                loaded=1
                break
              fi
              sleep 2
            done
            if [[ "$loaded" -eq 0 ]]; then
              echo "warning: failed to bootstrap $label after 3 attempts" >&2
            fi
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
