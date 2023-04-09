{ config, pkgs, lib, ... }:
let fontFamily = "JetBrainsMono Nerd Font";
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
      normal.family = "${fontFamily}";
      bold.family = "${fontFamily}";
      italic.family = "${fontFamily}";
      bold_italic.family = "${fontFamily}";
      size = 15.0;
    };
  };

  fonts.fontconfig.enable = true;
}
