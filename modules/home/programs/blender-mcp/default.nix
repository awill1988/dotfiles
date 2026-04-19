{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.blender-mcp;

  # fail-fast wrapper: probe blender's addon socket before exec'ing upstream.
  # mcp clients spawn this on demand per session; if blender is closed we exit
  # non-zero with a single json-rpc error frame on stderr so the agent surfaces
  # a clear "blender is not running" diagnostic instead of a hung connection.
  wrapper = pkgs.writeShellScriptBin "blender-mcp" ''
    set -euo pipefail

    export BLENDER_HOST="${cfg.blenderHost}"
    export BLENDER_PORT="${toString cfg.blenderPort}"
    ${lib.optionalString cfg.disableTelemetry ''export DISABLE_TELEMETRY="true"''}

    # 500ms tcp probe via bash /dev/tcp + coreutils timeout (no extra deps)
    if ! ${pkgs.coreutils}/bin/timeout 0.5 \
         ${pkgs.bash}/bin/bash -c "exec 3<>/dev/tcp/$BLENDER_HOST/$BLENDER_PORT" 2>/dev/null; then
      ${pkgs.coreutils}/bin/printf '%s\n' \
        '{"jsonrpc":"2.0","error":{"code":-32000,"message":"blender is not running or the blender-mcp addon is not enabled on '"$BLENDER_HOST:$BLENDER_PORT"'"}}' >&2
      exit 1
    fi

    exec ${cfg.package}/bin/blender-mcp-unwrapped "$@"
  '';

  # blender's user addons dir differs by platform
  addons_root =
    if pkgs.stdenv.isDarwin then "Library/Application Support/Blender" else ".config/blender";
in
{
  options.programs.blender-mcp = {
    enable = lib.mkEnableOption "blender-mcp standalone stdio MCP server";

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
