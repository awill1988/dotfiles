{ config, pkgs, ... }:
let
  # Curated themes. Add more by browsing
  # ${pkgs.base16-schemes}/share/themes/*.yaml.
  themes = {
    catppuccin-mocha = {
      file = "catppuccin-mocha.yaml";
      polarity = "dark";
    };
    catppuccin-latte = {
      file = "catppuccin-latte.yaml";
      polarity = "light";
    };
    gruvbox-dark = {
      file = "gruvbox-dark-medium.yaml";
      polarity = "dark";
    };
    gruvbox-light = {
      file = "gruvbox-light-medium.yaml";
      polarity = "light";
    };
    rose-pine = {
      file = "rose-pine.yaml";
      polarity = "dark";
    };
    rose-pine-dawn = {
      file = "rose-pine-dawn.yaml";
      polarity = "light";
    };
    tokyo-night-storm = {
      file = "tokyo-night-storm.yaml";
      polarity = "dark";
    };
    everforest = {
      file = "everforest.yaml";
      polarity = "dark";
    };
    nord = {
      file = "nord.yaml";
      polarity = "dark";
    };
    dracula = {
      file = "dracula.yaml";
      polarity = "dark";
    };
  };

  # Active theme name. To switch, edit home/active-theme.nix (a one-line
  # file: `"<name>"`) and run `darwin-rebuild switch`. Available names are
  # the keys of the `themes` attrset above.
  active = import ./active-theme.nix;
  theme = themes.${active};
in
{
  stylix = {
    enable = true;
    base16Scheme = "${pkgs.base16-schemes}/share/themes/${theme.file}";
    polarity = theme.polarity;

    # match the existing 0.9 alacritty window opacity so stylix and
    # terminal.nix don't fight over the alacritty.window.opacity option.
    opacity.terminal = 0.9;

    # Align stylix's font + size with the existing ext.fonts settings so it
    # doesn't fight terminal.nix/alacritty over font.size. Stylix still needs
    # *some* font config to compute fallbacks even when targets are off.
    fonts = {
      monospace = {
        package = pkgs.nerd-fonts.sauce-code-pro;
        name = config.ext.fonts.monospace_family;
      };
      serif = {
        package = pkgs.dejavu_fonts;
        name = "DejaVu Serif";
      };
      sansSerif = {
        package = pkgs.dejavu_fonts;
        name = "DejaVu Sans";
      };
      emoji = {
        package = pkgs.noto-fonts-color-emoji;
        name = "Noto Color Emoji";
      };
      sizes = {
        applications = builtins.floor config.ext.fonts.monospace_size;
        terminal = builtins.floor config.ext.fonts.monospace_size;
        desktop = 11;
        popups = 11;
      };
    };

    targets = {
      alacritty.enable = true;
      neovim.enable = true;
      tmux.enable = true;
      fzf.enable = true;
      # starship.toml is managed as a literal file (config-files.nix). Stylix
      # would inject its own settings via programs.starship.settings, which
      # conflicts with the file-source mapping. The existing TOML already
      # uses named colors that resolve against whatever palette the terminal
      # provides, so the visual diff from skipping stylix here is small.
      starship.enable = false;
    };
  };
}
