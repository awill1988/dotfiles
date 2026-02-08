{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.podman;
  is_darwin = pkgs.stdenv.isDarwin;

  # platform-conditional socket path
  docker_host =
    if is_darwin then
      "unix://$HOME/.local/share/containers/podman/machine/podman.sock"
    else
      "unix://$XDG_RUNTIME_DIR/podman/podman.sock";

  profile_bin = "${config.home.profileDirectory}/bin";

  # wrapper script for darwin launchd agent
  podman_machine_pkg = pkgs.writeShellScriptBin "podman-machine-init" ''
    set -euo pipefail
    export PATH="${lib.makeBinPath [ cfg.package ]}:$PATH"

    log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

    # ensure a default machine exists
    if ! podman machine inspect 2>/dev/null; then
      log "no default machine found, initializing..."
      podman machine init
    fi

    # start is idempotent — exits cleanly if already running
    log "starting podman machine..."
    podman machine start || true
    log "podman machine ready"
  '';
in
{
  options.programs.podman = {
    enable = lib.mkEnableOption "Podman container engine integration";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.podman;
      description = "Podman package to install.";
    };
  };

  config = lib.mkIf cfg.enable {
    # 1. package installation
    home.packages = [ cfg.package podman_machine_pkg ];

    # 2. DOCKER_HOST session variable (platform-conditional)
    home.sessionVariables.DOCKER_HOST = docker_host;

    # 3. darwin: launchd user agent for machine lifecycle
    launchd.agents.podman-machine = lib.mkIf is_darwin (
      let
        log_path = "${config.home.homeDirectory}/Library/Logs/podman-machine.log";
      in
      {
        enable = true;
        config = {
          Label = "com.github.containers.podman-machine";
          ProgramArguments = [ "${profile_bin}/podman-machine-init" ];
          RunAtLoad = true;
          KeepAlive = false;
          StandardOutPath = log_path;
          StandardErrorPath = log_path;
        };
      }
    );

    # 4. shell integration: podman-status function
    programs.zsh.initContent = lib.mkAfter (
      if is_darwin then
        ''
          # podman machine status helper
          function podman-status() {
            if ! command -v podman >/dev/null 2>&1; then
              echo "podman: not found"
              return 1
            fi
            local state
            state="$(podman machine inspect --format '{{.State}}' 2>/dev/null)" || state="not initialized"
            echo "podman machine: $state"
            echo "docker host:    ''${DOCKER_HOST:-unset}"
          }
        ''
      else
        ''
          # podman socket status helper
          function podman-status() {
            if ! command -v podman >/dev/null 2>&1; then
              echo "podman: not found"
              return 1
            fi
            local sock="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/podman/podman.sock"
            if [[ -S "$sock" ]]; then
              echo "podman socket: active ($sock)"
            else
              echo "podman socket: not found ($sock)"
            fi
            echo "docker host:    ''${DOCKER_HOST:-unset}"
          }
        ''
    );
  };
}
