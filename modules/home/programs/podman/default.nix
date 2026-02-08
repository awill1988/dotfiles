{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.podman;
  is_darwin = pkgs.stdenv.isDarwin;

  # linux socket path (static — systemd creates it at a known location)
  linux_docker_host = "unix://$XDG_RUNTIME_DIR/podman/podman.sock";

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

    # 2. DOCKER_HOST session variable (linux only — darwin resolves dynamically in zsh init)
    home.sessionVariables = lib.mkIf (!is_darwin) {
      DOCKER_HOST = linux_docker_host;
    };

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

    # 4. shell integration: DOCKER_HOST export + podman-status function
    programs.zsh.initContent = lib.mkAfter (
      if is_darwin then
        ''
          # resolve DOCKER_HOST dynamically — podman 5.x puts the socket under
          # /var/folders (TMPDIR), not a static ~/.local/share path.
          if command -v podman >/dev/null 2>&1; then
            _sock="$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}' 2>/dev/null)"
            if [[ -n "$_sock" ]]; then
              export DOCKER_HOST="unix://$_sock"
            fi
            unset _sock
          fi

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
          export DOCKER_HOST="${linux_docker_host}"

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
