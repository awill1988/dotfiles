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
  };

  config = mkIf cfg.enable {
    home.packages = [
      (pkgs.rust-bin.stable.latest.default.override {
        extensions = [
          "rust-src"
          "rust-analyzer"
          "clippy"
          "llvm-tools-preview"
        ];
      })
    ];
  };
}
