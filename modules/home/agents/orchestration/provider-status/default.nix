# Claude Provider Status Module
# Deploys upstream provider status monitoring engine and curated feeds
# from the pinned claude-provider-status flake input.
{ provider_status_src }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.claude-provider-status;
  engine_script = "${provider_status_src}/scripts/provider_status.py";
  default_config = "${provider_status_src}/config/status_feeds.json";
in
{
  options.programs.claude-provider-status = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Claude Code VCS and Cloud Provider Status monitoring.";
    };

    customFeeds = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Custom or override feed definitions merged into status_feeds.json.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Deploy executable engine to standard ~/.claude/hooks path
    home.file.".claude/hooks/vcs_status_hook.py" = {
      source = engine_script;
      executable = true;
    };

    # Deploy default or merged feeds config
    home.file.".claude/hooks/status_feeds.json" = {
      source =
        if cfg.customFeeds == { } then
          default_config
        else
          pkgs.runCommand "status_feeds.json" { } ''
            ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "${default_config}" "${pkgs.writeText "custom_feeds.json" (builtins.toJSON cfg.customFeeds)}" > $out
          '';
    };
  };
}
