{ lib, config, pkgs, ... }:

with lib;
let
  cfg = config.modules.dev.node;
  nodePkg = cfg.package;
  pnpmPkg = pkgs.pnpm.override { nodejs = nodePkg; };
in {
  options.modules.dev.node = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Node.js toolchain";
    };
    package = mkOption {
      type = types.package;
      default = pkgs.nodejs_latest;
      description = "Node.js package to install and use for tooling.";
    };
    installBun = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to install bun alongside Node.js.";
    };
    xdg.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Place npm cache/config under XDG directories.";
    };
  };

  config = mkIf cfg.enable {
    # Provide node & an npx shim using npm exec (corepack preferred now).
    home.packages = [ nodePkg pnpmPkg pkgs.nodePackages.typescript ]
      ++ optional cfg.installBun pkgs.bun;
    home.sessionVariables = {
      NPM_CONFIG_USERCONFIG = "${config.xdg.configHome}/npm/config";
      NPM_CONFIG_CACHE = "${config.xdg.cacheHome}/npm";
      NPM_CONFIG_PREFIX = "${config.xdg.dataHome}/npm";
      NODE_REPL_HISTORY = "${config.xdg.cacheHome}/node/repl_history";
    };

    # Add npm global bin directory to PATH
    home.sessionPath = [ "${config.xdg.dataHome}/npm/bin" ];

    # Ensure tmp dir exists (lightweight) via activation script
    home.activation.ensureNpmTmpDir =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p ${config.xdg.cacheHome}/npm-tmp
      '';
  };
}
