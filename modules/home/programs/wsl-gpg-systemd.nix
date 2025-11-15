{ config, lib, pkgs, ... }:
let
  cfg = config.programs.wslGpgSystemd;
  inherit (lib) mkEnableOption mkIf mkAfter;
  local_bin_dir = "${config.home.homeDirectory}/.local/bin";
  profile_dir = "${config.home.homeDirectory}/.profile.d";
  bash_runtime_dir = "$" + "{XDG_RUNTIME_DIR:-/run/user/$(id -u)}";
  bash_runtime_trim = "$" + "{runtime_dir%/}";
  bash_ssh_sock = "$"
    + "{XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ssh/ssh-agent.sock";
  bash_assuan_path = "$" + "{localappdata}\\gnupg\\S.gpg-agent";
in {
  options.programs.wslGpgSystemd = {
    enable = mkEnableOption
      "Expose Windows ssh-agent and gpg-agent sockets inside WSL using npiperelay + socat (profile.d based, no systemd).";
  };

  config = mkIf cfg.enable {
    assertions = [{
      assertion = pkgs.stdenv.isLinux;
      message = "programs.wslGpgSystemd is intended for WSL/Linux hosts.";
    }];

    home.packages = [ pkgs.socat pkgs.gnupg ];

    # Keep SSH_AUTH_SOCK stable so shells/env expect the WSL runtime path (with fallback when XDG_RUNTIME_DIR is unset).
    home.sessionVariables.SSH_AUTH_SOCK = "${bash_ssh_sock}";

    # Opportunistically symlink Windows npiperelay.exe into ~/.local/bin for PATH discovery.
    home.activation.wslGpgSystemd = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      set -euo pipefail
      mkdir -p "${local_bin_dir}"

      powershell_bin="powershell.exe"
      if command -v "$powershell_bin" >/dev/null 2>&1; then
        appdata_path="$($powershell_bin -NoProfile -Command '[Environment]::GetEnvironmentVariable("APPDATA")' | tr -d '\r')"
        if [ -n "$appdata_path" ]; then
          wslpath_bin="$(command -v wslpath || true)"
          if [ -n "$wslpath_bin" ]; then
            npiperelay_win="$appdata_path\\npiperelay\\npiperelay.exe"
            if npiperelay_wsl="$($wslpath_bin -u "$npiperelay_win" 2>/dev/null)"; then
              if [ -f "$npiperelay_wsl" ]; then
                ln -sf "$npiperelay_wsl" "${local_bin_dir}/npiperelay.exe"
              fi
            fi
          fi
        fi
      fi
    '';

    home.file.".profile.d/wsl-ssh-agent.sh" = {
      executable = true;
      text = ''
        #!/usr/bin/env sh
          # Expose Windows Win32-OpenSSH agent to WSL via npiperelay + socat
          runtime_dir="${bash_runtime_dir}"
          socket="${bash_runtime_trim}/ssh/ssh-agent.sock"
          export SSH_AUTH_SOCK="$socket"

        mkdir -p "$(dirname "$socket")"

        if command -v ss >/dev/null 2>&1; then
          if ss -lxn | grep -q "$socket"; then
            return
          fi
        elif [ -S "$socket" ]; then
          return
        fi

        rm -f "$socket"

        if ! command -v npiperelay.exe >/dev/null 2>&1; then
          echo "[wsl-ssh-agent] npiperelay.exe not found in PATH; install it on Windows or symlink into ~/.local/bin" >&2
          return
        fi

        (setsid socat \
          UNIX-LISTEN:"$socket",umask=007,fork \
          EXEC:"npiperelay.exe -ei -s //./pipe/openssh-ssh-agent",nofork \
          &) >/dev/null 2>&1
      '';
    };

    home.file.".profile.d/wsl-gpg-agent.sh" = {
      executable = true;
      text = ''
        #!/usr/bin/env sh
        # Expose Windows Gpg4win/Win32 gpg-agent to WSL via sorelay/npiperelay + socat

        resolve_localappdata() {
          /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -Command "[Environment]::GetEnvironmentVariable('LOCALAPPDATA')" 2>/dev/null | tr -d '\r'
        }

        start_gpg_bridge() {
          socket_path="$1"
          localappdata="$2"
          [ -z "$socket_path" ] && return
          mkdir -p "$(dirname "$socket_path")"

          if command -v ss >/dev/null 2>&1 && ss -lxn | grep -q "$socket_path"; then
            return
          elif [ -S "$socket_path" ]; then
            return
          fi

          rm -f "$socket_path"

          assuan_path="${bash_assuan_path}"
          pipe_path="//./pipe/S.gpg-agent"

          if command -v sorelay.exe >/dev/null 2>&1; then
            bridge_cmd="sorelay.exe -a \"$assuan_path\""
          elif command -v npiperelay.exe >/dev/null 2>&1; then
            if npiperelay.exe -h 2>&1 | grep -q -- ' -a '; then
              bridge_cmd="npiperelay.exe -ei -ep -a \"$assuan_path\""
            else
              bridge_cmd="npiperelay.exe -ei -s \"$pipe_path\""
            fi
          else
            echo "[wsl-gpg-agent] neither sorelay.exe nor npiperelay.exe found in PATH" >&2
            return
          fi

          (setsid socat \
            UNIX-LISTEN:"$socket_path",umask=007,fork \
            EXEC:"$bridge_cmd",nofork \
            &) >/dev/null 2>&1
        }

        localappdata="$(resolve_localappdata)"
        if [ -z "$localappdata" ]; then
          echo "[wsl-gpg-agent] could not resolve %LOCALAPPDATA%; skipping bridge" >&2
          return
        fi

        start_gpg_bridge "$(gpgconf --list-dirs agent-socket)" "$localappdata"
        start_gpg_bridge "$(gpgconf --list-dirs agent-ssh-socket)" "$localappdata"
      '';
    };

    # Ensure profile.d scripts are sourced for common shells.
    programs.zsh.profileExtra = mkAfter ''
      for f in "$HOME"/.profile.d/*.sh; do
        [ -r "$f" ] && . "$f"
      done
    '';
    programs.bash.profileExtra = mkAfter ''
      for f in "$HOME"/.profile.d/*.sh; do
        [ -r "$f" ] && . "$f"
      done
    '';
  };
}
