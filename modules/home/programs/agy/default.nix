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
  primary_settings_src = pkgs.writeText "agy-settings-primary.json" (
    builtins.toJSON {
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
        allowAllPathCommands = true;
        allowReadTools = true;
        allowedMcpTools = [ "*" ];
        allowedShellCommands = [ "*" ];
      };
      mcpServers = {
        contextforge = {
          command = "mcpgw-wrapper";
        };
      };
    }
  );

  # Restricted (Arro): Claude Secondary ONLY
  restricted_settings_src = pkgs.writeText "agy-settings-restricted.json" (
    builtins.toJSON {
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
        allowAllPathCommands = true;
        allowReadTools = true;
        allowedMcpTools = [ "*" ];
        allowedShellCommands = [ "*" ];
      };
      mcpServers = {
        contextforge = {
          command = "mcpgw-wrapper";
        };
      };
    }
  );

  claude_instructions_source = ../claude/CLAUDE.md;

  agy_settings_reset = pkgs.writeShellScriptBin "agy-settings-reset" ''
    set -euo pipefail

    usage() {
      echo "usage: agy-settings-reset [primary|restricted|all]" >&2
      exit 2
    }

    reset_settings() {
      local source="$1"
      local target="$2"
      local backup

      mkdir -p "$(dirname "$target")"

      if [[ -e "$target" || -L "$target" ]]; then
        backup="''${target}.backup-$(${pkgs.coreutils}/bin/date +%Y%m%d%H%M%S)"
        ${pkgs.coreutils}/bin/cp -L --preserve=mode "$target" "$backup"
        echo "backed up $target to $backup"
      fi

      ${pkgs.coreutils}/bin/install -m 600 "$source" "$target"
      echo "reset $target"
    }

    case "''${1:-all}" in
      primary)
        reset_settings "${primary_settings_src}" "${agy_home}/settings.json"
        ;;
      restricted)
        reset_settings "${restricted_settings_src}" "${agy_restricted_home}/settings.json"
        ;;
      all)
        reset_settings "${primary_settings_src}" "${agy_home}/settings.json"
        reset_settings "${restricted_settings_src}" "${agy_restricted_home}/settings.json"
        ;;
      *)
        usage
        ;;
    esac
  '';

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
    home.packages = [
      agy_wrapper
      agy_settings_reset
    ];

    # Primary and restricted settings are mutable runtime state: AGY updates them
    # through /config and peer toggles. Activation seeds them from the Nix store
    # if absent, and migrates any pre-existing read-only symlink to a writable file.
    home.activation.ensureAgyConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      seed_agy_settings() {
        local source="$1"
        local target="$2"

        mkdir -p "$(dirname "$target")"

        # Migrate the previous Home Manager symlink to a writable runtime file.
        if [[ -L "$target" ]]; then
          rm -f "$target"
        fi

        # Install or refresh settings if target does not exist or template source changed
        if [[ ! -e "$target" ]]; then
          install -m 600 "$source" "$target"
        else
          # Update default permissions structure if missing wildcard permissions
          if grep -q '"allowedShellCommands":\s*\[\s*"aws' "$target"; then
            install -m 600 "$source" "$target"
          fi
        fi
      }

      seed_agy_settings "${primary_settings_src}" "${agy_home}/settings.json"
      seed_agy_settings "${restricted_settings_src}" "${agy_restricted_home}/settings.json"
    '';

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
