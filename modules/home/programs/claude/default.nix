{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.claude;
  claude_home = "${config.xdg.configHome}/claude";
  claude_secondary_home = "${config.xdg.configHome}/claude-secondary";
  claude_cache = "${config.xdg.cacheHome}/claude";
  claude_state = "${config.xdg.stateHome}/claude";
  claude_root_config = "${config.home.homeDirectory}/.claude.json";
  claude_instructions_source = ./CLAUDE.md;

  # base user config from file (contains shared MCP servers like github)
  base_user_config = builtins.fromJSON (builtins.readFile ./claude.json);

  # non-destructive exploratory commands to auto-approve
  allowed_bash_commands = [
    "Bash(curl *)"
    "Bash(aws *)"
    "Bash(gh *)"
    "Bash(docker *)"
    "Bash(ls *)"
    "Bash(cat *)"
    "Bash(head *)"
    "Bash(tail *)"
    "Bash(grep *)"
    "Bash(find *)"
    "Bash(which *)"
    "Bash(file *)"
    "Bash(wc *)"
    "Bash(echo *)"
    "Bash(ps *)"
    "Bash(env)"
    "Bash(whoami)"
    "Bash(pwd)"
  ];

  # fivetran mcp tools that mutate state - deny these for read-only access
  denied_mcp_tools = [
    "mcp__fivetran__pause_connector"
    "mcp__fivetran__resume_connector"
    "mcp__fivetran__create_dynamic_connector"
    "mcp__fivetran__migrate_connector"
    "mcp__fivetran__reload_connector_schema"
    "mcp__fivetran__update_connector_schema"
    "mcp__fivetran__modify_sync_frequency"
  ];

  # settings.json - non-MCP settings only
  settings_json = pkgs.writeText "settings.json" (
    builtins.toJSON {
      env = {
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
        DISABLE_NON_ESSENTIAL_MODEL_CALLS = "1";
        CLAUDE_CODE_MAX_OUTPUT_TOKENS = "128000";
      };
      telemetry = {
        enabled = false;
        analytics = false;
        statsig.enabled = false;
      };
      feedback = {
        prompt = false;
        surveys.enabled = false;
      };
      permissions = {
        allow = allowed_bash_commands;
        deny = denied_mcp_tools;
      };
    }
  );

  # generate claude.json (user config) for an identity with merged MCP servers
  make_user_config =
    identity_cfg:
    let
      base_mcp = base_user_config.mcpServers or { };
      identity_mcp = identity_cfg.mcpServers or { };
      merged_mcp = base_mcp // identity_mcp;
      merged_config = base_user_config // {
        mcpServers = merged_mcp;
      };
    in
    pkgs.writeText "claude.json" (builtins.toJSON merged_config);

  primary_user_config = make_user_config cfg.primary;
  secondary_user_config = make_user_config cfg.secondary;

  # native binary, no nodejs dependency
  base_package = pkgs.claude;

  # wrapper that routes config based on current working directory
  claude_wrapper = pkgs.writeShellScriptBin "claude" ''
    set -euo pipefail

    # bypass socks proxy for claude and mcp servers
    unset ALL_PROXY all_proxy SOCKS_PROXY socks_proxy

    secondary_prefix="${cfg.secondary.pathPrefix}"

    if [[ -n "$secondary_prefix" && "$PWD" == "$secondary_prefix"* ]]; then
      export CLAUDE_CONFIG_DIR="${claude_secondary_home}"
      ${lib.optionalString (
        cfg.secondary.awsProfile != null
      ) ''export AWS_PROFILE="${cfg.secondary.awsProfile}"''}
      ${lib.optionalString (
        cfg.secondary.awsRegion != null
      ) ''export AWS_REGION="${cfg.secondary.awsRegion}"''}
    else
      export CLAUDE_CONFIG_DIR="${claude_home}"
      ${lib.optionalString (
        cfg.primary.awsProfile != null
      ) ''export AWS_PROFILE="${cfg.primary.awsProfile}"''}
      ${lib.optionalString (
        cfg.primary.awsRegion != null
      ) ''export AWS_REGION="${cfg.primary.awsRegion}"''}
    fi

    exec "${base_package}/bin/claude" "$@"
  '';

  # mcp server option type
  mcp_server_type = lib.types.submodule {
    options = {
      command = lib.mkOption {
        type = lib.types.str;
        description = "Command to run the MCP server";
      };
      args = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Arguments for the MCP server command";
      };
      env = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Environment variables for the MCP server";
      };
      disabledTools = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "List of tool names to disable for this MCP server";
      };
    };
  };

  # identity configuration options
  identity_options = {
    mcpServers = lib.mkOption {
      type = lib.types.attrsOf mcp_server_type;
      default = { };
      description = "MCP servers for this identity";
    };
    awsProfile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "AWS profile to use for this identity";
    };
    awsRegion = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "AWS region to use for this identity";
    };
  };
in
{
  options.programs.claude = {
    enable = lib.mkEnableOption "Claude Code CLI";
    package = lib.mkOption {
      type = lib.types.package;
      default = base_package;
      description = "Claude package to install.";
    };

    primary = identity_options;

    secondary = identity_options // {
      pathPrefix = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Directory prefix that activates secondary identity";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ claude_wrapper ];

    # symlink for native install method check (expects ~/.local/bin/claude)
    home.file.".local/bin/claude".source = "${claude_wrapper}/bin/claude";

    home.sessionVariables = {
      CLAUDE_CONFIG_DIR = lib.mkDefault claude_home;
      CLAUDE_CACHE_DIR = lib.mkDefault claude_cache;
      CLAUDE_STATE_DIR = lib.mkDefault claude_state;
    };

    # primary config
    xdg.configFile."claude/settings.json" = {
      source = settings_json;
      force = true;
    };
    xdg.configFile."claude/CLAUDE.md" = {
      source = claude_instructions_source;
      force = true;
    };
    # .claude.json (with dot) is where Claude reads MCP servers from
    # .claude.json is mutable, so seed it via activation instead of symlink.

    # secondary config
    xdg.configFile."claude-secondary/settings.json" = {
      source = settings_json;
      force = true;
    };
    xdg.configFile."claude-secondary/CLAUDE.md" = {
      source = claude_instructions_source;
      force = true;
    };
    # .claude.json (with dot) is where Claude reads MCP servers from
    # .claude.json is mutable, so seed it via activation instead of symlink.

    # ~/.claude.json used by claude for user-scoped config (when CLAUDE_CONFIG_DIR not set)
    # seed it via activation instead of a read-only symlink.

    home.activation.ensureClaudeConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      merge_claude_config() {
        local source="$1"
        local target="$2"
        local mode="$3"

        mkdir -p "$(dirname "$target")"

        # remove symlink if present (from old config)
        if [[ -L "$target" ]]; then
          rm -f "$target"
        fi

        if [[ ! -e "$target" ]]; then
          # file doesn't exist, seed it
          install -m "$mode" "$source" "$target"
        else
          # file exists, merge mcpServers from nix config into existing file
          # preserves runtime state (numStartups, projects, cache, etc.)
          ${pkgs.jq}/bin/jq -s '.[0] + {mcpServers: .[1].mcpServers}' \
            "$target" "$source" > "$target.tmp"
          chmod "$mode" "$target.tmp"
          mv "$target.tmp" "$target"
        fi
      }

      merge_claude_config "${primary_user_config}" "${claude_home}/.claude.json" 600
      merge_claude_config "${secondary_user_config}" "${claude_secondary_home}/.claude.json" 600
    '';
  };
}
