{ config, pkgs, lib, ... }: {
  programs.home-manager.enable = true;

  programs.browserpass.enable = true;
  programs.browserpass.browsers = [ "firefox" ];

  programs.direnv.enable = true;
  programs.direnv.nix-direnv.enable = true;

  programs.dircolors.enable = true;
  programs.dircolors.enableZshIntegration = true;

  programs.fzf.enable = true;
  programs.fzf.enableBashIntegration = true;
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
    act # local github actions testing
    terraform
    cmake
    gcc
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
    wget

    # code tools
    nodePackages.prettier # code formatter
    shellcheck
    shfmt # shell parser and formatter
    # programming languages 
    go_1_19
    nodejs-16_x-openssl_1_1
    nodePackages.typescript
    nodePackages.yarn
    nodePackages.lerna
    nodePackages."@vue/cli"

    # Useful nix related tools
    cachix # adding/managing alternative binary caches hosted by Cachix
    niv # easy dependency management for nix projects
    nix-prefetch-scripts
    nixfmt

    # dev stuff
    gh # github cli tool
    git-lfs
    top-git
    ruby
    rbenv

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

    # still python.. but installed standalone?

    # GDAL has an overlay in extra.nix
    gdal

    poetry

    pkg-config
    shellcheck
    thefuck
    postgresql.out
    openssl_1_1.dev
    bash-completion
    browserpass
    cacert
    curl
    direnv
    fd
    ffmpeg
    findutils
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
    wget
    zsh
    oh-my-zsh
    cargo
  ];
}
