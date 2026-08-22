{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.modules.cloud.containers;
in
{
  options.modules.cloud.containers = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable container runtimes (Podman).";
    };
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [ podman ];
  };
}
