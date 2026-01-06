{ config, lib, pkgs, ... }:
let
  cfg = config.programs.claude;
  claude_home = "${config.xdg.configHome}/claude";
  claude_work_home = "${config.xdg.configHome}/claude-work";
  claude_cache = "${config.xdg.cacheHome}/claude";
  claude_state = "${config.xdg.stateHome}/claude";
  claude_instructions_source = ./CLAUDE.md;
  claude_user_config_source = ./claude.json;
  settings_source = ./settings.json;

  base_package =
    if config.modules.dev.node.enable then
      pkgs.claude.override { nodejs = config.modules.dev.node.package; }
    else
      pkgs.claude;

  # wrapper that routes config based on current working directory
  claude_wrapper = pkgs.writeShellScriptBin "claude" ''
    set -euo pipefail

    work_prefix="$HOME/projects/arro"

    if [[ "$PWD" == "$work_prefix"* ]]; then
      export CLAUDE_CONFIG_DIR="${claude_work_home}"
    else
      export CLAUDE_CONFIG_DIR="${claude_home}"
    fi

    exec "${base_package}/bin/claude" "$@"
  '';
in
{
  options.programs.claude = {
    enable = lib.mkEnableOption "Claude Code CLI";
    package = lib.mkOption {
      type = lib.types.package;
      default = base_package;
      description = "Claude package to install.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ claude_wrapper ];
    home.sessionVariables = {
      CLAUDE_CONFIG_DIR = lib.mkDefault claude_home;
      CLAUDE_CACHE_DIR = lib.mkDefault claude_cache;
      CLAUDE_STATE_DIR = lib.mkDefault claude_state;
    };

    # personal config
    xdg.configFile."claude/settings.json" = {
      source = settings_source;
      force = true;
    };
    xdg.configFile."claude/CLAUDE.md" = {
      source = claude_instructions_source;
      force = true;
    };

    # work config (separate identity for ~/projects/arro)
    xdg.configFile."claude-work/settings.json" = {
      source = settings_source;
      force = true;
    };
    xdg.configFile."claude-work/CLAUDE.md" = {
      source = claude_instructions_source;
      force = true;
    };

    home.file.".claude.json" = {
      source = claude_user_config_source;
      force = true;
    };

    # backwards compatibility for tools that still look under ~/.claude
    home.file.".claude/settings.json".source = settings_source;
    home.file.".claude/CLAUDE.md".source = claude_instructions_source;
  };
}
