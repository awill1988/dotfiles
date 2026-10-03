{
  config,
  lib,
  pkgs,
  ...
}:
let
  permsLib = import ../../../../developer/permissions.nix { inherit lib; };
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
      general = {
        enableAutoUpdate = false;
        enableNotifications = false;
      };
      ui = {
        enableAnimations = false;
        showSpinner = false;
      };
      permissions = permsLib.toAgyPermissions (
        if config ? developer && config.developer ? baseline then
          config.developer.baseline.agents.permissions
        else
          permsLib.defaultPermissions
      );
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
      general = {
        enableAutoUpdate = false;
        enableNotifications = false;
      };
      ui = {
        enableAnimations = false;
        showSpinner = false;
      };
      permissions = permsLib.toAgyPermissions (
        if config ? developer && config.developer.profiles ? work then
          config.developer.profiles.work.agents.permissions
        else
          permsLib.defaultPermissions
      );
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
    export AGY_CLI_DISABLE_UPDATE_CHECK=true
    export AGY_UI_ANIMATIONS_DISABLED=true
    export OTEL_SDK_DISABLED=true
    export DO_NOT_TRACK=1

    run_agy() {
      if [ -n "''${AGY_CONFIG_DIR:-}" ] && [ -f "''${AGY_CONFIG_DIR}/settings.json" ]; then
        target="${home_dir}/.gemini/antigravity-cli/settings.json"
        mkdir -p "$(dirname "$target")"
        if [ ! -f "$target" ]; then
          ${pkgs.coreutils}/bin/install -m 600 "''${AGY_CONFIG_DIR}/settings.json" "$target"
        else
          ${pkgs.jq}/bin/jq -s '
            .[0] as $target | .[1] as $source | ($target * $source)
            | .permissions.allow = (((($target.permissions.allow // []) + ($source.permissions.allow // [])) | unique))
            | .permissions.deny = (((($target.permissions.deny // []) + ($source.permissions.deny // [])) | unique))
            | .permissions.ask = (((($target.permissions.ask // []) + ($source.permissions.ask // [])) | unique))
          ' "$target" "''${AGY_CONFIG_DIR}/settings.json" > "$target.tmp"
          ${pkgs.coreutils}/bin/chmod 600 "$target.tmp"
          ${pkgs.coreutils}/bin/mv "$target.tmp" "$target"
        fi
      fi
      exec "${cfg.package}/bin/agy" "$@"
    }

    if [ "''${PROFILE_ROUTER_ACTIVE:-0}" = "1" ]; then
      run_agy "$@"
    else
      export PROFILE_ROUTER_ACTIVE=1
      ${
        if config.developer.profileRouter != null then
          ''exec "${config.developer.profileRouter}/bin/profile-router" "$0" "$@"''
        else
          ''
            if command -v profile-router >/dev/null 2>&1; then
              exec profile-router "$0" "$@"
            else
              run_agy "$@"
            fi
          ''
      }
    fi
  '';
in
{
  options.programs.agy = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Antigravity CLI (agy)";
    };
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

        # Install or refresh settings if target does not exist or merge with source
        if [[ ! -e "$target" ]]; then
          install -m 600 "$source" "$target"
        else
          ${pkgs.jq}/bin/jq -s '
            .[0] as $target | .[1] as $source | ($target * $source)
            | .permissions.allow = (((($target.permissions.allow // []) + ($source.permissions.allow // [])) | unique))
            | .permissions.deny = (((($target.permissions.deny // []) + ($source.permissions.deny // [])) | unique))
            | .permissions.ask = (((($target.permissions.ask // []) + ($source.permissions.ask // [])) | unique))
          ' "$target" "$source" > "$target.tmp"
          chmod 600 "$target.tmp"
          mv "$target.tmp" "$target"
        fi
      }

      seed_agy_settings "${primary_settings_src}" "${agy_home}/settings.json"
      seed_agy_settings "${restricted_settings_src}" "${agy_restricted_home}/settings.json"
      seed_agy_settings "${primary_settings_src}" "${home_dir}/.gemini/antigravity-cli/settings.json"
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
