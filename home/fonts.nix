{ config, pkgs, lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options.ext.fonts = {
    monospace_family = mkOption {
      type = types.str;
      default = "SauceCodePro Nerd Font Mono";
    };
    monospace_size = mkOption {
      type = types.float;
      default = 13.0;
    };
  };

  config = {
    # Home Manager does not expose `fonts.packages` (that's a NixOS system option).
    # Enable fontconfig here and add the font via home.packages so it merges with
    # other package lists defined in the configuration.
    fonts.fontconfig.enable = true;

    home.sessionVariables = {
      TERMINAL_FONT_FAMILY = config.ext.fonts.monospace_family;
      TERMINAL_FONT_SIZE = toString config.ext.fonts.monospace_size;
    };

    home.packages = with pkgs; [
      inconsolata # extra monospace
      noto-fonts-cjk-sans # CJK support
      nerd-fonts.droid-sans-mono
      nerd-fonts.sauce-code-pro
      font-awesome_5
      source-code-pro
      dejavu_fonts
    ];

    # macOS: symlink fonts to ~/Library/Fonts so applications can find them
    home.activation.linkFonts = lib.mkIf pkgs.stdenv.isDarwin (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        font_dir="$HOME/Library/Fonts/nix-fonts"
        mkdir -p "$font_dir"

        # clean up old symlinks
        find "$font_dir" -type l -delete

        # symlink all fonts from packages
        for pkg in ${lib.concatStringsSep " " (map (p: "${p}") config.home.packages)}; do
          if [[ -d "$pkg/share/fonts" ]]; then
            find "$pkg/share/fonts" -type f \( -name "*.ttf" -o -name "*.otf" \) -exec ln -sf {} "$font_dir/" \;
          fi
        done

        echo "fonts symlinked to $font_dir"
      ''
    );
  };
}
