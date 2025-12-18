{ config, lib, ... }:
let inherit (config.home) homeDirectory;
in {
  xdg = {
    enable = true;
    configHome = "${homeDirectory}/.config";
    dataHome = "${homeDirectory}/.local/share";
    cacheHome = "${homeDirectory}/.cache";

    configFile."starship.toml".source = ./config/starship.toml;
    configFile."nvim/init.lua".source = ./config/nvim/init.lua;
    configFile."nvim/lua/ext".source = ./config/nvim/lua/ext;
    configFile."nvim/coc-settings.json".source = ./config/coc-settings.json;
  };

  # vim configuration (classic vim, xdg-compliant)
  home.file.".vimrc".source = ./config/vimrc;
}
