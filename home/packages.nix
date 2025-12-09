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

    # unix tooling
    bash-completion
    direnv # auto-activating shell envs
    oh-my-zsh
    zsh
    coreutils
    findutils # GNU find utils
    fd # fancy `find`
    ripgrep # fancy `grep`
    renameutils # rename files faster
    tree # depth indented directory listing
    rsync # incremental file transfer util
    xdg-utils # provides xdg-open and other XDG utilities
    htop # fancy `top`
    less # more advanced file pager than `more`
    lsof
    watch
    wget
    curl
    socat

    # software development
    gnumake
    cmake
    pkg-config
    jq # command line json processor
    shellcheck
    shfmt # shell parser and formatter
    gh # github cli tool
    vim
    neovim
    grpcurl
    jsonnet
    qemu
    protobuf
    graphviz # graph visualization tools

    # programming languages and runtimes
    # elixir / erlang (OTP)
    beam.packages.erlang_28.elixir_1_19
    erlang_28
    (pkgs.writeScriptBin "install-elixir-escripts" ''
      #!/bin/sh
      mix local.hex --force
      mix local.rebar --force
      mix escript.install --force hex protobuf
    '')

    # go
    go_1_25

    # python
    (python3.withPackages (ps:
      with ps; [
        tkinter
        ansible-core
        pip
        setuptools
        wheel
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

    # python package management
    uv
    poetry

    # ruby
    rbenv
    ruby
    jekyll

    # java / kotlin
    jdk
    gradle

    # rust
    rustup

    # cloud and infra
    opentofu
    k9s
    steampipe # select * from cloud

    # ai tooling
    chatgpt-cli
    claude-code
    codex
    llama-cpp

    # nix tools
    cachix
    nixfmt-classic

    # security and credentials
    gnupg
    gpgme # make gnupg easier
    pass # "password manager"
    xkcdpass # generate passwords
    yubikey-manager # configure yubikeys
    nmap

    # media and conversion
    ffmpeg # video processing and conversion
    imagemagick
    midicsv
  ];
}
