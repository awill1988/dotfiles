{ config, lib, ... }:
let inherit (config.home) homeDirectory;
in {
  xdg = {
    enable = true;
    configHome = "${homeDirectory}/.config";
    dataHome = "${homeDirectory}/.local/share";
    cacheHome = "${homeDirectory}/.cache";

    configFile."starship.toml".source = ./config/starship.toml;
    # force replace any existing nvim config so managed files install cleanly
    configFile."nvim" = {
      source = ./config/nvim;
      recursive = true;
      force = true;
    };
  };

  # vim configuration (classic vim, xdg-compliant)
  home.file.".vimrc".source = ./config/vimrc;
}
