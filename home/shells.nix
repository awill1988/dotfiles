{ pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    pure-prompt
    igloo-prompt
  ];

  programs.zsh = {
    enable = true;

    cdpath = [
      "."
      "~"
    ];

    defaultKeymap = "viins";
    dotDir = ".config/zsh";

    history = {
      size = 50000;
      save = 500000;
      ignoreDups = true;
      share = true;
    };

    sessionVariables = {
      CLICOLOR = true;
      GPG_TTY = "$TTY";
      PATH = "$PATH:$HOME/.local/bin";
    };

    shellAliases = {
      tf = "terraform";
      restartaudio = "sudo killall coreaudiod";
    };

    profileExtra = ''
      export GPG_TTY=$(tty)

      if ! pgrep -x "gpg-agent" > /dev/null; then
          ${pkgs.gnupg}/bin/gpgconf --launch gpg-agent
      fi
    '';

    initExtra = ''
      export KEYTIMEOUT=1

      vi-search-fix() {
        zle vi-cmd-mode
        zle .vi-history-search-backward
      }
      autoload vi-search-fix
      zle -N vi-search-fix
      bindkey -M viins '\e/' vi-search-fix

      bindkey "^?" backward-delete-char

      resume() {
        fg
        zle push-input
        BUFFER=""
        zle accept-line
      }
      zle -N resume
      bindkey "^Z" resume

      ls() {
          ${pkgs.coreutils}/bin/ls --color=auto --group-directories-first "$@"
      }

      autoload -U promptinit; promptinit

      # Configure pure-promt
      prompt pure
      zstyle :prompt:pure:prompt:success color green

      # Configure igloo-prompt
      # source ${pkgs.git}/share/git/contrib/completion/git-prompt.sh
      # IGLOO_ZSH_PROMPT_THEME_ALWAYS_SHOW_USER=true
      # IGLOO_ZSH_PROMPT_THEME_ALWAYS_SHOW_HOST=true
      # IGLOO_ZSH_PROMPT_THEME_HIDE_TIME=false
      # prompt igloo

      # The next line updates PATH for the Google Cloud SDK.
      if [ -f '/Users/martin/bin/google-cloud-sdk/path.zsh.inc' ]; then
        . '/Users/martin/.local/bin/google-cloud-sdk/path.zsh.inc'
      fi

      # The next line enables shell command completion for gcloud.
      if [ -f '/Users/martin/.local/bin/google-cloud-sdk/completion.zsh.inc' ]; then
        . '/Users/martin/.local/bin/google-cloud-sdk/completion.zsh.inc'
      fi
    '';
  };
}
