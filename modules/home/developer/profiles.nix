{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.developer;
  baseline = cfg.baseline;
  profilesList = attrValues cfg.profiles;

  primaries = filter (p: p.isPrimary) profilesList;
  primaryProfile =
    if primaries != [ ] then
      head primaries
    else if profilesList != [ ] then
      head profilesList
    else
      null;

  # Recursive resolution helper merging baseline -> profile -> hostOverrides
  resolveProfile =
    p:
    let
      parent =
        if p.inherits != null && hasAttr p.inherits cfg.profiles then
          resolveProfile cfg.profiles.${p.inherits}
        else
          baseline;
      mergedWithParent = recursiveUpdate parent p;
      hostOverride = cfg.hosts.${cfg.hostName}.profileOverrides.${p.name} or { };
    in
    recursiveUpdate mergedWithParent hostOverride;

  # List of fully resolved profiles
  resolvedProfiles = map resolveProfile profilesList;

  mkClaudeUserConfig =
    profile:
    pkgs.writeText "claude-user-config-${profile.name}.json" (
      builtins.toJSON {
        mcpServers = profile.agents.claude.mcpServers;
      }
    );

  mkClaudeSettings =
    profile:
    pkgs.writeText "claude-settings-${profile.name}.json" (
      builtins.toJSON {
        env = {
          CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
          DISABLE_NON_ESSENTIAL_MODEL_CALLS = "1";
          CLAUDE_CODE_MAX_OUTPUT_TOKENS = "128000";
          ENABLE_CLAUDEAI_MCP_SERVERS = "false";
        };
        effortLevel = profile.agents.claude.effortLevel;
        telemetry = {
          enabled = false;
          analytics = false;
          statsig.enabled = false;
        };
        feedback = {
          prompt = false;
          surveys.enabled = false;
        };
        feedbackSurveyRate = 0;
        attribution = {
          commit = "";
          pr = "";
          sessionUrl = false;
        };
      }
    );

  # Helper script to dynamically route tools based on CWD
  profile-router = pkgs.writeShellApplication {
    name = "profile-router";
    runtimeInputs = with pkgs; [
      coreutils
      jq
    ];
    text = ''
      cwd="$(pwd -P)"
      active_profile="${if primaryProfile != null then primaryProfile.name else "personal"}"

      ${concatMapStringsSep "\n" (p: ''
        ${concatMapStringsSep "\n" (prefix: ''
          expanded_prefix="$(eval echo "${prefix}")"
          if [[ "$cwd" == "$expanded_prefix"* ]]; then
            active_profile="${p.name}"
          fi
        '') p.pathPrefixes}
      '') resolvedProfiles}

      ${concatMapStringsSep "\n" (overridePath: ''
        expanded_override="$(eval echo "${overridePath}")"
        if [[ "$cwd" == "$expanded_override"* ]]; then
          active_profile="${cfg.folderOverrides.${overridePath}.inherits or primaryProfile.name}"
        fi
      '') (attrNames cfg.folderOverrides)}

      if [ -n "''${DEVELOPER_PROFILE:-}" ]; then
        active_profile="$DEVELOPER_PROFILE"
      fi

      export DEVELOPER_PROFILE="$active_profile"
      export CLAUDE_CONFIG_DIR="${config.xdg.configHome}/profiles/$active_profile/claude"
      export GEMINI_CONFIG_DIR="${config.xdg.configHome}/profiles/$active_profile/gemini"
      export CODEX_CONFIG_DIR="${config.xdg.configHome}/profiles/$active_profile/codex"
      export AGY_CONFIG_DIR="${config.xdg.configHome}/profiles/$active_profile/antigravity"

      ${concatMapStringsSep "\n" (p: ''
        if [ "$active_profile" = "${p.name}" ]; then
          ${optionalString (p.aws.profile != null) ''export AWS_PROFILE="${p.aws.profile}"''}
          ${optionalString (p.aws.region != null) ''export AWS_REGION="${p.aws.region}"''}
          ${optionalString (p.aws.roleArn != null) ''export AWS_ROLE_ARN="${p.aws.roleArn}"''}
          ${optionalString (p.identity.email != null) ''export GIT_AUTHOR_EMAIL="${p.identity.email}"''}
          ${optionalString (p.identity.email != null) ''export GIT_COMMITTER_EMAIL="${p.identity.email}"''}
          ${concatMapStringsSep "\n" (k: "export ${k}=\"${p.env.${k}}\"") (attrNames p.env)}
        fi
      '') resolvedProfiles}

      cmd="''${1:-}"
      if [ -n "$cmd" ]; then
        shift
        exec "$cmd" "$@"
      fi
    '';
  };
in
{
  imports = [ ../../developer/profiles.nix ];

  config = mkIf (cfg.profiles != { }) {
    home.packages = [ profile-router ];

    home.activation.ensureProfileDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      set -euo pipefail
      ${concatMapStringsSep "\n" (p: ''
        profile_dir="${config.xdg.configHome}/profiles/${p.name}"
        mkdir -p "$profile_dir/claude" "$profile_dir/gemini" "$profile_dir/codex" "$profile_dir/antigravity" "$profile_dir/git"

        if [ ! -f "$profile_dir/claude/settings.json" ]; then
          install -m 600 "${mkClaudeSettings p}" "$profile_dir/claude/settings.json"
        fi

        if [ ! -f "$profile_dir/claude/.claude.json" ]; then
          install -m 600 "${mkClaudeUserConfig p}" "$profile_dir/claude/.claude.json"
        else
          ${pkgs.jq}/bin/jq -s '.[0] + {mcpServers: .[1].mcpServers}' \
            "$profile_dir/claude/.claude.json" "${mkClaudeUserConfig p}" > "$profile_dir/claude/.claude.json.tmp"
          chmod 600 "$profile_dir/claude/.claude.json.tmp"
          mv "$profile_dir/claude/.claude.json.tmp" "$profile_dir/claude/.claude.json"
        fi

        cat <<'EOF' > "$profile_dir/git/config"
        [user]
          ${optionalString (p.identity.fullName != null) ''name = "${p.identity.fullName}"''}
          ${optionalString (p.identity.email != null) ''email = "${p.identity.email}"''}
          ${optionalString (p.identity.signingKey != null) ''signingKey = "${p.identity.signingKey}"''}
        EOF
      '') resolvedProfiles}
    '';

    xdg.configFile."direnv/direnvrc".text = ''
      use_profile() {
        local profile="$1"
        export DEVELOPER_PROFILE="$profile"
        export CLAUDE_CONFIG_DIR="$HOME/.config/profiles/$profile/claude"
        export GEMINI_CONFIG_DIR="$HOME/.config/profiles/$profile/gemini"
        export CODEX_CONFIG_DIR="$HOME/.config/profiles/$profile/codex"
        export AGY_CONFIG_DIR="$HOME/.config/profiles/$profile/antigravity"
        echo "activated developer profile: $profile"
      }
    '';
  };
}
