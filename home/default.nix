{ config, pkgs, lib, ... }:
let
  ca-bundle_crt = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

in
rec {
  imports = [
    ./newsboat.nix
  ];

  home = {
    stateVersion = "20.09";

    sessionVariables = {
      EDITOR = "${pkgs.vim}/bin/vim";
      PAGER = "${pkgs.less}/bin/less";
    };

    packages = with pkgs; [
      cacert
      cachix
      coreutils
      curl
      fd
      findutils
      getopt
      gnumake
      gnupg
      go
      gpgme
      gtypist
      htop
      jq
      less
      newsboat
      nixpkgs-fmt
      nodePackages.node2nix
      nodePackages.vim-language-server
      pass
      plantuml
      pure-prompt
      pywal
      renameutils
      ripgrep
      rsync
      taskwarrior
      tree
      universal-ctags
      urlscan
      vim
      vim-vint
      w3m
      weechat
      wget
    ] ++ lib.optionals stdenv.isDarwin [
      darwin-zsh-completions
    ];
  };

  programs = {

    home-manager = { enable = true; };

    browserpass = {
      enable = true;
      browsers = [ "firefox" ];
    };

    direnv = {
      enable = true;
      enableNixDirenvIntegration = true;
    };

    dircolors = {
      enable = true;
      enableZshIntegration = true;
    };

    zsh = rec {
      enable = true;

      cdpath = [
        "."
        "~"
      ];
      defaultKeymap = "viins";
      dotDir = ".config/zsh";

      history = {
        size = 50000;
        save = 500000;
        ignoreDups = true;
        share = true;
      };

      sessionVariables = {
        CLICOLOR = true;
        GPG_TTY = "$TTY";
        GOPATH = "$(go env GOPATH)";
        PATH = "$PATH:$HOME/.local/bin:$GOPATH/bin:$HOME/.cargo/bin";
      };

      shellAliases = {
        tf = "terraform";
        restartaudio = "sudo killall coreaudiod";
      };

      profileExtra = ''
        export GPG_TTY=$(tty)

        if ! pgrep -x "gpg-agent" > /dev/null; then
            ${pkgs.gnupg}/bin/gpgconf --launch gpg-agent
        fi
      '';

      initExtra = ''
        export KEYTIMEOUT=1

        vi-search-fix() {
          zle vi-cmd-mode
          zle .vi-history-search-backward
        }
        autoload vi-search-fix
        zle -N vi-search-fix
        bindkey -M viins '\e/' vi-search-fix

        bindkey "^?" backward-delete-char

        resume() {
          fg
          zle push-input
          BUFFER=""
          zle accept-line
        }
        zle -N resume
        bindkey "^Z" resume

        ls() {
            ${pkgs.coreutils}/bin/ls --color=auto --group-directories-first "$@"
        }

        # Configure pure-promt
        autoload -U promptinit; promptinit
        prompt pure
        zstyle :prompt:pure:prompt:success color green

        # The next line updates PATH for the Google Cloud SDK.
        if [ -f '/Users/martin/bin/google-cloud-sdk/path.zsh.inc' ]; then
          . '/Users/martin/.local/bin/google-cloud-sdk/path.zsh.inc'
        fi

        # The next line enables shell command completion for gcloud.
        if [ -f '/Users/martin/.local/bin/google-cloud-sdk/completion.zsh.inc' ]; then
          . '/Users/martin/.local/bin/google-cloud-sdk/completion.zsh.inc'
        fi
      '';
    };

    fzf = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
    };

    git = {
      enable = true;

      userName = "Martin Hardselius";
      userEmail = "martin@hardselius.dev";

      signing = {
        key = "84D80CE9A803D1C5";
        signByDefault = true;
      };

      aliases = {
        authors = "!${pkgs.git}/bin/git log --pretty=format:%aN"
          + " | ${pkgs.coreutils}/bin/sort" + " | ${pkgs.coreutils}/bin/uniq -c"
          + " | ${pkgs.coreutils}/bin/sort -rn";
        b = "branch --color -v";
        ca = "commit --amend";
        changes = "diff --name-status -r";
        clone = "clone --recursive";
        co = "checkout";
        ctags = "!.git/hooks/ctags";
        root = "!pwd";
        spull = "!${pkgs.git}/bin/git stash" + " && ${pkgs.git}/bin/git pull"
          + " && ${pkgs.git}/bin/git stash pop";
        su = "submodule update --init --recursive";
        undo = "reset --soft HEAD^";
        w = "status -sb";
        wdiff = "diff --color-words";
        l = "log --graph --pretty=format:'%Cred%h%Creset"
          + " —%Cblue%d%Creset %s %Cgreen(%cr)%Creset'"
          + " --abbrev-commit --date=relative --show-notes=*";
      };

      extraConfig = {
        core = {
          editor = "${pkgs.vim}/bin/vim";
          trustctime = false;
          logAllRefUpdates = true;
          precomposeunicode = true;
          whitespace = "trailing-space,space-before-tab";
        };

        branch.autosetupmerge = true;
        color.ui = "auto";
        commit.gpgsign = true;
        commit.verbose = true;
        diff.submodule = "log";
        diff.tool = "${pkgs.vim}/bin/vimdiff";
        difftool.prompt = false;
        github.user = "hardselius";
        http.sslCAinfo = "${ca-bundle_crt}";
        http.sslverify = true;
        hub.protocol = "${pkgs.openssh}/bin/ssh";
        # init.templatedir = "${xdg.configHome}/git/template";
        merge.tool = "${pkgs.vim}/bin/vimdiff";
        mergetool.keepBackup = true;
        pull.rebase = true;
        push.default = "tracking";
        rebase.autosquash = true;
        rerere.enabled = true;
        status.submoduleSummary = true;
      };

      ignores = import ../config/home/gitignore.nix;
    };
  };

  xdg = {
    enable = true;

    configFile."git/template" = {
      recursive = true;
      source = ../git/.git_template;
    };
  };
}
