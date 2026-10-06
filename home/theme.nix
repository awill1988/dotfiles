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

  # Pre-generate Alacritty TOML theme definitions from base16 YAML schemes
  alacrittyThemes =
    pkgs.runCommand "alacritty-themes"
      {
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        mkdir -p $out
        python3 ${./scripts/render-alacritty-themes.py} ${themesDir} $out
      '';

  # Native macOS Swift theme listener daemon
  darkModeListenerScript = pkgs.writeText "dark-mode-listener.swift" ''
    import Foundation

    func runSync() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "${theme-switch}/bin/theme-switch")
        task.arguments = ["sync-host", "--quiet"]
        try? task.run()
    }

    runSync()

    DistributedNotificationCenter.default().addObserver(
        forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
        object: nil,
        queue: nil
    ) { _ in
        runSync()
    }

    RunLoop.main.run()
  '';

  darwinThemeListenerRunner = pkgs.writeShellScriptBin "darwin-theme-listener" ''
    set -eu
    BIN="$HOME/.local/state/theme/darwin-theme-listener.bin"
    SRC="${darkModeListenerScript}"
    mkdir -p "$HOME/.local/state/theme"
    if [ ! -x "$BIN" ] || [ "$SRC" -nt "$BIN" ]; then
      if command -v /usr/bin/swiftc >/dev/null 2>&1; then
        /usr/bin/swiftc -O -o "$BIN" "$SRC" 2>/dev/null || rm -f "$BIN"
      fi
    fi
    if [ -x "$BIN" ]; then
      exec "$BIN" "$@"
    else
      exec /usr/bin/swift "$SRC" "$@"
    fi
  '';

  # CLI theme switcher script with Universal Profile & Host Sync support
  theme-switch = pkgs.writeShellScriptBin "theme-switch" ''
        set -euo pipefail

        STATE_DIR="$HOME/.local/state/theme"
        THEMES_DIR="$HOME/.config/alacritty/themes"
        if [ ! -d "$THEMES_DIR" ] && [ -d "${alacrittyThemes}" ]; then
          THEMES_DIR="${alacrittyThemes}"
        fi
        ACTIVE_THEME_FILE="${config.home.homeDirectory}/projects/awill1988/dotfiles/home/active-theme.nix"

        get_theme_family() {
          case "$1" in
            catppuccin*) echo "catppuccin" ;;
            gruvbox*) echo "gruvbox" ;;
            rose-pine*) echo "rose-pine" ;;
            tokyo-night*) echo "tokyo-night" ;;
            everforest*) echo "everforest" ;;
            nord*) echo "nord" ;;
            dracula*) echo "dracula" ;;
            *) echo "$1" ;;
          esac
        }

        get_family_variant() {
          fam="''${1:-gruvbox}"
          pol="''${2:-dark}"
          case "$fam" in
            catppuccin)
              [ "$pol" = "light" ] && echo "catppuccin-latte" || echo "catppuccin-mocha"
              ;;
            gruvbox)
              [ "$pol" = "light" ] && echo "gruvbox-light" || echo "gruvbox-dark"
              ;;
            rose-pine)
              [ "$pol" = "light" ] && echo "rose-pine-dawn" || echo "rose-pine"
              ;;
            tokyo-night)
              [ "$pol" = "light" ] && echo "tokyo-night-storm" || echo "tokyo-night-storm"
              ;;
            everforest) echo "everforest" ;;
            nord) echo "nord" ;;
            dracula) echo "dracula" ;;
            *) echo "$fam" ;;
          esac
        }

        get_active_family() {
          if [ -f "$STATE_DIR/family" ]; then
            cat "$STATE_DIR/family"
          else
            get_theme_family "$(get_current_theme)"
          fi
        }

        get_current_theme() {
          if [ -f "$STATE_DIR/active-theme" ]; then
            tr -d '[:space:]' < "$STATE_DIR/active-theme"
          elif [ -f "$ACTIVE_THEME_FILE" ]; then
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
            if [ -f "$HOME/.config/tmux/themes/$target.conf" ]; then
              tmux source-file "$HOME/.config/tmux/themes/$target.conf" 2>/dev/null || true
            fi
          fi

          for search_dir in "''${TMPDIR:-}" "/tmp" "$HOME/.local/state/nvim"; do
            [ -n "$search_dir" ] && [ -d "$search_dir" ] || continue
            while IFS= read -r sock; do
              [ -S "$sock" ] || continue
              nvim --server "$sock" --remote-send '<Cmd>ThemeReload<CR>' 2>/dev/null || true
            done < <(find "$search_dir" -maxdepth 3 -type s \( -name "nvim.*" -o -name "0" \) 2>/dev/null || true)
          done

          killall -USR1 zsh 2>/dev/null || true
        }

        apply_theme() {
          target="$1"
          pol="$2"
          fam="$(get_theme_family "$target")"

          mkdir -p "$STATE_DIR"
          printf '%s' "$target" > "$STATE_DIR/active-theme"
          printf '%s' "$pol" > "$STATE_DIR/polarity"
          printf '%s' "$fam" > "$STATE_DIR/family"

          cat > "$STATE_DIR/env.zsh" <<EOF
    export ACTIVE_THEME="$target"
    export THEME_POLARITY="$pol"
    export NVIM_THEME_POLARITY="$pol"
    EOF
          case "$fam" in
            catppuccin)
              if [ "$pol" = "light" ]; then
                echo 'export BAT_THEME="Catppuccin Latte"' >> "$STATE_DIR/env.zsh"
              else
                echo 'export BAT_THEME="Catppuccin Mocha"' >> "$STATE_DIR/env.zsh"
              fi
              ;;
            gruvbox)
              if [ "$pol" = "light" ]; then
                echo 'export BAT_THEME="gruvbox-light"' >> "$STATE_DIR/env.zsh"
              else
                echo 'export BAT_THEME="gruvbox-dark"' >> "$STATE_DIR/env.zsh"
              fi
              ;;
          esac

          # Alacritty live reloading via imported current-theme.toml
          alacritty_target="$THEMES_DIR/$target.toml"
          alacritty_dest="$HOME/.config/alacritty/current-theme.toml"
          if [ -f "$alacritty_target" ]; then
            mkdir -p "$(dirname "$alacritty_dest")"
            install -m 644 "$alacritty_target" "$alacritty_dest"
          fi

          if [ -f "$ACTIVE_THEME_FILE" ]; then
            printf '"%s"\n' "$target" > "$ACTIVE_THEME_FILE"
          fi

          notify_apps "$target" "$pol"
        }

        CURRENT="$(get_current_theme)"

        case "''${1:-list}" in
          list)
            pol="$(get_polarity "$CURRENT")"
            fam="$(get_active_family)"
            echo "Active Theme:  $CURRENT ($pol mode)"
            echo "Active Family: $fam"
            echo ""
            echo "Available local themes in home/themes/:"
            for f in ${themesDir}/*.yaml; do
              [ -f "$f" ] || continue
              basename "$f" .yaml
            done
            echo ""
            echo "Universal Profile Families:"
            echo "  - catppuccin (mocha / latte)"
            echo "  - gruvbox    (dark / light)"
            echo "  - rose-pine  (rose-pine / rose-pine-dawn)"
            echo "  - tokyo-night"
            echo "  - everforest"
            echo "  - nord"
            echo "  - dracula"
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
            apply_theme "$target" "$pol"
            echo "Switched active theme to '$target' ($pol mode)."
            ;;
          set-family)
            fam="''${2:-}"
            if [ -z "$fam" ]; then
              echo "usage: theme-switch set-family <family-name>" >&2
              exit 1
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
            target="$(get_family_variant "$fam" "$host_mode")"
            apply_theme "$target" "$host_mode"
            echo "Switched active theme family to '$fam' -> '$target' ($host_mode mode)."
            ;;
          toggle-mode)
            pair="$(get_pair "$CURRENT")"
            if [ "$pair" = "$CURRENT" ]; then
              echo "No distinct light/dark pair defined for '$CURRENT'."
            else
              pol="$(get_polarity "$pair")"
              apply_theme "$pair" "$pol"
              echo "Toggled theme mode: '$CURRENT' -> '$pair' ($pol mode)."
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
            current_theme="$(get_current_theme)"
            current_polarity="$(get_polarity "$current_theme")"
            active_fam="$(get_active_family)"
            target_variant="$(get_family_variant "$active_fam" "$host_mode")"

            if [ "$host_mode" != "$current_polarity" ] || [ "$target_variant" != "$current_theme" ]; then
              apply_theme "$target_variant" "$host_mode"
              if [ "$quiet" -eq 0 ]; then
                echo "Host OS mode ($host_mode) applied: '$current_theme' -> '$target_variant'."
              fi
            else
              if [ "$quiet" -eq 0 ]; then
                echo "Theme '$current_theme' ($current_polarity) is already in sync with host OS mode ($host_mode)."
              fi
            fi
            ;;
          *)
            echo "usage: theme-switch {list|set <theme>|set-family <family>|toggle-mode|sync-host}"
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
      # Alacritty colors are decoupled from immutable Stylix to allow live reload via current-theme.toml
      alacritty.enable = false;
      neovim.enable = true;
      tmux.enable = true;
      fzf.enable = true;
      starship.enable = false;
    };
  };

  # Expose pre-generated base16 Alacritty TOML themes
  xdg.configFile."alacritty/themes".source = alacrittyThemes;

  # Background event listener on macOS
  launchd.agents.dark-mode-listener = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [ "${darwinThemeListenerRunner}/bin/darwin-theme-listener" ];
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "${config.home.homeDirectory}/.cache/theme/listener.stdout.log";
      StandardErrorPath = "${config.home.homeDirectory}/.cache/theme/listener.stderr.log";
    };
  };

  # Ensure current-theme.toml exists upon activation
  home.activation.initTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "${config.xdg.configHome}/alacritty"
    if [ ! -f "${config.xdg.configHome}/alacritty/current-theme.toml" ]; then
      if [ -f "${alacrittyThemes}/${active}.toml" ]; then
        install -m 644 "${alacrittyThemes}/${active}.toml" "${config.xdg.configHome}/alacritty/current-theme.toml"
      fi
    fi
  '';

  home.packages = [
    theme-switch
    darwinThemeListenerRunner
  ];

  home.sessionVariables = {
    ACTIVE_THEME = active;
    THEME_POLARITY = themeMeta.polarity;
  };
}
