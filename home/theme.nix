{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  themesDir = ./themes;

  # Discover all local .yaml files in ./themes/
  localThemeFiles =
    if pathExists themesDir then
      mapAttrs
        (name: _: {
          file = "${themesDir}/${name}";
          isLocal = true;
        })
        (filterAttrs (name: type: type == "regular" && hasSuffix ".yaml" name) (builtins.readDir themesDir))
    else
      { };

  # Known theme metadata table with dark/light pairing rules
  knownThemes = {
    "catppuccin-mocha.yaml" = {
      polarity = "dark";
      family = "catppuccin";
      pair = "catppuccin-latte";
    };
    "catppuccin-latte.yaml" = {
      polarity = "light";
      family = "catppuccin";
      pair = "catppuccin-mocha";
    };
    "gruvbox-dark.yaml" = {
      polarity = "dark";
      family = "gruvbox";
      pair = "gruvbox-light";
    };
    "gruvbox-light.yaml" = {
      polarity = "light";
      family = "gruvbox";
      pair = "gruvbox-dark";
    };
    "rose-pine.yaml" = {
      polarity = "dark";
      family = "rose-pine";
      pair = "rose-pine-dawn";
    };
    "rose-pine-dawn.yaml" = {
      polarity = "light";
      family = "rose-pine";
      pair = "rose-pine";
    };
    "tokyo-night-storm.yaml" = {
      polarity = "dark";
      family = "tokyo-night";
      pair = "tokyo-night-storm";
    };
    "everforest.yaml" = {
      polarity = "dark";
      family = "everforest";
      pair = "everforest";
    };
    "nord.yaml" = {
      polarity = "dark";
      family = "nord";
      pair = "nord";
    };
    "dracula.yaml" = {
      polarity = "dark";
      family = "dracula";
      pair = "dracula";
    };
  };

  active = import ./active-theme.nix;
  activeFileName = "${active}.yaml";

  themeMeta =
    knownThemes.${activeFileName} or {
      polarity =
        if hasInfix "light" active || hasInfix "latte" active || hasInfix "dawn" active then
          "light"
        else
          "dark";
      family = head (splitString "-" active);
      pair = active;
    };

  base16SchemeFile =
    if hasAttr activeFileName localThemeFiles then
      localThemeFiles.${activeFileName}.file
    else
      "${pkgs.base16-schemes}/share/themes/${activeFileName}";

  # CLI theme switcher script
  theme-switch = pkgs.writeShellScriptBin "theme-switch" ''
    set -euo pipefail

    ACTIVE_THEME_FILE="${config.home.homeDirectory}/projects/awill1988/dotfiles/home/active-theme.nix"

    get_current_theme() {
      if [ -f "$ACTIVE_THEME_FILE" ]; then
        tr -d '"' < "$ACTIVE_THEME_FILE" | tr -d '[:space:]'
      else
        echo "${active}"
      fi
    }

    get_pair() {
      case "$1" in
        ${concatStringsSep "\n        " (
          mapAttrsToList (name: meta: "${removeSuffix ".yaml" name}) echo \"${meta.pair}\" ;;") knownThemes
        )}
        *-dark) echo "''${1%-dark}-light" ;;
        *-light) echo "''${1%-light}-dark" ;;
        *) echo "$1" ;;
      esac
    }

    get_polarity() {
      case "$1" in
        ${concatStringsSep "\n        " (
          mapAttrsToList (
            name: meta: "${removeSuffix ".yaml" name}) echo \"${meta.polarity}\" ;;"
          ) knownThemes
        )}
        *light*|*latte*|*dawn*) echo "light" ;;
        *) echo "dark" ;;
      esac
    }

    notify_apps() {
      target="''${1:-}"
      pol="''${2:-}"
      if command -v tmux >/dev/null 2>&1; then
        tmux set-environment -g ACTIVE_THEME "$target" 2>/dev/null || true
        tmux set-environment -g THEME_POLARITY "$pol" 2>/dev/null || true
        tmux set-environment -g NVIM_THEME_POLARITY "$pol" 2>/dev/null || true
      fi

      for sock in /tmp/nvim*/0 "''${XDG_RUNTIME_DIR:-/tmp}"/nvim*/0 ~/.local/state/nvim/*.sock; do
        if [ -S "$sock" ]; then
          nvim --server "$sock" --remote-send '<Cmd>ThemeReload<CR>' 2>/dev/null || true
        fi
      done
    }

    CURRENT="$(get_current_theme)"

    case "''${1:-list}" in
      list)
        pol="$(get_polarity "$CURRENT")"
        echo "Active Theme: $CURRENT ($pol mode)"
        echo ""
        echo "Available local themes in home/themes/:"
        for f in ${themesDir}/*.yaml; do
          [ -f "$f" ] || continue
          basename "$f" .yaml
        done
        ;;
      set)
        target="''${2:-}"
        if [ -z "$target" ]; then
          echo "usage: theme-switch set <theme-name>" >&2
          exit 1
        fi
        if [ ! -f "${themesDir}/$target.yaml" ] && [ ! -f "${pkgs.base16-schemes}/share/themes/$target.yaml" ]; then
          echo "error: theme '$target' not found in home/themes/ or base16-schemes" >&2
          exit 1
        fi
        pol="$(get_polarity "$target")"
        printf '"%s"\n' "$target" > "$ACTIVE_THEME_FILE"
        notify_apps "$target" "$pol"
        echo "Switched active theme to '$target' ($pol mode)."
        echo "Run 'darwin-rebuild switch' or './result/activate' to apply system-wide."
        ;;
      toggle-mode)
        pair="$(get_pair "$CURRENT")"
        if [ "$pair" = "$CURRENT" ]; then
          echo "No distinct light/dark pair defined for '$CURRENT'."
        else
          pol="$(get_polarity "$pair")"
          printf '"%s"\n' "$pair" > "$ACTIVE_THEME_FILE"
          notify_apps "$pair" "$pol"
          echo "Toggled theme mode: '$CURRENT' -> '$pair'."
          echo "Run 'darwin-rebuild switch' or './result/activate' to apply system-wide."
        fi
        ;;
      sync-host)
        quiet=0
        if [ "''${2:-}" = "--quiet" ] || [ "''${2:-}" = "-q" ]; then
          quiet=1
        fi

        detect_host_mode() {
          if [ "$(uname)" = "Darwin" ]; then
            if defaults read -g AppleInterfaceStyle 2>/dev/null | grep -qi "Dark"; then
              echo "dark"
            else
              echo "light"
            fi
          elif grep -qi "microsoft" /proc/version 2>/dev/null || [ -n "''${WSL_DISTRO_NAME:-}" ]; then
            if reg.exe query "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v AppsUseLightTheme 2>/dev/null | grep -qi "0x0"; then
              echo "dark"
            else
              echo "light"
            fi
          else
            if gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | grep -qi "dark"; then
              echo "dark"
            else
              echo "light"
            fi
          fi
        }

        host_mode="$(detect_host_mode)"
        current_polarity="$(get_polarity "$CURRENT")"
        if [ "$host_mode" != "$current_polarity" ]; then
          pair="$(get_pair "$CURRENT")"
          if [ "$pair" != "$CURRENT" ]; then
            printf '"%s"\n' "$pair" > "$ACTIVE_THEME_FILE"
            notify_apps "$pair" "$host_mode"
            if [ "$quiet" -eq 0 ]; then
              echo "Host OS mode ($host_mode) differs from theme polarity ($current_polarity). Switched to '$pair'."
              echo "Run 'darwin-rebuild switch' or './result/activate' to apply system-wide."
            fi
          fi
        else
          if [ "$quiet" -eq 0 ]; then
            echo "Theme '$CURRENT' ($current_polarity) is already in sync with host OS mode ($host_mode)."
          fi
        fi
        ;;
      *)
        echo "usage: theme-switch {list|set <name>|toggle-mode|sync-host}"
        exit 1
        ;;
    esac
  '';
in
{
  stylix = {
    enable = true;
    base16Scheme = base16SchemeFile;
    polarity = themeMeta.polarity;

    opacity.terminal = 0.9;

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
      starship.enable = false;
    };
  };

  home.packages = [ theme-switch ];

  home.sessionVariables = {
    ACTIVE_THEME = active;
    THEME_POLARITY = themeMeta.polarity;
  };
}
