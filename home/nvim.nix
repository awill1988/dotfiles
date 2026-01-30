{ config, ... }:

{
  config = {
    home.sessionVariables = {
      NVIM_GUI_FONT = "${config.ext.fonts.monospace_family}:h${toString config.ext.fonts.monospace_size}";
      NVIM_GUI_FONT_FAMILY = config.ext.fonts.monospace_family;
      NVIM_GUI_FONT_SIZE = toString config.ext.fonts.monospace_size;
    };
  };
}
