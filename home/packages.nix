{ config, lib, pkgs, ... }:
let
  nodePackages = pkgs.nodePackages_latest.override {
    nodejs = config.modules.dev.node.package;
  };
in {
  programs.home-manager.enable = true;

  modules.dev.node.enable = true;

  programs.codex.enable = true;
  programs.claude.enable = true;
  programs.gemini.enable = true;

  programs.awscli-custom.enable = true;
  programs.awscli-custom.package = pkgs.awscli2;
  programs.awscli-custom.enableBashIntegration = true;
  programs.awscli-custom.enableZshIntegration = true;
  programs.awscli-custom.awsVault = {
    enable = true;
    prompt = "ykman";
    passPrefix = "aws_vault/";
  };

  programs.browserpass.enable = true;
  programs.browserpass.browsers = [ "firefox" ];

  programs.direnv.enable = true;
  programs.direnv.nix-direnv.enable = true;

  programs.dircolors.enable = true;
  programs.dircolors.enableBashIntegration = true;
  programs.dircolors.enableZshIntegration = true;

  programs.fzf.enable = true;
  programs.fzf.enableBashIntegration = true;
  programs.fzf.enableZshIntegration = true;

  programs.htop.enable = true;
  programs.htop.settings.show_program_path = true;

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks = {
      "*" = {
        host = "*";
        controlMaster = "auto";
        controlPath = "/tmp/ssh-%u-%r@%h:%p";
        controlPersist = "60";
        forwardAgent = true;
        serverAliveInterval = 60;
        hashKnownHosts = true;
      };
      "private-nets" = {
        host = "master-* node-*";
        user = "admin";
        extraOptions = {
          StrictHostKeyChecking = "accept-new";
          UserKnownHostsFile = "~/.ssh/known_hosts";
        };
      };
    };
    extraConfig = "";
  };

  programs.tmux = {
    enable = true;
    aggressiveResize = true;
    clock24 = true;
    keyMode = "vi";
    terminal = "screen-256color";
    plugins = with pkgs.tmuxPlugins; [ sensible yank resurrect continuum ];
    extraConfig = ''
      # gpakosz-inspired ergonomics
      set -g prefix2 C-a
      bind C-a send-prefix -2
      set -g base-index 1
      setw -g pane-base-index 1
      setw -g automatic-rename on
      set -g renumber-windows on
      setw -g xterm-keys on
      set -g history-limit 5000
      set -g display-time 1000
      set -g set-titles on
      set -g mouse on
      set -g @continuum-restore 'on'
      # splits and navigation
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
      bind r source-file ~/.tmux.conf \; display-message "tmux reloaded"
      # quick exits (vim-like: prefix + z / Z)
      bind z confirm-before -p "kill-window? (y/n)" kill-window
      bind Z confirm-before -p "kill-session? (y/n)" kill-session
    '';
  };

  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    withNodeJs = true;
    withPython3 = true;
    plugins = (with pkgs.vimPlugins; [
      plenary-nvim
      nvim-web-devicons
      nui-nvim
      neo-tree-nvim
      nvim-lspconfig
      nvim-cmp
      cmp-nvim-lsp
      cmp-buffer
      cmp-path
      luasnip
      friendly-snippets
      lspkind-nvim
      nvim-treesitter.withAllGrammars
      telescope-nvim
      telescope-fzf-native-nvim
      which-key-nvim
      gitsigns-nvim
      mini-nvim
      vim-dadbod
      vim-dadbod-ui
      vim-dadbod-completion
    ]);
    extraPackages = with pkgs; [ ripgrep fd tree-sitter ];
    extraLuaConfig = ''require("aw")'';
  };

  home.packages = with pkgs; [

    # unix tooling
    bash-completion
    direnv # auto-activating shell envs
    oh-my-zsh
    zsh
    coreutils
    findutils # GNU find utils
    fd # fancy `find`
    ripgrep # fancy `grep`
    renameutils # rename files faster
    tree # depth indented directory listing
    rsync # incremental file transfer util
    xdg-utils # provides xdg-open and other XDG utilities
    htop # fancy `top`
    less # more advanced file pager than `more`
    lsof
    watch
    wget
    curl
    socat

    # software development
    gnumake
    cmake
    pkg-config
    jq # command line json processor
    shellcheck
    shfmt # shell parser and formatter
    vale
    gh # github cli tool
    (pkgs.writeShellScriptBin "ide" ''
      #!/bin/sh
      # tmux + neovim "IDE" launcher:
      # - left: neo-tree file explorer inside neovim
      # - right: two stacked tmux shell panes (30% column)
      set -euo pipefail
      target_path="''${1:-.}"
      resolved_path="$(realpath "$target_path")"
      session="ide-$(basename "$resolved_path")"
      shell_cmd="''${SHELL:-/bin/zsh}"
      if ! command -v "$shell_cmd" >/dev/null 2>&1; then
        shell_cmd="/bin/sh"
      fi

      if ! tmux has-session -t "$session" 2>/dev/null; then
        tmux new-session -d -s "$session" -c "$resolved_path" "cd -- \"$resolved_path\" && nvim '+Neotree left reveal' ."
        tmux split-window -t "$session":1 -h -p 30 -c "$resolved_path" "$shell_cmd"
        tmux split-window -t "$session":1.2 -v -c "$resolved_path" "$shell_cmd"
        tmux select-pane -t "$session":1.1
      fi

      tmux attach -t "$session"
    '')
    (pkgs.writeShellScriptBin "dbui" ''
      #!/bin/sh
      # tmux + neovim dadbod UI launcher:
      # - starts Neovim directly in dadbod-ui
      # - keeps a bottom tmux shell pane
      set -euo pipefail
      target_path="''${1:-.}"
      resolved_path="$(realpath "$target_path")"
      session="dbui-$(basename "$resolved_path")"

      if ! tmux has-session -t "$session" 2>/dev/null; then
        tmux new-session -d -s "$session" -c "$resolved_path" "cd -- \"$resolved_path\" && nvim '+DBUI' ."
        tmux split-window -t "$session":1 -v -p 30 -c "$resolved_path"
        tmux select-pane -t "$session":1.1
      fi

      tmux attach -t "$session"
    '')
    grpcurl
    sqlite
    jsonnet
    qemu
    protobuf

    # programming languages and runtimes
    # elixir / erlang (OTP)
    beam.packages.erlang_28.elixir_1_19
    erlang_28
    (pkgs.writeScriptBin "install-elixir-escripts" ''
      #!/bin/sh
      mix local.hex --force
      mix local.rebar --force
      mix escript.install --force hex protobuf
    '')

    # go
    go_1_25

    # python
    (python3.withPackages (ps:
      with ps; [
        tkinter
        ansible-core
        pip
        setuptools
        wheel
        numpy
        cython
        openai
        (ps.buildPythonPackage rec {
          pname = "ansibug";
          version = "0.3.1";
          pyproject = true;
          src = pkgs.fetchPypi {
            inherit pname version;
            sha256 = "10rp4jjqldwm4d31fnwliddzg4c8wiyi2qznvkk8yfbwsvhsjqwq";
          };
          nativeBuildInputs = with ps; [ setuptools wheel ];
          propagatedBuildInputs = with ps; [ ansible-core ];
        })
      ]))

    # python package management
    uv
    poetry

    # ruby
    rbenv
    ruby
    jekyll

    # java / kotlin
    jdk
    gradle

    # rust
    rustup

    # language servers
    gopls
    beam.packages.erlang_28."elixir-ls"
    nodePackages.bash-language-server
    nodePackages.typescript-language-server
    nodePackages.vim-language-server
    pyright
    rubyPackages.solargraph
    jdt-language-server
    kotlin-language-server

    # cloud and infra
    opentofu
    k9s
    steampipe # select * from cloud

    # ai tooling
    llama-cpp

    # nix tools
    cachix
    nixfmt-classic

    # security and credentials
    gnupg
    gpgme # make gnupg easier
    pass # "password manager"
    xkcdpass # generate passwords
    yubikey-manager # configure yubikeys
    nmap

    # media and conversion
    ffmpeg # video processing and conversion
    imagemagick
    midicsv
  ];
}
