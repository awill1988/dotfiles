#!/usr/bin/env bash
set -euo pipefail

# nix-wsl-init: main activation script for wsl configuration
# This script handles font installation and windows scheduled tasks setup

log_level="${LOG_LEVEL:-info}"
log_dbg() {
  [ "$log_level" = debug ] && echo "wsl[debug] $*" >&2 || true
}

# exit early if not running in wsl
if ! grep -qi microsoft /proc/version 2>/dev/null; then
  exit 0
fi

log_dbg "Starting nix-wsl-init script"

# --- find powershell executable ---
ps_cmd=""
for cand in pwsh.exe powershell.exe \
  /mnt/c/Program\ Files/PowerShell/7/pwsh.exe \
  /mnt/c/Program\ Files/PowerShell/7-preview/pwsh.exe \
  /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe \
  /mnt/c/Windows/System32/WindowsPowerShell/v1.0/pwsh.exe; do
  if command -v "$cand" >/dev/null 2>&1; then
    ps_cmd="$cand"
    break
  fi
  if [ -x "$cand" ]; then
    ps_cmd="$cand"
    break
  fi
done

if [ -z "$ps_cmd" ]; then
  echo "wsl: powershell not found; skipping windows tasks"
  exit 0
fi
log_dbg "Found powershell command: $ps_cmd"

# --- determine windows profile directory ---
win_profile_win=""
if command -v cmd.exe >/dev/null 2>&1; then
  win_profile_win="$(cmd.exe /c echo %USERPROFILE% 2>/dev/null | tr -d '\r' || true)"
fi
if [ -z "$win_profile_win" ]; then
  win_profile_win="$($ps_cmd -NoProfile -NonInteractive -Command "[Environment]::GetFolderPath('UserProfile')" 2>/dev/null | tr -d '\r' || true)"
fi
log_dbg "Determined Windows profile (Windows path): $win_profile_win"

win_profile_wsl=""
if [ -n "$win_profile_win" ]; then
  drive="${win_profile_win%%:*}"
  rest="${win_profile_win#*:}"
  rest="${rest#\\}"
  drive_lower="$(echo "$drive" | tr 'A-Z' 'a-z')"
  win_profile_wsl="/mnt/$drive_lower/${rest//\\//}"
fi

if [ -z "$win_profile_wsl" ] || [ ! -d "$win_profile_wsl" ]; then
  for d in /mnt/c/Users/*; do
    base="$(basename "$d")"
    case "$base" in
      Public|Default|"Default User"|"All Users"|WDAGUtilityAccount) continue ;;
    esac
    if [ -d "$d" ] && [ -d "$d/AppData/Local" ]; then
      win_profile_wsl="$d"
      win_profile_win="C:\\Users\\$base"
      break
    fi
  done
fi

if [ -z "$win_profile_wsl" ] || [ ! -d "$win_profile_wsl" ]; then
  echo "wsl: could not determine windows profile dir; skipping windows tasks"
  exit 0
fi
log_dbg "Determined Windows profile (WSL path): $win_profile_wsl"


# --- install nerd fonts into windows per-user fonts directory ---
fonts_dest="$win_profile_wsl/AppData/Local/Microsoft/Windows/Fonts"
mkdir -p "$fonts_dest"

font_sources=""
for p in \
  "$HOME/.nix-profile/share/fonts" \
  "/etc/profiles/per-user/$USER/share/fonts" \
  "@FONT_PACKAGE_PATH@"; do
  [ -d "$p" ] && font_sources="$font_sources $p"
done

if [ -n "$font_sources" ]; then
  log_dbg "Starting font copying process"
  whitelist_regex="(SauceCodePro|Sauce\\s*Code\\s*Pro|sauce)"
  ci_grep() { echo "$2" | grep -Eqi "$1"; }

  installed=0
  for src in $font_sources; do
    [ -d "$src" ] || continue
    while IFS= read -r -d $'\0' font_file; do
      file_name="$(basename "$font_file")"
      if ! ci_grep "$whitelist_regex" "$file_name"; then
        continue
      fi
      dest="$fonts_dest/$file_name"
      if [ ! -f "$dest" ]; then
        # avoid chmod errors on drvfs by not preserving source mode/metadata
        if cp --no-preserve=mode,ownership,timestamps -L "$font_file" "$dest" 2>/dev/null; then
          installed=$((installed + 1))
          log_dbg "Copied font: $file_name to $dest"
        else
          log_dbg "copy failed: $font_file"
        fi
      fi
    done < <(@FIND_BIN@ -L "$src" -maxdepth 10 \( -iname '*.ttf' -o -iname '*.otf' \) -print0 2>/dev/null)
  done

  if [ $installed -gt 0 ]; then
    echo "wsl: copied $installed new font file(s)"
  else
    log_dbg "No new fonts copied."
  fi
  log_dbg "Finished font copying process"
fi


# --- setup scheduled tasks via powershell entrypoint ---
log_dbg "Starting scheduled tasks setup"
win_temp_dir="$win_profile_wsl/AppData/Local/Temp"
mkdir -p "$win_temp_dir"
ps_entrypoint="$win_temp_dir/nix-wsl-init.ps1"
ps_entrypoint_win="${win_profile_win}\\AppData\\Local\\Temp\\nix-wsl-init.ps1"

log_dbg "Copying PS_ENTRYPOINT to $ps_entrypoint"
cp "@PS_ENTRYPOINT@" "$ps_entrypoint"
chmod 0644 "$ps_entrypoint" || true

# copy supporting powershell modules using stable filenames
ps_logon_dest="$win_temp_dir/wsl-on-logon.ps1"
ps_task_dest="$win_temp_dir/setup-wsl-on-logon-task.ps1"

if [ -f "@PS_LOGON_SCRIPT@" ]; then
  log_dbg "Copying wsl-on-logon script to $ps_logon_dest"
  cp "@PS_LOGON_SCRIPT@" "$ps_logon_dest"
  chmod 0644 "$ps_logon_dest" || true
else
  log_dbg "Supporting PS file not found: @PS_LOGON_SCRIPT@"
fi

if [ -f "@PS_TASK_SETUP_SCRIPT@" ]; then
  log_dbg "Copying task setup script to $ps_task_dest"
  cp "@PS_TASK_SETUP_SCRIPT@" "$ps_task_dest"
  chmod 0644 "$ps_task_dest" || true
else
  log_dbg "Supporting PS file not found: @PS_TASK_SETUP_SCRIPT@"
fi

# run powershell entrypoint with proper version
task_cmd="$ps_cmd"
log_dbg "Executing PowerShell entrypoint: $task_cmd -File $ps_entrypoint_win"
ps_init_rc=0
"$task_cmd" -NoProfile -ExecutionPolicy Bypass -File "$ps_entrypoint_win" \
  -WinProfilePath "$win_profile_win" \
  -UsbipdEnabled "@USBIPD_ENABLED@" \
  -UsbipdBusId "@USBIPD_BUSID@" \
  -UsbipdAutoAttach "@USBIPD_AUTO_ATTACH@" \
  -WslDistroName "@WSL_DISTRO_NAME@" \
  -WslWaitSeconds "@WSL_WAIT_SECONDS@" \
  -PcscdEnabled "@PCSCD_ENABLED@" \
  -PcscdAutoStartBin "@PCSCD_AUTO_START_BIN@" || ps_init_rc=$?

if [ $ps_init_rc -ne 0 ]; then
  log_dbg "powershell init script failed with exit code: $ps_init_rc"
fi
log_dbg "Finished nix-wsl-init script"
