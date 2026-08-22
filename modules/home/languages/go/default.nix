{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.modules.languages.go;
in
{
  options.modules.languages.go = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Go language toolchain and gopls.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      go_1_25
      gopls
    ];
  };
}
