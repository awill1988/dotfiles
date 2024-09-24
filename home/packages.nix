{ config, pkgs, lib, ... }: {
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
    elixir_1_17
    erlang_r27
    (pkgs.writeScriptBin "install-elixir-escripts" ''
      #!/bin/sh
      mix local.hex --force
      mix local.rebar --force
      mix escript.install --force hex protobuf
    '')
    # java
    gradle
    jdk

    # Golang
    go

    luarocks
    lua
    lua.pkgs.lua-resty-core

    grpcurl

    # Ruby
    rbenv

    # Domain-specific Languages
    # -------------------------------

    # Terraform
    terraform

    # Nix stuff
    cachix # adding/managing alternative binary caches hosted by Cachix
    niv # easy dependency management for nix projects
    nix-prefetch-scripts
    nixfmt

    # Terminal UIs
    # -------------------------------
    # k9s # kubernetes

    # Command-Line Utilities
    # -------------------------------

    unixtools.top # observe OS processes

    findutils # `xargs`, `find`
    fd # fancy `find`
    gnugrep # grep
    gnused # sed
    gnutar # tar
    htop # fancy `top`
    less # more advanced file pager than `more`
    ripgrep # fancy `grep`
    rsync # incremental file transfer util
    tree # depth indented directory listing
    unzip # zip files
    xz # save tar.gz files

    ffmpeg # multimedia conversion

    # Version Control System (git)
    git
    git-lfs
    top-git

    # GitHub.com
    act # local github actions testing

    jq.bin # json query

    flamegraph # visualizing / analyzing Python

    postgresql.out # psql cli only

    pre-commit # git VCS precommit hooks

    shellcheck # bash scripts 'n stuff
    shfmt # shell parser and formatter

    # Network Utilities
    # -------------------------------
    socat
    nmap
    unixtools.ifconfig
    unixtools.netstat
    unixtools.ping
    unixtools.route
    curl # http client
    wget # http client

    # Compilers & Software Libs
    # -------------------------------
    autoconf # producing configure scripts where a Bourne shell is available
    automake # generates one or more Makefile.in from files called Makefile.am
    gettext # internationalization and localization system
    gnumake # analog for `make`
    pkg-config # unified interface for querying installed libraries for
    # the purpose of compiling software that depends on them

    # Security / IAM
    # -------------------------------
    browserpass
    cacert
    gnupg

    # Convert Bitmap images on command-line
    imagemagick

    bazelisk

    zig
    xz
    cmake
  ];

  programs.home-manager.enable = true;

  programs.browserpass.enable = true;
  programs.browserpass.browsers = [ "firefox" ];

  programs.direnv.enable = true;
  programs.direnv.nix-direnv.enable = true;

  programs.dircolors.enable = true;
  programs.dircolors.enableBashIntegration = false;
  programs.dircolors.enableZshIntegration = true;

  programs.fzf.enable = true;
  programs.fzf.enableBashIntegration = false;
  programs.fzf.enableZshIntegration = true;

  programs.ssh.enable = true;
  programs.ssh.controlMaster = "auto";
  programs.ssh.controlPath = "/tmp/ssh-%u-%r@%h:%p";
  programs.ssh.controlPersist = "1800";
  programs.ssh.forwardAgent = true;
  programs.ssh.serverAliveInterval = 60;
  programs.ssh.hashKnownHosts = true;
  programs.ssh.extraConfig = "";
}
