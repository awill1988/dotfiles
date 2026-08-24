{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.modules.agents.agent-tools;
in
{
  imports = [
    ./contextforge
    ./blender-mcp
    ./drive-mcp
    ./mcp-remote-wrapper
  ];

  options.modules.agents.agent-tools = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable agent MCP tools, sidecars, and gateway infrastructure.";
    };
    enableDrawioMcp = mkOption {
      type = types.bool;
      default = true;
      description = "Install drawio-mcp tool.";
    };
    enableFivetranMcp = mkOption {
      type = types.bool;
      default = true;
      description = "Install fivetran-mcp-server tool.";
    };
    enableGithubMcp = mkOption {
      type = types.bool;
      default = true;
      description = "Install github-mcp-server tool.";
    };
  };

  config = mkIf cfg.enable {
    programs.contextforge.enable = true;
    programs.blender-mcp = {
      enable = true;
      blenderAddonVersions = [ ];
    };
    programs.drive-mcp.enable = true;

    home.packages =
      (optional cfg.enableDrawioMcp pkgs.drawio-mcp)
      ++ (optional cfg.enableFivetranMcp pkgs.fivetran-mcp-server)
      ++ (optional cfg.enableGithubMcp pkgs.github-mcp-server);
  };
}
