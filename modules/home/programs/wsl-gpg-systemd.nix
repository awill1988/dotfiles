{ config, lib, pkgs, ... }:
let
  cfg = config.programs.wslGpgSystemd;
  inherit (lib) mkEnableOption mkIf;
  localBinDir = "${config.home.homeDirectory}/.local/bin";
  npiperelayPath = "${localBinDir}/npiperelay.exe";
in
{
  options.programs.wslGpgSystemd = {
    enable = mkEnableOption
      "Expose the Windows ssh-agent socket inside WSL using npiperelay + systemd.";
  };

  config = mkIf cfg.enable {
    assertions = [{
      assertion = pkgs.stdenv.isLinux;
      message = "programs.wslGpgSystemd is intended for WSL/Linux hosts.";
    }];

    home.sessionVariables.SSH_AUTH_SOCK =
      "$XDG_RUNTIME_DIR/ssh/ssh-agent.sock";

    systemd.user.sockets."named-pipe-ssh-agent" = {
      Unit = {
        Description =
          "SSH Agent provided by Windows named pipe \\\\.\\pipe\\openssh-ssh-agent";
      };
      Socket = {
        ListenStream = "%t/ssh/ssh-agent.sock";
        SocketMode = "0600";
        DirectoryMode = "0700";
        Accept = true;
      };
      Install = { WantedBy = [ "sockets.target" ]; };
    };

    systemd.user.services."named-pipe-ssh-agent@" = {
      Unit = {
        Description =
          "Proxy to Windows SSH Agent (Win32-OpenSSH / 1Password / KeeAgent)";
      };
      Service = {
        Type = "simple";
        ExecStart =
          "%h/.local/bin/npiperelay.exe -p -l -ei -s '//./pipe/openssh-ssh-agent'";
        StandardInput = "socket";
        Restart = "on-failure";
      };
      Install = { };
    };

    home.activation.wslGpgSystemd = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      set -euo pipefail

      mkdir -p "${localBinDir}"

      powershell_bin="powershell.exe"
      if ! command -v "$powershell_bin" >/dev/null 2>&1; then
        fallback_pwsh="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
        if [ -x "$fallback_pwsh" ]; then
          powershell_bin="$fallback_pwsh"
        else
          echo "[wsl-gpg-systemd] powershell.exe not found in PATH and fallback $fallback_pwsh is missing" >&2
          exit 1
        fi
      fi

      appdata_path="$(
        "$powershell_bin" -NoProfile -Command '[Environment]::GetEnvironmentVariable("APPDATA")' \
          | tr -d '\r'
      )"

      if [ -z "$appdata_path" ]; then
        echo "[wsl-gpg-systemd] Could not resolve %APPDATA% via powershell.exe" >&2
        exit 1
      fi

      wslpath_bin="$(command -v wslpath || true)"
      if [ -z "$wslpath_bin" ]; then
        for candidate in /usr/bin/wslpath /bin/wslpath; do
          if [ -x "$candidate" ]; then
            wslpath_bin="$candidate"
            break
          fi
        done
      fi

      if [ -z "$wslpath_bin" ]; then
        echo "[wsl-gpg-systemd] wslpath command not found. Ensure it is installed and on PATH." >&2
        exit 1
      fi

      npiperelay_win="''${appdata_path}\\npiperelay\\npiperelay.exe"
      if ! npiperelay_wsl="$("$wslpath_bin" -u "$npiperelay_win" 2>/dev/null)"; then
        echo "[wsl-gpg-systemd] Failed to convert Windows path $npiperelay_win via $wslpath_bin" >&2
        exit 1
      fi

      if [ ! -f "$npiperelay_wsl" ]; then
        echo "[wsl-gpg-systemd] Expected binary $npiperelay_wsl not found. Run the Windows installer first." >&2
        exit 1
      fi

      ln -sf "$npiperelay_wsl" "${npiperelayPath}"
    '';
  };
}
