# This file contains configuration that is shared across all hosts.
{
  pkgs,
  lib,
  options,
  ...
}:
{
  nix.settings.auto-optimise-store = false;
  nix.settings.keep-derivations = false;
  nix.settings.keep-outputs = false;
  nix.settings.extra-platforms = lib.mkIf (pkgs.stdenv.hostPlatform.system == "aarch64-darwin") [
    "x86_64-darwin"
    "aarch64-darwin"
  ];
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.settings.substituters = [ "https://cache.nixos.org/" ];
  nix.settings.trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
  ];

  # scheduled gc: prune generations older than 7d weekly so darwin-rebuild
  # history does not accrue indefinitely (each generation pins its closure).
  nix.gc.automatic = true;
  nix.gc.interval = {
    Weekday = 0;
    Hour = 3;
    Minute = 15;
  };
  nix.gc.options = "--delete-older-than 7d";

  # scheduled store optimisation (hard-link dedup). kept separate from the
  # build-time auto-optimise-store path, which is intentionally disabled
  # above because it slows every store add.
  nix.optimise.automatic = true;
  nix.optimise.interval = {
    Weekday = 0;
    Hour = 4;
    Minute = 0;
  };

  programs.zsh.enable = true;
  programs.zsh.promptInit = "";

  fonts.packages = with pkgs; [ ];
}
