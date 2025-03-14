{ config, lib, pkgs, ... }: {
  nix.settings.trusted-users = [ "@admin" ];

  # Add shells installed by nix to /etc/shells file
  environment.shells = with pkgs; [ bashInteractive zsh ];

  environment.variables.SHELL = "${pkgs.zsh}/bin/zsh";

  programs.zsh.enable = true;

  system.stateVersion = 5;
}
