{ pkgs, lib, stdenv, ... }:

{
  # Nix configuration ------------------------------------------------------------------------------

  nix.settings = {
    substituters = [ "https://cache.nixos.org/" ];
    trusted-public-keys =
      [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];

    trusted-users = [ "@admin" ];

    auto-optimise-store = true;

    experimental-features = [ "nix-command" "flakes" ];

    extra-platforms = lib.mkIf (pkgs.system == "aarch64-darwin") [
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  };

  nix.configureBuildUsers = true;

  # Auto upgrade nix package and the daemon service.
  services.nix-daemon.enable = true;

  # Shells -----------------------------------------------------------------------------------------

  # Add shells installed by nix to /etc/shells file
  environment.shells = with pkgs; [ bashInteractive zsh ];

  users = {
    users = {
      adam.williams = {
        shell = pkgs.zsh;
        description = "Adam Williams";
        home = "/Users/adam.williams";
      };
    };
  };

  nix.extraOptions = ''
    auto-optimise-store = true
    experimental-features = nix-command flakes
  '' + lib.optionalString (pkgs.system == "aarch64-darwin") ''
    extra-platforms = x86_64-darwin aarch64-darwin
  '';

  programs.zsh.enable = true;

  environment.systemPackages = with pkgs; [ ];

  programs.nix-index.enable = true;
  fonts = {
    fonts = with pkgs; [
      recursive
      (nerdfonts.override {
        fonts = [ "JetBrainsMono" "FiraCode" "DroidSansMono" ];
      })
    ];
    fontDir.false = true;
  };

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;

  # Keyboard
  #system.keyboard.enableKeyMapping = true;
  #system.keyboard.remapCapsLockToEscape = true;

  # Add ability to used TouchID for sudo authentication
  security.pam.enableSudoTouchIdAuth = true;
}
