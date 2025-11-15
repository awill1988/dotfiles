{ config, pkgs, lib, ... }:
let fontFamily = "Source Code Pro";
in {
  programs = {
    alacritty.enable = true;
    alacritty.settings.window = {
      padding.x = 10;
      padding.y = 10;
      dynamic_title = true;
    };
    alacritty.settings.scrolling.history = 10000;
    alacritty.settings.key_bindings = [{
      key = "Q";
      mods = "Control";
      chars = "\\x11";
    }];
    alacritty.settings.font = {
      normal.family = fontFamily;
      bold.family = fontFamily;
      italic.family = fontFamily;
      bold_italic.family = fontFamily;
      size = 15.0; # adjust if you want a different default size
    };
  };

  # Home Manager does not expose `fonts.packages` (that's a NixOS system option).
  # Enable fontconfig here and add the font via home.packages so it merges with
  # other package lists defined in the configuration.
  fonts.fontconfig.enable = true;

  home.packages = with pkgs; [
    inconsolata # extra monospace
    noto-fonts-cjk-sans # CJK support
    nerd-fonts.droid-sans-mono
    nerd-fonts.fira-code
    font-awesome_5
    source-code-pro
    dejavu_fonts
  ];
}
