{ config, lib, ... }:
let inherit (config.home) homeDirectory;
in {
  xdg = {
    enable = true;
    configHome = "${homeDirectory}/.config";
    dataHome = "${homeDirectory}/.local/share";
    cacheHome = "${homeDirectory}/.cache";

    configFile."aws/config".source = ./config/aws/config;
    configFile."starship.toml".source = ./config/starship.toml;
    configFile."nvim/init.lua".source = ./config/nvim/init.lua;
    configFile."nvim/lua/aw".source = ./config/nvim/lua/aw;
  };
}
