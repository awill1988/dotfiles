{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.modules.security.credentials;
in
{
  options.modules.security.credentials = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable secrets and password management tools.";
    };
  };

  config = mkIf cfg.enable {
    programs.browserpass = {
      enable = true;
      browsers = [ "firefox" ];
    };

    home.packages = with pkgs; [
      pass
      sops
      xkcdpass
      gpgme
    ];
  };
}
