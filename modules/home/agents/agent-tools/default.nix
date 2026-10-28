{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.modules.agents.agent-tools;

  # snowflake mcp service config (enables query_manager for sql execution)
  # command: true allows ALTER SESSION and EXPLAIN; describe/show allow schema inspection
  snowflake_mcp_config = pkgs.writeText "snowflake-mcp-config.yaml" ''
    sql_statement_permissions:
      - select: true
      - describe: true
      - show: true
      - command: true
    other_services:
      query_manager: true
  '';
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
    enableHarness2 = mkOption {
      type = types.bool;
      default = true;
      description = "Install harness2 recursive agent harnessing CLI tools.";
    };
  };

  config = mkIf cfg.enable {
    programs.contextforge.enable = true;
    programs.blender-mcp = {
      enable = true;
      blenderAddonVersions = [ ];
    };
    programs.drive-mcp.enable = true;

    xdg.configFile."mcp/snowflake-mcp-config.yaml" = {
      source = snowflake_mcp_config;
      force = true;
    };

    home.packages =
      (optional cfg.enableDrawioMcp pkgs.drawio-mcp)
      ++ (optional cfg.enableFivetranMcp pkgs.fivetran-mcp-server)
      ++ (optional cfg.enableGithubMcp pkgs.github-mcp-server)
      ++ (optional cfg.enableHarness2 pkgs.harness2);
  };
}
