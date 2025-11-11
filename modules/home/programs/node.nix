{ lib, config, pkgs, ... }:

with lib;
let nodePkg = pkgs.nodejs_latest;
in {
  options.modules.dev.node = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Node.js toolchain";
    };
    xdg.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Place npm cache/config under XDG directories.";
    };
  };

  config = mkIf config.modules.dev.node.enable {
    # Provide node & an npx shim using npm exec (corepack preferred now).
    home.packages = [ nodePkg ];
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
