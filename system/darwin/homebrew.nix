{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    attrByPath
    hasAttrByPath
    mkIf
    optionals
    ;
  brewEnabled = config.homebrew.enable;
  primary_username = config.users.primaryUser.username;
  hm_karabiner_path = [
    "home-manager"
    "users"
    primary_username
    "programs"
    "karabiner-elements"
  ];
  hm_karabiner_cfg =
    if primary_username != null && hasAttrByPath hm_karabiner_path config then
      attrByPath hm_karabiner_path { } config
    else
      { };
  install_karabiner_via_homebrew =
    (hm_karabiner_cfg.enable or false) && (hm_karabiner_cfg.install_method or "nix") == "homebrew";
in
{
  programs.zsh.shellInit = mkIf brewEnabled ''
    # Set HOMEBREW_PREFIX and manually append paths to end of PATH
    export HOMEBREW_PREFIX="${builtins.dirOf config.homebrew.brewPrefix}"

    # Append Homebrew dirs to end of PATH only if not already present
    if [[ ":$PATH:" != *":$HOMEBREW_PREFIX/bin:"* ]]; then
      export PATH="$PATH:$HOMEBREW_PREFIX/bin"
    fi

    if [[ ":$PATH:" != *":$HOMEBREW_PREFIX/sbin:"* ]]; then
      export PATH="$PATH:$HOMEBREW_PREFIX/sbin"
    fi

    if type brew &>/dev/null
    then
      fpath+=($(brew --prefix)/share/zsh/site-functions)

      autoload -Uz compinit
      compinit
    fi
  '';

  homebrew.enable = true;
  homebrew.onActivation.autoUpdate = true;
  homebrew.onActivation.cleanup = "zap";
  homebrew.global.brewfile = true;

  homebrew.taps = [ "emqx/mqttx" ];

  homebrew.brews = [
    "apktool"
    "bundletool"
    "cocoapods"
    "emqx/mqttx/mqttx-cli"
    "imessage-exporter"
    "jadx"
    "ldns"
    "picotool"
    "pinentry-mac"
    "worktrunk"
    "xcsift"
  ];

  homebrew.casks = [
    "android-studio"
    "dbeaver-community"
    "macfuse"
  ]
  ++ optionals install_karabiner_via_homebrew [ "karabiner-elements" ];
}
