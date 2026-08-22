{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.modules.terminal.tmux;
in
{
  options.modules.terminal.tmux = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Tmux terminal multiplexer and plugins.";
    };
  };

  config = mkIf cfg.enable {
    programs.tmux = {
      enable = true;
      aggressiveResize = true;
      clock24 = true;
      keyMode = "vi";
      shell = "${pkgs.zsh}/bin/zsh";
      terminal = "screen-256color";
      plugins = with pkgs.tmuxPlugins; [
        sensible
        yank
        resurrect
        continuum
      ];
      extraConfig = ''
        # force zsh for new panes
        set -g default-command "${pkgs.zsh}/bin/zsh"
        # gpakosz-inspired ergonomics
        set -g prefix2 C-a
        bind C-a send-prefix -2
        set -g base-index 1
        setw -g pane-base-index 1
        setw -g automatic-rename on
        set -g renumber-windows on
        setw -g xterm-keys on
        set -g history-limit 5000
        set -g display-time 3000
        set -g set-titles on
        set -g mouse on
        setw -g remain-on-exit failed
        bind ? show-messages
        set -g @continuum-restore 'on'
        set -g @resurrect-capture-pane-contents 'on'
        set -g @resurrect-strategy-nvim 'session'
        set -g @resurrect-strategy-vim 'session'
        set -g @continuum-save-interval '5'
        set -g window-status-format " #I:#W#F "
        set -g window-status-current-format " #I:#W#F "
        bind - split-window -v
        bind _ split-window -h
        bind -r h select-pane -L
        bind -r j select-pane -D
        bind -r k select-pane -U
        bind -r l select-pane -R
        bind -r H resize-pane -L 2
        bind -r J resize-pane -D 2
        bind -r K resize-pane -U 2
        bind -r L resize-pane -R 2
        is_vim="ps -o state= -o comm= -t '#{pane_tty}' | grep -iqE '^[^TXZ ]+ +(\\S+\\/)?g?(view|l?n?vim?x?|fzf)(diff)?$'"
        bind-key -n 'C-h' if-shell "$is_vim" 'send-keys C-h' 'select-pane -L'
        bind-key -n 'C-j' if-shell "$is_vim" 'send-keys C-j' 'select-pane -D'
        bind-key -n 'C-k' if-shell "$is_vim" 'send-keys C-k' 'select-pane -U'
        bind-key -n 'C-l' if-shell "$is_vim" 'send-keys C-l' 'select-pane -R'
        bind-key -T copy-mode-vi 'C-h' select-pane -L
        bind-key -T copy-mode-vi 'C-j' select-pane -D
        bind-key -T copy-mode-vi 'C-k' select-pane -U
        bind-key -T copy-mode-vi 'C-l' select-pane -R
        bind r source-file ~/.config/tmux/tmux.conf \; display-message "tmux reloaded"
        bind z confirm-before -p "kill-window? (y/n)" kill-window
        bind Z confirm-before -p "kill-session? (y/n)" kill-session
        bind e run-shell "code --toggle-picker '#{session_name}:#{window_index}'"
      '';
    };
  };
}
