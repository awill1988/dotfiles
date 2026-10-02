{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.programs.continuous-agent;

  agent_loop_pkg = pkgs.writeShellApplication {
    name = "agent-loop";
    runtimeInputs = with pkgs; [
      python3
      coreutils
      git
      pkgs.worktrunk
    ];
    text = ''
      exec python3 "${./agent_loop.py}" "$@"
    '';
  };
in
{
  options.programs.continuous-agent = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable continuous agent loop orchestrator with profile switching";
    };
    defaultOrder = mkOption {
      type = types.listOf types.str;
      default = [
        "claude"
        "codex"
        "agy"
      ];
      description = "Default model failover sequence for personal profiles";
    };
    maxIterations = mkOption {
      type = types.int;
      default = 20;
      description = "Default maximum iterations for autonomous loops";
    };
    timeoutSeconds = mkOption {
      type = types.int;
      default = 600;
      description = "Turn timeout in seconds";
    };
    worktreeIsolation = mkOption {
      type = types.bool;
      default = true;
      description = "Isolate continuous loops into dedicated Git worktrees via worktrunk";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      agent_loop_pkg
      pkgs.worktrunk
    ];

    programs.zsh.shellAliases = {
      loop = "agent-loop";
      aloop = "agent-loop";
    };
  };
}
