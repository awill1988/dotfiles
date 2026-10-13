{ prompts_src }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.modules.agents.agent-prompts;
  profiles = lib.attrValues config.developer.resolvedProfiles;
  config_home = config.xdg.configHome;
  canonical = "${config_home}/agent-prompts/AGENTS.md";
  expand_home =
    path:
    if lib.hasPrefix "~/" path then config.home.homeDirectory + lib.removePrefix "~" path else path;
  clients = {
    claude = {
      directory = "claude";
      filenames = [ "CLAUDE.md" ];
    };
    codex = {
      directory = "codex";
      filenames = [ "AGENTS.override.md" ];
    };
    agy = {
      directory = "antigravity";
      filenames = [ "AGY.md" ];
    };
    opencode = {
      directory = "opencode";
      filenames = [
        "OPENCODE.md"
        "AGENTS.md"
      ];
    };
  };
  enabled = name: config.programs.${name}.enable;
  profile_aliases = lib.concatMap (
    profile:
    lib.concatMap (
      name:
      let
        client = clients.${name};
        settings = profile.agents.${name};
        directory =
          if settings.configDir != null then
            expand_home settings.configDir
          else
            "${config_home}/profiles/${profile.name}/${client.directory}";
      in
      lib.optionals (enabled name && settings.enable == true) (
        map (filename: "${directory}/${filename}") client.filenames
      )
    ) (builtins.attrNames clients)
  ) profiles;
  global_files =
    lib.optionalAttrs (enabled "codex") {
      "codex/AGENTS.override.md" = {
        source = cfg.instructionsSource;
        force = true;
      };
    }
    // lib.optionalAttrs (enabled "agy") {
      "antigravity/AGY.md".source = cfg.instructionsSource;
      "antigravity-restricted/AGY.md".source = cfg.instructionsSource;
    };
  manifest = {
    source = toString cfg.instructionsSource;
    files = [ canonical ] ++ map (p: "${config_home}/profiles/${p.name}/AGENTS.md") profiles;
    aliases = lib.genAttrs (lib.unique profile_aliases) (_: canonical);
    managed_files = map (name: "${config_home}/${name}") (builtins.attrNames global_files);
    backup_dir = "${config.xdg.stateHome}/agent-prompts/backups";
  };
  manifest_file = pkgs.writeText "agent-prompts-manifest.json" (builtins.toJSON manifest);
in
{
  options.modules.agents.agent-prompts = {
    enable = lib.mkEnableOption "shared instructions from the pinned prompts repository" // {
      default = true;
    };
    instructionsSource = lib.mkOption {
      type = lib.types.path;
      default = "${prompts_src}/instructions/AGENTS.md";
      description = "Canonical shared instructions used by every client and profile.";
    };
    installationManifest = lib.mkOption {
      type = lib.types.attrs;
      internal = true;
      readOnly = true;
      default = if cfg.enable then manifest else { };
      description = "Resolved installation contract for activation and verification.";
    };
  };

  config = lib.mkIf cfg.enable {
    xdg.configFile = global_files;
    home.activation.ensureAgentPrompts =
      lib.hm.dag.entryAfter [ "writeBoundary" "linkGeneration" "ensureProfileDirs" ]
        ''
          run ${pkgs.python3}/bin/python ${./install_prompts.py} ${manifest_file}
        '';
  };
}
