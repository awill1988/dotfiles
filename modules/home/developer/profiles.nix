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

  mergeNonNull =
    lhs: rhs:
    if isAttrs lhs && isAttrs rhs then
      lhs
      // (mapAttrs (
        name: rhsVal: if hasAttr name lhs then mergeNonNull lhs.${name} rhsVal else rhsVal
      ) rhs)
    else if rhs != null then
      rhs
    else
      lhs;

  # Recursive resolution helper merging baseline -> profile -> hostOverrides
  resolveProfile =
    p:
    let
      parent =
        if p.inherits != null && hasAttr p.inherits cfg.profiles then
          resolveProfile cfg.profiles.${p.inherits}
        else
          baseline;
      mergedWithParent = mergeNonNull parent p;
      hostOverride = cfg.hosts.${cfg.hostName}.profileOverrides.${p.name} or { };
    in
    mergeNonNull mergedWithParent hostOverride;

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
      active_profile=""

      # 1. Match folderOverrides (highest priority)
      ${concatMapStringsSep "\n" (overridePath: ''
        expanded_override="${builtins.replaceStrings [ "~" ] [ "$HOME" ] overridePath}"
        if [[ "$cwd" == "$expanded_override" || "$cwd" == "$expanded_override"/* ]]; then
          active_profile="${cfg.folderOverrides.${overridePath}.inherits or primaryProfile.name}"
        fi
      '') (attrNames cfg.folderOverrides)}

      # 2. Match pathPrefixes (directory match wins over environment defaults)
      if [ -z "$active_profile" ]; then
        ${concatMapStringsSep "\n" (p: ''
          ${concatMapStringsSep "\n" (prefix: ''
            expanded_prefix="${builtins.replaceStrings [ "~" ] [ "$HOME" ] prefix}"
            if [[ "$cwd" == "$expanded_prefix" || "$cwd" == "$expanded_prefix"/* ]]; then
              active_profile="${p.name}"
            fi
          '') p.pathPrefixes}
        '') resolvedProfiles}
      fi

      # 3. Fall back to environment variable or primary profile default
      if [ -z "$active_profile" ]; then
        active_profile="''${DEVELOPER_PROFILE:-${
          if primaryProfile != null then primaryProfile.name else "personal"
        }}"
      fi

      export DEVELOPER_PROFILE="$active_profile"

      ${concatMapStringsSep "\n" (p: ''
        if [ "$active_profile" = "${p.name}" ]; then
          CODE_AGENT="${p.agents.code}"
          export CODE_AGENT

          ${
            if p.agents.claude.configDir != null then
              ''
                CLAUDE_CONFIG_DIR="${builtins.replaceStrings [ "~" ] [ "$HOME" ] p.agents.claude.configDir}"
                export CLAUDE_CONFIG_DIR
              ''
            else
              ''
                CLAUDE_CONFIG_DIR="${config.xdg.configHome}/profiles/${p.name}/claude"
                export CLAUDE_CONFIG_DIR
              ''
          }

          ${
            if p.agents.gemini.configDir != null then
              ''
                GEMINI_CONFIG_DIR="${builtins.replaceStrings [ "~" ] [ "$HOME" ] p.agents.gemini.configDir}"
                export GEMINI_CONFIG_DIR
              ''
            else
              ''
                GEMINI_CONFIG_DIR="${config.xdg.configHome}/profiles/${p.name}/gemini"
                export GEMINI_CONFIG_DIR
              ''
          }

          ${
            if p.agents.codex.configDir != null then
              ''
                CODEX_CONFIG_DIR="${builtins.replaceStrings [ "~" ] [ "$HOME" ] p.agents.codex.configDir}"
                export CODEX_CONFIG_DIR
                CODEX_HOME="$CODEX_CONFIG_DIR"
                export CODEX_HOME
              ''
            else
              ''
                CODEX_CONFIG_DIR="${config.xdg.configHome}/profiles/${p.name}/codex"
                export CODEX_CONFIG_DIR
                CODEX_HOME="$CODEX_CONFIG_DIR"
                export CODEX_HOME
              ''
          }

          ${
            if p.agents.agy.configDir != null then
              ''
                AGY_CONFIG_DIR="${builtins.replaceStrings [ "~" ] [ "$HOME" ] p.agents.agy.configDir}"
                export AGY_CONFIG_DIR
              ''
            else
              ''
                AGY_CONFIG_DIR="${config.xdg.configHome}/profiles/${p.name}/antigravity"
                export AGY_CONFIG_DIR
              ''
          }

          ${optionalString (p.aws.profile != null) ''
            AWS_PROFILE="${p.aws.profile}"
            export AWS_PROFILE
          ''}
          ${optionalString (p.aws.region != null) ''
            AWS_REGION="${p.aws.region}"
            export AWS_REGION
          ''}
          ${optionalString (p.aws.roleArn != null) ''
            AWS_ROLE_ARN="${p.aws.roleArn}"
            export AWS_ROLE_ARN
          ''}
          ${optionalString (p.identity.email != null) ''
            GIT_AUTHOR_EMAIL="${p.identity.email}"
            export GIT_AUTHOR_EMAIL
          ''}
          ${optionalString (p.identity.email != null) ''
            GIT_COMMITTER_EMAIL="${p.identity.email}"
            export GIT_COMMITTER_EMAIL
          ''}
          ${concatMapStringsSep "\n" (k: ''
            ${k}="${p.env.${k}}"
            export ${k}
          '') (attrNames p.env)}
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
    programs.claude.enable = true;
    programs.gemini.enable = true;
    programs.agy.enable = true;
    developer.profileRouter = profile-router;
    developer.resolvedProfiles = listToAttrs (map (p: nameValuePair p.name p) resolvedProfiles);
    home.packages = [ profile-router ];

    home.activation.ensureProfileDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      set -euo pipefail
      ${concatMapStringsSep "\n" (p: ''
        profile_dir="${config.xdg.configHome}/profiles/${p.name}"
        mkdir -p "$profile_dir/gemini" "$profile_dir/antigravity" "$profile_dir/git"

        ${
          if p.agents.claude.configDir != null then
            ''
              target_claude_dir="${builtins.replaceStrings [ "~" ] [ "$HOME" ] p.agents.claude.configDir}"
              mkdir -p "$target_claude_dir"
              if [ -d "$profile_dir/claude" ] && [ ! -L "$profile_dir/claude" ]; then
                rm -rf "$profile_dir/claude"
              fi
              ln -sfn "$target_claude_dir" "$profile_dir/claude"
              claude_dest_dir="$target_claude_dir"
            ''
          else
            ''
              if [ -L "$profile_dir/claude" ]; then
                rm -f "$profile_dir/claude"
              fi
              mkdir -p "$profile_dir/claude"
              claude_dest_dir="$profile_dir/claude"
            ''
        }

        ${
          if p.agents.codex.configDir != null then
            ''
              target_codex_dir="${builtins.replaceStrings [ "~" ] [ "$HOME" ] p.agents.codex.configDir}"
              mkdir -p "$target_codex_dir"
              if [ -d "$profile_dir/codex" ] && [ ! -L "$profile_dir/codex" ]; then
                rm -rf "$profile_dir/codex"
              fi
              ln -sfn "$target_codex_dir" "$profile_dir/codex"
              codex_dest_dir="$target_codex_dir"
            ''
          else
            ''
              if [ -L "$profile_dir/codex" ]; then
                rm -f "$profile_dir/codex"
              fi
              mkdir -p "$profile_dir/codex"
              codex_dest_dir="$profile_dir/codex"
            ''
        }

        if [ ! -f "$codex_dest_dir/config.toml" ]; then
          install -m 600 "${./../agents/core/codex/config.toml}" "$codex_dest_dir/config.toml"
        fi

        if [ ! -f "$claude_dest_dir/settings.json" ]; then
          install -m 600 "${mkClaudeSettings p}" "$claude_dest_dir/settings.json"
        fi

        if [ ! -f "$claude_dest_dir/.claude.json" ]; then
          install -m 600 "${mkClaudeUserConfig p}" "$claude_dest_dir/.claude.json"
        else
          ${pkgs.jq}/bin/jq -s '.[0] + {mcpServers: .[1].mcpServers}' \
            "$claude_dest_dir/.claude.json" "${mkClaudeUserConfig p}" > "$claude_dest_dir/.claude.json.tmp"
          chmod 600 "$claude_dest_dir/.claude.json.tmp"
          mv "$claude_dest_dir/.claude.json.tmp" "$claude_dest_dir/.claude.json"
        fi

        cat <<EOF > "$profile_dir/git/config"
        [user]
          ${optionalString (p.identity.fullName != null) ''name = "${p.identity.fullName}"''}
          ${optionalString (p.identity.email != null) ''email = "${p.identity.email}"''}
          ${optionalString (p.identity.signingKey != null) ''signingKey = "${p.identity.signingKey}"''}
        ${optionalString (p.identity.signingKey != null && p.identity.signingFormat != null) ''
          [commit]
            gpgSign = true
          [gpg]
            format = "${p.identity.signingFormat}"
        ''}
        ${optionalString (p.identity.signingFormat == "ssh") ''
          [gpg "ssh"]
            program = "git-ssh-sign"
            allowedSignersFile = "${config.xdg.configHome}/git/allowed_signers"
        ''}
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
        export CODEX_HOME="$CODEX_CONFIG_DIR"
        export AGY_CONFIG_DIR="$HOME/.config/profiles/$profile/antigravity"
        echo "activated developer profile: $profile"
      }
    '';
  };
}
