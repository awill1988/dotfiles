{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.modules.editor.code;
in
{
  options.modules.editor.code = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable custom code launcher executable (tmux + neovim + claude workspace IDE launcher).";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      (pkgs.writeShellApplication {
        name = "code";
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
          zoxide_bin="zoxide"
          fzf_bin="fzf"
          tmux_bin="tmux"
          fd_bin="fd"
          shell_bin="zsh"
          claude_bin="$HOME/.local/bin/claude"
          [ -x "$claude_bin" ] || claude_bin="claude"
          nvim_bin="nvim"
          self="$0"

          run_picker() {
            local DIM=$'\e[2m' BOLD=$'\e[1m' R=$'\e[0m'
            local CYAN=$'\e[36m' GREEN=$'\e[32m' YELLOW=$'\e[33m'
            local ICON_SESSION ICON_GIT ICON_DIR
            printf -v ICON_SESSION '\xe2\x9d\xaf'
            printf -v ICON_GIT     '\xe2\x97\x86'
            printf -v ICON_DIR     '\xe2\x97\x87'

            emit() {
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
              local -a active_names=()
              while IFS='|' read -r sess proj; do
                [ -n "$sess" ] || continue
                local name="''${sess#code-}"
                active_names+=("$name")
                if [ -n "$proj" ] && [ -d "$proj" ]; then
                  emit "session:$sess" "$ICON_SESSION" "$CYAN" "$proj"
                else
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
                sleep 0.15
                continue
              fi

              ref="''${selection#*$'\t'}"
              case "$ref" in
                session:*)
                  target="''${ref#session:}"
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
                    nvim_pane=$("$tmux_bin" list-panes -t "$target" \
                      -F '#{pane_id} #{pane_current_command}' 2>/dev/null \
                      | awk '$2=="nvim"{print $1; exit}')
                    if [ -n "$nvim_pane" ]; then
                      "$tmux_bin" switch-client -t "$target" 2>/dev/null || true
                      "$tmux_bin" send-keys -t "$nvim_pane" Escape || true
                      "$tmux_bin" send-keys -t "$nvim_pane" \
                        ":cd $proj_dir | Neotree filesystem reveal_force_cwd" Enter || true
                    else
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

          detect_size() {
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

              "$tmux_bin" set-option -t "$session" "@project-dir" "$resolved_path" \
                >/dev/null 2>&1 || true
            } 2>>"$log"
            return 0
          }

          session_is_stale() {
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
    ];
  };
}
