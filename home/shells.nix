{ config, pkgs, lib, ... }: {
  home.sessionVariables = {

    XDG_CONFIG_HOME = "$HOME/.config";
    XDG_DATA_HOME = "$HOME/.local/share";
    XDG_CACHE_HOME = "$HOME/.cache";

    GPG_TTY = "$TTY";
    LC_CTYPE = "en_US.UTF-8";
    LEDGER_COLOR = "true";
    LESS = "-FRSXM";
    LESSCHARSET = "utf-8";
    EDITOR = "${pkgs.vim}/bin/vim";
    PAGER = "less";
    TERM = "xterm-256color";
    VISUAL = "${pkgs.vim}/bin/vim";
    CLICOLOR = true;

    # Golang Environment Variables
    GO111MODULE = "on";
    GOPATH = "$HOME/go";
    PKG_CONFIG_PATH =
      "${pkgs.openssl_1_1.dev}/lib/pkgconfig:${pkgs.gdal}/lib/pkgconfig";

    # Android SDK Environment Variables
    ANDROID_JAVA_HOME = "${pkgs.jdk.home}";
    ALLOW_NINJA_ENV = true;
    USE_CCACHE = 1;

    # Rust
    RUSTUP_HOME = "$HOME/rustup";
    CARGO_HOME = "$HOME/cargo";

    # OpenSSL, iconv is usually some kind of build dependency
    C_INCLUDE_PATH = "${pkgs.openssl_1_1.dev}/include:${pkgs.libiconv}/include";
    CPLUS_INCLUDE_PATH =
      "${pkgs.openssl_1_1.dev}/include:${pkgs.libiconv}/include";
    LD_LIBRARY_PATH = "${pkgs.openssl_1_1.dev}/lib:${pkgs.libiconv}/lib";
    LIBRARY_PATH = "${pkgs.openssl_1_1.dev}/lib:${pkgs.libiconv}/lib";

    # NodeJS
    NPM_CONFIG_PREFIX = "$HOME/.config/npm";
    NPM_CACHE_PREFIX = "$HOME/.cache/npm";

    PATH =
      "$NPM_CONFIG_PREFIX/bin:$CARGO_HOME:$GOPATH:$HOME/.rbenv/plugins/ruby-build/bin:$HOME/.local/bin:$HOME/google-cloud-sdk/bin:$PATH";

    USE_GKE_GCLOUD_AUTH_PLUGIN = 1; # for kubectl

  };

  home.file.".config/starship.toml".text = ''
    [battery]
    full_symbol = ""
    charging_symbol = ""
    discharging_symbol = ""

    [[battery.display]]
    threshold = 10
    style = "bold red"

    [[battery.display]]
    threshold = 30
    style = "bold yellow"

    [memory_usage]
    disabled = false

    [git_branch]
    symbol = "git "

    [hg_branch]
    symbol = "hg "

    [nix_shell]
    symbol = "nix-shell "
  '';

  home.shellAliases = {
    tf = "terraform";
    switch-yubikey = ''gpg-connect-agent "scd serialno" "learn --force" /bye'';

    # Get public ip directly from a DNS server instead of from some hip
    # whatsmyip HTTP service. https://unix.stackexchange.com/a/81699
    wanip = "dig @resolver4.opendns.com myip.opendns.com +short";
    wanip4 = "dig @resolver4.opendns.com myip.opendns.com +short -4";
    wanip6 =
      "dig @resolver1.ipv6-sandbox.opendns.com AAAA myip.opendns.com +short -6";
  } // lib.optionalAttrs pkgs.stdenv.isDarwin {
    lightswitch =
      "osascript -e  'tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode'";
    restartaudio = "sudo killall coreaudiod";
    loadenv = "set -a; source .env; set +a";
    nixgc = "nix-collect-garbage -d";
    nixq = "nix-env -qaP";
    nixupgrade =
      "sudo -i sh -c 'nix-channel --update && nix-env -iA nixpkgs.nix && launchctl remove org.nixos.nix-daemon && launchctl load /Library/LaunchDaemons/org.nixos.nix-daemon.plist'";
    nixup = "nix-env -u";
    go-cov =
      "go test -coverprofile='coverage.out' ./... && gcov2lcov -infile=coverage.out -outfile=lcov.info";
    nixshow = "nix show-derivation -r";
  };

  programs.starship.enable = true;
  programs.starship.enableBashIntegration = false;
  programs.starship.enableZshIntegration = true;

  programs.tmux = {
    enable = true;

    aggressiveResize = true;
    baseIndex = 1;
    disableConfirmationPrompt = true;
    keyMode = "vi";
    newSession = true;
    secureSocket = false;
    shell = "${pkgs.zsh}/bin/zsh";
    shortcut = "a";
    terminal = "screen-256color";

    plugins = with pkgs.tmuxPlugins; [
      sensible
      yank
      {
        plugin = dracula;
        extraConfig = ''
          # -------------------- Plugins ------------------------
          # -----------------------------------------------------
          set -g @plugin 'tmux-plugins/tpm'
          set -g @plugin 'tmux-plugins/tmux-sensible'
          set -g @plugin 'dracula/tmux'
          set -g @plugin 'tmux-plugins/tmux-resurrect'
          set -g @plugin 'tmux-plugins/tmux-continuum'
          set -g @plugin 'tmux-plugins/tmux-yank'
          set -g @plugin 'nhdaly/tmux-better-mouse-mode'
          set -g @plugin 'dracula/tmux'

          set -g @emulate-scroll-for-no-mouse-alternate-buffer "on"
          set -g @dracula-plugins "cpu-usage ram-usage git"
          set -g @dracula-show-powerline true
          set -g @dracula-show-left-icon session
          set -g @dracula-show-flags true
          set -g @dracula-refresh-rate 10
        '';
      }
    ];

    extraConfig = ''
      bind-key C-b last-window
      set -g history-limit 10000

      # -- display -------------------------------------------------------------------

      set -g base-index 1           # start windows numbering at 1
      setw -g pane-base-index 1     # make pane numbering consistent with windows

      setw -g automatic-rename on   # rename window to reflect current program
      set -g renumber-windows on    # renumber windows when a window is closed

      set -g set-titles on          # set terminal title

      # --------------  Multiple Panes  ----------------------
      # ------------------------------------------------------
      # synchronize all panes in a window
      # don't use control S, too easily confused
      # with navigation key sequences in tmux (show sessions)

      unbind C-S
      bind C-Y set-window-option synchronize-panes

      # Initialize TMUX plugin manager (keep this line at the very bottom of tmux.conf)
      run '$HOME/.tmux/plugins/tpm/tpm'
    '';
  };

  programs.zsh = {

    enable = true;
    enableCompletion = true;
    enableAutosuggestions = true;
    enableSyntaxHighlighting = true;
    completionInit = ''
      autoload bashcompinit && bashcompinit
      autoload -Uz compinit && compinit
      compinit
    '';
    cdpath = [ "." "~" ];
    dotDir = ".config/zsh";

    plugins = [{
      name = "git-extra-commands";
      src = pkgs.fetchFromGitHub {
        owner = "unixorn";
        repo = "git-extra-commands";
        rev = "894ffb9dde1f74ed7a1cccda908830e63ff5d747";
        sha256 = "Tuc6lPYiZWXNjhNpRJqt6V348iMjx3dM8fFq2b1DvCA=";
      };
    }];

    oh-my-zsh = {
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

    history = {
      size = 50000;
      save = 500000;
      ignoreDups = false;
      expireDuplicatesFirst = true;
      share = true;
      extended = true;
    };

    profileExtra = ''
      export GPG_TTY=$(tty)

      if ! pgrep -x "gpg-agent" > /dev/null; then
        ${pkgs.gnupg}/bin/gpgconf --launch gpg-agent
      fi

      source "$HOME/.cargo/env"

      eval "$(rbenv init -)"
    '';

    initExtra = ''
      ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=238'
      setopt HIST_IGNORE_ALL_DUPS

      SPACESHIP_PROMPT_ORDER=(
        time          # Time stampts section
        user          # Username section
        host          # Hostname section
        dir           # Current directory section
        git           # Git section (git_branch + git_status)
        line_sep      # Line break
        jobs          # Backgound jobs indicator
        exit_code     # Exit code section
        char          # Prompt character
      )

      # using ripgrep combined with preview
      # find-in-file - usage: fif <searchTerm>
      function fif {
        if [ ! "$#" -gt 0 ]; then echo "Need a string to search for!"; return 1; fi
        rg --files-with-matches --no-messages "$1" | fzf --preview "highlight -O ansi -l {} 2> /dev/null | rg --colors 'match:bg:yellow' --ignore-case --pretty --context 10 '$1' || rg --ignore-case --pretty --context 10 '$1' {}"
      }

      function ls {
        ${pkgs.coreutils}/bin/ls --color=auto --group-directories-first "$@"
      }

      function optimize-screen-record {
        filename=$1
        mov_file="''${filename%.*}.mov"
        mp4_file="''${filename%.*}.mp4"
        ${pkgs.ffmpeg}/bin/ffmpeg -i $mov_file -c:v libx265 -an -x265-params crf=25 $mp4_file
        ${pkgs.ffmpeg}/bin/ffmpeg -i $mp4_file -filter_complex "[0:v]setpts=0.5*PTS[v];[0:a]atempo=2[a]" -map "[v]" -map "[a]" $mp4_file
      }

      function create_cacert {
        domain=$1
        echo -n | ${pkgs.openssl} s_client -servername $domain -connect $domain:443 2>/dev/null | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > $domain.pem
      }

      function export_cloudsmith_onx {
        export CLOUDSMITH_TOKEN=$(gcloud --project=onx-ci secrets versions access latest --secret="cloudsmith_adam-williams");
        export CARGO_REGISTRIES_CLOUDSMITH_INDEX="sparse+https://dl.cloudsmith.io/$CLOUDSMITH_TOKEN/onxmaps-6aJ/onx-backend-api/cargo/"
      }

      function mk_favicon {
        set -u
        if test -d $2; then
          convert -resize x16 -gravity center -background transparent -extent 16x16 "$1" "$2/favicon-16x16.ico"
          convert -resize x32 -gravity center -background transparent -extent 32x32 "$1" "$2/favicon-32x32.ico"
          convert -resize x64 -gravity center -background transparent -extent 64x64 "$1" "$2/favicon-64x64.ico"
        fi
      }

      # secrets
      [[ -f "$HOME/.env" ]] && source "$HOME/.env"

      autoload -U promptinit; promptinit
    '';

  };

}
