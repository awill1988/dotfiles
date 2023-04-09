{
  system = {
    defaults.trackpad = {
      Clicking = true;
      TrackpadThreeFingerDrag = true;
    };

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
    # Keyboard
    # keyboard = {
    #   enableKeyMapping = true;
    #   remapCapsLockToEscape = true;
    # }

    # Add ability to used TouchID for sudo authentication
    security.pam.enableSudoTouchIdAuth = true;

    defaults.finder = {
      AppleShowAllExtensions = true;
      QuitMenuItem = true;
      FXEnableExtensionChangeWarning = false;
    };
  };
}
