{ config, lib, pkgs, ... }:
let
  cfg = config.programs.codex;
  codex_config_dir = "${config.xdg.configHome}/codex";
  config_source = ../../../home/config/codex/config.toml;
  agents_override_source = ../../../home/config/codex/AGENTS.override.md;
in {
  config = lib.mkIf cfg.enable {
    programs.codex.package = lib.mkDefault pkgs.codex;
    home.sessionVariables.CODEX_HOME = lib.mkDefault codex_config_dir;

    xdg.configFile."codex/config.toml" = {
      source = config_source;
      force = true;
    };
    xdg.configFile."codex/AGENTS.override.md" = {
      source = agents_override_source;
      force = true;
    };
  };
}
