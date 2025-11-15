{ config, pkgs, lib, ... }:
let inherit (config.home) user-info;
in {

  home.sessionVariables = {
    GPG_TTY = "$TTY";
    LC_CTYPE = "en_US.UTF-8";
    LEDGER_COLOR = "true";
    LESS = "-FRSXM";
    LESSCHARSET = "utf-8";
    EDITOR = "${pkgs.vim}/bin/vim";
    PAGER = "${pkgs.less}/bin/less";
    TERM = "xterm-256color";
    VISUAL = "${pkgs.vim}/bin/vim";
    CLICOLOR = "true";

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

    PATH =
      "$LOCAL_BIN:$PYENV_HOME/shims:$PYENV_HOME/bin:$CUDA_HOME/bin:$LOCAL_BIN:$ELIXIR_PATH:$CARGO_HOME/bin:$GOPATH/bin:$HOME/.rbenv/plugins/ruby-build/bin:$HOME/google-cloud-sdk/bin:$PATH";

    USE_GKE_GCLOUD_AUTH_PLUGIN = 1; # for kubectl
  };

  xdg.configFile."git/personal.gitconfig" = {
    text = ''
      [commit]
        gpgSign = true
        verbose = true
      [tag]
        gpgSign = true
      [user]
        email = "${user-info.email}"
        signingkey = "${user-info.email}"
    '';
  };

  # gpg signing key for work
  xdg.configFile."git/work.gitconfig" = {
    text = ''
      [user]
        email = "${user-info.work.email}"
        signingkey = "${user-info.work.email}"
    '';
  };

  #
  # STARSHIP
  #
  xdg.configFile."starship.toml" = { text = builtins.readFile ./starship.toml; };

  home.shellAliases = {
    tf = "terraform";
    switch-yubikey = ''gpg-connect-agent "scd serialno" "learn --force" /bye'';

    # Get public ip directly from a DNS server instead of from some hip
    # whatsmyip HTTP service. https://unix.stackexchange.com/a/81699
    wanip = "dig @resolver4.opendns.com myip.opendns.com +short";
    wanip4 = "dig @resolver4.opendns.com myip.opendns.com +short -4";
    wanip6 =
      "dig @resolver1.ipv6-sandbox.opendns.com AAAA myip.opendns.com +short -6";
    git-prune-local =
      "git fetch -p && git branch -vv | awk '/: gone]/{print $1}' | xargs git branch -D";
    codeenv = "[ -f ${config.xdg.configHome}/codeenv.env ] && export $(grep -v '^#' ${config.xdg.configHome}/codeenv.env | xargs); code .";
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
  programs.zsh.profileExtra = ''
    export GPG_TTY=$(tty)
  '';
  programs.zsh.initContent = ''
    function ls() {
      ${pkgs.coreutils}/bin/ls --color=auto --group-directories-first "$@"
    }

    # Decrypt token: hex = IV(24 hex) + CT + TAG(32 hex). Key = base64 or hex.
    decrypt_oidc_token_hex() {
      local token_hex="''${1:-''$TOKEN_HEX}"
      local key_in="''${2:-''$CIPHER_KEY}"

      if [[ -z "''$token_hex" || -z "''$key_in" ]]; then
        echo "Usage: decrypt_oidc_token_hex <hex_token> <base64|hex_key>"
        return 1
      fi

      # Normalize key (hex lengths 32/48/64 OR base64)
      local key_hex
      if [[ "''$key_in" =~ ^[0-9a-fA-F]+$ ]] && [[ "''${#key_in}" =~ ^(32|48|64)$ ]]; then
        key_hex="''$key_in"
      else
        local pad=$(( (4 - ''${#key_in} % 4) % 4 ))
        if (( pad > 0 )); then
          key_in="''$key_in$(printf '=%.0s' $(seq 1 $pad))"
        fi
        if ! key_hex="$(echo -n "''$key_in" | ${pkgs.coreutils}/bin/base64 -d 2>/dev/null | ${pkgs.xxd}/bin/xxd -p -c256)"; then
          echo "Key decode failed"
          return 1
        fi
      fi

      local key_len_bytes=$(( ''${#key_hex} / 2 ))
      local algo
      case "''$key_len_bytes" in
        16) algo="aes-128-gcm" ;;
        24) algo="aes-192-gcm" ;;
        32) algo="aes-256-gcm" ;;
        *) echo "Unsupported key size: ''$key_len_bytes"; return 1 ;;
      esac

      # Compute lengths & extract slices using cut/sed to remain fully zsh-safe.
      local token_len=$(( ''${#token_hex} ))
      if (( token_len < 24 + 32 )); then
        echo "Token too short"
        return 1
      fi
      local iv_hex="''${token_hex:0:24}"
      local ct_end=$(( token_len - 32 ))  # last 32 hex chars are the tag
      local ct_len=$(( ct_end - 24 ))
      if (( ct_len <= 0 )); then
        echo "Malformed token"
        return 1
      fi
      # Use cut with 1-based indices: IV spans 1-24, CT spans 25-ct_end, TAG spans ct_end+1-token_len
      local ct_hex="$(echo "''$token_hex" | cut -c $((24+1))-$ct_end)"
      local tag_hex="$(echo "''$token_hex" | cut -c $((ct_end+1))-$token_len)"

      if [[ -n "''$DECRYPT_DEBUG" ]]; then
        echo "Algo: ''$algo  KeyBytes: ''$key_len_bytes"
        echo "IV(24): ''$iv_hex"
        echo "CT(hex) len: ''$ct_len"
        echo "TAG(32): ''$tag_hex"
        echo "Token total len: ''$token_len"
      fi

      local ct_file
      ct_file="$(mktemp)"
      echo -n "''$ct_hex" | ${pkgs.xxd}/bin/xxd -r -p > "''$ct_file"

      if ! ${pkgs.openssl}/bin/openssl enc -"''$algo" -d -in "''$ct_file" \
           -K "''$key_hex" -iv "''$iv_hex" -tag "''$tag_hex" -nosalt; then
        echo "Decryption failed"
        rm -f "''$ct_file"
        return 1
      fi
      rm -f "''$ct_file"
    }

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

  home.activation.createWslSymlinks =
    lib.optionalString (!pkgs.stdenv.isDarwin) ''
      if [ ! -L "$HOME/.local/bin/gpg" ]; then
        ln -s /mnt/c/Program\ Files\ \(x86\)/GnuPG/bin/gpg.exe $HOME/.local/bin/gpg
      fi
    '';

  home.packages = with pkgs; [ pure-prompt ];
}
