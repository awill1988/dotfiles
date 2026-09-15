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
      export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
      export DISABLE_NON_ESSENTIAL_MODEL_CALLS=1
      export CLAUDE_CODE_DISABLE_AUTO_MEMORY=1
      export CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY=1
      export ENABLE_CLAUDEAI_MCP_SERVERS=false
      export OTEL_SDK_DISABLED=true
      export DO_NOT_TRACK=1

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
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ claude_wrapper ];

    # symlink for native install method check (expects ~/.local/bin/claude)
    home.file.".local/bin/claude" = {
      source = "${claude_wrapper}/bin/claude";
      force = true;
    };

    home.sessionVariables = {
      CLAUDE_CACHE_DIR = lib.mkDefault claude_cache;
      CLAUDE_STATE_DIR = lib.mkDefault claude_state;
    };
  };
}
