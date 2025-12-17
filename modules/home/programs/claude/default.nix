{ config, lib, pkgs, ... }:
let
  cfg = config.programs.claude;
  claude_home = "${config.xdg.configHome}/claude";
  claude_cache = "${config.xdg.cacheHome}/claude";
  claude_state = "${config.xdg.stateHome}/claude";
  claude_instructions_source = ./CLAUDE.md;
  claude_user_config_source = ./claude.json;
  settings_source = ./settings.json;
in {
  options.programs.claude = {
    enable = lib.mkEnableOption "Claude Code CLI";
    package = lib.mkOption {
      type = lib.types.package;
      default =
        if config.modules.dev.node.enable then
          pkgs.claude.override { nodejs = config.modules.dev.node.package; }
        else
          pkgs.claude;
      description = "Claude package to install.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
    home.sessionVariables = {
      CLAUDE_CONFIG_DIR = lib.mkDefault claude_home;
      CLAUDE_CACHE_DIR = lib.mkDefault claude_cache;
      CLAUDE_STATE_DIR = lib.mkDefault claude_state;
    };

    xdg.configFile."claude/settings.json" = {
      source = settings_source;
      force = true;
    };
    xdg.configFile."claude/CLAUDE.md" = {
      source = claude_instructions_source;
      force = true;
    };

    home.file.".claude.json" = {
      source = claude_user_config_source;
      force = true;
    };

    # Backwards compatibility for tools that still look under ~/.claude
    home.file.".claude/settings.json".source = settings_source;
    home.file.".claude/CLAUDE.md".source = claude_instructions_source;
  };
}
