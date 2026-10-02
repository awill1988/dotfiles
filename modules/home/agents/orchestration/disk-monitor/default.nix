{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.programs.disk-monitor;

  harness_pkg = pkgs.writeShellApplication {
    name = "disk-monitor-harness";
    runtimeInputs = with pkgs; [
      python3
      coreutils
      llama-cpp
    ];
    text = ''
      exec python3 "${./disk_monitor_harness.py}" \
        --model-path "${cfg.modelPath}" \
        --runner "${cfg.runner}" \
        --gpu-layers "${toString cfg.gpuLayers}" \
        --threshold "${toString cfg.thresholdPercent}" \
        --mount "${cfg.mountPoint}" \
        "$@"
    '';
  };
in
{
  options.programs.disk-monitor = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable 30-minute offline Metal disk space monitoring background harness";
    };
    modelPath = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/.local/share/models/qwen2.5-coder-7b.gguf";
      description = "Filesystem path to local offline GGUF model checkpoint";
    };
    runner = mkOption {
      type = types.enum [
        "llama_metal"
        "local_server"
        "dry_run"
      ];
      default = "llama_metal";
      description = "Execution engine for offline Metal-accelerated inference";
    };
    gpuLayers = mkOption {
      type = types.int;
      default = 99;
      description = "Number of layers to offload to Apple Silicon Metal GPU";
    };
    thresholdPercent = mkOption {
      type = types.float;
      default = 1.0;
      description = "Drop threshold in percentage points before triggering alert workflow";
    };
    mountPoint = mkOption {
      type = types.str;
      default = "/";
      description = "Filesystem mount point to monitor";
    };
    enableLaunchd = mkOption {
      type = types.bool;
      default = pkgs.stdenv.isDarwin;
      description = "Install macOS launchd user agent running every 1800 seconds (30m)";
    };
    enableSidecar = mkOption {
      type = types.bool;
      default = true;
      description = "Install sidecar.json definition in ~/.gemini/config/sidecars/disk_monitor/";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      harness_pkg
      pkgs.llama-cpp
    ];

    launchd.agents.disk-monitor = mkIf (cfg.enableLaunchd && pkgs.stdenv.isDarwin) {
      enable = true;
      config = {
        ProgramArguments = [ "${harness_pkg}/bin/disk-monitor-harness" ];
        StartInterval = 1800; # Run every 30 minutes
        StandardOutPath = "${config.home.homeDirectory}/.cache/disk_monitor/launchd.stdout.log";
        StandardErrorPath = "${config.home.homeDirectory}/.cache/disk_monitor/launchd.stderr.log";
      };
    };

    xdg.configFile."gemini/sidecars/disk_monitor/sidecar.json" = mkIf cfg.enableSidecar {
      source = ./sidecar.json;
    };
    xdg.configFile."gemini/sidecars/disk_monitor/disk_monitor_harness.py" = mkIf cfg.enableSidecar {
      source = ./disk_monitor_harness.py;
    };
  };
}
