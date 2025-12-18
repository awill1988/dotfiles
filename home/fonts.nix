{ config, pkgs, lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options.ext.fonts = {
    monospace_family = mkOption {
      type = types.str;
      default = "SauceCodePro Nerd Font Mono";
    };
    monospace_size = mkOption {
      type = types.float;
      default = 15.0;
    };
  };

  config = {
    # Home Manager does not expose `fonts.packages` (that's a NixOS system option).
    # Enable fontconfig here and add the font via home.packages so it merges with
    # other package lists defined in the configuration.
    fonts.fontconfig.enable = true;

    home.sessionVariables = {
      TERMINAL_FONT_FAMILY = config.ext.fonts.monospace_family;
      TERMINAL_FONT_SIZE = toString config.ext.fonts.monospace_size;
    };

    home.packages = with pkgs; [
      inconsolata # extra monospace
      noto-fonts-cjk-sans # CJK support
      nerd-fonts.droid-sans-mono
      nerd-fonts.sauce-code-pro
      font-awesome_5
      source-code-pro
      dejavu_fonts
    ];
  };
}
