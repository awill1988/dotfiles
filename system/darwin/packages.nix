{ pkgs, ... }:

{
  programs.nix-index.enable = true;

  environment.systemPackages = with pkgs; [ weechat gnupg cocoapods m-cli ];
}
