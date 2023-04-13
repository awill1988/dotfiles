# This file contains configuration that is shared across all hosts.
{ pkgs, lib, options, ... }:

{
  nix.settings.auto-optimise-store = true;
  nix.settings.keep-derivations = true;
  nix.settings.keep-outputs = true;
  nix.settings.extra-platforms = lib.mkIf (pkgs.system == "aarch64-darwin") [
    "x86_64-darwin"
    "aarch64-darwin"
  ];
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.substituters = [ "https://cache.nixos.org/" ];
  nix.settings.trusted-public-keys =
    [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];

  programs.zsh.enable = true;
  programs.zsh.promptInit = "";

  fonts.fontDir.enable = false;
  fonts.fonts = with pkgs;
    [ (nerdfonts.override { fonts = [ "JetBrainsMono" ]; }) ];
}
