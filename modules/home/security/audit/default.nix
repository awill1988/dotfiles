{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.modules.security.audit;
in
{
  options.modules.security.audit = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable auditing and secret scanning tools.";
    };
    enableTrufflehog = mkOption {
      type = types.bool;
      default = true;
      description = "Install trufflehog secret scanner.";
    };
    enableNiro = mkOption {
      type = types.bool;
      default = true;
      description = "Install Niro CLI tool.";
    };
  };

  config = mkIf cfg.enable {
    home.packages =
      (optional cfg.enableTrufflehog pkgs.trufflehog) ++ (optional cfg.enableNiro pkgs.niro);

    home.sessionVariables = mkIf cfg.enableNiro {
      NIRO_STATE_ROOT = mkDefault "${config.xdg.configHome}/niro";
      NIRO_HARNESS = mkDefault "harness2";
      NIRO_OFFLINE = mkDefault "1";
      NIRO_PROVIDER = mkDefault "openai";
      OPENAI_API_BASE = mkDefault "http://127.0.0.1:11434/v1";
      OPENAI_API_KEY = mkDefault "ollama";
      NIRO_MODEL = mkDefault "qwen2.5-coder:32b";
      HARNESS2_SOLVER_MODEL = mkDefault "ollama/qwen2.5-coder:32b";
      HARNESS2_IMPROVER_MODEL = mkDefault "ollama/qwen2.5-coder:32b";
      HARNESS2_JUDGE_MODEL = mkDefault "ollama/qwen2.5-coder:32b";
      HARNESS2_JUDGE_BASE_URL = mkDefault "http://127.0.0.1:11434/v1";
      HARNESS2_JUDGE_API_KEY = mkDefault "ollama";
    };

    home.shellAliases = mkIf cfg.enableNiro {
      niro = "NIRO_HARNESS=harness2 NIRO_OFFLINE=1 niro";
    };
  };
}
