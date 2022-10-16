{ pkgs, ... }: {
  programs.nix-index.enable = true;
  environment.systemPackages = with pkgs; [
    alacritty
    git
    vim
    wget
    (bazel.overrideAttrs (old: {
      doCheck = false;
      doInstallCheck = false;
    }))
  ];
}
