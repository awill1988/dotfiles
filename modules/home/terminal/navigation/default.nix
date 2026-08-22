{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.modules.terminal.navigation;
in
{
  options.modules.terminal.navigation = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable terminal navigation, fuzzy search, environment management, and core CLI utilities.";
    };
  };

  config = mkIf cfg.enable {
    programs.mise = {
      enable = true;
      enableZshIntegration = true;
      package = pkgs.pkgs-unstable.mise;
    };

    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    programs.dircolors = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
    };

    programs.fzf = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
    };

    programs.zoxide = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
    };

    programs.htop = {
      enable = true;
      settings.show_program_path = true;
    };

    home.packages = with pkgs; [
      # unix & navigation tooling
      bash-completion
      oh-my-zsh
      coreutils
      findutils
      fd
      ripgrep
      renameutils
      tree
      rsync
      xdg-utils
      less
      lsof
      watch
      wget
      curl
      socat
      mqttx-cli

      # build & execution helpers
      vim
      gnumake
      cmake
      pkg-config
      jq
      just

      # media & rendering
      ffmpeg
      imagemagick
      midicsv
      poppler-utils

      # nix tools
      cachix
      nixfmt-classic
    ];
  };
}
