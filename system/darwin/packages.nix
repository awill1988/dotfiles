{ pkgs, ... }:

{
  programs.nix-index.enable = true;

  environment.systemPackages = with pkgs; [
    cocoapods
    m-cli
  ];
}
