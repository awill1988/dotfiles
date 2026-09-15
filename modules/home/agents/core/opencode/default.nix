{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.opencode;
  base_package = pkgs.opencode;
  opencode_config_dir = "${config.xdg.configHome}/opencode";
  opencode_cache_dir = "${config.xdg.cacheHome}/opencode";
  opencode_state_dir = "${config.xdg.stateHome}/opencode";

  default_opencode_config = pkgs.writeText "opencode-default.json" (
    builtins.toJSON {
      provider = "local";
      endpoint = cfg.localEndpoint;
      model = cfg.model;
      offlineOnly = true;
      telemetry = {
        enabled = false;
      };
      general = {
        enableAutoUpdate = false;
      };
      ui = {
        enableAnimations = false;
      };
    }
  );

  opencode_wrapper = pkgs.writeShellApplication {
    name = "opencode";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      export OPENCODE_TELEMETRY_ENABLED=false
      export OPENCODE_OFFLINE_ONLY=1
      export OPENCODE_DISABLE_AUTO_UPDATE=1
      export OPENCODE_UI_ANIMATIONS_DISABLED=1
      export OTEL_SDK_DISABLED=true
      export DO_NOT_TRACK=1

      if [ "''${PROFILE_ROUTER_ACTIVE:-0}" = "1" ]; then
        exec "${base_package}/bin/opencode" "$@"
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
                exec "${base_package}/bin/opencode" "$@"
              fi
            ''
        }
      fi
    '';
  };
in
{
  options.programs.opencode = {
    localEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:11434/v1";
      description = "Local OpenAI-compatible API endpoint for offline LLM execution";
    };
    model = lib.mkOption {
      type = lib.types.str;
      default = "ollama/qwen2.5-coder:32b";
      description = "Default local model identifier";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.opencode.package = lib.mkForce opencode_wrapper;

    home.sessionVariables = {
      OPENCODE_CONFIG_DIR = lib.mkDefault opencode_config_dir;
      OPENCODE_CACHE_DIR = lib.mkDefault opencode_cache_dir;
      OPENCODE_STATE_DIR = lib.mkDefault opencode_state_dir;
    };

    xdg.configFile."opencode/opencode.json" = {
      source = default_opencode_config;
      force = true;
    };
  };
}
