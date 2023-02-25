{ pkgs, ... }: {
  programs.nix-index.enable = true;
  environment.systemPackages = with pkgs; [
    alacritty
    pkg-config
    git
    git-lfs
    top-git
    vim

    # (bazel.overrideAttrs (old: {
    #   doCheck = false;
    #   doInstallCheck = false;
    # }))
  
    bazelisk
    weechat
    gnupg
  ];
}
