{ pkgs, prompts_src }:
let
  inherit (pkgs) lib;
  module = import ./default.nix { inherit prompts_src; };
  profile = name: {
    inherit name;
    agents = lib.genAttrs [ "claude" "codex" "agy" "opencode" ] (_: {
      enable = true;
      configDir = null;
    });
  };
  evaluate =
    settings:
    lib.evalModules {
      specialArgs = {
        inherit pkgs;
        lib = lib // {
          hm.dag.entryAfter = after: data: { inherit after data; };
        };
      };
      modules = [
        {
          options = {
            home.homeDirectory = lib.mkOption { default = "/home/example"; };
            home.activation = lib.mkOption {
              type = lib.types.attrs;
              default = { };
            };
            xdg.configHome = lib.mkOption { default = "/home/example/.config"; };
            xdg.stateHome = lib.mkOption { default = "/home/example/.local/state"; };
            xdg.configFile = lib.mkOption {
              type = lib.types.attrs;
              default = { };
            };
            programs = lib.genAttrs [ "claude" "codex" "agy" "opencode" ] (_: {
              enable = lib.mkOption { default = true; };
            });
            developer.resolvedProfiles = lib.mkOption {
              default = {
                personal = profile "personal";
                work = lib.recursiveUpdate (profile "work") { agents.codex.enable = false; };
                custom = lib.recursiveUpdate (profile "custom") {
                  agents.agy.configDir = "~/custom agy";
                  agents.claude.configDir = "~/custom claude";
                  agents.codex.configDir = "~/custom codex";
                  agents.opencode.configDir = "~/custom opencode";
                };
              };
            };
          };
        }
        module
        settings
      ];
    };
  cases =
    lib.mapAttrs
      (
        _: settings:
        let
          config = (evaluate settings).config;
        in
        {
          manifest = config.modules.agents.agent-prompts.installationManifest;
          activation = config.home.activation;
          global_files = config.xdg.configFile;
        }
      )
      {
        enabled = { };
        disabled.modules.agents.agent-prompts.enable = false;
        no_profiles.developer.resolvedProfiles = lib.mkForce { };
        no_codex.programs.codex.enable = false;
        source_override.modules.agents.agent-prompts.instructionsSource =
          pkgs.writeText "override.md" "override instructions\n";
      };
in
pkgs.runCommand "agent-prompts-contracts"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    cases_file = pkgs.writeText "agent-prompts-cases.json" (builtins.toJSON cases);
  }
  ''
    export PYTHONDONTWRITEBYTECODE=1
    python3 -m unittest discover -s ${./.} -p 'test_*.py' -v
    python3 ${./.}/verify_module.py "$cases_file"
    touch "$out"
  ''
