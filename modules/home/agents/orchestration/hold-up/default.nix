{ hold_up_src }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.hold-up;
  has_pyproject = builtins.pathExists "${hold_up_src}/pyproject.toml";
  application =
    if has_pyproject then
      pkgs.python3Packages.buildPythonApplication {
        pname = "hold-up";
        version = "2.0.0";
        src = hold_up_src;
        pyproject = true;
        build-system = [ pkgs.python3Packages.poetry-core ];
        pythonImportsCheck = [ "holdup" ];
      }
    else
      null;
  default_config =
    if builtins.pathExists "${hold_up_src}/src/holdup/data/status_feeds.json" then
      "${hold_up_src}/src/holdup/data/status_feeds.json"
    else
      "${hold_up_src}/config/status_feeds.json";
  engine_script = "${hold_up_src}/scripts/hold_up.py";
  feeds =
    if cfg.customFeeds == { } then
      default_config
    else
      pkgs.runCommand "hold-up-feeds.json" { } ''
        ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "${default_config}" \
          "${pkgs.writeText "hold-up-custom-feeds.json" (builtins.toJSON cfg.customFeeds)}" > "$out"
      '';
  package = pkgs.writeShellScriptBin "hold-up" ''
    export HOLD_UP_CONFIG="''${HOLD_UP_CONFIG:-${feeds}}"
    export HOLD_UP_MODE="${cfg.mode}"
    export HOLD_UP_STATE_DIR="''${HOLD_UP_STATE_DIR:-${state_dir}}"
    ${if has_pyproject then "exec ${application}/bin/hold-up \"$@\"" else "exec ${pkgs.python3}/bin/python3 ${engine_script} \"$@\""}
  '';
  evaluator =
    if has_pyproject then
      pkgs.writeShellScriptBin "hold-up-evaluate" ''
        export HOLD_UP_STATE_DIR="''${HOLD_UP_STATE_DIR:-${state_dir}}"
        exec ${application}/bin/hold-up-evaluate "$@"
      ''
    else
      null;
  state_dir = "${config.home.homeDirectory}/.local/state/hold-up";
  runtime_commands = {
    hold-up-inference = [
      "${package}/bin/hold-up"
      "serve"
      "--runner"
      "${pkgs.llama-cpp}/bin/llama-server"
    ];
    hold-up-evidence = [
      "${package}/bin/hold-up"
      "collect"
      "--config"
      "${feeds}"
    ];
  };
  home_dir = config.home.homeDirectory;
  expand_home = path: if lib.hasPrefix "~/" path then home_dir + lib.removePrefix "~" path else path;
  profiles = lib.attrValues (config.developer.resolvedProfiles or { });
  primary_profiles = lib.filter (profile: profile.isPrimary) profiles;
  primary =
    if primary_profiles != [ ] then
      builtins.head primary_profiles
    else if profiles != [ ] then
      builtins.head profiles
    else
      null;
  eligible =
    client: profile:
    config.programs.${client}.enable && (profile == null || profile.agents.${client}.enable);
  mk_hooks =
    client: profile:
    let
      enabled = cfg.enable && eligible client profile;
      profile_name = if profile == null then "default" else profile.name;
      mk_group = event: matcher: {
        inherit matcher;
        hooks = [
          {
            type = "command";
            command = lib.escapeShellArgs [
              "${package}/bin/hold-up"
              "--client"
              client
              "--event"
              event
              "--cache-dir"
              "${config.xdg.cacheHome}/hold-up/${profile_name}"
              "--profile"
              profile_name
            ];
          }
        ];
      };
      tool_event = if client == "claude" then "PostToolUseFailure" else "PostToolUse";
    in
    {
      hooks = lib.optionalAttrs enabled {
        SessionStart = [ (mk_group "SessionStart" "") ];
        UserPromptSubmit = [ (mk_group "UserPromptSubmit" "") ];
        PreToolUse = [ (mk_group "PreToolUse" ".*") ];
        ${tool_event} = [ (mk_group tool_event "Bash") ];
      };
    };
  legacy_hooks = {
    hooks = lib.genAttrs [ "SessionStart" "UserPromptSubmit" "PostToolUseFailure" ] (event: [
      {
        matcher = if event == "PostToolUseFailure" then "Bash" else "";
        hooks = [
          {
            type = "command";
            command = "python3 ${home_dir}/.claude/hooks/vcs_status_hook.py --event ${event}";
          }
        ];
      }
    ]);
  };
  target = client: profile: directory: {
    path = "${directory}/${if client == "claude" then "settings.json" else "hooks.json"}";
    desired = mk_hooks client profile;
    legacy = if client == "claude" then legacy_hooks else { };
  };
  profile_targets = lib.concatMap (
    profile:
    map
      (
        client:
        let
          directory = profile.agents.${client}.configDir;
        in
        target client profile (
          if directory != null then
            expand_home directory
          else
            "${config.xdg.configHome}/profiles/${profile.name}/${client}"
        )
      )
      [
        "claude"
        "codex"
      ]
  ) profiles;
  targets = lib.unique (
    profile_targets
    ++ [
      (target "claude" primary "${home_dir}/.claude")
      (target "claude" primary "${config.xdg.configHome}/claude")
      (target "codex" primary "${config.xdg.configHome}/codex")
    ]
  );
  specification = pkgs.writeText "hold-up-hooks.json" (builtins.toJSON targets);
in
{
  imports = [
    (lib.mkRenamedOptionModule
      [
        "programs"
        "claude-provider-status"
        "enable"
      ]
      [ "programs" "hold-up" "enable" ]
    )
    (lib.mkRenamedOptionModule
      [
        "programs"
        "claude-provider-status"
        "customFeeds"
      ]
      [ "programs" "hold-up" "customFeeds" ]
    )
  ];

  options.programs.hold-up = {
    mode = lib.mkOption {
      type = lib.types.enum [
        "guard"
        "advisory"
        "off"
      ];
      default = "guard";
      description = "Outage decision mode; guard requires a passing local model evaluation.";
    };
    manageRuntime = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Manage local inference and provider evidence services; provision weights explicitly.";
    };
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable hold-up! cloud and VCS status advisories.";
    };
    customFeeds = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Overrides merged into the bundled status feed configuration.";
    };
  };

  config = lib.mkMerge [
    {
      home.activation.reconcileHoldUpHooks =
        lib.hm.dag.entryAfter
          [
            "writeBoundary"
            "ensureProfileDirs"
            "ensureCodexConfig"
          ]
          ''
            ${pkgs.python3}/bin/python3 ${./reconcile_hooks.py} ${specification}
          '';
    }
    (lib.mkIf cfg.enable {
      home.packages = [ package ] ++ lib.optional (evaluator != null) evaluator;
      xdg.configFile."hold-up/status_feeds.json".source = feeds;
      home.file.".claude/hooks/status_feeds.json" = {
        source = feeds;
        force = true;
      };
      home.file.".claude/hooks/vcs_status_hook.py" = {
        text = ''
          #!${pkgs.python3}/bin/python3
          import os
          import sys
          os.execv("${package}/bin/hold-up", ["hold-up", "--client", "claude", *sys.argv[1:]])
        '';
        executable = true;
        force = true;
      };
    })
    (lib.mkIf (pkgs.stdenv.isDarwin && cfg.enable && cfg.manageRuntime) {
      launchd.agents = lib.mapAttrs (_: command: {
        enable = true;
        config = {
          ProgramArguments = command;
          EnvironmentVariables = {
            HOLD_UP_STATE_DIR = state_dir;
          };
          RunAtLoad = true;
          KeepAlive = {
            SuccessfulExit = false;
          };
          ThrottleInterval = 60;
          ProcessType = "Background";
        };
      }) runtime_commands;
    })
    (lib.mkIf (pkgs.stdenv.isLinux && cfg.enable && cfg.manageRuntime) {
      systemd.user.services = lib.mapAttrs (name: command: {
        Unit.Description = name;
        Service = {
          ExecStart = lib.escapeShellArgs command;
          Environment = "HOLD_UP_STATE_DIR=${state_dir}";
          Restart = "on-failure";
          RestartSec = 60;
          UMask = "0077";
        };
        Install.WantedBy = [ "default.target" ];
      }) runtime_commands;
    })
  ];
}
