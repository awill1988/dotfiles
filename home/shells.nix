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
    LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";

    # OpenSSL, iconv is usually some kind of build dependency
    PKG_CONFIG_PATH =
      "${pkgs.openssl.dev}/lib/pkgconfig:${pkgs.gdal}/lib/pkgconfig";
    C_INCLUDE_PATH = "${pkgs.openssl.dev}/include:${pkgs.libiconv}/include";
    CPLUS_INCLUDE_PATH = "${pkgs.openssl.dev}/include:${pkgs.libiconv}/include";
    LD_LIBRARY_PATH = "${pkgs.openssl.dev}/lib:${pkgs.libiconv}/lib";
    LIBRARY_PATH = "${pkgs.openssl.dev}/lib:${pkgs.libiconv}/lib";

    PATH =
      "$LOCAL_BIN:$ELIXIR_PATH:$CARGO_HOME/bin:$GOPATH/bin:$HOME/.rbenv/plugins/ruby-build/bin:$HOME/.local/bin:$HOME/google-cloud-sdk/bin:$PATH";

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
  xdg.configFile."starship.toml" = { text = builtins.readFile ./jetpack.toml; };

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
  programs.zsh.dotDir = ".config/zsh";
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
  programs.zsh.initExtra = ''
    function ls() {
      ${pkgs.coreutils}/bin/ls --color=auto --group-directories-first "$@"
    }

    if test -f $HOME/.env; then
      source $HOME/.env;
    fi

    autoload -U promptinit; promptinit
  '';

  home.activation.createWslSymlinks =
    lib.optionalString (!pkgs.stdenv.isDarwin) ''
      if [ ! -L "$HOME/.local/bin/ssh" ]; then
        ln -s /mnt/c/Windows/System32/OpenSSH/ssh.exe $HOME/.local/bin/ssh
      fi
      if [ ! -L "$HOME/.local/bin/ssh-add" ]; then
        ln -s /mnt/c/Windows/System32/OpenSSH/ssh-add.exe $HOME/.local/bin/ssh-add
      fi
      if [ ! -L "$HOME/.local/bin/scp" ]; then
        ln -s /mnt/c/Windows/System32/OpenSSH/scp.exe $HOME/.local/bin/scp
      fi
      if [ ! -L "$HOME/.local/bin/gpg" ]; then
        ln -s /mnt/c/Program\ Files\ \(x86\)/GnuPG/bin/gpg.exe $HOME/.local/bin/gpg
      fi
    '';

  home.packages = with pkgs; [ pure-prompt ];
}
