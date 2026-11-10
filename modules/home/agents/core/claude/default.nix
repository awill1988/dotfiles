{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.claude;
  claude_home = "${config.xdg.configHome}/claude";
  claude_cache = "${config.xdg.cacheHome}/claude";
  claude_state = "${config.xdg.stateHome}/claude";

  base_package = pkgs.claude;

  # wrapper delegates profile resolution directly to profile-router
  claude_wrapper = pkgs.writeShellApplication {
    name = "claude";
    runtimeInputs = with pkgs; [
      coreutils
    ];
    text = ''
      # bypass socks proxy for claude and mcp servers
      unset ALL_PROXY all_proxy SOCKS_PROXY socks_proxy

      export DISABLE_AUTOUPDATER=1
      export DISABLE_UPDATES=1
      export DISABLE_UPGRADE_COMMAND=1
      export DISABLE_BUG_COMMAND=1
      export DISABLE_FEEDBACK_COMMAND=1
      export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
      export DISABLE_NON_ESSENTIAL_MODEL_CALLS=1
      export CLAUDE_CODE_ENABLE_TELEMETRY=0
      export CLAUDE_CODE_DISABLE_FEATURE_FLAGS=1
      export CLAUDE_CODE_AUTO_MODE_SERVER=0
      export CLAUDE_CODE_ATTRIBUTION_HEADER=0
      export CLAUDE_CODE_SUPPRESS_SESSION_ATTRIBUTION=1
      export CLAUDE_CODE_DISABLE_AUTO_MEMORY=1
      export CLAUDE_CODE_DISABLE_ORG_MEMORY=1
      export CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY=1
      export CLAUDE_CODE_SEND_FEEDBACK=0
      export CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1
      export CLAUDE_CODE_DISABLE_AWAY_SUMMARY=1
      export CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL=1
      export CLAUDE_CODE_PACKAGE_MANAGER_AUTO_UPDATE=0
      export BUN_ENABLE_CRASH_REPORTING=0
      export SENTRY_DSN=""
      export ENABLE_LSP_TOOL=1
      export CLAUDE_CODE_BASH_SANDBOX_SHOW_INDICATOR=1
      export CLAUDE_CODE_NO_FLICKER=1
      export CLAUDE_CODE_USE_NATIVE_FILE_SEARCH=1
      : "''${ENABLE_CLAUDEAI_MCP_SERVERS:=false}"
      export ENABLE_CLAUDEAI_MCP_SERVERS
      export OTEL_SDK_DISABLED=true
      export OTEL_TRACES_EXPORTER=none
      export OTEL_METRICS_EXPORTER=none
      export OTEL_LOGS_EXPORTER=none
      export DO_NOT_TRACK=1
      export DISABLE_TELEMETRY=1
      export DISABLE_GROWTHBOOK=1
      export DISABLE_ERROR_REPORTING=1
      ${lib.optionalString cfg.disableAutoMode ''
        export CLAUDE_CODE_DISABLE_PROACTIVITY=1
      ''}

      ${
        if config.developer.profileRouter != null then
          ''
            exec "${config.developer.profileRouter}/bin/profile-router" "${base_package}/bin/claude" "$@"
          ''
        else
          ''
            if command -v profile-router >/dev/null 2>&1; then
              exec profile-router "${base_package}/bin/claude" "$@"
            else
              exec "${base_package}/bin/claude" "$@"
            fi
          ''
      }
    '';
  };
  claude_secondary_wrapper = pkgs.writeShellApplication {
    name = "claude-secondary";
    runtimeInputs = with pkgs; [
      coreutils
    ];
    text = ''
      export DEVELOPER_PROFILE="work"
      export CLAUDE_CONFIG_DIR="${config.xdg.configHome}/claude-secondary"
      export ARRO_ENGINEERING_PATH="$HOME/projects/arro/arro-engineering"
      export ARRO_REPOS_PATH="$HOME/projects/arro"
      exec "${claude_wrapper}/bin/claude" "$@"
    '';
  };
in
{
  options.programs.claude = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Claude Code CLI";
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = base_package;
      description = "Claude package to install.";
    };
    disableAutoMode = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Completely disable auto-mode in Claude Code CLI";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      claude_wrapper
      claude_secondary_wrapper
    ];

    # symlink for native install method check (expects ~/.local/bin/claude)
    home.file.".local/bin/claude" = {
      source = "${claude_wrapper}/bin/claude";
      force = true;
    };

    home.file.".local/bin/claude-secondary" = {
      source = "${claude_secondary_wrapper}/bin/claude-secondary";
      force = true;
    };

    home.sessionVariables = {
      CLAUDE_CACHE_DIR = lib.mkDefault claude_cache;
      CLAUDE_STATE_DIR = lib.mkDefault claude_state;
    };
  };
}
