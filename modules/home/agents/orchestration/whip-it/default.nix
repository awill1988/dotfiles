{ whip_it_src }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.whip-it;
  has_pyproject = builtins.pathExists "${whip_it_src}/pyproject.toml";
  application =
    if has_pyproject then
      pkgs.python3Packages.buildPythonApplication {
        pname = "whip-it";
        version = "0.1.0";
        src = whip_it_src;
        pyproject = true;
        build-system = [ pkgs.python3Packages.poetry-core ];
        pythonImportsCheck = [ "whipit" ];
      }
    else
      null;
  engine_script = "${whip_it_src}/scripts/whip_it.py";
  state_dir = "${config.home.homeDirectory}/.local/state/whip-it";
  package = pkgs.writeShellScriptBin "whip-it" ''
    export WHIP_IT_MODE="${cfg.mode}"
    export WHIP_IT_MAX_SUBAGENTS="${toString cfg.defaultMaxSubagents}"
    export WHIP_IT_AUTO_CLAMP="${if cfg.autoClamp then "true" else "false"}"
    export WHIP_IT_STATE_DIR="''${WHIP_IT_STATE_DIR:-${state_dir}}"
    ${
      if has_pyproject then
        "exec ${application}/bin/whip-it \"$@\""
      else
        "exec ${pkgs.python3}/bin/python3 ${engine_script} \"$@\""
    }
  '';
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
    let
      clientEnable =
        if client == "antigravity" then
          config.programs.agy.enable or true
        else
          config.programs.${client}.enable or true;
      profileEnable =
        if profile == null then
          true
        else if client == "antigravity" then
          profile.agents.agy.enable or true
        else
          profile.agents.${client}.enable or true;
    in
    clientEnable && profileEnable;
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
              "${package}/bin/whip-it"
              "--client"
              client
              "--event"
              event
            ];
          }
        ];
      };
      tool_matcher =
        if client == "claude" then
          "Agent|Task"
        else if client == "codex" then
          "spawn_agent|subagent|agent"
        else
          "invoke_subagent|define_subagent";
      prompt_event = if client == "antigravity" then "PreInvocation" else "UserPromptSubmit";
    in
    {
      hooks = lib.optionalAttrs enabled {
        ${prompt_event} = [ (mk_group prompt_event "") ];
        PreToolUse = [ (mk_group "PreToolUse" tool_matcher) ];
        PostToolUse = [ (mk_group "PostToolUse" tool_matcher) ];
      };
    };
  target = client: profile: directory: {
    path = "${directory}/${if client == "claude" then "settings.json" else "hooks.json"}";
    desired = mk_hooks client profile;
    legacy = { };
  };
  profile_targets = lib.concatMap (
    profile:
    map
      (
        client:
        let
          clientKey = if client == "antigravity" then "agy" else client;
          directory = profile.agents.${clientKey}.configDir or null;
        in
        target client profile (
          if directory != null then
            expand_home directory
          else
            "${config.xdg.configHome}/profiles/${profile.name}/${clientKey}"
        )
      )
      [
        "claude"
        "codex"
        "antigravity"
      ]
  ) profiles;
  targets = lib.unique (
    profile_targets
    ++ [
      (target "claude" primary "${home_dir}/.claude")
      (target "claude" primary "${config.xdg.configHome}/claude")
      (target "codex" primary "${config.xdg.configHome}/codex")
      (target "antigravity" primary "${home_dir}/.gemini/config")
    ]
  );
  specification = pkgs.writeText "whip-it-hooks.json" (builtins.toJSON targets);
in
{
  options.programs.whip-it = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable whip-it agent-planning guardrail and simplification hooks.";
    };
    mode = lib.mkOption {
      type = lib.types.enum [
        "enforce"
        "advisory"
        "off"
      ];
      default = "enforce";
      description = "Guardrail intervention mode: enforce (block & redirect), advisory, or off.";
    };
    defaultMaxSubagents = lib.mkOption {
      type = lib.types.int;
      default = 0;
      description = "Default maximum permitted subagents before blocking delegation.";
    };
    autoClamp = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Clamp excessive subagent argument arrays rather than hard-denying.";
    };
  };

  config = lib.mkMerge [
    {
      home.activation.reconcileWhipItHooks =
        lib.hm.dag.entryAfter
          [
            "writeBoundary"
            "ensureProfileDirs"
          ]
          ''
            ${pkgs.python3}/bin/python3 ${./reconcile_hooks.py} ${specification}
          '';
    }
    (lib.mkIf cfg.enable {
      home.packages = [
        package
      ];
    })
  ];
}
