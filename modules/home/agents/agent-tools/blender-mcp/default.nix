{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.blender-mcp;

  # Keep the MCP transport available even when Blender is not running. The
  # upstream server defers connection failures to tool calls, allowing clients
  # to complete their initialize handshake during startup.
  wrapper = pkgs.writeShellScriptBin "blender-mcp" ''
    set -euo pipefail

    export BLENDER_HOST="${cfg.blenderHost}"
    export BLENDER_PORT="${toString cfg.blenderPort}"
    ${lib.optionalString cfg.disableTelemetry ''export DISABLE_TELEMETRY="true"''}

    exec ${cfg.package}/bin/blender-mcp-unwrapped "$@"
  '';

  # blender's user addons dir differs by platform
  addons_root =
    if pkgs.stdenv.isDarwin then "Library/Application Support/Blender" else ".config/blender";
in
{
  options.programs.blender-mcp = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable blender-mcp standalone stdio MCP server";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.blender-mcp;
      description = "blender-mcp package providing blender-mcp-unwrapped.";
    };

    blenderHost = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "host the blender addon listens on";
    };

    blenderPort = lib.mkOption {
      type = lib.types.port;
      default = 9876;
      description = "tcp port the blender addon listens on";
    };

    disableTelemetry = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "set DISABLE_TELEMETRY=true for the upstream server";
    };

    blenderAddonVersions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "4.2"
        "4.3"
      ];
      description = ''
        blender major.minor versions to install the blender-mcp addon into.
        empty list disables symlinking (user manages the addon manually).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      wrapper
      cfg.package
    ];

    home.file = lib.listToAttrs (
      map (ver: {
        name = "${addons_root}/${ver}/scripts/addons/blender_mcp_addon.py";
        value = {
          source = cfg.package.addon;
        };
      }) cfg.blenderAddonVersions
    );
  };
}
