{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.modules.agents.local-ai;
in
{
  imports = [ ./hunyuan3d ];

  options.modules.agents.local-ai = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable local AI engines and 3D generative tools.";
    };
    enableLlamaCpp = mkOption {
      type = types.bool;
      default = true;
      description = "Install llama-cpp runtime.";
    };
  };

  config = mkIf cfg.enable {
    programs.hunyuan3d.enable = false;
    home.packages = optional cfg.enableLlamaCpp pkgs.llama-cpp;
  };
}
