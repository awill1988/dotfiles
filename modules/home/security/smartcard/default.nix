{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.modules.security.smartcard;
in
{
  options.modules.security.smartcard = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable smartcard and YubiKey support tools.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      yubikey-manager
      pcsclite
    ];
  };
}
