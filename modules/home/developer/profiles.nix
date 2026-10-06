{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  permsLib = import ../../developer/permissions.nix { inherit lib; };
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
    let
      filteredMcpServers = lib.filterAttrs (
        name: _: !builtins.elem name profile.agents.claude.excludeMcpServers
      ) profile.agents.claude.mcpServers;
    in
    pkgs.writeText "claude-user-config-${profile.name}.json" (
      builtins.toJSON {
        mcpServers = filteredMcpServers;
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
          ENABLE_CLAUDEAI_MCP_SERVERS =
            if profile.agents.claude.enableOrganizationalMcp then "true" else "false";
          DISABLE_AUTOUPDATER = "1";
          DISABLE_UPDATES = "1";
          CLAUDE_CODE_DISABLE_AUTO_MEMORY = "1";
          CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY = "1";
          DISABLE_TELEMETRY = "1";
          DISABLE_GROWTHBOOK = "1";
          DISABLE_ERROR_REPORTING = "1";
          DO_NOT_TRACK = "1";
        };
        autoUpdaterStatus = "disabled";
        axScreenReader = false;
        prefersReducedMotion = true;
        spinnerTipsEnabled = false;
        autoMemoryEnabled = false;
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
        hooks = {
          SessionStart = [
            {
              matcher = "";
              hooks = [
                {
                  type = "command";
                  command = "python3 ${config.home.homeDirectory}/.claude/hooks/vcs_status_hook.py --event SessionStart";
                }
              ];
            }
          ];
          UserPromptSubmit = [
            {
              matcher = "";
              hooks = [
                {
                  type = "command";
                  command = "python3 ${config.home.homeDirectory}/.claude/hooks/vcs_status_hook.py --event UserPromptSubmit";
                }
              ];
            }
          ];
          PostToolUseFailure = [
            {
              matcher = "Bash";
              hooks = [
                {
                  type = "command";
                  command = "python3 ${config.home.homeDirectory}/.claude/hooks/vcs_status_hook.py --event PostToolUseFailure";
                }
              ];
            }
          ];
        };
        permissions = permsLib.toClaudePermissions profile.agents.permissions;
      }
    );

  mkAgySettings =
    profile:
    let
      peers =
        if profile.name == "work" then
          [
            {
              name = "claude-secondary";
              bin = "claude";
              enabled = true;
            }
          ]
        else
          [
            {
              name = "claude";
              bin = "claude";
              enabled = true;
            }
            {
              name = "gemini";
              bin = "gemini";
              enabled = true;
            }
            {
              name = "codex";
              bin = "codex";
              enabled = true;
            }
          ];
    in
    pkgs.writeText "agy-settings-${profile.name}.json" (
      builtins.toJSON (
        {
          agentEcosystem = {
            orchestrator = "agy";
            inherit peers;
          };
          privacy = {
            enableTelemetry = false;
            interactionCollection = "off";
            usageStatisticsEnabled = false;
            telemetry = false;
          };
          general = {
            enableAutoUpdate = false;
            enableNotifications = false;
          };
          ui = {
            enableAnimations = false;
            showSpinner = false;
          };
          permissions = permsLib.toAgyPermissions profile.agents.permissions;
          mcpServers = {
            contextforge = {
              command = "mcpgw-wrapper";
            };
          };
        }
        // profile.agents.agy.settings
      )
    );

  mkCodexRules =
    profile:
    pkgs.writeText "codex-rules-${profile.name}.rules" (
      permsLib.toCodexRules profile.agents.permissions
    );

  mkGeminiPolicy =
    profile:
    pkgs.writeText "gemini-policy-${profile.name}.toml" (
      permsLib.toGeminiPolicy profile.agents.permissions
    );

  mkGeminiSettings =
    profile:
    pkgs.writeText "gemini-settings-${profile.name}.json" (
      builtins.toJSON (
        {
          general = {
            enableAutoUpdate = false;
            enableNotifications = false;
            defaultApprovalMode = "default";
          };
          ui = {
            enableAnimations = false;
            showSpinner = false;
          };
          context = {
            fileName = [
              "AGENTS.md"
              "CLAUDE.md"
              "CONTEXT.md"
              "GEMINI.md"
            ];
          };
          telemetry = {
            enabled = false;
            target = "local";
            logPrompts = false;
          };
          privacy = {
            usageStatisticsEnabled = false;
          };
          security = {
            disableYoloMode = true;
            disableAlwaysAllow = true;
            enablePermanentToolApproval = false;
            autoAddToPolicyByDefault = false;
            environmentVariableRedaction = {
              enabled = true;
            };
          };
          tools = permsLib.toGeminiSettings profile.agents.permissions;
        }
        // profile.agents.gemini.settings
      )
    );

  mkOpencodeConfig =
    profile:
    pkgs.writeText "opencode-config-${profile.name}.json" (
      builtins.toJSON (
        {
          provider = profile.agents.opencode.provider;
          endpoint = profile.agents.opencode.localEndpoint;
          model = profile.agents.opencode.model;
          offlineOnly = (profile.agents.opencode.provider == "local");
          telemetry = {
            enabled = false;
          };
          general = {
            enableAutoUpdate = false;
          };
          ui = {
            enableAnimations = false;
          };
        }
        // (
          if profile.agents.opencode.apiKeyEnvVar != null then
            {
              providerOptions = {
                "${profile.agents.opencode.provider}" = {
                  apiKeyEnvVar = profile.agents.opencode.apiKeyEnvVar;
                };
              };
            }
          else
            { }
        )
        // profile.agents.opencode.config
      )
    );

  mkOpencodeProfileWrapper =
    p:
    let
      target_dir =
        if p.agents.opencode.configDir != null then
          builtins.replaceStrings [ "~" ] [ "$HOME" ] p.agents.opencode.configDir
        else
          "${config.xdg.configHome}/profiles/${p.name}/opencode";
    in
    pkgs.writeShellApplication {
      name = "opencode-${p.name}";
      runtimeInputs = with pkgs; [ coreutils ];
      text = ''
        export DEVELOPER_PROFILE="${p.name}"
        export OPENCODE_CONFIG_DIR="${target_dir}"
        export OPENCODE_CACHE_DIR="${target_dir}/cache"
        export OPENCODE_STATE_DIR="${target_dir}/state"
        export OPENCODE_TELEMETRY_ENABLED=false
        export OPENCODE_OFFLINE_ONLY=${if p.agents.opencode.provider == "local" then "true" else "false"}
        export OPENCODE_DISABLE_AUTO_UPDATE=1
        export OPENCODE_UI_ANIMATIONS_DISABLED=1
        export OTEL_SDK_DISABLED=true
        export DO_NOT_TRACK=1

        exec "${pkgs.opencode}/bin/opencode" "$@"
      '';
    };

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
            if p.agents.claude.enableOrganizationalMcp then
              ''
                ENABLE_CLAUDEAI_MCP_SERVERS="true"
                export ENABLE_CLAUDEAI_MCP_SERVERS
              ''
            else
              ''
                ENABLE_CLAUDEAI_MCP_SERVERS="false"
                export ENABLE_CLAUDEAI_MCP_SERVERS
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

          ${
            if p.agents.opencode.configDir != null then
              ''
                OPENCODE_CONFIG_DIR="${builtins.replaceStrings [ "~" ] [ "$HOME" ] p.agents.opencode.configDir}"
                export OPENCODE_CONFIG_DIR
                OPENCODE_CACHE_DIR="${
                  builtins.replaceStrings [ "~" ] [ "$HOME" ] p.agents.opencode.configDir
                }/cache"
                export OPENCODE_CACHE_DIR
                OPENCODE_STATE_DIR="${
                  builtins.replaceStrings [ "~" ] [ "$HOME" ] p.agents.opencode.configDir
                }/state"
                export OPENCODE_STATE_DIR
              ''
            else
              ''
                OPENCODE_CONFIG_DIR="${config.xdg.configHome}/profiles/${p.name}/opencode"
                export OPENCODE_CONFIG_DIR
                OPENCODE_CACHE_DIR="${config.xdg.cacheHome}/profiles/${p.name}/opencode"
                export OPENCODE_CACHE_DIR
                OPENCODE_STATE_DIR="${config.xdg.stateHome}/profiles/${p.name}/opencode"
                export OPENCODE_STATE_DIR
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

      case "''${1:-}" in
        --show-profile)
          echo "$active_profile"
          exit 0
          ;;
        --show-allowed-models)
          ${concatMapStringsSep "\n" (p: ''
            if [ "$active_profile" = "${p.name}" ]; then
              echo "${concatStringsSep "," p.agents.continuousLoop.allowedModels}"
              exit 0
            fi
          '') resolvedProfiles}
          echo "claude,codex,agy"
          exit 0
          ;;
        --show-env)
          echo "DEVELOPER_PROFILE=$DEVELOPER_PROFILE"
          echo "CODE_AGENT=''${CODE_AGENT:-}"
          echo "CLAUDE_CONFIG_DIR=''${CLAUDE_CONFIG_DIR:-}"
          echo "CODEX_CONFIG_DIR=''${CODEX_CONFIG_DIR:-}"
          echo "AGY_CONFIG_DIR=''${AGY_CONFIG_DIR:-}"
          echo "OPENCODE_CONFIG_DIR=''${OPENCODE_CONFIG_DIR:-}"
          exit 0
          ;;
      esac

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
    programs.opencode.enable = true;
    developer.profileRouter = profile-router;
    developer.resolvedProfiles = listToAttrs (map (p: nameValuePair p.name p) resolvedProfiles);
    home.packages = [ profile-router ] ++ (map mkOpencodeProfileWrapper resolvedProfiles);

    home.file = listToAttrs (
      concatMap (p: [
        {
          name = ".local/bin/opencode-${p.name}";
          value = {
            source = "${mkOpencodeProfileWrapper p}/bin/opencode-${p.name}";
            force = true;
          };
        }
      ]) resolvedProfiles
    );

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

        ${
          if p.agents.opencode.configDir != null then
            ''
              target_opencode_dir="${builtins.replaceStrings [ "~" ] [ "$HOME" ] p.agents.opencode.configDir}"
              mkdir -p "$target_opencode_dir"
              if [ -d "$profile_dir/opencode" ] && [ ! -L "$profile_dir/opencode" ]; then
                rm -rf "$profile_dir/opencode"
              fi
              ln -sfn "$target_opencode_dir" "$profile_dir/opencode"
              opencode_dest_dir="$target_opencode_dir"
            ''
          else
            ''
              if [ -L "$profile_dir/opencode" ]; then
                rm -f "$profile_dir/opencode"
              fi
              mkdir -p "$profile_dir/opencode"
              opencode_dest_dir="$profile_dir/opencode"
            ''
        }

        if [ -L "$opencode_dest_dir/opencode.json" ]; then
          rm -f "$opencode_dest_dir/opencode.json"
        fi
        if [ ! -f "$opencode_dest_dir/opencode.json" ]; then
          install -m 600 "${mkOpencodeConfig p}" "$opencode_dest_dir/opencode.json"
        else
          ${pkgs.jq}/bin/jq -s '.[0] * .[1]' \
            "$opencode_dest_dir/opencode.json" "${mkOpencodeConfig p}" > "$opencode_dest_dir/opencode.json.tmp"
          chmod 600 "$opencode_dest_dir/opencode.json.tmp"
          mv "$opencode_dest_dir/opencode.json.tmp" "$opencode_dest_dir/opencode.json"
        fi

        ${optionalString (p.name == primaryProfile.name) ''
          primary_opencode_dir="${config.xdg.configHome}/opencode"
          mkdir -p "$primary_opencode_dir"
          if [ -L "$primary_opencode_dir/opencode.json" ]; then
            rm -f "$primary_opencode_dir/opencode.json"
          fi
          if [ ! -f "$primary_opencode_dir/opencode.json" ]; then
            install -m 600 "${mkOpencodeConfig p}" "$primary_opencode_dir/opencode.json"
          else
            ${pkgs.jq}/bin/jq -s '.[0] * .[1]' \
              "$primary_opencode_dir/opencode.json" "${mkOpencodeConfig p}" > "$primary_opencode_dir/opencode.json.tmp"
            chmod 600 "$primary_opencode_dir/opencode.json.tmp"
            mv "$primary_opencode_dir/opencode.json.tmp" "$primary_opencode_dir/opencode.json"
          fi
        ''}

        if [ ! -f "$codex_dest_dir/config.toml" ]; then
          install -m 600 "${./../agents/core/codex/config.toml}" "$codex_dest_dir/config.toml"
        fi

        if [ ! -f "$claude_dest_dir/settings.json" ]; then
          install -m 600 "${mkClaudeSettings p}" "$claude_dest_dir/settings.json"
        else
          ${pkgs.jq}/bin/jq -s '
            .[0] as $target | .[1] as $source
            | (($target * $source) | del(.env.CLAUDE_AX_SCREEN_READER))
            | .permissions.allow = (((($target.permissions.allow // []) + ($source.permissions.allow // [])) | unique))
            | .permissions.deny = (((($target.permissions.deny // []) + ($source.permissions.deny // [])) | unique))
          ' "$claude_dest_dir/settings.json" "${mkClaudeSettings p}" > "$claude_dest_dir/settings.json.tmp"
          chmod 600 "$claude_dest_dir/settings.json.tmp"
          mv "$claude_dest_dir/settings.json.tmp" "$claude_dest_dir/settings.json"
        fi

        ${optionalString (p.name == primaryProfile.name) ''
          for base_claude_dir in "${config.xdg.configHome}/claude" "${config.home.homeDirectory}/.claude"; do
            mkdir -p "$base_claude_dir"
            if [ ! -f "$base_claude_dir/settings.json" ]; then
              install -m 600 "${mkClaudeSettings p}" "$base_claude_dir/settings.json"
            else
              ${pkgs.jq}/bin/jq -s '
                .[0] as $target | .[1] as $source
                | (($target * $source) | del(.env.CLAUDE_AX_SCREEN_READER))
                | .permissions.allow = (((($target.permissions.allow // []) + ($source.permissions.allow // [])) | unique))
                | .permissions.deny = (((($target.permissions.deny // []) + ($source.permissions.deny // [])) | unique))
              ' "$base_claude_dir/settings.json" "${mkClaudeSettings p}" > "$base_claude_dir/settings.json.tmp"
              chmod 600 "$base_claude_dir/settings.json.tmp"
              mv "$base_claude_dir/settings.json.tmp" "$base_claude_dir/settings.json"
            fi
          done
        ''}

        agy_dest_dir="$profile_dir/antigravity"
        mkdir -p "$agy_dest_dir"
        if [ ! -f "$agy_dest_dir/settings.json" ]; then
          install -m 600 "${mkAgySettings p}" "$agy_dest_dir/settings.json"
        else
          ${pkgs.jq}/bin/jq -s '
            .[0] as $target | .[1] as $source | ($target * $source)
            | .permissions.allow = (((($target.permissions.allow // []) + ($source.permissions.allow // [])) | unique))
            | .permissions.deny = (((($target.permissions.deny // []) + ($source.permissions.deny // [])) | unique))
            | .permissions.ask = (((($target.permissions.ask // []) + ($source.permissions.ask // [])) | unique))
          ' "$agy_dest_dir/settings.json" "${mkAgySettings p}" > "$agy_dest_dir/settings.json.tmp"
          chmod 600 "$agy_dest_dir/settings.json.tmp"
          mv "$agy_dest_dir/settings.json.tmp" "$agy_dest_dir/settings.json"
        fi

        ${optionalString (p.name == primaryProfile.name) ''
          for base_agy_dir in "${config.home.homeDirectory}/.gemini/antigravity-cli" "${config.xdg.configHome}/antigravity"; do
            mkdir -p "$base_agy_dir"
            if [ ! -f "$base_agy_dir/settings.json" ]; then
              install -m 600 "${mkAgySettings p}" "$base_agy_dir/settings.json"
            else
              ${pkgs.jq}/bin/jq -s '
                .[0] as $target | .[1] as $source | ($target * $source)
                | .permissions.allow = (((($target.permissions.allow // []) + ($source.permissions.allow // [])) | unique))
                | .permissions.deny = (((($target.permissions.deny // []) + ($source.permissions.deny // [])) | unique))
                | .permissions.ask = (((($target.permissions.ask // []) + ($source.permissions.ask // [])) | unique))
              ' "$base_agy_dir/settings.json" "${mkAgySettings p}" > "$base_agy_dir/settings.json.tmp"
              chmod 600 "$base_agy_dir/settings.json.tmp"
              mv "$base_agy_dir/settings.json.tmp" "$base_agy_dir/settings.json"
            fi
          done
        ''}

        ${optionalString (p.name == "work") ''
          restricted_agy_dir="${config.xdg.configHome}/antigravity-restricted"
          mkdir -p "$restricted_agy_dir"
          if [ ! -f "$restricted_agy_dir/settings.json" ]; then
            install -m 600 "${mkAgySettings p}" "$restricted_agy_dir/settings.json"
          else
            ${pkgs.jq}/bin/jq -s '
              .[0] as $target | .[1] as $source | ($target * $source)
              | .permissions.allow = (((($target.permissions.allow // []) + ($source.permissions.allow // [])) | unique))
              | .permissions.deny = (((($target.permissions.deny // []) + ($source.permissions.deny // [])) | unique))
              | .permissions.ask = (((($target.permissions.ask // []) + ($source.permissions.ask // [])) | unique))
            ' "$restricted_agy_dir/settings.json" "${mkAgySettings p}" > "$restricted_agy_dir/settings.json.tmp"
            chmod 600 "$restricted_agy_dir/settings.json.tmp"
            mv "$restricted_agy_dir/settings.json.tmp" "$restricted_agy_dir/settings.json"
          fi
        ''}

        mkdir -p "$codex_dest_dir/rules"
        install -m 600 "${mkCodexRules p}" "$codex_dest_dir/rules/default.rules"
        ${optionalString (p.name == primaryProfile.name) ''
          mkdir -p "${config.xdg.configHome}/codex/rules"
          install -m 600 "${mkCodexRules p}" "${config.xdg.configHome}/codex/rules/default.rules"
        ''}

        mkdir -p "$profile_dir/gemini/policies"
        install -m 600 "${mkGeminiPolicy p}" "$profile_dir/gemini/policies/permissions.toml"
        install -m 600 "${mkGeminiSettings p}" "$profile_dir/gemini/settings.json"
        ${optionalString (p.name == primaryProfile.name) ''
          mkdir -p "${config.xdg.configHome}/gemini/policies"
          install -m 600 "${mkGeminiPolicy p}" "${config.xdg.configHome}/gemini/policies/permissions.toml"
          install -m 600 "${mkGeminiSettings p}" "${config.xdg.configHome}/gemini/settings.json"
        ''}

        if [ ! -f "$claude_dest_dir/.claude.json" ]; then
          install -m 600 "${mkClaudeUserConfig p}" "$claude_dest_dir/.claude.json"
        else
          ${pkgs.jq}/bin/jq -s '.[0] + {mcpServers: (.[0].mcpServers // {}) + .[1].mcpServers}' \
            "$claude_dest_dir/.claude.json" "${mkClaudeUserConfig p}" > "$claude_dest_dir/.claude.json.tmp"
          chmod 600 "$claude_dest_dir/.claude.json.tmp"
          mv "$claude_dest_dir/.claude.json.tmp" "$claude_dest_dir/.claude.json"
        fi

        ${optionalString (p.name == primaryProfile.name) ''
          for primary_claude_base in "${config.xdg.configHome}/claude" "${config.home.homeDirectory}"; do
            mkdir -p "$primary_claude_base"
            if [ ! -f "$primary_claude_base/.claude.json" ]; then
              install -m 600 "${mkClaudeUserConfig p}" "$primary_claude_base/.claude.json"
            else
              ${pkgs.jq}/bin/jq -s '.[0] + {mcpServers: (.[0].mcpServers // {}) + .[1].mcpServers}' \
                "$primary_claude_base/.claude.json" "${mkClaudeUserConfig p}" > "$primary_claude_base/.claude.json.tmp"
              chmod 600 "$primary_claude_base/.claude.json.tmp"
              mv "$primary_claude_base/.claude.json.tmp" "$primary_claude_base/.claude.json"
            fi
          done
        ''}

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
        export OPENCODE_CONFIG_DIR="$HOME/.config/profiles/$profile/opencode"
        echo "activated developer profile: $profile"
      }
    '';
  };
}
