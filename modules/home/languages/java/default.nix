{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.modules.languages.java;
in
{
  options.modules.languages.java = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable JDK, Gradle, jdtls, and kotlin language server.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      jdk
      gradle
      jdt-language-server
      kotlin-language-server
    ];
  };
}
