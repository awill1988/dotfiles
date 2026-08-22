# Vendors external agent skill bundles into the shared
# ~/.local/share/agent-skills directory that the claude and codex wrappers
# sync into their per-agent config dirs at launch (see sync_local_skills in
# modules/home/programs/{claude,codex}/default.nix). Source is a flake input,
# so builtins.readDir runs at eval time over a store path (no import-from-
# derivation) and the skill set tracks upstream automatically.
{ golang_skills_src }:
{ config, lib, ... }:
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
  };
}
