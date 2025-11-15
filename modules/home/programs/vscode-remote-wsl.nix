{ config, lib, pkgs, ... }:
let
  cfg = config.programs.remoteVscode;
  baselineSettings = {
    "editor.fontFamily" = "FiraCode Nerd Font Mono, monospace";
    "editor.fontLigatures" = true;
    "terminal.integrated.fontFamily" = "FiraCode Nerd Font Mono, monospace";
    "terminal.integrated.fontLigatures" = true;
  };
  baselineFile = pkgs.writeText "vscode-remote-wsl-settings.json"
    (builtins.toJSON baselineSettings);
  boolStr = b: if b then "true" else "false";
in {
  options.programs.remoteVscode = {
    enable = lib.mkEnableOption
      "Manage Windows VS Code (Remote WSL) settings.json font-related keys";
    backup = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description =
        "Create timestamped backup of existing settings.json before modifying.";
    };
    enforce = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description =
        "If true, override font keys every activation. If false, only add them when missing.";
    };
    syncFonts = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description =
        "If true, copy managed font files into Windows per-user Fonts directory and register them.";
    };
    powerShellCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description =
        "Override command/path to invoke Windows PowerShell (powershell.exe) or PowerShell 7 (pwsh.exe). If null, attempt auto-detection.";
    };
    fontWhitelistRegex = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "(Fira|Nerd|Deja|Source|JetBrains)";
      description =
        "Case-insensitive regex applied to font filenames; only matches are synced. Null disables filtering.";
    };
    addRunKey = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description =
        "If true, install an HKCU Run key that re-registers all synced fonts at each Windows logon (persistence across reboot).";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.jq ];
    home.activation.vscodeRemoteSettings =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              set -eu

              debug_flag="''${DEBUG_REMOTE_VSCODE_FONTS:-0}"
              log_dbg() { [ "$debug_flag" = 1 ] && echo "[remoteVscode][debug] $*" >&2 || true; }

              # --- Detect Windows username (heuristic) ---
              winUser=""
              for d in /mnt/c/Users/*; do
                base="$(basename "$d")"
                case "$base" in
                  Public|Default|"Default User"|"All Users"|WDAGUtilityAccount) continue ;;
                esac
                if [ -d "$d/AppData/Roaming/Code/User" ]; then
                  winUser="$base"; break
                fi
              done
              if [ -z "$winUser" ]; then
                echo "[remoteVscode] Could not determine Windows username; aborting." >&2
                exit 0
              fi
              settingsDir="/mnt/c/Users/$winUser/AppData/Roaming/Code/User"
              settingsFile="$settingsDir/settings.json"
              mkdir -p "$settingsDir"

              # --- Merge / Enforce settings.json font keys ---
              if [ -f "$settingsFile" ] && ${boolStr cfg.backup}; then
                cp "$settingsFile" "$settingsFile.bak.$(date +%Y%m%d%H%M%S)"
              fi
              if command -v jq >/dev/null 2>&1 && [ -f "$settingsFile" ]; then
                if ${boolStr cfg.enforce}; then
                  # User first then baseline overrides relevant keys
                  jq -s '.[0] * .[1]' "$settingsFile" "${baselineFile}" > "$settingsFile.tmp" || cp "${baselineFile}" "$settingsFile.tmp"
                else
                  # Baseline first; user may override if already set
                  jq -s '.[0] * .[1]' "${baselineFile}" "$settingsFile" > "$settingsFile.tmp" || cp "${baselineFile}" "$settingsFile.tmp"
                fi
                mv "$settingsFile.tmp" "$settingsFile"
              else
                cp "${baselineFile}" "$settingsFile"
              fi

              # Helper: Convert WSL path to Windows path (prefers wslpath; falls back to UNC)
              wsl_win_path() {
                # Convert a WSL path to a Windows path robustly.
                # Preference order: wslpath -> /mnt/<drive> mapping -> UNC fallback.
                local original="$1" real
                if command -v readlink >/dev/null 2>&1; then
                  real="$(readlink -f "$original" 2>/dev/null || printf '%s' "$original")"
                else
                  real="$original"
                fi
                if command -v wslpath >/dev/null 2>&1; then
                  if wslpath -w "$real" 2>/dev/null; then return; fi
                fi
                case "$real" in
                  /mnt/[a-zA-Z]/?*)
                    # /mnt/c/Users/... -> C:\Users\...
                    local drive rest driveUpper
                    drive=$(printf '%s' "''${real#/mnt/}" | cut -c1)
                    rest="''${real#/mnt/?/}"
                    driveUpper=$(printf '%s' "$drive" | tr 'a-z' 'A-Z')
                    printf '%s' "''${driveUpper}:\\''${rest//\//\\}"
                    return
                    ;;
                esac
                if [ -n "''${WSL_DISTRO_NAME:-}" ]; then
                  # UNC into Linux root as last resort (may not expose /mnt/c reliably on older builds)
                  local rel="''${real#/}"; rel="''${rel//\//\\}"
                  printf '\\wsl$\\%s\\%s' "''${WSL_DISTRO_NAME}" "$rel"
                else
                  printf '%s' "$real"
                fi
              }

              # --- Font Sync & Registration (optional) ---
              if [ "${boolStr cfg.syncFonts}" = true ]; then
                psCmd="${
                  lib.optionalString (cfg.powerShellCommand != null)
                  cfg.powerShellCommand
                }"
                if [ -z "$psCmd" ]; then
                  for cand in powershell.exe pwsh.exe \
                    /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe \
                    /mnt/c/Windows/System32/WindowsPowerShell/v1.0/pwsh.exe \
                    /mnt/c/Program\ Files/PowerShell/7/pwsh.exe \
                    /mnt/c/Program\ Files/PowerShell/7-preview/pwsh.exe; do
                    if command -v "$cand" >/dev/null 2>&1; then psCmd="$cand"; break; fi
                    if [ -x "$cand" ]; then psCmd="$cand"; break; fi
                  done
                fi

                fontsDest="/mnt/c/Users/$winUser/AppData/Local/Microsoft/Windows/Fonts"
                mkdir -p "$fontsDest"

                # Candidate font directories (follow symlinks via find -L)
                fontSources=""
                for p in \
                  "$HOME/.nix-profile/share/fonts" \
                  "/etc/profiles/per-user/$USER/share/fonts"; do
                  [ -d "$p" ] && fontSources="$fontSources $p"
                done

                considered=0
                installed=0
                newFontsList="$(mktemp)"
                whitelist="${cfg.fontWhitelistRegex or ""}"
                ci_grep() { grep -Eqi "$1" <<<"$2"; }

                for src in $fontSources; do
                  [ -d "$src" ] || continue
                  while IFS= read -r -d $'\0' f; do
                      considered=$((considered+1))
                      fname="$(basename "$f")"
                      if [ -n "$whitelist" ] && ! ci_grep "$whitelist" "$fname"; then
                        log_dbg "skip (whitelist) $fname"; continue
                      fi
                      dest="$fontsDest/$fname"
                      if [ ! -f "$dest" ]; then
                        if cp -L "$f" "$dest" 2>/dev/null; then
                          installed=$((installed+1))
                          echo "$(wsl_win_path "$dest")" >> "$newFontsList"
                          log_dbg "copied $f -> $dest"
                        else
                          log_dbg "warn copy failed $f"
                        fi
                      else
                        log_dbg "exists $dest"
                      fi
                    done < <(find -L "$src" -maxdepth 10 \( -iname '*.ttf' -o -iname '*.otf' \) -print0 2>/dev/null)
                done

                # Always perform (re)registration so fonts persist across reboot even if none were just copied.
                if [ $installed -gt 0 ]; then
                  echo "[remoteVscode] Copied $installed new font file(s)." >&2
                else
                  log_dbg "no newly copied fonts; proceeding with re-registration scan"
                fi

                if [ -n "$psCmd" ]; then
                  # Build list of fonts to register: if we have new ones use those, otherwise enumerate destination matching whitelist
                  registrationList="$(mktemp)"
                  if [ -s "$newFontsList" ]; then
                    cat "$newFontsList" > "$registrationList"
                  else
                    # harvest existing font files in destination (only whitelist if set)
                    while IFS= read -r -d $'\0' f; do
                      fname="$(basename "$f")"
                      if [ -n "$whitelist" ] && ! ci_grep "$whitelist" "$fname"; then
                        continue
                      fi
                      echo "$(wsl_win_path "$f")" >> "$registrationList"
                    done < <(find -L "$fontsDest" -maxdepth 1 \( -iname '*.ttf' -o -iname '*.otf' \) -print0 2>/dev/null)
                  fi
                  if [ ! -s "$registrationList" ]; then
                    echo "[remoteVscode] No fonts found to register." >&2
                  else
                    psScript="$(mktemp).ps1"
                    {
                      echo '$ErrorActionPreference = "Stop"'
                      echo 'Write-Host "[remoteVscode][ps] Registering new fonts..."'
                      cat <<'PS_ADD'
        Add-Type @'
        using System; using System.Runtime.InteropServices;
        public static class FontUtil { [DllImport("gdi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern int AddFontResourceEx(string lpszFilename, uint fl, IntPtr pdv); }
        '@
        PS_ADD
                      echo '$fonts = @('
                      while IFS= read -r win; do
                        [ -z "$win" ] && continue
                        printf "'%s'\n" "$win"
                      done < "$registrationList"
                      echo ')'
                      cat <<'PS_BODY'
        $regPath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
        if (-not (Test-Path $regPath)) { New-Item -Path $regPath | Out-Null }
        $added = 0
        foreach($f in $fonts){
          if (-not (Test-Path $f)) { Write-Host "[remoteVscode][ps][warn] Missing file $f"; continue }
          $bn = Split-Path $f -Leaf
          $ext = [System.IO.Path]::GetExtension($bn).ToLowerInvariant()
          $valueName = if ($ext -eq '.otf') { ($bn + ' (OpenType)') } else { ($bn + ' (TrueType)') }
          try {
            # Use flags = 0 (no FR_PRIVATE) so the font is globally available, not process-private.
            $res = [FontUtil]::AddFontResourceEx($f,0,[IntPtr]::Zero)
            if ($res -gt 0) {
              New-ItemProperty -Path $regPath -Name $valueName -Value $bn -Force | Out-Null
              Write-Host "[remoteVscode][ps] Registered $bn"
              $added++
            } else {
              Write-Host "[remoteVscode][ps][note] Already registered or AddFontResourceEx returned 0: $bn"
            }
          } catch {
            Write-Host ("[remoteVscode][ps][error] " + $bn + ' : ' + $_.Exception.Message)
          }
        }
        try { Add-Type -AssemblyName PresentationCore; [void][System.Windows.Media.Fonts]::SystemTypefaces } catch {}
        if ($added -gt 0) {
          Add-Type @'
        using System; using System.Runtime.InteropServices;
        public static class Notify { [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd,uint Msg, UIntPtr wParam,string lParam,uint fuFlags,uint uTimeout,out UIntPtr lpdwResult); }
        '@
          [UIntPtr]$out = [UIntPtr]::Zero
          [Notify]::SendMessageTimeout([IntPtr]0xffff,0x001D,[UIntPtr]::Zero,$null,0,1000,[ref]$out) | Out-Null
          Write-Host "[remoteVscode][ps] Broadcast WM_FONTCHANGE ($added new)."
        }
        Write-Host '[remoteVscode][ps] Font registration phase complete.'
        Write-Host '[remoteVscode][ps] Enumerating sample font families (Fira|Nerd|Deja|Source|JetBrains)...'
        try {
          Add-Type -AssemblyName PresentationCore
          [System.Windows.Media.Fonts]::SystemTypefaces |
            Where-Object { $_.FontFamily.Source -match 'Fira|Nerd|Deja|Source|JetBrains' } |
            ForEach-Object { Write-Host "[remoteVscode][ps] family $_.FontFamily.Source" }
        } catch {
          Write-Host "[remoteVscode][ps][warn] Enumeration failed: $($_.Exception.Message)"
        }
        PS_BODY
                    } > "$psScript"
                    psBase="$(basename "$psCmd" | tr 'A-Z' 'a-z')"
                    winTempDir="/mnt/c/Users/$winUser/AppData/Local/Temp"
                    mkdir -p "$winTempDir"
                    winScript="$winTempDir/$(basename "$psScript")"
                    cp "$psScript" "$winScript"
                    chmod 0644 "$winScript" || true
                    scriptWinPath="$(wsl_win_path "$winScript")"
                    if [ -z "$scriptWinPath" ]; then
                      scriptWinPath="C:\\Users\\$winUser\\AppData\\Local\\Temp\\$(basename "$psScript")"
                    fi
                    [ "$debug_flag" = 1 ] && {
                      echo "[remoteVscode][debug] registration script (wsl): $psScript" >&2
                      echo "[remoteVscode][debug] registration script copied (win fs): $winScript" >&2
                      echo "[remoteVscode][debug] registration script Windows path: $scriptWinPath" >&2
                      sed 's/^/[remoteVscode][debug] | /' "$psScript" >&2
                    }
                    rc=0
                    if echo "$psBase" | grep -q pwsh; then
                      if [ "$debug_flag" = 1 ]; then
                        "$psCmd" -NoLogo -NoProfile -File "$scriptWinPath" || rc=$?
                      else
                        "$psCmd" -NoLogo -NoProfile -File "$scriptWinPath" >/dev/null 2>&1 || rc=$?
                      fi
                    else
                      if [ "$debug_flag" = 1 ]; then
                        "$psCmd" -NoProfile -ExecutionPolicy Bypass -File "$scriptWinPath" || rc=$?
                      else
                        "$psCmd" -NoProfile -ExecutionPolicy Bypass -File "$scriptWinPath" >/dev/null 2>&1 || rc=$?
                      fi
                    fi
                    if [ $rc -ne 0 ]; then
                      echo "[remoteVscode] PowerShell font registration script failed (exit $rc)." >&2
                    else
                      log_dbg "font registration script exit 0"
                    fi
                    rm -f "$psScript" || true
                    if [ "$debug_flag" != 1 ]; then
                      rm -f "$winScript" || true
                    else
                      echo "[remoteVscode][debug] retained Windows script at $winScript" >&2
                    fi
                    rm -f "$registrationList" || true
                  fi
                else
                  echo "[remoteVscode] Skipping registration (no PowerShell found)." >&2
                fi
                rm -f "$newFontsList"
                log_dbg "considered $considered font file(s)."
              fi

              # --- Optional persistence via HKCU Run key (re-register fonts at user logon) ---
              if [ "${boolStr cfg.syncFonts}" = true ] && [ "${
                boolStr cfg.addRunKey
              }" = true ]; then
                if [ -n "$psCmd" ]; then
                  persistDir="/mnt/c/Users/$winUser/AppData/Local/FontReRegister"
                  mkdir -p "$persistDir"
                  persistScript="$persistDir/font-re-register.ps1"
                  cat > "$persistScript" <<'PS_PERSIST'
        $ErrorActionPreference = 'SilentlyContinue'
        Add-Type @'
        using System; using System.Runtime.InteropServices;
        public static class FontUtil { [DllImport("gdi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern int AddFontResourceEx(string lpszFilename, uint fl, IntPtr pdv); }
        '@
        $fontRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
        if (-not (Test-Path $fontRoot)) { return }
        $files = Get-ChildItem -Path $fontRoot -Include *.ttf,*.otf -File -Name
        if (-not $files) { return }
        $regPath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
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
        PS_PERSIST
                  chmod 0644 "$persistScript" || true
                  winPersistPath="C:\\Users\\$winUser\\AppData\\Local\\FontReRegister\\font-re-register.ps1"
                  # Determine base PowerShell executable for Run key
                  psExeBase="$(basename "$psCmd")"
                  case "$psExeBase" in
                    *.exe) ;; # keep
                    *) psExeBase="$psExeBase.exe" ;;
                  esac
                  # Use absolute path if psCmd is an absolute Windows path
                  runPs="$psExeBase"
                  if echo "$psCmd" | grep -qi '^/mnt/'; then
                    # Translate to Windows path
                    runPs="$(wsl_win_path "$psCmd")"
                  fi
                  # Quote paths with spaces
                  runPsEsc="$runPs"
                  echo "$runPsEsc" | grep -q ' ' && runPsEsc="\"$runPsEsc\""
                  runCmd="$runPsEsc -NoProfile -ExecutionPolicy Bypass -File \"$winPersistPath\""
                  # Install / refresh Run key via a short PowerShell inline script
                  if command -v "$psCmd" >/dev/null 2>&1; then
                    "$psCmd" -NoProfile -ExecutionPolicy Bypass -Command "try { New-Item -Path 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run' -ErrorAction SilentlyContinue | Out-Null; New-ItemProperty -Path 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run' -Name 'FontReRegister' -Value '$runCmd' -Force | Out-Null } catch { }" >/dev/null 2>&1 || true
                    log_dbg "Run key installed for font re-registration"
                  else
                    echo '[remoteVscode] Unable to install Run key (PowerShell not found again).' >&2
                  fi
                else
                  echo '[remoteVscode] Skipping persistence (no PowerShell found for Run key).' >&2
                fi
              fi
      '';
  };
}
