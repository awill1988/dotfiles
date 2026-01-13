{ config, pkgs, lib, ... }:
let
  font_family = config.ext.fonts.monospace_family;
  font_size = config.ext.fonts.monospace_size;
in
{
  programs = {
    alacritty.enable = true;
    alacritty.settings.window = {
      padding.x = 12;
      padding.y = 12;
      dynamic_title = true;
      opacity = 0.9;
      option_as_alt = "Both";
    };
    alacritty.settings.general.working_directory =
      "${config.home.homeDirectory}/projects";
    alacritty.settings.scrolling.history = 10000;
    alacritty.settings.keyboard.bindings = [{
      key = "Q";
      mods = "Control";
      chars = "\\u0011";
    }];
    alacritty.settings.terminal.shell = {
      program = "${pkgs.zsh}/bin/zsh";
      args = [ "-l" ];
    };
    alacritty.settings.font = {
      normal = {
        family = font_family;
        style = "Regular";
      };
      bold = {
        family = font_family;
        style = "Bold";
      };
      italic = {
        family = font_family;
        style = "Italic";
      };
      bold_italic = {
        family = font_family;
        style = "Bold Italic";
      };
      size = font_size;
    };
  };
}
