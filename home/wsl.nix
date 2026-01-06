{ config, pkgs, lib, ... }:
let
  inherit (lib) mkEnableOption mkOption types;
  cfg = config.ext.wsl;

  # read template files
  bashScriptTemplate = builtins.readFile ./wsl-scripts/nix-wsl-init.sh.tpl;
  psEntrypointTemplate = builtins.readFile ./wsl-scripts/nix-wsl-init.ps1.tpl;
  psLogonScriptTemplate = builtins.readFile ./wsl-scripts/wsl-on-logon.ps1.tpl;
  psTaskSetupScriptTemplate = builtins.readFile ./wsl-scripts/setup-wsl-on-logon-task.ps1.tpl;

  # create derivations for powershell scripts
  psEntrypoint = pkgs.writeText "nix-wsl-init.ps1" psEntrypointTemplate;
  psLogonScript = pkgs.writeText "wsl-on-logon.ps1" psLogonScriptTemplate;
  psTaskSetupScript = pkgs.writeText "setup-wsl-on-logon-task.ps1" psTaskSetupScriptTemplate;

  # pcscd auto-start script with baked-in nix store paths
  pcscdAutoStart = pkgs.writeShellScriptBin "pcscd-auto-start" ''
    #!/usr/bin/env bash
    # auto-start pcscd with correct ccid drivers path
    # intended to be called from windows logon hook after usbipd attach

    if pgrep -x pcscd > /dev/null; then
      exit 0
    fi

    export PCSCLITE_HP_DROPDIR="${pkgs.ccid}/pcsc/drivers"
    exec ${pkgs.pcsclite}/bin/pcscd
  '';

  # substitute placeholders in bash script
  bashScript = pkgs.writeTextFile {
    name = "nix-wsl-init.sh";
    text = builtins.replaceStrings
      [
        "@FONT_PACKAGE_PATH@"
        "@FIND_BIN@"
        "@PS_ENTRYPOINT@"
        "@PS_LOGON_SCRIPT@"
        "@PS_TASK_SETUP_SCRIPT@"
        "@USBIPD_ENABLED@"
        "@USBIPD_BUSID@"
        "@USBIPD_AUTO_ATTACH@"
        "@WSL_DISTRO_NAME@"
        "@WSL_WAIT_SECONDS@"
        "@PCSCD_ENABLED@"
        "@PCSCD_AUTO_START_BIN@"
      ]
      [
        "${pkgs.nerd-fonts.sauce-code-pro}/share/fonts"
        "${pkgs.findutils}/bin/find"
        "${psEntrypoint}"
        "${psLogonScript}"
        "${psTaskSetupScript}"
        (if cfg.usbipd.enable then "true" else "false")
        (if cfg.usbipd.busid == null then "" else cfg.usbipd.busid)
        (if cfg.usbipd.auto_attach then "true" else "false")
        (if cfg.usbipd.distro_name == null then "" else cfg.usbipd.distro_name)
        (toString cfg.usbipd.wait_seconds)
        (if cfg.pcscd.enable then "true" else "false")
        "${pcscdAutoStart}/bin/pcscd-auto-start"
      ]
      bashScriptTemplate;
    executable = true;
  };
in
{
  options.ext.wsl = {
    enable = mkEnableOption "wsl-specific configuration";

    usbipd = {
      enable = mkEnableOption "usbipd auto-attach at windows logon";
      busid = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "usb device busid to attach, or null to auto-detect smart card reader";
      };
      auto_attach = mkOption {
        type = types.bool;
        default = true;
      };
      distro_name = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "wsl distro name, or null to auto-detect running distro";
      };
      wait_seconds = mkOption {
        type = types.int;
        default = 30;
      };
    };

    pcscd = {
      enable = mkEnableOption "pc/sc smart card daemon for yubikey oath/piv";
    };
  };

  config = lib.mkIf cfg.enable {
    home.activation.nix-wsl-init = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${bashScript}
    '';

    # pcscd support for yubikey smart card operations (oath, piv)
    home.packages = lib.mkIf cfg.pcscd.enable [
      pkgs.pcsclite
      pkgs.pcsc-tools
      pkgs.ccid
      pcscdAutoStart
    ];

    # shell function to start pcscd (requires sudo)
    # ccid drivers path passed via PCSCLITE_HP_DROPDIR env var
    programs.zsh.initContent = lib.mkIf cfg.pcscd.enable ''
      # start pcscd if not running (needed for yubikey oath/piv)
      pcscd-start() {
        if ! pgrep -x pcscd > /dev/null; then
          echo "starting pcscd..."
          sudo PCSCLITE_HP_DROPDIR=${pkgs.ccid}/pcsc/drivers ${pkgs.pcsclite}/bin/pcscd
          sleep 1
          if pgrep -x pcscd > /dev/null; then
            echo "pcscd started"
          else
            echo "error: failed to start pcscd" >&2
            return 1
          fi
        else
          echo "pcscd already running"
        fi
      }

      # stop pcscd
      pcscd-stop() {
        if pgrep -x pcscd > /dev/null; then
          echo "stopping pcscd..."
          sudo pkill pcscd
        else
          echo "pcscd not running"
        fi
      }

      # check pcscd and yubikey status
      pcscd-status() {
        if pgrep -x pcscd > /dev/null; then
          echo "pcscd: running (pid $(pgrep -x pcscd))"
          echo ""
          ${pkgs.pcsc-tools}/bin/pcsc_scan -r 2>/dev/null || true
        else
          echo "pcscd: not running"
          echo "run 'pcscd-start' to start the daemon"
        fi
      }
    '';

    programs.bash.initExtra = lib.mkIf cfg.pcscd.enable ''
      # start pcscd if not running (needed for yubikey oath/piv)
      pcscd-start() {
        if ! pgrep -x pcscd > /dev/null; then
          echo "starting pcscd..."
          sudo PCSCLITE_HP_DROPDIR=${pkgs.ccid}/pcsc/drivers ${pkgs.pcsclite}/bin/pcscd
          sleep 1
          if pgrep -x pcscd > /dev/null; then
            echo "pcscd started"
          else
            echo "error: failed to start pcscd" >&2
            return 1
          fi
        else
          echo "pcscd already running"
        fi
      }

      # stop pcscd
      pcscd-stop() {
        if pgrep -x pcscd > /dev/null; then
          echo "stopping pcscd..."
          sudo pkill pcscd
        else
          echo "pcscd not running"
        fi
      }

      # check pcscd and yubikey status
      pcscd-status() {
        if pgrep -x pcscd > /dev/null; then
          echo "pcscd: running (pid $(pgrep -x pcscd))"
          echo ""
          ${pkgs.pcsc-tools}/bin/pcsc_scan -r 2>/dev/null || true
        else
          echo "pcscd: not running"
          echo "run 'pcscd-start' to start the daemon"
        fi
      }
    '';
  };
}