{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.hunyuan3d;
  cache_dir = "${config.xdg.cacheHome}/hy3dgen";
  is_darwin = pkgs.stdenv.isDarwin;
  default_device = if is_darwin then "mps" else "cuda";

  # launchd ProgramArguments must be a flat list (no shell expansion).
  # build the args list in nix so each flag is a discrete element.
  server_program_args = [
    "${cfg.package}/bin/hunyuan3d-server"
    "--host"
    cfg.host
    "--port"
    (toString cfg.port)
    "--device"
    cfg.device
    "--model_path"
    cfg.modelPath
  ]
  ++ lib.optionals (cfg.enableTexture && !is_darwin) [
    "--enable_tex"
    "--tex_model_path"
    cfg.texModelPath
  ];

  # convenience: start the launchd/systemd service
  start_script = pkgs.writeShellScriptBin "hunyuan3d-start" ''
    set -euo pipefail
    echo "starting hunyuan3d-2 on ${cfg.host}:${toString cfg.port} (device=${cfg.device})"
    ${
      if is_darwin then
        "launchctl start com.hy3dgen.server"
      else
        "systemctl --user start hunyuan3d.service"
    }
  '';

  # convenience: stop the service
  stop_script = pkgs.writeShellScriptBin "hunyuan3d-stop" ''
    ${
      if is_darwin then "launchctl stop com.hy3dgen.server" else "systemctl --user stop hunyuan3d.service"
    }
    echo "hunyuan3d-2 stopped"
  '';

  venv_dir = "${cache_dir}/venv";

  # pre-download model weights into XDG cache.
  # also bootstraps the venv if it doesn't exist yet (same as hunyuan3d-server first run).
  fetch_script = pkgs.writeShellScriptBin "hunyuan3d-fetch" ''
    set -euo pipefail
    export HY3DGEN_MODELS="${cache_dir}"
    export HY3DGEN_VENV="${venv_dir}"
    mkdir -p "$HY3DGEN_MODELS"

    # ensure venv exists (triggers one-time bootstrap via the server wrapper)
    if [[ ! -f "$HY3DGEN_VENV/pyvenv.cfg" ]]; then
      echo "bootstrapping venv first ..."
      ${cfg.package}/bin/hunyuan3d-server --help >/dev/null 2>&1 || true
    fi

    echo "downloading ${cfg.modelPath} weights into $HY3DGEN_MODELS ..."
    "$HY3DGEN_VENV/bin/python" -c "
    from huggingface_hub import snapshot_download
    import os
    cache = os.environ['HY3DGEN_MODELS']
    snapshot_download('${cfg.modelPath}', local_dir=os.path.join(cache, '${cfg.modelPath}'))
    print('done')
    "
  '';
in
{
  options.programs.hunyuan3d = {
    enable = lib.mkEnableOption "hunyuan3d-2 local inference server";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.hunyuan3d-2;
      description = "hunyuan3d-2 package providing hunyuan3d-server.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "address the api server binds to";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8081;
      description = "port for the api server (matches blender-mcp addon default)";
    };

    device = lib.mkOption {
      type = lib.types.str;
      default = default_device;
      description = "pytorch device: mps (darwin), cuda (linux), or cpu";
    };

    modelPath = lib.mkOption {
      type = lib.types.str;
      default = "tencent/Hunyuan3D-2mini";
      description = "huggingface model id (mini ~25 GB, full ~62 GB)";
    };

    texModelPath = lib.mkOption {
      type = lib.types.str;
      default = "tencent/Hunyuan3D-2";
      description = "huggingface model id for texture generation";
    };

    enableTexture = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "enable texture generation (requires CUDA, linux-only)";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      cfg.package
      start_script
      stop_script
      fetch_script
    ];

    home.sessionVariables.HY3DGEN_MODELS = cache_dir;

    # darwin: launchd user agent — manually started via hunyuan3d-start.
    # heavy process (~6 GB RAM, 30-60s cold start) so RunAtLoad = false.
    launchd.agents.hunyuan3d = lib.mkIf is_darwin (
      let
        log_path = "${config.home.homeDirectory}/Library/Logs/hunyuan3d.log";
      in
      {
        enable = true;
        config = {
          Label = "com.hy3dgen.server";
          ProgramArguments = server_program_args;
          RunAtLoad = false;
          KeepAlive = false;
          StandardOutPath = log_path;
          StandardErrorPath = log_path;
          EnvironmentVariables = {
            HY3DGEN_MODELS = cache_dir;
            HY3DGEN_VENV = venv_dir;
            PYTORCH_ENABLE_MPS_FALLBACK = "1";
            PATH = lib.makeBinPath [ pkgs.coreutils ];
          };
        };
      }
    );

    # linux: systemd user service — manually started via hunyuan3d-start.
    systemd.user.services.hunyuan3d = lib.mkIf (!is_darwin) {
      Unit.Description = "hunyuan3d-2 local inference server";
      Service = {
        Type = "simple";
        ExecStart = lib.concatStringsSep " " server_program_args;
        Environment = [ "HY3DGEN_MODELS=${cache_dir}" ];
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}
