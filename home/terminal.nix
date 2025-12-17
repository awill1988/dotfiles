{ config, pkgs, lib, ... }:
let
  font_family = config.aw.fonts.monospace_family;
  font_size = config.aw.fonts.monospace_size;
in
{
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
      normal.family = font_family;
      bold.family = font_family;
      italic.family = font_family;
      bold_italic.family = font_family;
      size = font_size; # adjust if you want a different default size
    };
  };
}
