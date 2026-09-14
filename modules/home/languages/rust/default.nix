{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.modules.languages.rust;
  cargoSweepAll = pkgs.writeShellScriptBin "cargo-sweep-all" ''
    set -euo pipefail
    max_days="''${1:-${toString cfg.sweep.maxAgeDays}}"
    echo "==> Sweeping Rust target directories older than ''${max_days} days..."

    dirs=(
      "${config.home.homeDirectory}/projects"
      "${config.xdg.cacheHome}/yourmood/flockem/cargo-target"
    )

    for target_dir in "''${dirs[@]}"; do
      if [[ -d "$target_dir" ]]; then
        echo "--> Sweeping $target_dir..."
        ${pkgs.cargo-sweep}/bin/cargo-sweep --time "$max_days" --recursive "$target_dir" || true
      fi
    done
    echo "==> Cargo sweep complete."
  '';
in
{
  options.modules.languages.rust = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Rust language toolchain and analyzer.";
    };
    sccache = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable sccache shared rustc compiler cache across projects.";
      };
      cacheSize = mkOption {
        type = types.str;
        default = "30G";
        description = "Maximum size limit for sccache storage.";
      };
    };
    sweep = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable periodic cargo-sweep background pruning for rust target directories.";
      };
      maxAgeDays = mkOption {
        type = types.int;
        default = 14;
        description = "Maximum age in days for retaining stale build artifacts in target directories.";
      };
    };
  };

  config = mkIf cfg.enable {
    home.packages =
      with pkgs;
      [
        (rust-bin.stable.latest.default.override {
          extensions = [
            "rust-src"
            "rust-analyzer"
            "clippy"
            "llvm-tools-preview"
          ];
        })
        cargo-cache
        cargo-sweep
        cargoSweepAll
      ]
      ++ optional cfg.sccache.enable sccache;

    home.sessionVariables = mkIf cfg.sccache.enable {
      RUSTC_WRAPPER = "${pkgs.sccache}/bin/sccache";
      SCCACHE_DIR = "${config.xdg.cacheHome}/sccache";
      SCCACHE_CACHE_SIZE = cfg.sccache.cacheSize;
    };

    xdg.configFile."cargo/config.toml".text = mkIf cfg.sccache.enable ''
      [build]
      rustc-wrapper = "${pkgs.sccache}/bin/sccache"

      [profile.dev]
      split-debuginfo = "unpacked"

      [profile.release]
      split-debuginfo = "unpacked"
    '';

    launchd.agents.cargo-sweep = lib.mkIf (pkgs.stdenv.isDarwin && cfg.sweep.enable) {
      enable = true;
      config = {
        Program = "${cargoSweepAll}/bin/cargo-sweep-all";
        ProgramArguments = [
          "${cargoSweepAll}/bin/cargo-sweep-all"
          (toString cfg.sweep.maxAgeDays)
        ];
        StartInterval = 604800; # 7 days
        RunAtLoad = true;
        StandardOutPath = "${config.xdg.cacheHome}/cargo-sweep.log";
        StandardErrorPath = "${config.xdg.cacheHome}/cargo-sweep-err.log";
      };
    };
  };
}

