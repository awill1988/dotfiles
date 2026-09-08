{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.modules.terminal.shell;
  resolvedProfilesList = attrValues config.developer.resolvedProfiles;
  primaries = filter (p: p.isPrimary) resolvedProfilesList;
  primaryProfile =
    if primaries != [ ] then
      head primaries
    else if resolvedProfilesList != [ ] then
      head resolvedProfilesList
    else
      null;
  font_family = config.ext.fonts.monospace_family;
in
{
  options.modules.terminal.shell = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Zsh, oh-my-zsh, Starship, Alacritty, and shell environment.";
    };
  };

  config = mkIf cfg.enable {
    programs = {
      alacritty = {
        enable = true;
        settings = {
          window = {
            padding.x = 12;
            padding.y = 12;
            dynamic_title = true;
            opacity = 0.9;
            option_as_alt = "Both";
          };
          general.working_directory = "${config.home.homeDirectory}/projects";
          scrolling.history = 10000;
          keyboard.bindings = [
            {
              key = "Q";
              mods = "Control";
              chars = "\\u0011";
            }
          ];
          terminal.shell = {
            program = "${pkgs.zsh}/bin/zsh";
            args = [ "-l" ];
          };
          font = {
            normal = {
              family = font_family;
              style = "Regular";
            };
            bold = {
              family = font_family;
              style = "Bold";
            };
            italic = {
              family = font_family;
              style = "Italic";
            };
            bold_italic = {
              family = font_family;
              style = "Bold Italic";
            };
          };
        };
      };

      starship = {
        enable = true;
        enableBashIntegration = false;
        enableZshIntegration = true;
      };

      bash = {
        enable = false;
        enableCompletion = true;
        bashrcExtra = "";
      };

      zsh = {
        enable = true;
        enableCompletion = true;
        autosuggestion.enable = true;
        syntaxHighlighting.enable = true;
        completionInit = ''
          autoload bashcompinit && bashcompinit
          autoload -Uz compinit && compinit
          compinit
        '';
        cdpath = [
          "."
          "~"
        ];
        dotDir = "${config.xdg.configHome}/zsh";
        plugins = [
          {
            name = "git-extra-commands";
            src = pkgs.fetchFromGitHub {
              owner = "unixorn";
              repo = "git-extra-commands";
              rev = "4d39286f349a7f50171829f06da77c5097b41f9d";
              sha256 = "sha256-Dr9fOhVKrd3+t7dMBHX5PCRCwkeblAc9t2F/vvWiHc0=";
            };
          }
        ];
        history = {
          size = 50000;
          save = 500000;
          expireDuplicatesFirst = true;
          ignoreDups = true;
          share = true;
          extended = true;
        };
        oh-my-zsh = {
          enable = true;
          plugins = [
            "sudo"
            "gcloud"
            "rust"
            "docker"
            "docker-compose"
            "git"
            "python"
            "pip"
            "command-not-found"
            "npm"
            "golang"
            "history-substring-search"
            "tmux"
          ];
        };
        initContent = ''
          if [ -t 0 ]; then
            export GPG_TTY="$(${pkgs.coreutils}/bin/tty 2>/dev/null || true)"
          fi
          export SSH_AUTH_SOCK="''${SSH_AUTH_SOCK:-$(${pkgs.gnupg}/bin/gpgconf --list-dirs agent-ssh-socket 2>/dev/null || true)}"

          if command -v theme-switch >/dev/null 2>&1; then
            theme-switch sync-host --quiet 2>/dev/null || true
          fi

          if [ -t 0 ] && command -v ${pkgs.pass}/bin/pass >/dev/null 2>&1; then
            if [ -n "''${PASSWORD_STORE_DIR:-}" ] && [ ! -f "''${PASSWORD_STORE_DIR}/.gpg-id" ] && [ -n "''${KEY_ID:-}" ]; then
              mkdir -p "''${PASSWORD_STORE_DIR}"
              ${pkgs.pass}/bin/pass init "''${KEY_ID}" || true
            fi
          fi

          function ls() {
            ${pkgs.coreutils}/bin/ls --color=auto --group-directories-first "$@"
          }

          function trim_history() {
            local trim_count="''${1:-10}"
            local total keep tmp_file

            if [[ ! "$trim_count" =~ ^[0-9]+$ ]] || (( trim_count < 1 )); then
              echo "usage: trim_history [line_count]"
              return 1
            fi

            if [[ -z "''${HISTFILE:-}" ]]; then
              echo "histfile is not set"
              return 1
            fi

            fc -W || return 1

            if [[ ! -f "$HISTFILE" ]]; then
              echo "histfile does not exist: $HISTFILE"
              return 1
            fi

            total="$(${pkgs.coreutils}/bin/wc -l < "$HISTFILE")"
            keep=$(( total - trim_count ))
            tmp_file="$(${pkgs.coreutils}/bin/mktemp "''${HISTFILE}.XXXXXX")" || return 1

            if (( keep > 0 )); then
              ${pkgs.coreutils}/bin/head -n "$keep" "$HISTFILE" > "$tmp_file" || return 1
            else
              : > "$tmp_file"
            fi

            ${pkgs.coreutils}/bin/mv "$tmp_file" "$HISTFILE"
            fc -R
          }

          if [[ -n "''${GITHUB_TOKEN:-}" ]]; then
            _codex_nix_token="access-tokens = github.com=''${GITHUB_TOKEN}"
            if [[ -n "''${NIX_CONFIG:-}" ]]; then
              export NIX_CONFIG="$NIX_CONFIG"$'\n'"$_codex_nix_token"
            else
              export NIX_CONFIG="$_codex_nix_token"
            fi
            unset _codex_nix_token
          fi

          function vid2gif() {
            local input="$1"
            local output="''${2:-$(basename "$input" | sed 's/\.[^.]*$/.gif/')}"
            local width="''${3:-800}"
            
            if [[ -z "$input" ]]; then
              echo "Usage: vid2gif input.mp4 [output.gif] [width]"
              echo "Optimized for screen recordings with text"
              return 1
            fi
            
            echo "Converting $input to $output (width: $width px)..."
            
            ${pkgs.ffmpeg}/bin/ffmpeg -i "$input" \
              -vf "fps=10,scale=$width:-1:flags=neighbor,split[s0][s1];[s0]palettegen=max_colors=64:reserve_transparent=1[p];[s1][p]paletteuse=dither=bayer:bayer_scale=2" \
              -loop 0 "$output"
            
            if [[ $? -eq 0 ]]; then
              local size=$(du -h "$output" | cut -f1)
              echo "✅ Created: $output ($size)"
            else
              echo "❌ Conversion failed"
              return 1
            fi
          }

          if test -f "$HOME/.env"; then
            set -a
            source "$HOME/.env"
            set +a
          fi

          function tf() {
            if [[ -n "''${AWS_PROFILE:-}" ]]; then
              aws-vault exec "''${AWS_PROFILE}" -- tofu "$@"
            else
              tofu "$@"
            fi
          }

          autoload -U promptinit; promptinit

          function git-prune-local() {
            local dry_run=true

            for arg in "$@"; do
              case "$arg" in
                --dry-run)    dry_run=true ;;
                --no-dry-run) dry_run=false ;;
                *)
                  echo "usage: git-prune-local [--dry-run|--no-dry-run]"
                  return 1
                  ;;
              esac
            done

            git fetch --prune

            local branches
            branches="$(git branch -vv | awk '/: gone]/{print $1}')"

            if [[ -z "$branches" ]]; then
              echo "no stale local branches found"
              return 0
            fi

            if [[ "$dry_run" == true ]]; then
              echo "[dry-run] branches that would be deleted:"
              echo "$branches"
              echo ""
              echo "run with --no-dry-run to delete"
            else
              echo "deleting stale local branches:"
              echo "$branches"
              echo "$branches" | xargs git branch -D
            fi
          }
        '';
      };
    };

    home.sessionVariables = {
      XDG_CONFIG_HOME = config.xdg.configHome;
      XDG_DATA_HOME = config.xdg.dataHome;
      XDG_CACHE_HOME = config.xdg.cacheHome;
      PASSWORD_STORE_DIR = "${config.xdg.dataHome}/password-store";
      KEY_ID =
        if primaryProfile != null && primaryProfile.identity.signingKey != null then
          primaryProfile.identity.signingKey
        else
          "";
      LC_CTYPE = "en_US.UTF-8";
      LEDGER_COLOR = "true";
      LESS = "-FRSXM";
      LESSCHARSET = "utf-8";
      EDITOR = "${pkgs.vim}/bin/vim";
      PAGER = "${pkgs.less}/bin/less";
      TERM = "xterm-256color";
      VISUAL = "${pkgs.vim}/bin/vim";
      CLICOLOR = "true";
      RBENV_ROOT = "$HOME/.rbenv";
      RBENV_SHELL = "zsh";
      LOCAL_BIN = "$HOME/.local/bin";
      PYENV_HOME = "$HOME/.pyenv";
      ELIXIR_PATH = "$HOME/.mix/escripts";
      GO111MODULE = "on";
      GOPATH = "$HOME/go";
      ANDROID_HOME = if pkgs.stdenv.isDarwin then "$HOME/Library/Android/sdk" else "$HOME/Android/Sdk";
      ANDROID_JAVA_HOME = "${pkgs.jdk.home}";
      ALLOW_NINJA_ENV = "true";
      USE_CCACHE = 1;
      RUSTUP_HOME = "${config.xdg.dataHome}/rustup";
      CARGO_HOME = "${config.xdg.dataHome}/cargo";
      MISE_DATA_DIR = "${config.xdg.dataHome}/mise";
      MISE_CACHE_DIR = "${config.xdg.cacheHome}/mise";
      MISE_STATE_DIR = "${config.xdg.stateHome}/mise";
      CP_HOME_DIR = "${config.xdg.dataHome}/cocoapods";
      AWS_CONFIG_FILE = "${config.xdg.configHome}/aws/config";
      AWS_SHARED_CREDENTIALS_FILE = "${config.xdg.configHome}/aws/credentials";
      AWS_SSO_SESSION_CACHE_DIR = "${config.xdg.cacheHome}/aws/sso/cache";
      AWS_VAULT_PASS_CMD = "${pkgs.pass}/bin/pass";
      PATH = "$LOCAL_BIN:/opt/homebrew/bin:/opt/homebrew/sbin:$PYENV_HOME/shims:$PYENV_HOME/bin:$ELIXIR_PATH:$GOPATH/bin:$RBENV_ROOT/plugins/ruby-build/bin:$HOME/google-cloud-sdk/bin:$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$PATH:$CARGO_HOME/bin";
    };

    home.shellAliases = {
      terraform = "tofu";
      switch-yubikey = ''gpg-connect-agent "scd serialno" "learn --force" /bye'';
      wanip = "dig @resolver4.opendns.com myip.opendns.com +short";
      wanip4 = "dig @resolver4.opendns.com myip.opendns.com +short -4";
      wanip6 = "dig @resolver1.ipv6-sandbox.opendns.com AAAA myip.opendns.com +short -6";
      mlx-serve-r1 = "source ~/.local/share/mlx-env/bin/activate && mlx_lm.server --model mlx-community/DeepSeek-R1-Distill-Qwen-32B-4bit --port 8082";
      mlx-serve-qwen = "source ~/.local/share/mlx-env/bin/activate && mlx_lm.server --model mlx-community/Qwen2.5-Coder-32B-Instruct-4bit --port 8082";
      mlx-setup-env = "source ~/.local/share/mlx-env/bin/activate && python3 -c 'import mlx_lm; print(\"Pre-loading DeepSeek-R1...\"); mlx_lm.load(\"mlx-community/DeepSeek-R1-Distill-Qwen-32B-4bit\"); print(\"Pre-loading Qwen-2.5-Coder...\"); mlx_lm.load(\"mlx-community/Qwen2.5-Coder-32B-Instruct-4bit\")'";
    }
    // optionalAttrs pkgs.stdenv.isDarwin {
      lightswitch = "osascript -e  'tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode'";
      restartaudio = "sudo killall coreaudiod";
    };

    home.activation.ensureCryptoDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      set -euo pipefail
      mkdir -p "${config.xdg.dataHome}/gnupg" "${config.xdg.dataHome}/password-store" "${config.xdg.configHome}/gpg"
      chmod 700 "${config.xdg.dataHome}/gnupg" "${config.xdg.dataHome}/password-store" "${config.xdg.configHome}/gpg"
    '';

    home.activation.setupLocalMlx = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      set -euo pipefail
      MLX_ENV="$HOME/.local/share/mlx-env"
      if [[ ! -d "$MLX_ENV" ]]; then
        echo "seeding local mlx-lm virtual environment..."
        ${pkgs.python3}/bin/python3 -m venv "$MLX_ENV"
        "$MLX_ENV/bin/pip" install -U mlx-lm
      fi
    '';
  };
}
