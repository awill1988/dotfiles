{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.gemini;
  gemini_home = "${config.xdg.configHome}/gemini";
  settings_source = ./settings.json;
  gemini_instructions_source = ./GEMINI.md;
in
{
  options.programs.gemini = {
    enable = lib.mkEnableOption "Gemini CLI";
    package = lib.mkOption {
      type = lib.types.package;
      default =
        if config.modules.dev.node.enable then
          pkgs.gemini.override {
            nodejs = config.modules.dev.node.package;
          }
        else
          pkgs.gemini;
      description = "Gemini CLI package to install.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
    home.sessionVariables.GEMINI_CLI_SYSTEM_SETTINGS_PATH = lib.mkDefault "${gemini_home}/settings.json";

    xdg.configFile."gemini/settings.json" = {
      source = settings_source;
      force = true;
    };
    xdg.configFile."gemini/GEMINI.md" = {
      source = gemini_instructions_source;
      force = true;
    };

    # Backwards compatibility for tools that still look under ~/.gemini
    home.file.".gemini/settings.json".source = settings_source;
    home.file.".gemini/GEMINI.md".source = gemini_instructions_source;
  };
}
