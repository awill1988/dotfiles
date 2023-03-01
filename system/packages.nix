{ pkgs, ... }: {
  programs.nix-index.enable = true;
  environment.systemPackages = with pkgs; [
    alacritty
    pkg-config
    vim
    weechat
    gnupg
  ];
}
