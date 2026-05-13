{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.drive-mcp;

  bridge_py = pkgs.writeText "drive-mcp-bridge.py" (builtins.readFile ./scripts/bridge.py);

  # stdio<->http mcp bridge for drivemcp.googleapis.com. uses native oauth
  # (installed-app flow) against a user-owned google cloud oauth client.
  # account switching: `drive-account login`, `drive-account use <email>`.
  bridge = pkgs.writeShellScriptBin "drive-mcp-bridge" ''
    set -euo pipefail
    exec ${cfg.pythonPackage}/bin/python3 ${bridge_py} bridge "$@"
  '';

  account = pkgs.writeShellScriptBin "drive-account" ''
    set -euo pipefail
    exec ${cfg.pythonPackage}/bin/python3 ${bridge_py} "$@"
  '';
in
{
  options.programs.drive-mcp = {
    enable = lib.mkEnableOption "drive-mcp stdio bridge for Google Drive MCP";

    pythonPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.python3;
      description = "python interpreter used to run the bridge.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      bridge
      account
    ];
  };
}
