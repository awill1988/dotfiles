{ pkgs, ... }: {
  programs.nix-index.enable = true;
  environment.systemPackages = with pkgs; [ alacritty git vim gnupg ];
}
