{
  config,
  pkgs,
  lib,
  ...
}:
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

  # pcscd systemd unit (Type=simple, runs in foreground)
  pcscd_systemd_unit = pkgs.writeText "pcscd-wsl.service" ''
    [Unit]
    Description=pcscd smart card daemon (wsl/nix)
    After=multi-user.target

    [Service]
    Type=simple
    Environment=PCSCLITE_HP_DROPDIR=${pkgs.ccid}/pcsc/drivers
    ExecStart=${pkgs.pcsclite}/bin/pcscd --foreground
    Restart=on-failure
    RestartSec=5

    [Install]
    WantedBy=multi-user.target
  '';

  # script to install/update systemd unit (requires sudo, run once)
  pcscd_systemd_install = pkgs.writeShellScriptBin "pcscd-systemd-install" ''
    set -euo pipefail

    unit_src="${pcscd_systemd_unit}"
    unit_dest="/etc/systemd/system/pcscd-wsl.service"

    if [ -f "$unit_dest" ] && ${pkgs.coreutils}/bin/cmp -s "$unit_src" "$unit_dest"; then
      echo "pcscd-wsl.service: already up to date"
      exit 0
    fi

    echo "installing pcscd-wsl.service..."
    sudo cp "$unit_src" "$unit_dest"
    sudo chmod 0644 "$unit_dest"
    sudo systemctl daemon-reload
    sudo systemctl enable --now pcscd-wsl.service
    echo "pcscd-wsl.service: installed and started"
  '';

  # substitute placeholders in bash script
  bashScript = pkgs.writeTextFile {
    name = "nix-wsl-init.sh";
    text =
      builtins.replaceStrings
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
          "@PCSCD_SYSTEMD_UNIT@"
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
          "${pcscd_systemd_unit}"
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

    # pcscd packages for yubikey smart card operations
    home.packages = lib.mkIf cfg.pcscd.enable [
      pkgs.pcsclite
      pkgs.pcsc-tools
      pkgs.ccid
      pcscd_systemd_install
    ];

    programs.zsh.initContent = lib.mkIf cfg.pcscd.enable ''
      pcscd-status() {
        if ! systemctl is-enabled pcscd-wsl.service > /dev/null 2>&1; then
          echo "pcscd-wsl.service: not installed"
          echo "run: pcscd-systemd-install"
          return 1
        fi
        if pgrep -x pcscd > /dev/null; then
          echo "pcscd: running (pid $(pgrep -x pcscd))"
          echo ""
          ${pkgs.pcsc-tools}/bin/pcsc_scan -r 2>/dev/null || true
        else
          echo "pcscd: not running"
          echo "run: sudo systemctl start pcscd-wsl"
        fi
      }
    '';

    programs.bash.initExtra = lib.mkIf cfg.pcscd.enable ''
      pcscd-status() {
        if ! systemctl is-enabled pcscd-wsl.service > /dev/null 2>&1; then
          echo "pcscd-wsl.service: not installed"
          echo "run: pcscd-systemd-install"
          return 1
        fi
        if pgrep -x pcscd > /dev/null; then
          echo "pcscd: running (pid $(pgrep -x pcscd))"
          echo ""
          ${pkgs.pcsc-tools}/bin/pcsc_scan -r 2>/dev/null || true
        else
          echo "pcscd: not running"
          echo "run: sudo systemctl start pcscd-wsl"
        fi
      }
    '';
  };
}
