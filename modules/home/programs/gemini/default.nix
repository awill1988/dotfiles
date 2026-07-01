{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.gemini;
  gemini_home = "${config.xdg.configHome}/gemini";
  settings_source = ./settings.json;
  gemini_instructions_source = ./GEMINI.md;
  aws_readonly_policy = ''
    [[rule]]
    mcpName = "contextforge"
    toolName = [
      "aws-call-aws",
      "aws-suggest-aws-commands",
      "aws-docs-read-documentation",
      "aws-docs-read-sections",
      "aws-docs-search-documentation",
      "aws-docs-recommend",
    ]
    decision = "allow"
    priority = 900

    [[rule]]
    toolName = "run_shell_command"
    commandPrefix = [
      "aws configure list",
      "aws sts get-caller-identity",
      "aws s3 ls",
      "aws ec2 describe-",
      "aws iam get-",
      "aws iam list-",
      "aws lambda get-",
      "aws lambda list-",
      "aws logs describe-",
      "aws logs get-",
      "aws rds describe-",
      "aws ssm describe-",
      "aws ssm get-",
      "aws sts get-",
    ]
    decision = "allow"
    priority = 850

    [[rule]]
    toolName = "run_shell_command"
    commandPrefix = "aws"
    decision = "deny"
    priority = 840
    denyMessage = "aws shell commands must use an explicit read-only allowlist entry or the read-only aws mcp server"

    [[rule]]
    toolName = "run_shell_command"
    commandPrefix = [
      "cat",
      "env",
      "file",
      "find",
      "grep",
      "head",
      "ls",
      "pwd",
      "rg",
      "tail",
      "wc",
      "which",
      "whoami",
    ]
    decision = "allow"
    priority = 800
  '';
  gemini_wrapper = pkgs.writeShellScriptBin "gemini" ''
    set -euo pipefail

    export GEMINI_TELEMETRY_ENABLED=false
    export GEMINI_TELEMETRY_TRACES_ENABLED=false
    export GEMINI_TELEMETRY_LOG_PROMPTS=false
    export GEMINI_ANALYTICS_DISABLED=true
    export OTEL_SDK_DISABLED=true
    export DO_NOT_TRACK=1

    exec "${cfg.package}/bin/gemini" --policy "${gemini_home}/policies/aws-readonly.toml" "$@"
  '';
in
{
  options.programs.gemini = {
    enable = lib.mkEnableOption "Gemini CLI";
    package = lib.mkOption {
      type = lib.types.package;
      default =
        if config.modules.dev.node.enable then
          pkgs.gemini.override {
            nodejs = config.modules.dev.node.package;
          }
        else
          pkgs.gemini;
      description = "Gemini CLI package to install.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ gemini_wrapper ];
    home.sessionVariables.GEMINI_CLI_SYSTEM_SETTINGS_PATH = lib.mkDefault "${gemini_home}/settings.json";

    xdg.configFile."gemini/settings.json" = {
      source = settings_source;
      force = true;
    };
    xdg.configFile."gemini/GEMINI.md" = {
      source = gemini_instructions_source;
      force = true;
    };
    xdg.configFile."gemini/policies/aws-readonly.toml" = {
      text = aws_readonly_policy;
      force = true;
    };

    # Backwards compatibility for tools that still look under ~/.gemini
    home.file.".gemini/settings.json".source = settings_source;
    home.file.".gemini/GEMINI.md".source = gemini_instructions_source;
  };
}
