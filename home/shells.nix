{ config, pkgs, lib, ... }:
let inherit (config.home) user-info;
in {

  home.sessionVariables = {
    # XDG locations
    XDG_CONFIG_HOME = config.xdg.configHome;
    XDG_DATA_HOME = config.xdg.dataHome;
    XDG_CACHE_HOME = config.xdg.cacheHome;

    # Secrets / crypto
    PASSWORD_STORE_DIR = "${config.xdg.dataHome}/password-store";
    KEY_ID =
      if user-info.gpg.masterKey == null then "" else user-info.gpg.masterKey;

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

    # Local bin
    LOCAL_BIN = "$HOME/.local/bin";
    CUDA_HOME = "/usr/local/cuda";
    PYENV_HOME = "$HOME/.pyenv";
    CUDA_TOOLKIT_ROOT = "/usr/local/cuda";

    # Elixir
    ELIXIR_PATH = "$HOME/.mix/escripts";

    # Golang Environment Variables
    GO111MODULE = "on";
    GOPATH = "$HOME/go";

    # Android SDK Environment Variables
    ANDROID_JAVA_HOME = "${pkgs.jdk.home}";
    ALLOW_NINJA_ENV = "true";
    USE_CCACHE = 1;

    # Rust
    RUSTUP_HOME = "$HOME/.rustup";
    CARGO_HOME = "$HOME/.cargo";
    CODEX_HOME = "${config.xdg.configHome}/codex";

    # Amazon Web Services
    AWS_CONFIG_FILE = "${config.xdg.configHome}/aws/config";
    AWS_SHARED_CREDENTIALS_FILE = "${config.xdg.configHome}/aws/credentials";
    AWS_SSO_SESSION_CACHE_DIR = "${config.xdg.cacheHome}/aws/sso/cache";
    AWS_VAULT_PASS_CMD = "${pkgs.pass}/bin/pass";

    # Prefer nix-provided tools (e.g., gnupg) ahead of system binaries to avoid version skew.
    PATH =
      "$LOCAL_BIN:$PYENV_HOME/shims:$PYENV_HOME/bin:$CUDA_HOME/bin:$ELIXIR_PATH:$CARGO_HOME/bin:$GOPATH/bin:$RBENV_ROOT/plugins/ruby-build/bin:$HOME/google-cloud-sdk/bin:$PATH";
  };

  xdg.configFile = {
    "git/personal.gitconfig" = {
      text = ''
        [user]
          email = "${user-info.email}"
      '';
    };
  } // lib.optionalAttrs (user-info.work.email != null) {
    # gpg signing key for work
    "git/work.gitconfig" = {
      text = ''
        [user]
          email = "${user-info.work.email}"
      '';
    };
  };

  home.shellAliases = {
    terraform = "tofu";
    tf = "tofu";
    switch-yubikey = ''gpg-connect-agent "scd serialno" "learn --force" /bye'';

    # Get public ip directly from a DNS server instead of from some hip
    # whatsmyip HTTP service. https://unix.stackexchange.com/a/81699
    wanip = "dig @resolver4.opendns.com myip.opendns.com +short";
    wanip4 = "dig @resolver4.opendns.com myip.opendns.com +short -4";
    wanip6 =
      "dig @resolver1.ipv6-sandbox.opendns.com AAAA myip.opendns.com +short -6";

    git-prune-local =
      "git fetch -p && git branch -vv | awk '/: gone]/{print $1}' | xargs git branch -D";
  } // lib.optionalAttrs pkgs.stdenv.isDarwin {
    lightswitch =
      "osascript -e  'tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode'";
    restartaudio = "sudo killall coreaudiod";
  };

  programs.starship.enable = true;
  programs.starship.enableBashIntegration = false;
  programs.starship.enableZshIntegration = true;

  #
  # BASH
  #

  programs.bash.enable = false;
  programs.bash.enableCompletion = true;
  programs.bash.bashrcExtra = "";

  #
  # ZSH
  #

  programs.zsh.enable = true;
  programs.zsh.enableCompletion = true;
  programs.zsh.autosuggestion.enable = true;
  programs.zsh.syntaxHighlighting.enable = true;
  programs.zsh.completionInit = ''
    autoload bashcompinit && bashcompinit
    autoload -Uz compinit && compinit
    compinit
  '';
  programs.zsh.cdpath = [ "." "~" ];
  # Use absolute XDG path to avoid deprecation warning about relative dotDir
  programs.zsh.dotDir = "${config.xdg.configHome}/zsh";
  programs.zsh.plugins = [{
    name = "git-extra-commands";
    src = pkgs.fetchFromGitHub {
      owner = "unixorn";
      repo = "git-extra-commands";
      rev = "10163075bd97a49d74c510283a9d7b4fe9e123e1";
      sha256 = "sha256-uc0zODi02X6a6igTpqSCxLzg7dh3W8ePzZG0+EesTc0=";
    };
  }];
  programs.zsh.history = {
    size = 50000;
    save = 500000;
    expireDuplicatesFirst = true;
    ignoreDups = true;
    share = true;
    extended = true;
  };
  programs.zsh.oh-my-zsh = {
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
  programs.zsh.initContent = ''
    export GPG_TTY="$(${pkgs.coreutils}/bin/tty)"
    export SSH_AUTH_SOCK="''${SSH_AUTH_SOCK:-$(${pkgs.gnupg}/bin/gpgconf --list-dirs agent-ssh-socket)}"

    # Auto-init password-store with YubiKey-backed key if missing
    if command -v ${pkgs.pass}/bin/pass >/dev/null 2>&1; then
      if [ ! -f "''${PASSWORD_STORE_DIR}/.gpg-id" ] && [ -n "''${KEY_ID:-}" ]; then
        mkdir -p "''${PASSWORD_STORE_DIR}"
        ${pkgs.pass}/bin/pass init "''${KEY_ID}"
      fi
    fi

    function ls() {
      ${pkgs.coreutils}/bin/ls --color=auto --group-directories-first "$@"
    }

    # Pipe GitHub token into nix only when it's available in the environment.
    if [[ -n "''${GITHUB_TOKEN:-}" ]]; then
      _codex_nix_token="access-tokens=github.com=''${GITHUB_TOKEN}"
      if [[ -n "''${NIX_CONFIG:-}" ]]; then
        export NIX_CONFIG="$NIX_CONFIG"$'\n'"$_codex_nix_token"
      else
        export NIX_CONFIG="$_codex_nix_token"
      fi
      unset _codex_nix_token
    fi

    # Convert screen recording to optimized GIF for web/GitHub
    # Optimized for text readability and smaller file sizes
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
      
      # Screen recording optimized conversion
      # - Higher quality palette for text clarity
      # - Lower FPS to reduce file size for screen recordings
      # - Optimized for sharp text and UI elements
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

    if test -f $HOME/.env; then
      source $HOME/.env;
    fi

    autoload -U promptinit; promptinit
  '';

  # Ensure crypto directories exist with proper permissions before shells run.
  home.activation.ensureCryptoDirs =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      set -euo pipefail
      mkdir -p "${config.xdg.dataHome}/gnupg" "${config.xdg.dataHome}/password-store" "${config.xdg.configHome}/gpg"
      chmod 700 "${config.xdg.dataHome}/gnupg" "${config.xdg.dataHome}/password-store" "${config.xdg.configHome}/gpg"
    '';
}
