{ config, lib, pkgs, ... }:
let
  inherit (lib) mkIf elem;
  brewEnabled = config.homebrew.enable;
in
{
  programs.zsh.shellInit = mkIf brewEnabled ''
    # Set HOMEBREW_PREFIX and manually append paths to end of PATH
    export HOMEBREW_PREFIX="${config.homebrew.brewPrefix}"

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

  homebrew.brews =
    [ "emqx/mqttx/mqttx-cli" "picotool" "pinentry" "ldns" "imessage-exporter" ];
}
