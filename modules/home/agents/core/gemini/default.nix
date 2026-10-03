{
  config,
  lib,
  pkgs,
  ...
}:
let
  permsLib = import ../../../../developer/permissions.nix { inherit lib; };
  cfg = config.programs.gemini;
  gemini_home = "${config.xdg.configHome}/gemini";
  gemini_instructions_source = ./GEMINI.md;

  baseline_permissions =
    if config ? developer && config.developer ? baseline then
      config.developer.baseline.agents.permissions
    else
      permsLib.defaultPermissions;

  unified_policy = permsLib.toGeminiPolicy baseline_permissions;

  generated_settings = pkgs.writeText "gemini-settings.json" (
    builtins.toJSON (
      (builtins.fromJSON (builtins.readFile ./settings.json))
      // {
        tools = permsLib.toGeminiSettings baseline_permissions;
      }
    )
  );

  gemini_wrapper = pkgs.writeShellApplication {
    name = "gemini";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      run_gemini() {
        policy_file="''${GEMINI_CONFIG_DIR:-${gemini_home}}/policies/permissions.toml"
        if [ ! -f "$policy_file" ]; then
          policy_file="${gemini_home}/policies/permissions.toml"
        fi
        if [ ! -f "$policy_file" ]; then
          policy_file="${gemini_home}/policies/aws-readonly.toml"
        fi

        policy_args=()
        if [ -f "$policy_file" ]; then
          policy_args=(--policy "$policy_file")
        fi

        export GEMINI_TELEMETRY_ENABLED=false
        export GEMINI_TELEMETRY_TRACES_ENABLED=false
        export GEMINI_TELEMETRY_LOG_PROMPTS=false
        export GEMINI_ANALYTICS_DISABLED=true
        export GEMINI_DISABLE_AUTO_UPDATE=1
        export GEMINI_UI_ANIMATIONS_DISABLED=true
        export OTEL_SDK_DISABLED=true
        export DO_NOT_TRACK=1

        exec "${cfg.package}/bin/gemini" "''${policy_args[@]}" "$@"
      }

      if [ "''${PROFILE_ROUTER_ACTIVE:-0}" = "1" ]; then
        run_gemini "$@"
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
                run_gemini "$@"
              fi
            ''
        }
      fi
    '';
  };
in
{
  options.programs.gemini = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Gemini CLI";
    };
    package = lib.mkOption {
      type = lib.types.package;
      default =
        if config.modules.dev.node.enable then
          pkgs.gemini.override { nodejs = config.modules.dev.node.package; }
        else
          pkgs.gemini;
      description = "Gemini CLI package to install.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ gemini_wrapper ];
    home.sessionVariables.GEMINI_CLI_SYSTEM_SETTINGS_PATH = lib.mkDefault "${gemini_home}/settings.json";

    xdg.configFile."gemini/settings.json" = {
      source = generated_settings;
      force = true;
    };
    xdg.configFile."gemini/GEMINI.md" = {
      source = gemini_instructions_source;
      force = true;
    };
    xdg.configFile."gemini/policies/permissions.toml" = {
      text = unified_policy;
      force = true;
    };
    xdg.configFile."gemini/policies/aws-readonly.toml" = {
      text = unified_policy;
      force = true;
    };

    # Backwards compatibility for tools that still look under ~/.gemini
    home.file.".gemini/settings.json".source = generated_settings;
    home.file.".gemini/GEMINI.md".source = gemini_instructions_source;
  };
}
