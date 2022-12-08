{ pkgs, ... }:

{
  programs.nix-index.enable = true;

  environment.systemPackages = with pkgs; [ google-cloud-sdk.out gnupg.out ];
}
