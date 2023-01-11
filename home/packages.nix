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

  home.packages = with pkgs;
    [
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
      nodejs
       nodePackages.typescript
      
      
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

      # global python stuff
      python310Full
      python310Full.pkgs.pip
      python310Full.pkgs.setuptools
      python310Full.pkgs.wheel
      python310Full.pkgs.numpy
      # still python.. but installed standalone?
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
      gdal
      cargo
    ];
}
