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
  install_pentest_foss_tools = pkgs.writeShellScriptBin "install-pentest-foss-tools" ''
    set -euo pipefail

    bin_dir="${config.home.homeDirectory}/.local/bin"
    share_dir="${config.xdg.dataHome}/pentest-tools"
    src_dir="$share_dir/src"
    dist_dir="$share_dir/dist"
    npm_prefix="${config.xdg.dataHome}/npm"

    mkdir -p "$bin_dir" "$src_dir" "$dist_dir" "$npm_prefix"

    fetch_latest_asset_url() {
      local repo="$1"
      local asset_regex="$2"

      ${pkgs.curl}/bin/curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
        | ${pkgs.jq}/bin/jq -r --arg asset_regex "$asset_regex" '
          .assets[]
          | select(.name | test($asset_regex))
          | .browser_download_url
        ' \
        | ${pkgs.coreutils}/bin/head -n 1
    }

    sync_repo() {
      local repo_url="$1"
      local repo_dir="$2"

      if [ -d "$repo_dir/.git" ]; then
        git -C "$repo_dir" pull --ff-only
      else
        git clone --depth 1 "$repo_url" "$repo_dir"
      fi
    }

    install_repo_python_tool() {
      local repo_url="$1"
      local repo_name="$2"
      local entry_script="$3"
      local command_name="$4"
      local repo_dir="$src_dir/$repo_name"
      local venv_dir="$repo_dir/.venv"

      echo "installing $command_name"
      sync_repo "$repo_url" "$repo_dir"

      ${pkgs.python3}/bin/python3 -m venv "$venv_dir"
      "$venv_dir/bin/pip" install --upgrade pip setuptools wheel
      if [ -f "$repo_dir/requirements.txt" ]; then
        "$venv_dir/bin/pip" install -r "$repo_dir/requirements.txt"
      fi

      printf '%s\n' \
        '#!/bin/sh' \
        "exec \"$venv_dir/bin/python\" \"$repo_dir/$entry_script\" \"\$@\"" \
        > "$bin_dir/$command_name"
      chmod 755 "$bin_dir/$command_name"
    }

    install_uv_tool() {
      local package_name="$1"
      local python_version="$2"

      echo "installing $package_name"
      if [ -n "$python_version" ]; then
        ${pkgs.uv}/bin/uv tool install --force --python "$python_version" "$package_name"
      else
        ${pkgs.uv}/bin/uv tool install --force "$package_name"
      fi
    }

    install_npm_tool() {
      local package_name="$1"

      echo "installing $package_name"
      export NPM_CONFIG_USERCONFIG="${config.xdg.configHome}/npm/config"
      export NPM_CONFIG_CACHE="${config.xdg.cacheHome}/npm"
      export NPM_CONFIG_PREFIX="$npm_prefix"
      mkdir -p "$(dirname "$NPM_CONFIG_USERCONFIG")" "$NPM_CONFIG_CACHE" "$NPM_CONFIG_PREFIX"

      ${config.modules.dev.node.package}/bin/npm install -g "$package_name"
    }

    install_uber_apk_signer() {
      local jar_url
      jar_url="$(fetch_latest_asset_url "patrickfav/uber-apk-signer" "uber-apk-signer-.*\\.jar$")"

      echo "installing uber-apk-signer"
      ${pkgs.curl}/bin/curl -fsSL "$jar_url" -o "$dist_dir/uber-apk-signer.jar"

      printf '%s\n' \
        '#!/bin/sh' \
        "exec ${pkgs.jdk}/bin/java -jar \"$dist_dir/uber-apk-signer.jar\" \"\$@\"" \
        > "$bin_dir/uber-apk-signer"
      chmod 755 "$bin_dir/uber-apk-signer"
    }

    install_optool() {
      local zip_url
      local tmp_dir

      zip_url="$(fetch_latest_asset_url "alexzielenski/optool" "optool\\.zip$")"
      tmp_dir="$(${pkgs.coreutils}/bin/mktemp -d)"

      echo "installing optool"
      ${pkgs.curl}/bin/curl -fsSL "$zip_url" -o "$tmp_dir/optool.zip"
      ${pkgs.unzip}/bin/unzip -oq "$tmp_dir/optool.zip" -d "$tmp_dir"
      install -m 755 "$tmp_dir/optool" "$bin_dir/optool"
    }

    install_dsdump() {
      local repo_dir="$src_dir/dsdump"
      local tmp_dir

      echo "installing dsdump"
      sync_repo "https://github.com/DerekSelander/dsdump.git" "$repo_dir"

      tmp_dir="$(${pkgs.coreutils}/bin/mktemp -d)"
      ${pkgs.unzip}/bin/unzip -oq "$repo_dir/compiled/dsdump_compiled.zip" -d "$tmp_dir"
      install -m 755 "$tmp_dir/dsdump" "$bin_dir/dsdump"

      printf '%s\n' \
        '#!/bin/sh' \
        "exec \"$bin_dir/dsdump\" \"\$@\"" \
        > "$bin_dir/class-dump"
      chmod 755 "$bin_dir/class-dump"
    }

    install_zap() {
      local zip_url
      local tmp_dir
      local zap_root

      zip_url="$(fetch_latest_asset_url "zaproxy/zaproxy" "ZAP_.*_Crossplatform\\.zip$")"
      tmp_dir="$(${pkgs.coreutils}/bin/mktemp -d)"

      echo "installing owasp zap"
      ${pkgs.curl}/bin/curl -fsSL "$zip_url" -o "$tmp_dir/zap.zip"
      ${pkgs.unzip}/bin/unzip -oq "$tmp_dir/zap.zip" -d "$dist_dir"
      zap_root="$(${pkgs.findutils}/bin/find "$dist_dir" -maxdepth 1 -type d -name 'ZAP_*' | ${pkgs.coreutils}/bin/head -n 1)"

      printf '%s\n' \
        '#!/bin/sh' \
        "cd \"$zap_root\"" \
        'exec ./zap.sh "$@"' \
        > "$bin_dir/zap.sh"
      chmod 755 "$bin_dir/zap.sh"

      printf '%s\n' \
        '#!/bin/sh' \
        "exec \"$bin_dir/zap.sh\" \"\$@\"" \
        > "$bin_dir/zaproxy"
      chmod 755 "$bin_dir/zaproxy"
    }

    install_uv_tool "frida-tools" "3.11"
    install_uv_tool "objection" "3.11"
    install_uv_tool "drozer" "3.11"
    install_uv_tool "mobsf" "3.11"
    install_npm_tool "apk-mitm"
    install_repo_python_tool "https://github.com/ticarpi/jwt_tool.git" "jwt_tool" "jwt_tool.py" "jwt_tool"
    install_repo_python_tool "https://github.com/AloneMonkey/frida-ios-dump.git" "frida-ios-dump" "dump.py" "frida-ios-dump"
    install_uber_apk_signer
    install_optool
    install_dsdump
    install_zap
  '';
in
{
  programs.home-manager.enable = true;

  modules.dev.node.enable = true;

  programs.mise = {
    enable = true;
    enableZshIntegration = true;
    # stable 25.11 ships mise 2025.11.x; pull the newer build from unstable
    # (the pkgs-unstable overlay exists for exactly this cherry-pick) so the
    # fast-moving tool stays current without bumping the whole nixpkgs pin.
    package = pkgs.pkgs-unstable.mise;
  };
  programs.codex.enable = true;
  programs.agy.enable = true;
  programs.agent-skills.enable = true;
  programs.contextforge.enable = true;
  programs.blender-mcp = {
    enable = true;
    # populate per-host once blender major.minor versions are confirmed
    blenderAddonVersions = [ ];
  };
  programs.drive-mcp.enable = true;
  programs.hunyuan3d.enable = false;
  programs.claude = {
    enable = true;
    primary = { };
    secondary = {
      pathPrefix = "$HOME/projects/arro";
      awsProfile = "arro-staging";
      awsRegion = "us-west-2";
      excludeMcpServers = [ "blender" ];
      mcpServers = {
        atlassian = {
          command = "npx";
          args = [
            "-y"
            "mcp-remote"
            "https://mcp.atlassian.com/v1/mcp"
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
        figma = {
          command = "npx";
          args = [
            "-y"
            "mcp-remote"
            "https://mcp.figma.com/mcp"
          ];
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
        posthog = {
          command = "npx";
          args = [
            "-y"
            "mcp-remote@latest"
            "https://mcp.posthog.com/mcp"
          ];
        };
        sentry = {
          command = "npx";
          args = [
            "-y"
            "mcp-remote"
            "https://mcp.sentry.dev/mcp"
          ];
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

  programs.zoxide.enable = true;
  programs.zoxide.enableBashIntegration = true;
  programs.zoxide.enableZshIntegration = true;

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
      set -g display-time 3000
      set -g set-titles on
      set -g mouse on
      # keep failed panes visible with their exit status (clean exits still close).
      # prefix-? opens the tmux message log so errors past the status flash stay
      # readable.
      setw -g remain-on-exit failed
      bind ? show-messages
      set -g @continuum-restore 'on'
      # restore the visible scrollback of every pane (shell prompts, last
      # commands, claude output) so tmux server restarts come up populated
      # rather than empty. saves a few tens of KB per pane.
      set -g @resurrect-capture-pane-contents 'on'
      # resurrect knows how to relaunch nvim with the matching session file
      # written by persistence.nvim — keyed off cwd, so each project's nvim
      # comes back with its prior buffers/splits.
      set -g @resurrect-strategy-nvim 'session'
      set -g @resurrect-strategy-vim 'session'
      # tighter snapshot cadence so the gap between "last good state" and
      # "tmux died" is bounded by 5 min instead of the default 15.
      set -g @continuum-save-interval '5'
      # status bar palette is driven by stylix (home/theme.nix); leave the
      # bg/fg styles unset here so the active base16 scheme fills them in.
      # #F surfaces pane flags (notably Z for zoom) so a stray <prefix>z is obvious
      set -g window-status-format " #I:#W#F "
      set -g window-status-current-format " #I:#W#F "
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
      # vim-tmux-navigator: prefix-free C-h/j/k/l that crosses into nvim splits
      is_vim="ps -o state= -o comm= -t '#{pane_tty}' | grep -iqE '^[^TXZ ]+ +(\\S+\\/)?g?(view|l?n?vim?x?|fzf)(diff)?$'"
      bind-key -n 'C-h' if-shell "$is_vim" 'send-keys C-h' 'select-pane -L'
      bind-key -n 'C-j' if-shell "$is_vim" 'send-keys C-j' 'select-pane -D'
      bind-key -n 'C-k' if-shell "$is_vim" 'send-keys C-k' 'select-pane -U'
      bind-key -n 'C-l' if-shell "$is_vim" 'send-keys C-l' 'select-pane -R'
      bind-key -T copy-mode-vi 'C-h' select-pane -L
      bind-key -T copy-mode-vi 'C-j' select-pane -D
      bind-key -T copy-mode-vi 'C-k' select-pane -U
      bind-key -T copy-mode-vi 'C-l' select-pane -R
      # home-manager writes the config to the XDG path, not ~/.tmux.conf; point
      # the reload bind at the real file so `prefix r` actually re-sources.
      bind r source-file ~/.config/tmux/tmux.conf \; display-message "tmux reloaded"
      # quick exits (vim-like: prefix + z / Z)
      bind z confirm-before -p "kill-window? (y/n)" kill-window
      bind Z confirm-before -p "kill-session? (y/n)" kill-session
      # prefix+e toggles the code picker (mnemonic: explorer, matching nvim's
      # <leader>e neo-tree toggle). the no-prefix alt-space variant is
      # intentionally omitted: on wsl/windows the win32 window manager claims
      # alt-space for the window system menu, so the keystroke never reaches
      # tmux. the toggle logic lives in `code --toggle-picker` (single source of
      # truth, shellchecked); the bind only resolves the target window and passes
      # it as an argument. we pass #{session_name}:#{window_index}, never
      # #{session_id}: a session id such as `$10` gets re-expanded by run-shell's
      # sh -c as positional parameter $1 followed by `0`, collapsing the target
      # to `0` ("can't find session: 0"). names and indices carry no $ or @, so
      # they survive intact.
      bind e run-shell "code --toggle-picker '#{session_name}:#{window_index}'"
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
    mqttx-cli # mqtt cli (replaces untrusted emqx/mqttx homebrew tap)

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
    (pkgs.writeShellApplication {
      name = "code";
      # runtimeInputs are prepended to PATH so bare binary names resolve to the
      # pinned nix-store builds; writeShellApplication also runs shellcheck at
      # build time, gating the script against quoting/expansion regressions.
      runtimeInputs = with pkgs; [
        zoxide
        fzf
        tmux
        fd
        zsh
        neovim
        gawk
      ];
      text = ''
        # tmux + neovim "IDE" launcher and sidebar project picker.
        # one binary, four modes:
        #   code [path]            -> launcher: attach or create code-{basename}
        #   code -f|--rebuild [p]  -> launcher: kill existing session for p, recreate
        #   code --picker          -> sidebar picker loop (invoked by tmux pane)
        #   code --toggle-picker T -> toggle the picker pane in tmux target T
        #                             (T is session_name:window_index; bind-only)
        # layout:
        #   left (24 cols): code --picker (fzf over active sessions + zoxide)
        #   top-right:      neovim with neo-tree
        #   bottom-mid:     zsh
        #   bottom-right:   claude
        # writeShellApplication already injects `set -euo pipefail` and puts
        # runtimeInputs on PATH, so bare names resolve to the pinned builds
        # regardless of the invoking tmux pane's PATH.
        zoxide_bin="zoxide"
        fzf_bin="fzf"
        tmux_bin="tmux"
        fd_bin="fd"
        shell_bin="zsh"
        # prefer the user's ~/.local/bin/claude wrapper (sets CLAUDE_CONFIG_DIR
        # and AWS_PROFILE based on cwd); fall back to the wrapper on PATH.
        # claude is deliberately NOT in runtimeInputs: that would prepend the
        # unwrapped binary to PATH and shadow the routing wrapper, breaking the
        # secondary identity (it would read ~/.config/claude instead).
        claude_bin="$HOME/.local/bin/claude"
        [ -x "$claude_bin" ] || claude_bin="claude"
        nvim_bin="nvim"
        self="$0"

        run_picker() {
          # row format (rendered with fzf --ansi):
          #   <dim>parent</dim>/<color>icon</color> <bold>name</bold>\t<ref>
          # parent = basename of dirname(path); when unknown, omitted with a leading space.
          # icons: codicons terminal (sessions), devicons git (repos), FA folder (dirs).
          local DIM=$'\e[2m' BOLD=$'\e[1m' R=$'\e[0m'
          local CYAN=$'\e[36m' GREEN=$'\e[32m' YELLOW=$'\e[33m'
          # plain Unicode shapes (Geometric Shapes block, present in every
          # monospace font). ANSI color does the heavy lifting; shape reinforces.
          # U+276F heavy chevron (session), U+25C6 black diamond (git), U+25C7
          # white diamond (dir).
          local ICON_SESSION ICON_GIT ICON_DIR
          printf -v ICON_SESSION '\xe2\x9d\xaf'
          printf -v ICON_GIT     '\xe2\x97\x86'
          printf -v ICON_DIR     '\xe2\x97\x87'

          emit() {
            # args: ref icon icon_color path
            local ref="$1" icon="$2" color="$3" path="$4"
            local name parent
            name="$(basename "$path")"
            parent="$(basename "$(dirname "$path")")"
            if [ -n "$parent" ] && [ "$parent" != "/" ]; then
              printf '%s%s%s/%s%s%s %s%s%s\t%s\n' \
                "$DIM" "$parent" "$R" \
                "$color" "$icon" "$R" \
                "$BOLD" "$name" "$R" \
                "$ref"
            else
              printf '%s%s%s %s%s%s\t%s\n' \
                "$color" "$icon" "$R" \
                "$BOLD" "$name" "$R" \
                "$ref"
            fi
          }

          list_sources() {
            # pass 1: active sessions (always shown first, regardless of zoxide).
            # also collect basenames so we can suppress duplicate dir rows below.
            local -a active_names=()
            while IFS='|' read -r sess proj; do
              [ -n "$sess" ] || continue
              local name="''${sess#code-}"
              active_names+=("$name")
              if [ -n "$proj" ] && [ -d "$proj" ]; then
                emit "session:$sess" "$ICON_SESSION" "$CYAN" "$proj"
              else
                # legacy session without @project-dir: synthesize a path-less row
                # so the rest of the format machinery still works.
                emit "session:$sess" "$ICON_SESSION" "$CYAN" "/$name"
              fi
            done < <(
              "$tmux_bin" list-sessions -F '#{session_name}|#{@project-dir}' 2>/dev/null \
                | grep '^code-'
            )

            is_active() {
              local needle="$1" n
              for n in "''${active_names[@]+"''${active_names[@]}"}"; do
                [ "$n" = "$needle" ] && return 0
              done
              return 1
            }

            # pass 2: zoxide entries, skipping any whose basename is already an
            # active session (dedup) and picking icon based on git presence.
            local zoxide_count=0
            while IFS= read -r d; do
              [ -d "$d" ] || continue
              d="''${d%/}"
              local name; name="$(basename "$d")"
              is_active "$name" && continue
              if [ -d "$d/.git" ] || [ -f "$d/.git" ]; then
                emit "dir:$d" "$ICON_GIT" "$GREEN" "$d"
              else
                emit "dir:$d" "$ICON_DIR" "$YELLOW" "$d"
              fi
              zoxide_count=$((zoxide_count + 1))
            done < <("$zoxide_bin" query --list 2>/dev/null)

            # fd fallback when zoxide is empty — only emits git repos.
            if [ "$zoxide_count" -eq 0 ] && [ -d "$HOME/projects" ]; then
              "$fd_bin" -t d -H --max-depth 3 . "$HOME/projects" 2>/dev/null \
                | while IFS= read -r d; do
                    d="''${d%/}"
                    [ -d "$d/.git" ] || [ -f "$d/.git" ] || continue
                    local name; name="$(basename "$d")"
                    is_active "$name" && continue
                    emit "dir:$d" "$ICON_GIT" "$GREEN" "$d"
                  done
            fi
          }

          while true; do
            # --highlight-line wraps the selection bg across the full row including
            # the parent prefix; reverse on current-fg swaps fg/bg so the row reads
            # as a single highlighted band. pointer is the heavy filled triangle
            # so it doesn't get confused with the diamond row icons.
            if ! selection=$(
              list_sources \
              | awk '!seen[$0]++' \
              | "$fzf_bin" --ansi --reverse --no-info \
                           --delimiter=$'\t' --with-nth=1 \
                           --pointer='▶' \
                           --highlight-line \
                           --color='pointer:bright-magenta:bold,current-bg:-1,current-fg:-1:reverse' \
                           --bind='double-click:accept' \
                           --prompt='code › ' \
                           --header='⏎ open · esc cancel' --header-first
            ); then
              # esc / no match — keep the picker visible so the user can retry
              sleep 0.15
              continue
            fi

            ref="''${selection#*$'\t'}"
            case "$ref" in
              session:*)
                target="''${ref#session:}"
                # round-trip through `code` so stale layouts get rebuilt. for
                # legacy sessions without @project-dir, guess via zoxide; if no
                # match, fall back to bare switch-client (no rebuild).
                proj_dir=$("$tmux_bin" show-option -qv -t "$target" "@project-dir" 2>/dev/null || true)
                if [ -z "''${proj_dir:-}" ] || [ ! -d "$proj_dir" ]; then
                  base="''${target#code-}"
                  proj_dir=$(
                    "$zoxide_bin" query --list 2>/dev/null \
                      | while IFS= read -r d; do
                          [ -d "$d" ] && [ "$(basename "$d")" = "$base" ] && printf '%s\n' "$d" && break
                        done | head -n1
                  )
                fi
                if [ -n "''${proj_dir:-}" ] && [ -d "$proj_dir" ]; then
                  # locate the destination's nvim pane (if any) so we can reset
                  # cwd in-place instead of killing the session — preserves the
                  # shell pane's history/in-flight command and claude's chat.
                  nvim_pane=$("$tmux_bin" list-panes -t "$target" \
                    -F '#{pane_id} #{pane_current_command}' 2>/dev/null \
                    | awk '$2=="nvim"{print $1; exit}')
                  if [ -n "$nvim_pane" ]; then
                    "$tmux_bin" switch-client -t "$target" 2>/dev/null || true
                    # Escape first to drop out of insert/visual modes safely; the
                    # chained :cd | Neotree command runs as one user-typed line.
                    "$tmux_bin" send-keys -t "$nvim_pane" Escape || true
                    "$tmux_bin" send-keys -t "$nvim_pane" \
                      ":cd $proj_dir | Neotree filesystem reveal_force_cwd" Enter || true
                  else
                    # nvim gone — session has decayed, do a clean rebuild.
                    "$self" --rebuild "$proj_dir" || true
                  fi
                else
                  "$tmux_bin" switch-client -t "$target" 2>/dev/null || true
                fi
                exit 0
                ;;
              dir:*)
                "$self" "''${ref#dir:}" || true
                exit 0
                ;;
            esac
          done
        }

        toggle_picker() {
          # toggle the sidebar picker for the tmux target passed by the bind as
          # session_name:window_index. lives here (not inlined in tmux config)
          # so it is shellchecked and shared by both binds; the bind resolves the
          # target with format vars that carry no $ or @, so the value survives
          # run-shell's sh -c without positional-parameter expansion.
          local target="$1" picker_pane
          picker_pane=$("$tmux_bin" list-panes -t "$target" \
            -F '#{pane_id} #{pane_start_command}' 2>/dev/null \
            | awk '/--picker/{print $1; exit}')
          if [ -n "$picker_pane" ]; then
            "$tmux_bin" kill-pane -t "$picker_pane"
          else
            "$tmux_bin" split-window -hbf -l 24 -t "$target" "$self --picker"
          fi
        }

        mode=launch
        force=0
        case "''${1:-}" in
          --picker)            mode=picker; shift ;;
          --toggle-picker)     mode=toggle; shift ;;
          -f|--rebuild|--new)  force=1;     shift ;;
        esac

        if [ "$mode" = "picker" ]; then
          run_picker
          exit 0
        fi

        if [ "$mode" = "toggle" ]; then
          toggle_picker "''${1:-}"
          exit 0
        fi

        target_path="''${1:-.}"
        resolved_path="$(realpath "$target_path")"

        # session name derivation. two failure modes to defend against:
        #   1. tmux target syntax treats `.` and `:` as window/pane separators,
        #      so `code-yourmood.ai` parses as session `code-yourmood`
        #      window `ai`. sanitize anything outside [A-Za-z0-9_-] to `-`.
        #   2. two checkouts with the same basename (e.g. ~/projects/arro/
        #      arro-platform and ~/work/arro-platform) collide. if an existing
        #      `code-*` session points at a different @project-dir, suffix the
        #      name with a short hash of resolved_path to disambiguate.
        sanitize_name() {
          printf '%s' "$1" | tr -c 'A-Za-z0-9_-' '-' | sed 's/-\{2,\}/-/g; s/^-//; s/-$//'
        }
        path_hash() {
          printf '%s' "$1" | shasum | cut -c1-6
        }
        base_name="$(sanitize_name "$(basename "$resolved_path")")"
        [ -n "$base_name" ] || base_name="$(path_hash "$resolved_path")"
        session="code-$base_name"
        if "$tmux_bin" has-session -t "=$session" 2>/dev/null; then
          existing_dir=$("$tmux_bin" show-option -qv -t "=$session" "@project-dir" 2>/dev/null || true)
          if [ -n "$existing_dir" ] && [ "$existing_dir" != "$resolved_path" ]; then
            session="code-$base_name-$(path_hash "$resolved_path")"
          fi
        fi

        # detached sessions default to 80x24, which makes absolute -l sizes
        # scale wrongly when the real client attaches. seed dimensions from
        # the controlling terminal so the layout lands at the right scale.
        detect_size() {
          # inside tmux, prefer the client (terminal) size — stty reports the
          # calling pane's size, which is wrong when code runs from the narrow
          # picker pane and we want the new session to match the full terminal.
          if [ -n "''${TMUX:-}" ]; then
            cols=$("$tmux_bin" display-message -p '#{client_width}' 2>/dev/null || true)
            rows=$("$tmux_bin" display-message -p '#{client_height}' 2>/dev/null || true)
          fi
          if [ -z "''${cols:-}" ] || [ -z "''${rows:-}" ]; then
            if size=$(stty size </dev/tty 2>/dev/null) && [ -n "$size" ]; then
              rows="''${size% *}"; cols="''${size#* }"
            fi
          fi
          : "''${cols:=$(tput cols 2>/dev/null || echo 0)}"
          : "''${rows:=$(tput lines 2>/dev/null || echo 0)}"
          [ "$cols" -ge 120 ] 2>/dev/null || cols=220
          [ "$rows" -ge 30 ]  2>/dev/null || rows=55
        }
        detect_size

        spawn_session() {
          local log="/tmp/code-spawn-$session.log"
          : >"$log"
          # capture each new pane's id so subsequent splits target unambiguously.
          # this dodges base-index / window-index assumptions and surfaces errors
          # per step instead of silently chaining onto the wrong pane.
          # 3-pane default layout. The picker is on-demand only — prefix+e
          # spawns it as a 4th pane, and the single-shot picker collapses it
          # after a selection (or via prefix+e again).
          local nvim_pane shell_pane
          {
            nvim_pane=$("$tmux_bin" new-session -d -s "$session" -c "$resolved_path" \
              -x "$cols" -y "$rows" \
              -P -F '#{pane_id}' \
              "$nvim_bin '+Neotree filesystem show position=left' .") \
              || { echo "new-session failed" >&2; return 1; }

            shell_pane=$("$tmux_bin" split-window -v -l 30% \
              -t "$nvim_pane" -c "$resolved_path" \
              -P -F '#{pane_id}' \
              "$shell_bin") \
              || echo "shell split failed" >&2

            "$tmux_bin" split-window -h -l 50% \
              -t "$shell_pane" -c "$resolved_path" \
              "$claude_bin" \
              || echo "claude split failed" >&2

            "$tmux_bin" select-pane -t "$nvim_pane" || true

            # record the project dir on the session so the picker can hand
            # active sessions back to `code --rebuild` to reset cwd to root.
            "$tmux_bin" set-option -t "$session" "@project-dir" "$resolved_path" \
              >/dev/null 2>&1 || true
          } 2>>"$log"
          return 0
        }

        session_is_stale() {
          # healthy session: nvim is one of the panes. anything else (no nvim,
          # zero panes, etc.) means the session has decayed and should rebuild.
          local panes
          panes=$("$tmux_bin" list-panes -t "$session" -F '#{pane_current_command}' 2>/dev/null) || return 0
          printf '%s\n' "$panes" | grep -q '^nvim$' || return 0
          return 1
        }

        if "$tmux_bin" has-session -t "=$session" 2>/dev/null; then
          if [ "$force" -eq 1 ]; then
            "$tmux_bin" kill-session -t "$session"
          elif session_is_stale; then
            echo "code: rebuilding stale '$session' (layout mismatch)" >&2
            "$tmux_bin" kill-session -t "$session"
          fi
        fi

        if [ -n "''${TMUX:-}" ]; then
          "$tmux_bin" has-session -t "=$session" 2>/dev/null || spawn_session
          exec "$tmux_bin" switch-client -t "$session"
        fi

        if "$tmux_bin" has-session -t "=$session" 2>/dev/null; then
          exec "$tmux_bin" attach -t "$session"
        fi
        spawn_session
        exec "$tmux_bin" attach -t "$session"
      '';
    })
    grpcurl
    sqlite
    postgresql
    jsonnet
    qemu
    protobuf
    openssl
    onnxruntime

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
    cf2tf # convert cloudformation to terraform/opentofu
    pkgs-unstable.opentofu # tracks latest upstream (stable channel lags by ~one minor)
    k9s
    lazydocker # terminal ui for docker
    steampipe # select * from cloud

    # ai tooling
    drawio-mcp
    fivetran-mcp-server
    github-mcp-server
    llama-cpp

    # nix tools
    cachix
    nixfmt-classic

    # android
    mtkclient # mediatek bootrom exploit tool
    apksigner
    ghidra

    # security and credentials
    python3Packages.checkdmarc
    gitleaks
    gnupg
    grype # vulnerability scanner for container images and filesystems
    gpgme # make gnupg easier
    mitmproxy
    nikto
    nuclei
    pass # "password manager"
    radare2
    semgrep
    testssl
    trivy # container and filesystem vulnerability scanner
    trufflehog
    xkcdpass # generate passwords
    yubikey-manager # configure yubikeys
    nmap

    # media and conversion
    ffmpeg # video processing and conversion
    imagemagick
    midicsv
    poppler-utils # pdf rendering and utilities (pdftotext, pdfinfo, etc.)
    install_pentest_foss_tools
  ];
}
