{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.codex;
  codex_config_dir = "${config.xdg.configHome}/codex";
  local_skills_dir = "${config.home.homeDirectory}/.local/share/agent-skills";
  config_source = ./config.toml;
  permsLib = import ../../../../developer/permissions.nix { inherit lib; };
  baseline_permissions =
    if config ? developer && config.developer ? baseline then
      config.developer.baseline.agents.permissions
    else
      permsLib.defaultPermissions;
  default_rules = permsLib.toCodexRules baseline_permissions;
  codex_wrapper = pkgs.writeShellApplication {
    name = "codex";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      run_codex() {
        active_config_dir="''${CODEX_HOME:-''${CODEX_CONFIG_DIR:-${codex_config_dir}}}"
        target_dir="$active_config_dir/skills"

        if [[ -d "${local_skills_dir}" ]]; then
          mkdir -p "$target_dir"
          for source in "${local_skills_dir}"/*; do
            [[ -f "$source/SKILL.md" ]] || continue
            target="$target_dir/$(basename "$source")"
            if [[ -e "$target" && ! -L "$target" ]]; then
              echo "preserving unmanaged skill $target" >&2
              continue
            fi
            ln -sfnT "$source" "$target"
          done
        fi

        export CODEX_DISABLE_TELEMETRY=1
        export CODEX_DISABLE_ANALYTICS=1
        export CODEX_DISABLE_FEEDBACK=1
        export CODEX_DISABLE_AUTO_UPDATE=1
        export CODEX_DISABLE_UPDATE_CHECK=1
        export CODEX_DISABLE_ERROR_REPORTING=1
        export CODEX_DISABLE_ANIMATIONS=1
        export OPENAI_LOG=error
        export RUST_BACKTRACE=0
        export GOTELEMETRY=off
        export SENTRY_DSN=""
        export OTEL_SDK_DISABLED=true
        export OTEL_TRACES_EXPORTER=none
        export OTEL_METRICS_EXPORTER=none
        export OTEL_LOGS_EXPORTER=none
        export DO_NOT_TRACK=1

        exec "${cfg.package}/bin/codex" "$@"
      }

      if [ "''${PROFILE_ROUTER_ACTIVE:-0}" = "1" ]; then
        run_codex "$@"
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
                run_codex "$@"
              fi
            ''
        }
      fi
    '';
  };
in
{
  config = lib.mkMerge [
    {
      programs.codex.enable = lib.mkDefault true;
    }
    (lib.mkIf cfg.enable {
      programs.codex.package = lib.mkDefault pkgs.codex;
      home.sessionVariables.CODEX_HOME = lib.mkDefault codex_config_dir;

      # Keep private skills outside the Nix store. This wrapper materializes them
      # into Codex's native discovery directory at every invocation.
      home.file.".local/bin/codex".source = "${codex_wrapper}/bin/codex";
      home.file.".local/bin/codex-code-mode-host".source = "${cfg.package}/bin/codex-code-mode-host";

      home.activation.ensureCodexConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        set -euo pipefail

        config_target="${codex_config_dir}/config.toml"
        rules_target="${codex_config_dir}/rules/default.rules"

        mkdir -p "${codex_config_dir}/rules"

        # Replace read-only nix store symlinks with writable files managed in user space.
        if [[ -L "$config_target" ]]; then
          rm -f "$config_target"
        fi
        if [[ -L "$rules_target" ]]; then
          rm -f "$rules_target"
        fi

        install -m 600 "${config_source}" "$config_target"
        install -m 600 "${pkgs.writeText "codex-default.rules" default_rules}" "$rules_target"
      '';
    })
  ];
}
