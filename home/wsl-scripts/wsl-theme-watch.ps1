# wsl-theme-watch.ps1
# Monitors Windows AppsUseLightTheme registry changes and signals WSL theme-switch

$ErrorActionPreference = "SilentlyContinue"

function Trigger-WslThemeSync {
  try {
    $distroArg = if ($env:WSL_DISTRO_NAME) { "-d $($env:WSL_DISTRO_NAME)" } else { "" }
    Start-Process -FilePath "wsl.exe" -ArgumentList "$distroArg -- sh -c 'command -v theme-switch >/dev/null 2>&1 && theme-switch sync-host --quiet || true'" -WindowStyle Hidden
  } catch {}
}

# Run initial sync
Trigger-WslThemeSync

# Attempt WMI Registry Event Registration
$sid = $null
try {
  $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
} catch {}

$wmiSuccess = $false
if ($sid) {
  $query = "SELECT * FROM RegistryValueChangeEvent WHERE Hive='HKEY_USERS' AND KeyPath='$sid\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize' AND ValueName='AppsUseLightTheme'"
  try {
    Register-WmiEvent -Query $query -SourceIdentifier "WindowsThemeWatcher" -Action {
      Trigger-WslThemeSync
    } | Out-Null
    $wmiSuccess = $true
  } catch {}
}

if ($wmiSuccess) {
  while ($true) {
    Start-Sleep -Seconds 3600
  }
} else {
  # Fallback to polling loop every 3 seconds
  $lastMode = $null
  while ($true) {
    try {
      $val = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -ErrorAction SilentlyContinue).AppsUseLightTheme
      if ($val -ne $null) {
        $mode = if ($val -eq 0) { "dark" } else { "light" }
        if ($lastMode -ne $null -and $mode -ne $lastMode) {
          Trigger-WslThemeSync
        }
        $lastMode = $mode
      }
    } catch {}
    Start-Sleep -Seconds 3
  }
}
