{ config, lib, ... }:
let
  inherit (config.users.primaryUser) username;
in
{
  # nix-darwin now needs a primary user for per-user system defaults
  assertions = [
    {
      assertion = username != null;
      message = "Set users.primaryUser.username so system.primaryUser can be configured.";
    }
  ];

  system.primaryUser = username;

  security.pam.services.sudo_local = {
    touchIdAuth = true;
    reattach = true; # support Touch ID from tmux and screen sessions
  };

  system = {
    defaults.LaunchServices.LSQuarantine = false;

    defaults.NSGlobalDomain = {
      AppleKeyboardUIMode = 3;
      ApplePressAndHoldEnabled = false;
      AppleShowAllExtensions = true;
      InitialKeyRepeat = 20;
      KeyRepeat = 1;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
      NSNavPanelExpandedStateForSaveMode = true;
      NSNavPanelExpandedStateForSaveMode2 = true;
      _HIHideMenuBar = false;
    };

    defaults.dock = {
      autohide = true;
      mru-spaces = false;
      orientation = "bottom";
      showhidden = true;
    };

    defaults.finder = {
      AppleShowAllExtensions = true;
      QuitMenuItem = true;
      FXEnableExtensionChangeWarning = false;
    };
  };
}
