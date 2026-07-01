{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.agy;
  home_dir = config.home.homeDirectory;
  agy_home = "${config.xdg.configHome}/antigravity";
  agy_restricted_home = "${config.xdg.configHome}/antigravity-restricted";

  # Unrestricted: Standard peer suite
  primary_settings = builtins.toJSON {
    agentEcosystem = {
      orchestrator = "agy";
      peers = [
        {
          name = "claude";
          bin = "claude";
          enabled = true;
        }
        {
          name = "gemini";
          bin = "gemini";
          enabled = true;
        }
        {
          name = "codex";
          bin = "codex";
          enabled = true;
        }
      ];
    };
    privacy = {
      enableTelemetry = false;
      interactionCollection = "off";
      usageStatisticsEnabled = false;
      telemetry = false;
    };
    permissions = {
      allowedMcpTools = [
        "contextforge.aws-call-aws"
        "contextforge.aws-suggest-aws-commands"
        "contextforge.aws-docs-read-documentation"
        "contextforge.aws-docs-read-sections"
        "contextforge.aws-docs-search-documentation"
        "contextforge.aws-docs-recommend"
      ];
      allowedShellCommands = [
        "aws configure list"
        "aws sts get-caller-identity"
        "aws s3 ls"
        "cat"
        "env"
        "file"
        "find"
        "grep"
        "head"
        "ls"
        "pwd"
        "rg"
        "tail"
        "wc"
        "which"
        "whoami"
      ];
    };
    mcpServers = {
      contextforge = {
        command = "mcpgw-wrapper";
      };
    };
  };

  # Restricted (Arro): Claude Secondary ONLY
  restricted_settings = builtins.toJSON {
    agentEcosystem = {
      orchestrator = "agy";
      peers = [
        {
          name = "claude-secondary";
          bin = "claude";
          enabled = true;
        }
      ];
    };
    privacy = {
      enableTelemetry = false;
      interactionCollection = "off";
      usageStatisticsEnabled = false;
      telemetry = false;
    };
    permissions = {
      allowedMcpTools = [
        "contextforge.aws-call-aws"
        "contextforge.aws-suggest-aws-commands"
        "contextforge.aws-docs-read-documentation"
        "contextforge.aws-docs-read-sections"
        "contextforge.aws-docs-search-documentation"
        "contextforge.aws-docs-recommend"
      ];
      allowedShellCommands = [
        "aws configure list"
        "aws sts get-caller-identity"
        "aws s3 ls"
        "cat"
        "env"
        "file"
        "find"
        "grep"
        "head"
        "ls"
        "pwd"
        "rg"
        "tail"
        "wc"
        "which"
        "whoami"
      ];
    };
    mcpServers = {
      contextforge = {
        command = "mcpgw-wrapper";
      };
    };
  };

  claude_instructions_source = ../claude/CLAUDE.md;

  # The Identity-Routing Wrapper
  agy_wrapper = pkgs.writeShellScriptBin "agy" ''
    set -euo pipefail

    # Privacy Lockdown (Mandatory Dark Mode)
    export AGY_TELEMETRY_ENABLED=false
    export ANTIGRAVITY_TELEMETRY_ENABLED=false
    export ANTIGRAVITY_DATA_COLLECTION=opt-out
    export GOTELEMETRY=off
    export AGY_CLI_DISABLE_TELEMETRY=true
    export OTEL_SDK_DISABLED=true
    export DO_NOT_TRACK=1

    # Path-Based Identity Routing
    # Restriction zone: ~/projects/arro/* uses Claude-Secondary only.
    arro_prefix="${home_dir}/projects/arro"
    current_dir="$(pwd -P)"

    if [[ "$current_dir" == "$arro_prefix" || "$current_dir" == "$arro_prefix"/* ]]; then
      export AGY_CONFIG_DIR="${agy_restricted_home}"
      export AGY_PEERS="claude-secondary"
      export AGY_STATUS_LABEL="ARRO-RESTRICTED"
      export CLAUDE_CONFIG_DIR="${config.xdg.configHome}/claude-secondary"
    else
      export AGY_CONFIG_DIR="${agy_home}"
      export AGY_PEERS="claude,gemini,codex"
    fi

    exec "${cfg.package}/bin/agy" "$@"
  '';
in
{
  options.programs.agy = {
    enable = lib.mkEnableOption "Antigravity CLI (agy)";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.agy;
      description = "Antigravity CLI package to install.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ agy_wrapper ];

    # Seed Dual Identities
    xdg.configFile."antigravity/settings.json".text = primary_settings;
    xdg.configFile."antigravity-restricted/settings.json".text = restricted_settings;

    # Compatibility instructions are sourced from the Claude canonical file.
    xdg.configFile."antigravity/AGY.md".source = claude_instructions_source;
    xdg.configFile."antigravity-restricted/AGY.md".source = claude_instructions_source;

    home.sessionVariables = {
      ANTIGRAVITY_AGENT = "1";
      AGY_MISSION_CONTROL = "1";
    };

    programs.zsh.shellAliases = {
      g = "agy";
      gemini = "agy";
    };
  };
}
