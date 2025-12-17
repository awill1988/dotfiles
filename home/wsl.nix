{ config, pkgs, lib, ... }:
let
  inherit (lib) mkEnableOption mkOption types;
  cfg = config.aw.wsl;

  ps_bool = b: if b then "\\$true" else "\\$false";
in
{
  options.aw.wsl = {
    enable = mkEnableOption "wsl-specific configuration";

    usbipd = {
      enable = mkEnableOption "usbipd auto-attach at windows logon";
      busid = mkOption {
        type = types.str;
        default = "1-1";
      };
      auto_attach = mkOption {
        type = types.bool;
        default = true;
      };
      distro_name = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      wait_seconds = mkOption {
        type = types.int;
        default = 30;
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.activation.install_wsl_tasks =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                set -euo pipefail

                log_level="''${LOG_LEVEL:-info}"
                log_dbg() {
                  [ "$log_level" = debug ] && echo "wsl[debug] $*" >&2 || true
                }

                if ! grep -qi microsoft /proc/version 2>/dev/null; then
                  exit 0
                fi

                ps_cmd=""
                for cand in powershell.exe pwsh.exe \
                  /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe \
                  /mnt/c/Windows/System32/WindowsPowerShell/v1.0/pwsh.exe \
                  /mnt/c/Program\ Files/PowerShell/7/pwsh.exe \
                  /mnt/c/Program\ Files/PowerShell/7-preview/pwsh.exe; do
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

                ps5_cmd=""
                if [ -x /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe ]; then
                  ps5_cmd="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
                elif command -v powershell.exe >/dev/null 2>&1; then
                  ps5_cmd="powershell.exe"
                fi

                win_profile_win=""
                if command -v cmd.exe >/dev/null 2>&1; then
                  win_profile_win="$(cmd.exe /c echo %USERPROFILE% 2>/dev/null | tr -d '\r' || true)"
                fi
                if [ -z "$win_profile_win" ]; then
                  win_profile_win="$("$ps_cmd" -NoProfile -NonInteractive -Command "\$env:USERPROFILE" 2>/dev/null | tr -d '\r' || true)"
                fi

                win_profile_wsl=""
                if [ -n "$win_profile_win" ]; then
                  drive="''${win_profile_win%%:*}"
                  rest="''${win_profile_win#*:}"
                  rest="''${rest#\\}"
                  drive_lower="$(echo "$drive" | tr 'A-Z' 'a-z')"
                  win_profile_wsl="/mnt/$drive_lower/''${rest//\\//}"
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

                # --- install nerd fonts into windows per-user fonts directory ---
                fonts_dest="$win_profile_wsl/AppData/Local/Microsoft/Windows/Fonts"
                mkdir -p "$fonts_dest"

                font_sources=""
                for p in \
                  "$HOME/.nix-profile/share/fonts" \
                  "/etc/profiles/per-user/$USER/share/fonts" \
                  "${pkgs.nerd-fonts.sauce-code-pro}/share/fonts"; do
                  [ -d "$p" ] && font_sources="$font_sources $p"
                done

                if [ -z "$font_sources" ]; then
                  log_dbg "no font sources found; skipping windows font install"
                  exit 0
                fi

                whitelist_regex="(SauceCodePro|Sauce\\s*Code\\s*Pro|sauce)"
                ci_grep() { echo "$2" | grep -Eqi "$1"; }

                considered=0
                installed=0
                new_fonts_list="$(mktemp)"
        cleanup() {
          rm -f "$new_fonts_list" "''${registration_list:-}" "''${ps_script:-}" \
            "''${font_task_setup:-}" "''${usb_task_setup:-}" || true
        }
                trap cleanup EXIT

                for src in $font_sources; do
                  [ -d "$src" ] || continue
                  while IFS= read -r -d $'\0' font_file; do
                    considered=$((considered + 1))
                    file_name="$(basename "$font_file")"
                    if ! ci_grep "$whitelist_regex" "$file_name"; then
                      continue
                    fi
                    dest="$fonts_dest/$file_name"
                    if [ ! -f "$dest" ]; then
                      if cp -L "$font_file" "$dest" 2>/dev/null; then
                        installed=$((installed + 1))
                        echo "$dest" >> "$new_fonts_list"
                      else
                        log_dbg "copy failed: $font_file"
                      fi
                    fi
                  done < <(${pkgs.findutils}/bin/find -L "$src" -maxdepth 10 \( -iname '*.ttf' -o -iname '*.otf' \) -print0 2>/dev/null)
                done

                if [ $installed -gt 0 ]; then
                  echo "wsl: copied $installed new font file(s)"
                else
                  log_dbg "no new fonts copied; continuing with re-registration"
                fi

                registration_list="$(mktemp)"
                if [ -s "$new_fonts_list" ]; then
                  cat "$new_fonts_list" > "$registration_list"
                else
                  while IFS= read -r -d $'\0' font_file; do
                    file_name="$(basename "$font_file")"
                    if ! ci_grep "$whitelist_regex" "$file_name"; then
                      continue
                    fi
                    echo "$font_file" >> "$registration_list"
                  done < <(${pkgs.findutils}/bin/find -L "$fonts_dest" -maxdepth 1 \( -iname '*.ttf' -o -iname '*.otf' \) -print0 2>/dev/null)
                fi

                if [ ! -s "$registration_list" ]; then
                  log_dbg "no fonts found to register"
                  exit 0
                fi

                win_fonts_dest="''${win_profile_win}\\AppData\\Local\\Microsoft\\Windows\\Fonts"
                ps_script="$(mktemp).ps1"
                cat > "$ps_script" <<'PS_HEAD'
$ErrorActionPreference = "Stop"
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class FontUtil { [DllImport("gdi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern int AddFontResourceEx(string lpszFilename, uint fl, IntPtr pdv); }
'@
$fonts = @(
PS_HEAD
                while IFS= read -r wsl_font; do
                  [ -z "$wsl_font" ] && continue
                  bn="$(basename "$wsl_font")"
                  printf "  '%s\\\\%s'\n" "$win_fonts_dest" "$bn" >> "$ps_script"
                done < "$registration_list"
                cat >> "$ps_script" <<'PS_BODY'
)

$regPath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
if (-not (Test-Path $regPath)) { New-Item -Path $regPath | Out-Null }
$added = 0
foreach($f in $fonts){
if (-not (Test-Path $f)) { continue }
$bn = Split-Path $f -Leaf
$ext = [System.IO.Path]::GetExtension($bn).ToLowerInvariant()
$valueName = if ($ext -eq '.otf') { ($bn + ' (OpenType)') } else { ($bn + ' (TrueType)') }
try {
$res = [FontUtil]::AddFontResourceEx($f,0,[IntPtr]::Zero)
if ($res -gt 0) {
New-ItemProperty -Path $regPath -Name $valueName -Value $bn -Force | Out-Null
$added++
}
} catch {}
}
try { Add-Type -AssemblyName PresentationCore; [void][System.Windows.Media.Fonts]::SystemTypefaces } catch {}
if ($added -gt 0) {
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class Notify { [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd,uint Msg, UIntPtr wParam,string lParam,uint fuFlags,uint uTimeout,out UIntPtr lpdwResult); }
'@
[UIntPtr]$out = [UIntPtr]::Zero
[Notify]::SendMessageTimeout([IntPtr]0xffff,0x001D,[UIntPtr]::Zero,$null,0,1000,[ref]$out) | Out-Null
}
PS_BODY

                win_temp_dir="$win_profile_wsl/AppData/Local/Temp"
                mkdir -p "$win_temp_dir"
                win_script="$win_temp_dir/$(basename "$ps_script")"
                cp "$ps_script" "$win_script"
                chmod 0644 "$win_script" || true
                script_win_path="''${win_profile_win}\\AppData\\Local\\Temp\\$(basename "$ps_script")"

                reg_rc=0
                if [ "$log_level" = debug ]; then
                  "$ps_cmd" -NoProfile -ExecutionPolicy Bypass -File "$script_win_path" || reg_rc=$?
                else
                  "$ps_cmd" -NoProfile -ExecutionPolicy Bypass -File "$script_win_path" >/dev/null 2>&1 || reg_rc=$?
                fi
                if [ $reg_rc -ne 0 ]; then
                  echo "wsl: windows font registration failed; continuing"
                fi

                # --- persistence: scheduled task at logon (fonts) ---
        persist_dir="$win_profile_wsl/AppData/Local/FontReRegister"
        mkdir -p "$persist_dir"
        font_persist_script="$persist_dir/font-re-register.ps1"

        cat > "$font_persist_script" <<'PS_PERSIST'
$ErrorActionPreference = 'SilentlyContinue'
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class FontUtil { [DllImport("gdi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern int AddFontResourceEx(string lpszFilename, uint fl, IntPtr pdv); }
'@
$fontRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\\Windows\\Fonts'
if (Test-Path $fontRoot) {
$files = Get-ChildItem -Path $fontRoot -Include *.ttf,*.otf -File -Name
if ($files) {
$regPath = 'HKCU:\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts'
if (-not (Test-Path $regPath)) { New-Item -Path $regPath | Out-Null }
$added = 0
foreach($fn in $files){
$full = Join-Path $fontRoot $fn
if (-not (Test-Path $full)) { continue }
$ext = [System.IO.Path]::GetExtension($fn).ToLowerInvariant()
$valueName = if ($ext -eq '.otf') { ($fn + ' (OpenType)') } else { ($fn + ' (TrueType)') }
try {
$res = [FontUtil]::AddFontResourceEx($full,0,[IntPtr]::Zero)
if ($res -gt 0) {
New-ItemProperty -Path $regPath -Name $valueName -Value $fn -Force | Out-Null
$added++
}
} catch {}
}
if ($added -gt 0) {
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class Notify { [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd,uint Msg, UIntPtr wParam,string lParam,uint fuFlags,uint uTimeout,out UIntPtr lpdwResult); }
'@
[UIntPtr]$out=[UIntPtr]::Zero
[Notify]::SendMessageTimeout([IntPtr]0xffff,0x001D,[UIntPtr]::Zero,$null,0,1000,[ref]$out) | Out-Null
}
}
}
PS_PERSIST
        chmod 0644 "$font_persist_script" || true

        win_font_persist_script="''${win_profile_win}\\AppData\\Local\\FontReRegister\\font-re-register.ps1"
        font_task_setup="$(mktemp).ps1"
        {
          echo '$ErrorActionPreference = "Stop"'
          echo '$taskName = "font-re-register"'
          echo '$scriptPath = "'"$win_font_persist_script"'"'
          echo '$psExe = (Join-Path $env:SystemRoot "System32\\WindowsPowerShell\\v1.0\\powershell.exe")'
          echo '$action = New-ScheduledTaskAction -Execute $psExe -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""'
          echo '$trigger = New-ScheduledTaskTrigger -AtLogOn'
          echo 'try { $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest } catch { $principal = $null }'
          echo 'if (-not $principal) { $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited }'
          echo 'Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null'
        } > "$font_task_setup"

        font_task_setup_win="$win_temp_dir/$(basename "$font_task_setup")"
        cp "$font_task_setup" "$font_task_setup_win"
        chmod 0644 "$font_task_setup_win" || true
        font_task_setup_win_path="''${win_profile_win}\\AppData\\Local\\Temp\\$(basename "$font_task_setup")"

        task_cmd="''${ps5_cmd:-$ps_cmd}"
        font_task_rc=0
        if [ "$log_level" = debug ]; then
          "$task_cmd" -NoProfile -ExecutionPolicy Bypass -File "$font_task_setup_win_path" || font_task_rc=$?
        else
          "$task_cmd" -NoProfile -ExecutionPolicy Bypass -File "$font_task_setup_win_path" >/dev/null 2>&1 || font_task_rc=$?
        fi

        if [ $font_task_rc -ne 0 ]; then
          log_dbg "font task install failed; falling back to run key"
          "$task_cmd" -NoProfile -ExecutionPolicy Bypass -Command "try { New-Item -Path 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run' -ErrorAction SilentlyContinue | Out-Null; New-ItemProperty -Path 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run' -Name 'FontReRegister' -Value ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"\"$win_font_persist_script\"\"') -Force | Out-Null } catch { }" >/dev/null 2>&1 || true
        fi

        usbipd_enabled="${if cfg.usbipd.enable then "true" else "false"}"
        if [ "$usbipd_enabled" = "true" ]; then
          usb_dir="$win_profile_wsl/AppData/Local/UsbipdAttach"
          mkdir -p "$usb_dir"
          usb_persist_script="$usb_dir/usbipd-attach.ps1"

          cat > "$usb_persist_script" <<PS_USB_HEAD
\$ErrorActionPreference = 'SilentlyContinue'
\$usbipd_busid = '${cfg.usbipd.busid}'
\$usbipd_auto_attach = ${ps_bool cfg.usbipd.auto_attach}
\$wsl_distro_name = ${if cfg.usbipd.distro_name == null then "\\$null" else "'${cfg.usbipd.distro_name}'"}
\$wsl_wait_seconds = ${toString cfg.usbipd.wait_seconds}
PS_USB_HEAD

          cat >> "$usb_persist_script" <<'PS_USB'
try {
$usbipd = (Get-Command usbipd.exe -ErrorAction SilentlyContinue).Source
if (-not $usbipd) { $usbipd = (Get-Command usbipd -ErrorAction SilentlyContinue).Source }
if (-not $usbipd) {
$usbipd_default = 'C:\\Program Files\\usbipd-win\\usbipd.exe'
if (Test-Path $usbipd_default) { $usbipd = $usbipd_default }
}
if (-not $usbipd) {
Write-Host 'usbipd not found; skipping usb attach'
return
}

$distro = $wsl_distro_name
if (-not $distro) {
$distro = (& wsl.exe -l -q 2>$null | Select-Object -First 1).Trim()
}
if (-not $distro) {
Write-Host 'wsl distro not found; skipping usb attach'
return
}

$deadline = (Get-Date).AddSeconds([Math]::Max(0, $wsl_wait_seconds))
while ((Get-Date) -lt $deadline) {
& wsl.exe -d $distro -e /bin/sh -lc 'true' 1>$null 2>$null
if ($LASTEXITCODE -eq 0) { break }
Start-Sleep -Milliseconds 500
}

$args = @('attach','--wsl','--busid',$usbipd_busid)
if ($usbipd_auto_attach) { $args += '--auto-attach' }
& $usbipd @args 1>$null 2>$null
} catch {
Write-Host 'usbipd attach failed; continuing'
}
PS_USB
          chmod 0644 "$usb_persist_script" || true

          win_usb_persist_script="''${win_profile_win}\\AppData\\Local\\UsbipdAttach\\usbipd-attach.ps1"
          usb_task_setup="$(mktemp).ps1"
          {
            echo '$ErrorActionPreference = "Stop"'
            echo '$taskName = "usbipd-attach"'
            echo '$scriptPath = "'"$win_usb_persist_script"'"'
            echo '$psExe = (Join-Path $env:SystemRoot "System32\\WindowsPowerShell\\v1.0\\powershell.exe")'
            echo '$action = New-ScheduledTaskAction -Execute $psExe -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""'
            echo '$trigger = New-ScheduledTaskTrigger -AtLogOn'
            echo 'try { $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest } catch { $principal = $null }'
            echo 'if (-not $principal) { $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited }'
            echo 'Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null'
          } > "$usb_task_setup"

          usb_task_setup_win="$win_temp_dir/$(basename "$usb_task_setup")"
          cp "$usb_task_setup" "$usb_task_setup_win"
          chmod 0644 "$usb_task_setup_win" || true
          usb_task_setup_win_path="''${win_profile_win}\\AppData\\Local\\Temp\\$(basename "$usb_task_setup")"

          usb_task_rc=0
          if [ "$log_level" = debug ]; then
            "$task_cmd" -NoProfile -ExecutionPolicy Bypass -File "$usb_task_setup_win_path" || usb_task_rc=$?
          else
            "$task_cmd" -NoProfile -ExecutionPolicy Bypass -File "$usb_task_setup_win_path" >/dev/null 2>&1 || usb_task_rc=$?
          fi

          if [ $usb_task_rc -ne 0 ]; then
            log_dbg "usbipd task install failed"
          fi
        fi
        log_dbg "considered $considered font file(s)"
      '';
  };
}
