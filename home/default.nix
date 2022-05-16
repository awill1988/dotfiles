{ config, pkgs, lib, ... }:
let
  tmp_directory = "/tmp";
  home_directory = "${config.home.homeDirectory}";
in
rec {
  imports = [
    ./git.nix
    ./shells.nix
    ./terminal.nix
  ];

  home = {
    sessionVariables = {
      EDITOR = "${pkgs.vim}/bin/vim";
      EMAIL = "${config.programs.git.userEmail}";
      PAGER = "${pkgs.less}/bin/less";
      CLICOLOR = true;
      GPG_TTY = "$TTY";
      PATH = "$PATH:$HOME/.local/bin:$HOME/.tfenv/bin";
    };

    packages = with pkgs; [
      asciinema
      cacert
      cachix
      coreutils
      curl
      exiftool
      fd
      findutils
      getopt
      gh
      gnumake
      gnupg
      gpgme
      htop
      jq
      jsonnet-language-server
      less
      ncspot
      nixpkgs-fmt
      nodePackages.bash-language-server
      nodePackages.node2nix
      nodePackages.prettier
      nodePackages.vim-language-server
      paperkey
      pass
      socat
      steampipe
      plantuml
      prs
      python39Packages.sqlparse
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
      wget
      xkcdpass
      yubikey-manager
    ];
  };

  programs = {

    home-manager = { enable = true; };

    awscli = {
      package = pkgs.awscli2;
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      awsVault = {
        enable = true;
        prompt = "ykman";
        backend = "pass";
        passPrefix = "aws_vault/";
      };
    };

    browserpass = {
      enable = true;
      browsers = [ "firefox" ];
    };

    direnv = {
      enable = true;
      nix-direnv = {
        enable = true;
      };
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

    go.enable = true;

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

    tmux = {
      enable = true;
      aggressiveResize = true;
      keyMode = "vi";
    };
  };
}
