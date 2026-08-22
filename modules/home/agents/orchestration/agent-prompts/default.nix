{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.modules.agents.agent-prompts;
  profilesList = attrValues config.developer.profiles;
  instructions_source = cfg.instructionsSource;
in
{
  options.modules.agents.agent-prompts = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable independent agent-prompts instruction architecture (AGENTS.md canonical with CLAUDE.md / GEMINI.md / AGY.md symlinks).";
    };
    instructionsSource = mkOption {
      type = types.path;
      default = ./AGENTS.md;
      description = "Canonical instructions file source.";
    };
  };

  config = mkIf cfg.enable {
    home.activation.ensureAgentPrompts = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      set -euo pipefail
      ${concatMapStringsSep "\n" (p: ''
        profile_dir="${config.xdg.configHome}/profiles/${p.name}"
        mkdir -p "$profile_dir/claude" "$profile_dir/gemini" "$profile_dir/antigravity" "$profile_dir/codex"

        # 1. Seed canonical AGENTS.md
        install -m 600 -C "${instructions_source}" "$profile_dir/AGENTS.md"

        # 2. Create relative symlinks for tool-specific instruction files
        ln -sfT "../AGENTS.md" "$profile_dir/claude/CLAUDE.md"
        ln -sfT "../AGENTS.md" "$profile_dir/gemini/GEMINI.md"
        ln -sfT "../AGENTS.md" "$profile_dir/antigravity/AGY.md"
        ln -sfT "../AGENTS.md" "$profile_dir/codex/AGENTS.override.md"
      '') profilesList}
    '';
  };
}
