{ pkgs, ... }: {
  programs.home-manager.enable = true;

  modules.dev.node.enable = true;

  programs.awscli-custom.enable = true;
  programs.awscli-custom.package = pkgs.awscli2;
  programs.awscli-custom.enableBashIntegration = true;
  programs.awscli-custom.enableZshIntegration = true;
  programs.awscli-custom.awsVault = {
    enable = true;
    prompt = "ykman";
    passPrefix = "aws_vault/";
  };

  programs.browserpass.enable = true;
  programs.browserpass.browsers = [ "firefox" ];

  programs.direnv.enable = true;
  programs.direnv.nix-direnv.enable = true;

  programs.dircolors.enable = true;
  programs.dircolors.enableBashIntegration = true;
  programs.dircolors.enableZshIntegration = true;

  programs.fzf.enable = true;
  programs.fzf.enableBashIntegration = true;
  programs.fzf.enableZshIntegration = true;

  programs.htop.enable = true;
  programs.htop.settings.show_program_path = true;

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks = {
      "*" = {
        host = "*";
        controlMaster = "auto";
        controlPath = "/tmp/ssh-%u-%r@%h:%p";
        controlPersist = "60";
        forwardAgent = true;
        serverAliveInterval = 60;
        hashKnownHosts = true;
      };
      "private-nets" = {
        host = "master-* node-*";
        user = "admin";
        extraOptions = {
          StrictHostKeyChecking = "accept-new";
          UserKnownHostsFile = "~/.ssh/known_hosts";
        };
      };
    };
    extraConfig = "";
  };

  programs.tmux.enable = true;
  programs.tmux.aggressiveResize = true;
  programs.tmux.clock24 = true;
  programs.tmux.keyMode = "vi";
  programs.tmux.terminal = "screen-256color";

  home.packages = with pkgs; [

    # Shell Environment
    # -------------------------------
    bash-completion
    direnv # auto-activating shell envs
    oh-my-zsh
    zsh

    # Programming Languages
    # -------------------------------
    # Elixir / Erlang (OTP)
    beam.packages.erlang_27.elixir_1_18
    erlang_28
    (pkgs.writeScriptBin "install-elixir-escripts" ''
      #!/bin/sh
      mix local.hex --force
      mix local.rebar --force
      mix escript.install --force hex protobuf
    '')

    # Golang
    go_1_25

    # Python
    (python3.withPackages (ps:
      with ps; [
        tkinter
        ansible-core
        pip
        setuptools
        wheel
        gdal
        numpy
        cython
        openai
        (ps.buildPythonPackage rec {
          pname = "ansibug";
          version = "0.3.1";
          pyproject = true;
          src = pkgs.fetchPypi {
            inherit pname version;
            sha256 = "10rp4jjqldwm4d31fnwliddzg4c8wiyi2qznvkk8yfbwsvhsjqwq";
          };
          nativeBuildInputs = with ps; [ setuptools wheel ];
          propagatedBuildInputs = with ps; [ ansible-core ];
        })
      ]))

    poetry # python package / project cli

    # Ruby
    rbenv

    opentofu
    k9s

    protobuf
    pkg-config

    # basics
    coreutils
    curl
    fd # fancy `find`
    findutils # GNU find utils
    htop # fancy `top`
    less # more advanced file pager than `more`
    #renameutils # rename files faster
    ripgrep # fancy `grep`
    rsync # incremental file transfer util
    tree # depth indented directory listing
    wget
    xdg-utils # provides xdg-open and other XDG utilities
    grpcurl
    lsof

    # dev stuff
    gh # github cli tool
    gnumake
    jq # command line json processor
    steampipe # select * from cloud
    vim

    jdk
    gradle

    # code tools
    jsonnet-language-server
    nodePackages.eslint
    nodePackages.bash-language-server
    nodePackages.prettier # code formatter
    nodePackages.typescript-language-server
    nodePackages.vim-language-server
    rustup
    shellcheck
    shfmt # shell parser and formatter
    socat

    ruby
    jekyll
    codex
    jsonnet

    # nix tools
    alejandra
    cachix
    nixfmt-classic

    # opsec
    gnupg
    gpgme # make gnupg easier
    pass # "password manager"
    xkcdpass # generate passwords
    yubikey-manager # configure yubikeys

    # other
    asciidoctor
    chatgpt-cli
    ffmpeg # video processing and conversion
    graphviz # graph visualization tools
    nmap
    renameutils
    watch
    qemu
    imagemagick
    ffmpeg
    uv
    cmake
    jsonnet
    midicsv
    llama-cpp
  ];
}
