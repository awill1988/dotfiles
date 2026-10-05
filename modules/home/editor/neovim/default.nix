{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.modules.editor.neovim;
  palette = config.lib.stylix.colors.withHashtag;
  palette_names = [
    "base00"
    "base01"
    "base02"
    "base03"
    "base04"
    "base05"
    "base06"
    "base07"
    "base08"
    "base09"
    "base0A"
    "base0B"
    "base0C"
    "base0D"
    "base0E"
    "base0F"
  ];
  palette_variables = builtins.listToAttrs (
    map (name: {
      name = "NVIM_THEME_${toUpper name}";
      value = palette.${name};
    }) palette_names
  );
in
{
  options.modules.editor.neovim = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Neovim editor stack.";
    };
  };

  config = mkIf cfg.enable {
    programs.neovim = {
      enable = true;
      viAlias = true;
      vimAlias = true;
      withNodeJs = true;
      withPython3 = true;
      plugins = [ ];
      extraPackages = with pkgs; [
        ripgrep
        fd
        tree-sitter
        fzf
        nil
      ];
    };

    home.sessionVariables = {
      NVIM_GUI_FONT = "${config.ext.fonts.monospace_family}:h${toString config.ext.fonts.monospace_size}";
      NVIM_GUI_FONT_FAMILY = config.ext.fonts.monospace_family;
      NVIM_GUI_FONT_SIZE = toString config.ext.fonts.monospace_size;
      NVIM_THEME_BASE16_PATH = "${pkgs.vimPlugins.mini-nvim}";
      NVIM_THEME_POLARITY = config.stylix.polarity or "dark";
    }
    // palette_variables;
  };
}
