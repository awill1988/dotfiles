{ pkgs, hold_up_src }:
let
  inherit (pkgs) lib;
  module = import ./default.nix { inherit hold_up_src; };
  profile = name: directory: {
    inherit name;
    isPrimary = name == "personal";
    agents = lib.genAttrs [ "claude" "codex" ] (_: {
      enable = true;
      configDir = directory;
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
            launchd.agents = lib.mkOption {
              type = lib.types.attrs;
              default = { };
            };
            systemd.user.services = lib.mkOption {
              type = lib.types.attrs;
              default = { };
            };
            xdg.configHome = lib.mkOption { default = "/home/example/.config"; };
            xdg.cacheHome = lib.mkOption { default = "/home/example/.cache"; };
            xdg.configFile = lib.mkOption {
              type = lib.types.attrs;
              default = { };
            };
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
          activation = config.home.activation.reconcileHoldUpHooks.data;
          enabled = config.programs.hold-up.enable;
          files = builtins.attrNames config.home.file;
          feeds =
            if config.programs.hold-up.enable then
              config.xdg.configFile."hold-up/status_feeds.json".source
            else
              null;
        }
      )
      {
        enabled = { };
        disabled.programs.hold-up.enable = false;
        legacy_disabled.programs.claude-provider-status.enable = false;
        custom.programs.hold-up.customFeeds = {
          feeds = [ ];
          cache_ttl_seconds = 42;
        };
        legacy_custom.programs.claude-provider-status.customFeeds = {
          feeds = [ ];
        };
        no_codex.programs.codex.enable = false;
        no_profiles.developer.resolvedProfiles = lib.mkForce { };
      };
in
pkgs.runCommand "hold-up-contracts"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    cases_file = pkgs.writeText "hold-up-module-cases.json" (builtins.toJSON cases);
  }
  ''
    export PYTHONDONTWRITEBYTECODE=1
    python3 -m unittest discover -s ${hold_up_src}/tests -p 'test_*.py' -v
    python3 -m unittest discover -s ${./.} -p 'test_reconcile_hooks.py' -v
    python3 ${./verify_module.py} "$cases_file"
    touch "$out"
  ''
