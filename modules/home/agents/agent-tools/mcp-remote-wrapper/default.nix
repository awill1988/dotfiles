{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.modules.agents.agent-tools;

  mcp-remote-wrapper = pkgs.writeShellScriptBin "mcp-remote-wrapper" ''
    set -euo pipefail

    BASE_CONFIG_DIR="''${MCP_REMOTE_CONFIG_DIR:-$HOME/.mcp-auth}"
    mkdir -p "$BASE_CONFIG_DIR"

    MCP_REMOTE_VERSION="0.2.1"
    TARGET_DIR="$BASE_CONFIG_DIR/mcp-remote-$MCP_REMOTE_VERSION"
    mkdir -p "$TARGET_DIR"

    # Migrate tokens & client info from previous version directories if missing in target dir
    for prev_dir in $(ls -vd "$BASE_CONFIG_DIR"/mcp-remote-* 2>/dev/null | grep -v "mcp-remote-$MCP_REMOTE_VERSION$" || true); do
      if [ -d "$prev_dir" ]; then
        for f in "$prev_dir"/*_tokens.json "$prev_dir"/*_client_info.json; do
          if [ -f "$f" ]; then
            filename="$(basename "$f")"
            if [ ! -f "$TARGET_DIR/$filename" ]; then
              cp "$f" "$TARGET_DIR/$filename"
            fi
          fi
        done
      fi
    done

    exec ${pkgs.nodejs}/bin/npx -y mcp-remote@"$MCP_REMOTE_VERSION" "$@"
  '';
in
{
  options.modules.agents.agent-tools = {
    enableMcpRemoteWrapper = mkOption {
      type = types.bool;
      default = true;
      description = "Install mcp-remote-wrapper script for credential-preserving remote MCP server execution.";
    };
  };

  config = mkIf (cfg.enable && cfg.enableMcpRemoteWrapper) {
    home.packages = [ mcp-remote-wrapper ];
  };
}
