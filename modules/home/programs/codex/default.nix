{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.codex;
  codex_config_dir = "${config.xdg.configHome}/codex";
  config_source = ./config.toml;
  agents_override_source = ./AGENTS.override.md;
in
{
  config = lib.mkIf cfg.enable {
    programs.codex.package = lib.mkDefault pkgs.codex;
    home.sessionVariables.CODEX_HOME = lib.mkDefault codex_config_dir;

    xdg.configFile."codex/AGENTS.override.md" = {
      source = agents_override_source;
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
      elif grep -q '^model = "gpt-5\.4"$' "$config_target"; then
        ${pkgs.gnused}/bin/sed -i 's/^model = "gpt-5\.4"$/model = "gpt-5.5"/' "$config_target"
      fi
    '';
  };
}
