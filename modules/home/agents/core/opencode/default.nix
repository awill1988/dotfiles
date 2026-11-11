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

  permsLib = import ../../../../developer/permissions.nix { inherit lib; };
  baseline_permissions =
    if config ? developer && config.developer ? baseline then
      config.developer.baseline.agents.permissions
    else
      permsLib.defaultPermissions;

  base_opencode_json = builtins.toJSON {
    provider = "local";
    endpoint = cfg.localEndpoint;
    model = cfg.model;
    offlineOnly = true;
    autoupdate = false;
    share = "disabled";
    telemetry = {
      enabled = false;
    };
    general = {
      enableAutoUpdate = false;
    };
    ui = {
      enableAnimations = false;
    };
  };

  default_opencode_config = pkgs.writeText "opencode-default.json" (
    "${lib.removeSuffix "}" base_opencode_json},\"permission\":${permsLib.toOpencodePermissionsJson baseline_permissions}}"
  );

  opencode_wrapper = pkgs.writeShellApplication {
    name = "opencode";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      export OPENCODE_TELEMETRY_ENABLED=false
      export OPENCODE_TELEMETRY_DISABLED=1
      export OPENCODE_DISABLE_TELEMETRY=1
      export OPENCODE_NO_TELEMETRY=1
      export OPENCODE_OFFLINE_ONLY=1
      export OPENCODE_DISABLE_AUTO_UPDATE=1
      export OPENCODE_DISABLE_AUTOUPDATE=1
      export OPENCODE_DISABLE_FREE_MODELS=1
      export OPENCODE_UI_ANIMATIONS_DISABLED=1
      export BUN_ENABLE_CRASH_REPORTING=0
      export SENTRY_DSN=""
      export OTEL_SDK_DISABLED=true
      export OTEL_TRACES_EXPORTER=none
      export OTEL_METRICS_EXPORTER=none
      export OTEL_LOGS_EXPORTER=none
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

    home.file.".local/bin/opencode" = {
      source = "${opencode_wrapper}/bin/opencode";
      force = true;
    };

    home.sessionVariables = {
      OPENCODE_CONFIG_DIR = lib.mkDefault opencode_config_dir;
      OPENCODE_CACHE_DIR = lib.mkDefault opencode_cache_dir;
      OPENCODE_STATE_DIR = lib.mkDefault opencode_state_dir;
    };

    home.activation.ensureOpencodeConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      set -euo pipefail
      target="${opencode_config_dir}/opencode.json"
      mkdir -p "${opencode_config_dir}"
      if [[ -L "$target" ]]; then
        rm -f "$target"
      fi
      if [[ ! -e "$target" ]]; then
        install -m 600 "${default_opencode_config}" "$target"
      else
        ${pkgs.jq}/bin/jq -s '.[0] as $target | .[1] as $source | ($target * $source) | .permission = $source.permission' \
          "$target" "${default_opencode_config}" > "$target.tmp"
        chmod 600 "$target.tmp"
        mv "$target.tmp" "$target"
      fi
    '';
  };
}
