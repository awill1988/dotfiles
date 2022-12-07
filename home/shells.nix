{ config, pkgs, lib, ... }: {
  home.sessionVariables = {
    LC_CTYPE = "en_US.UTF-8";
    LEDGER_COLOR = "true";
    LESS = "-FRSXM";
    LESSCHARSET = "utf-8";
    TERM = "xterm-256color";
    VISUAL = "vim";
    CLICOLOR = true;
    GPG_TTY = "$TTY";
    PATH = "$PATH:$HOME/.local/bin";
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
  };
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

      # -------------------- Plugins ------------------------
      # -----------------------------------------------------
      set -g @plugin 'tmux-plugins/tpm'
      set -g @plugin 'tmux-plugins/tmux-sensible'
      set -g @plugin 'dracula/tmux'
      set -g @plugin 'tmux-plugins/tmux-resurrect'
      set -g @plugin 'tmux-plugins/tmux-continuum'
      set -g @plugin 'tmux-plugins/tmux-yank'
      set -g @plugin 'nhdaly/tmux-better-mouse-mode'
      set -g @emulate-scroll-for-no-mouse-alternate-buffer "on"
      set -g @plugin 'dracula/tmux'
      set -g @dracula-plugins "cpu-usage ram-usage git"
      set -g @dracula-show-powerline true
      set -g @dracula-show-left-icon session
      set -g @dracula-show-flags true

      # Initialize TMUX plugin manager (keep this line at the very bottom of tmux.conf)
      run 'plugins/tpm/tpm'
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
        "thefuck"
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

    sessionVariables = {
      LC_CTYPE = "en_US.UTF-8";
      LEDGER_COLOR = "true";
      LESS = "-FRSXM";
      LESSCHARSET = "utf-8";
      EDITOR = "vim";
      PAGER = "less";
      TERM = "xterm-256color";
      VISUAL = "vim";
      PKG_CONFIG_PATH =
        "$PKG_CONFIG_PATH:${pkgs.openssl_1_1.dev}/lib/pkgconfig";
    };

    shellAliases = {
      loadenv = "set -a; source .env; set +a";
      nixre = "darwin-rebuild switch";
      nixgc = "nix-collect-garbage -d";
      nixq = "nix-env -qaP";
      nixupgrade =
        "sudo -i sh -c 'nix-channel --update && nix-env -iA nixpkgs.nix && launchctl remove org.nixos.nix-daemon && launchctl load /Library/LaunchDaemons/org.nixos.nix-daemon.plist'";
      nixup = "nix-env -u";
      go-cov =
        "go test -coverprofile='coverage.out' ./... && gcov2lcov -infile=coverage.out -outfile=lcov.info";
      nixshow = "nix show-derivation -r";
    };

    initExtra = ''
        ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=238'
        setopt HIST_IGNORE_ALL_DUPS
        eval $(thefuck --alias)

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
        fif() {
          if [ ! "$#" -gt 0 ]; then echo "Need a string to search for!"; return 1; fi
          rg --files-with-matches --no-messages "$1" | fzf --preview "highlight -O ansi -l {} 2> /dev/null | rg --colors 'match:bg:yellow' --ignore-case --pretty --context 10 '$1' || rg --ignore-case --pretty --context 10 '$1' {}"
        }

      function ls() {
          ${pkgs.coreutils}/bin/ls --color=auto --group-directories-first "$@"
      }
      autoload -U promptinit; promptinit
    '';

    profileExtra = ''
          export GPG_TTY=$(tty)
          if ! pgrep -x "gpg-agent" > /dev/null; then
      	${pkgs.gnupg}/bin/gpgconf --launch gpg-agent
          fi

    '';
  };

  programs.starship.enable = true;
  programs.starship.enableZshIntegration = true;
}
