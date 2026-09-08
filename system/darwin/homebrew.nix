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
    # Set HOMEBREW_PREFIX and prefer Homebrew-managed tools over legacy installer binaries
    export HOMEBREW_PREFIX="${builtins.dirOf config.homebrew.brewPrefix}"

    # Prepend Homebrew dirs only if not already present
    if [[ ":$PATH:" != *":$HOMEBREW_PREFIX/bin:"* ]]; then
      export PATH="$HOMEBREW_PREFIX/bin:$PATH"
    fi

    if [[ ":$PATH:" != *":$HOMEBREW_PREFIX/sbin:"* ]]; then
      export PATH="$HOMEBREW_PREFIX/sbin:$PATH"
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
  # newer brew requires --force when --cleanup is passed non-interactively
  homebrew.onActivation.extraFlags = [ "--force" ];
  homebrew.global.brewfile = true;

  homebrew.brews = [
    "apktool"
    "bundletool"
    "cocoapods"
    "eas-cli"
    "imessage-exporter"
    "jadx"
    "ldns"
    "node"
    "periphery"
    "picotool"
    "pinentry-mac"
    "worktrunk"
    "xcsift"
  ];

  homebrew.casks = [
    "android-studio"
    "dbeaver-community"
    "macfuse"
    "qgis"
    "tuist"
  ]
  ++ optionals install_karabiner_via_homebrew [ "karabiner-elements" ];
}
