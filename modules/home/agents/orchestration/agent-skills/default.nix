# Vendors external agent skill bundles into the shared
# ~/.local/share/agent-skills directory that the claude and codex wrappers
# sync into their per-agent config dirs at launch (see sync_local_skills in
# modules/home/programs/{claude,codex}/default.nix). Source is a flake input,
# so builtins.readDir runs at eval time over a store path (no import-from-
# derivation) and the skill set tracks upstream automatically.
{ golang_skills_src }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.agent-skills;
  skills_dir = golang_skills_src + "/skills";

  # each child directory of skills/ is one skill (contains its own SKILL.md)
  discovered = lib.attrNames (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir skills_dir)
  );
  selected = lib.subtractLists cfg.exclude discovered;

  target_base = ".local/share/agent-skills";
in
{
  options.programs.agent-skills = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable vendored agent skills in ~/.local/share/agent-skills";
    };

    exclude = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "go-linting" ];
      description = "skill directory names to omit from installation";
    };

    repositories = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "https://github.com/awill1988/agent-skills.git"
      ];
      description = "List of git URLs for external agent-skills repositories to shallow clone as read-only state.";
    };

    storageDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.local/share/agent-skills-repos";
      description = "Directory storing shallow-cloned read-only skill repositories.";
    };

    stagedDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.local/share/agent-skills";
      description = "Shared directory where discovered skills are staged.";
    };
  };

  config = lib.mkIf cfg.enable {
    # one read-only store symlink per skill; user-added skills in the same dir
    # stay unmanaged and writable since home.file only owns these entries.
    home.file = lib.listToAttrs (
      map (name: {
        name = "${target_base}/${name}";
        value.source = skills_dir + "/${name}";
      }) selected
    );

    home.activation.syncExternalAgentSkills = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      set -euo pipefail

      STORAGE_DIR="${cfg.storageDir}"
      STAGED_DIR="${cfg.stagedDir}"
      mkdir -p "$STORAGE_DIR" "$STAGED_DIR"

      REPOS=(${lib.concatStringsSep " " (map (r: "\"${r}\"") cfg.repositories)})

      for repo_url in "''${REPOS[@]}"; do
        repo_name=$(basename "$repo_url" .git)
        target_repo_dir="$STORAGE_DIR/$repo_name"

        if [[ ! -d "$target_repo_dir/.git" ]]; then
          echo "cloning $repo_url (shallow, read-only)..." >&2
          mkdir -p "$target_repo_dir"
          ${pkgs.git}/bin/git clone --depth 1 "$repo_url" "$target_repo_dir" || true
        else
          echo "updating $repo_name (shallow, reset)..." >&2
          chmod -R u+w "$target_repo_dir" 2>/dev/null || true
          (
            cd "$target_repo_dir"
            ${pkgs.git}/bin/git fetch --depth 1 origin main 2>/dev/null && \
            ${pkgs.git}/bin/git reset --hard origin/main 2>/dev/null
          ) || echo "warning: network fetch failed for $repo_name, using existing state" >&2
        fi

        # Lock down cloned repo as read-only state
        chmod -R a-w "$target_repo_dir" 2>/dev/null || true

        # Discover and stage individual skills containing SKILL.md
        skills_root="$target_repo_dir/skills"
        if [[ -d "$skills_root" ]]; then
          for skill_path in "$skills_root"/*; do
            if [[ -f "$skill_path/SKILL.md" ]]; then
              skill_name=$(basename "$skill_path")
              staged_link="$STAGED_DIR/$skill_name"

              if [[ -e "$staged_link" && ! -L "$staged_link" ]]; then
                echo "skipping unmanaged directory at $staged_link" >&2
                continue
              fi
              ln -sfnT "$skill_path" "$staged_link"
            fi
          done
        fi
      done

      # Materialize staged skills across all active agent configuration paths
      TARGET_AGENT_DIRS=(
        "${config.home.homeDirectory}/.codex/skills"
        "${config.xdg.configHome}/claude/skills"
        "${config.home.homeDirectory}/.claude/skills"
        "${config.xdg.configHome}/gemini/skills"
        "${config.home.homeDirectory}/.gemini/skills"
        "${config.xdg.configHome}/antigravity/skills"
        "${config.xdg.configHome}/antigravity-restricted/skills"
        "${config.xdg.configHome}/opencode/skills"
      )

      for target_dir in "''${TARGET_AGENT_DIRS[@]}"; do
        mkdir -p "$target_dir"
        if [[ -d "$STAGED_DIR" ]]; then
          for source in "$STAGED_DIR"/*; do
            [[ -f "$source/SKILL.md" ]] || continue
            skill_name=$(basename "$source")
            target_link="$target_dir/$skill_name"

            if [[ -e "$target_link" && ! -L "$target_link" ]]; then
              echo "preserving unmanaged skill directory $target_link" >&2
              continue
            fi
            ln -sfnT "$source" "$target_link"
          done
        fi
      done
    '';
  };
}
