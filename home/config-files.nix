{ config, lib, ... }:
let inherit (config.home) homeDirectory;
in {
  xdg = {
    enable = true;
    configHome = "${homeDirectory}/.config";
    dataHome = "${homeDirectory}/.local/share";
    cacheHome = "${homeDirectory}/.cache";

    configFile."aws/config".source = ./files/aws/config;
    configFile."starship.toml".source = ./files/starship.toml;
    configFile."codex/config.toml".source = ./files/codex/config.toml;
    configFile."codex/AGENTS.override.md".source =
      ./files/codex/AGENTS.override.md;
  };
}
