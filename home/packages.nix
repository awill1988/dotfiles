{ config, pkgs, lib, ... }: {
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

  home.packages = with pkgs; [
    terraform
    cmake
    jq.bin
    # basics
    coreutils
    curl
    fd # fancy `find`
    findutils # GNU find utils
    htop # fancy `top`
    less # more advanced file pager than `more`
    ripgrep # fancy `grep`
    rsync # incremental file transfer util
    tree # depth indented directory listing
    wget # basic tool

    act # local github actions testing
    gh # github cli tool

    shellcheck # bash scripts 'n stuff
    shfmt # shell parser and formatter

    go # Go programming language

    # Nix stuff
    cachix # adding/managing alternative binary caches hosted by Cachix
    niv # easy dependency management for nix projects
    nix-prefetch-scripts
    nixfmt

    ruby
    rbenv

    # for Android Studio
    androidenv.androidPkgs_9_0.platform-tools
    jdk
    k9s
    # Python 3.8
    # python38Full
    # python38Full.pkgs.pip
    # python38Full.pkgs.setuptools
    # python38Full.pkgs.wheel
    # python38Full.pkgs.numpy
    # python38Full.pkgs.cython

    # Python 3.9
    # python39Full
    # python39Full.pkgs.pip
    # python39Full.pkgs.setuptools
    # python39Full.pkgs.wheel
    # python39Full.pkgs.numpy
    # python39Full.pkgs.cython

    # Python 3.10
    python310
    python310.pkgs.pip
    python310.pkgs.setuptools
    python310.pkgs.wheel
    python310.pkgs.gdal
    python310.pkgs.numpy
    python310.pkgs.python
    python310.pkgs.cython

    postgresql.out # psql cli only

    # GDAL has an overlay in extra.nix
    gdal

    poetry

<<<<<<< Updated upstream
    # visualizing Python profiling
    flamegraph
=======
    gdal # GDAL

    gfortran

    postgresql.out # psql cli only
>>>>>>> Stashed changes

    pkg-config
    shellcheck
    thefuck
    openssl_1_1.dev
    bash-completion

    # security
    browserpass
    cacert
    curl
    direnv
    fd
    ffmpeg
    findutils
    libwebp
    gnugrep
    gnumake
    gnuplot
    gnused
    gnutar
    pre-commit
    less
    socat
    unixtools.ifconfig
    unixtools.netstat
    unixtools.ping
    unixtools.route
    unixtools.top
    autoconf
    automake
    gettext
    xz
    nmap
    unzip

    watchman

    # Shell Environment
    zsh
    oh-my-zsh

    git
    git-lfs
    top-git
    gradle
    gnupg
    pinentry

    beam.packages.erlangR25.elixir_1_14
    erlangR25
    gdb
  ];
}
