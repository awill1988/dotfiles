{ config, ... }:

{
  config = {
    home.sessionVariables = {
      NVIM_GUI_FONT = "${config.aw.fonts.monospace_family}:h${
          toString config.aw.fonts.monospace_size
        }";
      NVIM_GUI_FONT_FAMILY = config.aw.fonts.monospace_family;
      NVIM_GUI_FONT_SIZE = toString config.aw.fonts.monospace_size;
    };
  };
}
