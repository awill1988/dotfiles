{ config, pkgs, lib, ... }:
let
  tmp_directory = "/tmp";
  home_directory = "${config.home.homeDirectory}";
in
rec {
  imports = [
    ./git.nix
    ./kitty.nix
    ./newsboat.nix
    ./shells.nix
  ];

  home = {
    stateVersion = "20.09";

    sessionVariables = {
      EDITOR = "${pkgs.vim}/bin/vim";
      EMAIL = "${config.programs.git.userEmail}";
      PAGER = "${pkgs.less}/bin/less";
    };

    packages = with pkgs; [
      asciinema
      cacert
      cachix
      coreutils
      curl
      fd
      findutils
      getopt
      gnumake
      gnupg
      gpgme
      htop
      jq
      less
      nodePackages.node2nix
      nodePackages.vim-language-server
      pass
      plantuml
      pywal
      renameutils
      ripgrep
      rsync
      shellcheck
      shfmt
      tree
      universal-ctags
      urlscan
      vim
      vim-vint
      w3m
      weechat
      wget
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

    fzf = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
    };

    go = {
      enable = true;
    };

    ssh = {
      enable = true;

      controlMaster = "auto";
      controlPath = "${tmp_directory}/ssh-%u-%r@%h:%p";
      controlPersist = "1800";

      forwardAgent = true;
      serverAliveInterval = 60;

      hashKnownHosts = true;

      extraConfig = ''
        Host remarkable
          Hostname 10.11.99.1
          User root
          ForwardX11 no
          ForwardAgent no
      '';
    };
  };

  xdg = {
    enable = true;

    configHome = "${home_directory}/.config";
    dataHome = "${home_directory}/.local/share";
    cacheHome = "${home_directory}/.cache";
  };
}
