{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.drive-mcp;
  is_darwin = pkgs.stdenv.isDarwin;
  libexec_dir = "${config.home.homeDirectory}/.local/libexec/drive-mcp";
  log_path = "${config.home.homeDirectory}/Library/Logs/drive-mcp-bridge.log";

  bridge_py = pkgs.writeText "drive-mcp-bridge.py" (builtins.readFile ./scripts/bridge.py);

  # stdio<->http mcp bridge for drivemcp.googleapis.com (and `serve` mode for
  # local streamable-http behind contextforge with X-Drive-Account passthrough).
  # account switching: `drive-account login`, `drive-account use <email>`.
  bridge = pkgs.writeShellScriptBin "drive-mcp-bridge" ''
    set -euo pipefail
    if [[ "''${1:-}" == "serve" ]]; then
      shift
      exec ${cfg.pythonPackage}/bin/python3 ${bridge_py} serve "$@"
    fi
    exec ${cfg.pythonPackage}/bin/python3 ${bridge_py} bridge "$@"
  '';

  serve_script = pkgs.writeShellScript "drive-mcp-serve" ''
    set -euo pipefail
    exec ${cfg.pythonPackage}/bin/python3 ${bridge_py} serve --host "${cfg.host}" --port "${toString cfg.port}"
  '';

  account = pkgs.writeShellScriptBin "drive-account" ''
    set -euo pipefail
    exec ${cfg.pythonPackage}/bin/python3 ${bridge_py} "$@"
  '';
in
{
  options.programs.drive-mcp = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable drive-mcp bridge and local HTTP daemon for Google Drive MCP";
    };

    pythonPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.python3;
      description = "Python interpreter used to run the bridge.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Bind address for the local Streamable HTTP server.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 4445;
      description = "Bind port for the local Streamable HTTP server (gateway-reserved 4445-4449).";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      bridge
      account
    ];

    # Stable launchd wrapper path avoids nix-store hash churn in macOS Login Items.
    home.activation.drive_mcp_wrapper = lib.mkIf is_darwin (
      lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "linkGeneration" ] ''
        mkdir -p "${libexec_dir}"
        printf '#!/bin/bash\nexec "%s" "$@"\n' "${serve_script}" > "${libexec_dir}/drive-mcp-serve"
        chmod +x "${libexec_dir}/drive-mcp-serve"

        if [[ -f "${log_path}" ]]; then
          lines="$(wc -l < "${log_path}" 2>/dev/null || echo 0)"
          if (( lines > 5000 )); then
            tmp="$(mktemp)"
            tail -n 5000 "${log_path}" > "$tmp" && mv "$tmp" "${log_path}"
          fi
        fi
      ''
    );

    # Ensure drive-mcp is up before contextforge_ensure_agents kicks contextforge-mcp-sync.
    home.activation.drive_mcp_ensure_agent = lib.mkIf is_darwin (
      lib.hm.dag.entryBetween
        (lib.optional (config.programs.contextforge.enable or false) "contextforge_ensure_agents")
        [
          "setupLaunchAgents"
          "linkGeneration"
        ]
        ''
          uid="$(id -u)"
          domain="gui/$uid"
          label="com.drive-mcp.bridge"
          plist="$HOME/Library/LaunchAgents/$label.plist"
          /bin/launchctl bootout "$domain/$label" 2>/dev/null || true
          if [[ -f "$plist" ]]; then
            for attempt in 1 2 3 4 5; do
              if /bin/launchctl bootstrap "$domain" "$plist" 2>/dev/null; then
                break
              fi
              sleep 1
            done
            for _ in 1 2 3 4 5 6 7 8 9 10; do
              if ${pkgs.curl}/bin/curl -sf --max-time 1 "http://${cfg.host}:${toString cfg.port}/health" >/dev/null 2>&1; then
                break
              fi
              sleep 0.5
            done
          fi
        ''
    );

    launchd.agents.drive-mcp-bridge = lib.mkIf is_darwin {
      enable = true;
      config = {
        Label = "com.drive-mcp.bridge";
        ProgramArguments = [ "${libexec_dir}/drive-mcp-serve" ];
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 5;
        StandardOutPath = log_path;
        StandardErrorPath = log_path;
        EnvironmentVariables = {
          HOME = config.home.homeDirectory;
          PATH = lib.makeBinPath [ pkgs.coreutils ];
        };
      };
    };

    systemd.user.services.drive-mcp-bridge = lib.mkIf (!is_darwin) {
      Unit = {
        Description = "Google Drive MCP local Streamable HTTP bridge";
        After = [ "default.target" ];
        Before = [ "contextforge-setup.service" ];
      };
      Service = {
        ExecStart = "${serve_script}";
        Restart = "always";
        RestartSec = 5;
        Environment = [
          "HOME=${config.home.homeDirectory}"
          "PATH=${lib.makeBinPath [ pkgs.coreutils ]}"
        ];
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };
  };
}
