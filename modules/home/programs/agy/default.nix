{ config, lib, pkgs, ... }:
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
        { name = "claude"; bin = "claude"; enabled = true; }
        { name = "gemini"; bin = "gemini"; enabled = true; }
        { name = "codex"; bin = "codex"; enabled = true; }
      ];
    };
    privacy = { enableTelemetry = false; interactionCollection = "off"; };
    mcpServers = { contextforge = { command = "mcpgw-wrapper"; }; };
  };

  # Restricted (Arro): Claude Secondary ONLY
  restricted_settings = builtins.toJSON {
    agentEcosystem = {
      orchestrator = "agy";
      peers = [
        { name = "claude-secondary"; bin = "claude"; enabled = true; }
      ];
    };
    privacy = { enableTelemetry = false; interactionCollection = "off"; };
    mcpServers = { contextforge = { command = "mcpgw-wrapper"; }; };
  };

  # The Identity-Routing Wrapper
  agy_wrapper = pkgs.writeShellScriptBin "agy" ''
    set -euo pipefail

    # Privacy Lockdown (Mandatory Dark Mode)
    export AGY_TELEMETRY_ENABLED=false
    export ANTIGRAVITY_DATA_COLLECTION=opt-out
    export GOTELEMETRY=off

    # Path-Based Identity Routing
    # Restriction zone: ~/projects/arro/* uses Claude-Secondary only.
    arro_prefix="${home_dir}/projects/arro"
    
    if [[ "$PWD" == "$arro_prefix"* ]]; then
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
    
    # Standard Instructions (Pinned to repository state)
    xdg.configFile."antigravity/AGY.md".source = ./AGY.md;
    xdg.configFile."antigravity-restricted/AGY.md".source = ./AGY.md;

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
