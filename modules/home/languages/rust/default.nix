{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.modules.languages.rust;
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
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
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
    ] ++ optional cfg.sccache.enable sccache;

    home.sessionVariables = mkIf cfg.sccache.enable {
      RUSTC_WRAPPER = "${pkgs.sccache}/bin/sccache";
      SCCACHE_DIR = "${config.xdg.cacheHome}/sccache";
      SCCACHE_CACHE_SIZE = cfg.sccache.cacheSize;
    };

    xdg.configFile."cargo/config.toml".text = mkIf cfg.sccache.enable ''
      [build]
      rustc-wrapper = "${pkgs.sccache}/bin/sccache"
    '';
  };
}
