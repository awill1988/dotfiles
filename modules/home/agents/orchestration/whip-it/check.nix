{ pkgs, whip_it_src }:
let
  inherit (pkgs) lib;
  module = import ./default.nix { inherit whip_it_src; };
  profile = name: directory: {
    inherit name;
    isPrimary = name == "personal";
    agents = {
      claude = {
        enable = true;
        configDir = if directory == null then null else "${directory}/claude";
      };
      codex = {
        enable = true;
        configDir = if directory == null then null else "${directory}/codex";
      };
      agy = {
        enable = true;
        configDir = if directory == null then null else "${directory}/agy";
      };
    };
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
            home.packages = lib.mkOption {
              type = lib.types.listOf lib.types.package;
              default = [ ];
            };
            home.file = lib.mkOption {
              type = lib.types.attrs;
              default = { };
            };
            home.activation = lib.mkOption {
              type = lib.types.attrs;
              default = { };
            };
            xdg.configHome = lib.mkOption { default = "/home/example/.config"; };
            xdg.cacheHome = lib.mkOption { default = "/home/example/.cache"; };
            developer.resolvedProfiles = lib.mkOption {
              default = {
                personal = profile "personal" null;
                work = lib.recursiveUpdate (profile "work" null) { agents.codex.enable = false; };
                restricted = lib.recursiveUpdate (profile "restricted" null) { agents.codex.enable = false; };
                custom = profile "custom" "~/custom-client";
              };
            };
            programs.claude.enable = lib.mkOption { default = true; };
            programs.codex.enable = lib.mkOption { default = true; };
            programs.agy.enable = lib.mkOption { default = true; };
            warnings = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
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
          activation = config.home.activation.reconcileWhipItHooks.data;
          enabled = config.programs.whip-it.enable;
          mode = config.programs.whip-it.mode;
          defaultMaxSubagents = config.programs.whip-it.defaultMaxSubagents;
          autoClamp = config.programs.whip-it.autoClamp;
        }
      )
      {
        enabled = { };
        disabled.programs.whip-it.enable = false;
        custom = {
          programs.whip-it.mode = "advisory";
          programs.whip-it.defaultMaxSubagents = 2;
          programs.whip-it.autoClamp = true;
        };
      };
in
pkgs.runCommand "whip-it-contracts"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    cases_file = pkgs.writeText "whip-it-module-cases.json" (builtins.toJSON cases);
  }
  ''
    python3 ${./verify_module.py} "$cases_file"
    touch "$out"
  ''
