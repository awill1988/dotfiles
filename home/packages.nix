{
  config,
  lib,
  pkgs,
  ...
}:
let
  nodePackages = pkgs.nodePackages_latest.override {
    nodejs = config.modules.dev.node.package;
  };
in
{
  programs.home-manager.enable = true;

  modules.dev.node.enable = true;

  programs.codex.enable = true;
  programs.contextforge.enable = true;
  programs.podman.enable = true;
  programs.claude = {
    enable = true;
    primary = {
      mcpServers = {
        aws = {
          command = "uvx";
          args = [ "awslabs.core-mcp-server@latest" ];
        };
      };
    };
    secondary = {
      pathPrefix = "$HOME/projects/arro";
      awsProfile = "arro-staging";
      awsRegion = "us-west-2";
      mcpServers = {
        atlassian = {
          command = "npx";
          args = [
            "-y"
            "mcp-remote"
            "https://mcp.atlassian.com/v1/mcp"
          ];
        };
        expo = {
          command = "npx";
          args = [
            "-y"
            "mcp-remote"
            "https://mcp.expo.dev/mcp"
          ];
        };
        linear = {
          command = "npx";
          args = [
            "-y"
            "mcp-remote"
            "https://mcp.linear.app/mcp"
          ];
        };
        aws = {
          command = "uvx";
          args = [ "awslabs.core-mcp-server@latest" ];
        };
        vanta = {
          command = "npx";
          args = [
            "-y"
            "@vantasdk/vanta-mcp-server"
          ];
          env = {
            VANTA_ENV_FILE = "\${VANTA_ENV_FILE}";
          };
        };
        google-docs = {
          command = "npx";
          args = [
            "-y"
            "google-docs-mcp"
          ];
          env = {
            GOOGLE_CLIENT_ID = "\${GOOGLE_CLIENT_ID}";
            GOOGLE_CLIENT_SECRET = "\${GOOGLE_CLIENT_SECRET}";
          };
        };
      };
    };
  };
  programs.gemini.enable = true;
  programs.karabiner-elements = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    install_method = "homebrew";
    tartarus_pro = {
      enable = true;
      # from `karabiner_cli --list-connected-devices`
      # to ensure remaps only apply to the razer tartarus pro.
      vendor_id = 5426;
      product_id = 580;
      frontmost_application = {
        bundle_identifiers = [
          "^com\\.avid\\.Sibelius.*$"
          "^com\\.avid\\.sibelius.*$"
        ];
        file_paths = [ "^/Applications/Sibelius.*\\.app/" ];
      };
      mapping = {
        "1" = "delete_or_backspace";
        "2" = "keypad_7";
        "3" = "keypad_8";
        "4" = "keypad_9";
        "5" = "keypad_plus";
        a = "keypad_1";
        c = "keypad_slash";
        caps_lock = "delete_or_backspace";
        d = "keypad_3";
        e = "keypad_6";
        f = "keypad_asterisk";
        left_shift = "keypad_enter";
        q = "keypad_4";
        r = "keypad_hyphen";
        s = "keypad_2";
        spacebar = "keypad_period";
        tab = "keypad_7";
        w = "keypad_5";
        x = "keypad_period";
        z = "keypad_0";
      };
      simple_modifications = [
        # { from_key_code = "q"; to_key_code = "keypad_7"; }
      ];
    };
  };

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
        identityFile = [ "~/.ssh/id_ed25519" ];
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
      set -g display-time 1000
      set -g set-titles on
      set -g mouse on
      set -g @continuum-restore 'on'
      # status bar theme: muted neutral palette for less visual noise
      set -g status-style "bg=colour236,fg=colour250"
      set -g window-status-style "bg=default,fg=colour245"
      set -g window-status-current-style "bg=colour239,fg=colour223,bold"
      set -g window-status-format " #I:#W "
      set -g window-status-current-format " #I:#W "
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
    # plugins managed by lazy.nvim, not nix
    plugins = [ ];
    extraPackages = with pkgs; [
      ripgrep
      fd
      tree-sitter
    ];
    # no extraLuaConfig - init.lua handles bootstrapping
  };

  home.packages = with pkgs; [

    # unix tooling
    bash-completion
    direnv # auto-activating shell envs
    oh-my-zsh
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
    vim
    git
    gnumake
    cmake
    pkg-config
    jq # command line json processor
    shellcheck
    shfmt # shell parser and formatter
    vale
    gh # github cli tool
    act # github action test
    (pkgs.writeShellScriptBin "code" ''
      # tmux + neovim "IDE" launcher (vscode-like):
      # - top-left: neovim with neo-tree file explorer
      # - top-right: claude code assistant
      # - bottom: zsh shell pane
      set -euo pipefail

      target_path="''${1:-.}"
      resolved_path="$(realpath "$target_path")"
      session="code-$(basename "$resolved_path")"
      shell_cmd="${pkgs.zsh}/bin/zsh"

      if tmux has-session -t "$session" 2>/dev/null; then
        exec tmux attach -t "$session"
      fi

      # create session with layout in a single command chain
      # split vertically first for full-width bottom pane, then horizontally on top
      exec tmux new-session -s "$session" -c "$resolved_path" \
        "nvim '+Neotree left reveal' ." \; \
        split-window -v -p 30 -c "$resolved_path" "$shell_cmd" \; \
        select-pane -t 0 \; \
        split-window -h -p 50 -c "$resolved_path" "claude" \; \
        select-pane -t 0
    '')
    grpcurl
    sqlite
    postgresql
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

    # rust
    rustup

    # go
    go_1_25

    # python
    (python3.withPackages (
      ps: with ps; [
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
          nativeBuildInputs = with ps; [
            setuptools
            wheel
          ];
          propagatedBuildInputs = with ps; [ ansible-core ];
        })
      ]
    ))

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
    nil # nix language server
    # marksman # markdown language server

    # cloud and infra
    opentofu
    k9s
    lazydocker # terminal ui for docker
    steampipe # select * from cloud

    # ai tooling
    fivetran-mcp-server
    github-mcp-server
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
    poppler-utils # pdf rendering and utilities (pdftotext, pdfinfo, etc.)
  ];
}
