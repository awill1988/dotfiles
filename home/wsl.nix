{ config, pkgs, lib, ... }:
let
  inherit (lib) mkEnableOption mkOption types;
  cfg = config.aw.wsl;

  # read template files
  bashScriptTemplate = builtins.readFile ./wsl-scripts/nix-wsl-init.sh.tpl;
  psEntrypointTemplate = builtins.readFile ./wsl-scripts/nix-wsl-init.ps1.tpl;
  psLogonScriptTemplate = builtins.readFile ./wsl-scripts/wsl-on-logon.ps1.tpl;
  psTaskSetupScriptTemplate = builtins.readFile ./wsl-scripts/setup-wsl-on-logon-task.ps1.tpl;

  # create derivations for powershell scripts
  psEntrypoint = pkgs.writeText "nix-wsl-init.ps1" psEntrypointTemplate;
  psLogonScript = pkgs.writeText "wsl-on-logon.ps1" psLogonScriptTemplate;
  psTaskSetupScript = pkgs.writeText "setup-wsl-on-logon-task.ps1" psTaskSetupScriptTemplate;

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
      ]
      [
        "${pkgs.nerd-fonts.sauce-code-pro}/share/fonts"
        "${pkgs.findutils}/bin/find"
        "${psEntrypoint}"
        "${psLogonScript}"
        "${psTaskSetupScript}"
        (if cfg.usbipd.enable then "true" else "false")
        cfg.usbipd.busid
        (if cfg.usbipd.auto_attach then "true" else "false")
        (if cfg.usbipd.distro_name == null then "" else cfg.usbipd.distro_name)
        (toString cfg.usbipd.wait_seconds)
      ]
      bashScriptTemplate;
    executable = true;
  };
in
{
  options.aw.wsl = {
    enable = mkEnableOption "wsl-specific configuration";

    usbipd = {
      enable = mkEnableOption "usbipd auto-attach at windows logon";
      busid = mkOption {
        type = types.str;
        default = "1-1";
      };
      auto_attach = mkOption {
        type = types.bool;
        default = true;
      };
      distro_name = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      wait_seconds = mkOption {
        type = types.int;
        default = 30;
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.activation.nix-wsl-init = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${bashScript}
    '';
  };
}