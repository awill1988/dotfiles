{ pkgs, ... }: {
  programs.nix-index.enable = true;
  environment.systemPackages = with pkgs; [
    alacritty
    pkg-config
    git
    # vim
    wget
    (bazel.overrideAttrs (old: {
      doCheck = false;
      doInstallCheck = false;
    }))
  ];
}
