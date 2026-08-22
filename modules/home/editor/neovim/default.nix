{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.modules.editor.neovim;
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
      ];
    };

    home.sessionVariables = {
      NVIM_GUI_FONT = "${config.ext.fonts.monospace_family}:h${toString config.ext.fonts.monospace_size}";
      NVIM_GUI_FONT_FAMILY = config.ext.fonts.monospace_family;
      NVIM_GUI_FONT_SIZE = toString config.ext.fonts.monospace_size;
    };
  };
}
