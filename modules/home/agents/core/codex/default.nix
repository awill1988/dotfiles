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
  agents_override_source = ./AGENTS.override.md;
  default_rules = ''
    prefix_rule(
        pattern = ["aws", "configure", "list"],
        decision = "allow",
    )

    prefix_rule(
        pattern = ["aws", "sts", "get-caller-identity"],
        decision = "allow",
    )

    prefix_rule(
        pattern = ["aws", "s3", "ls"],
        decision = "allow",
    )

    prefix_rule(
        pattern = ["ls"],
        decision = "allow",
    )

    prefix_rule(
        pattern = ["cat"],
        decision = "allow",
    )

    prefix_rule(
        pattern = ["head"],
        decision = "allow",
    )

    prefix_rule(
        pattern = ["tail"],
        decision = "allow",
    )

    prefix_rule(
        pattern = ["rg"],
        decision = "allow",
    )

    prefix_rule(
        pattern = ["grep"],
        decision = "allow",
    )

    prefix_rule(
        pattern = ["find"],
        decision = "allow",
    )

    prefix_rule(
        pattern = ["which"],
        decision = "allow",
    )

    prefix_rule(
        pattern = ["file"],
        decision = "allow",
    )

    prefix_rule(
        pattern = ["wc"],
        decision = "allow",
    )

    prefix_rule(
        pattern = ["env"],
        decision = "allow",
    )

    prefix_rule(
        pattern = ["whoami"],
        decision = "allow",
    )

    prefix_rule(
        pattern = ["pwd"],
        decision = "allow",
    )
  '';
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
        export OTEL_SDK_DISABLED=true
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

      xdg.configFile."codex/AGENTS.override.md" = {
        source = agents_override_source;
        force = true;
      };
      xdg.configFile."codex/rules/default.rules" = {
        text = default_rules;
        force = true;
      };

      home.activation.ensureCodexConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        set -euo pipefail

        config_target="${codex_config_dir}/config.toml"

        mkdir -p "${codex_config_dir}"

        # Replace the read-only nix store symlink with a writable file Codex can update in place.
        if [[ -L "$config_target" ]]; then
          rm -f "$config_target"
        fi

        if [[ ! -e "$config_target" ]]; then
          install -m 600 "${config_source}" "$config_target"
        else
          if grep -q '^model = "gpt-5\.4"$' "$config_target"; then
            ${pkgs.gnused}/bin/sed -i 's/^model = "gpt-5\.4"$/model = "gpt-5.5"/' "$config_target"
          fi
          if ! grep -q 'code_mode_host' "$config_target"; then
            if grep -q '^\[features\]' "$config_target"; then
              ${pkgs.gnused}/bin/sed -i '/^\[features\]/a code_mode_host = true' "$config_target"
            else
              echo -e "\n[features]\ncode_mode_host = true" >> "$config_target"
            fi
          else
            ${pkgs.gnused}/bin/sed -i 's/^code_mode_host = false/code_mode_host = true/' "$config_target"
          fi

          for feature in apps plugins remote_plugin; do
            if grep -q "^$feature[[:space:]]*=" "$config_target"; then
              ${pkgs.gnused}/bin/sed -i "s/^$feature[[:space:]]*=.*/$feature = false/" "$config_target"
            else
              ${pkgs.gnused}/bin/sed -i "/^\[features\]/a $feature = false" "$config_target"
            fi
          done
        fi
      '';
    })
  ];
}
