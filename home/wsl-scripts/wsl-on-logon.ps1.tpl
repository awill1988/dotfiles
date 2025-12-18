# wsl-on-logon.ps1
# consolidated script for wsl logon tasks: font registration and usbipd attachment

param(
  [Parameter(Mandatory=$true)]
  [bool]$UsbipdEnabled,

  [Parameter(Mandatory=$false)]
  [string]$BusId = "1-1",

  [Parameter(Mandatory=$false)]
  [bool]$AutoAttach = $true,

  [Parameter(Mandatory=$false)]
  [string]$DistroName = $null,

  [Parameter(Mandatory=$false)]
  [int]$WaitSeconds = 30
)

$ErrorActionPreference = 'SilentlyContinue'

# --- font re-registration ---
try {
  Add-Type @'
  using System; using System.Runtime.InteropServices;
  public static class FontUtil { [DllImport("gdi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern int AddFontResourceEx(string lpszFilename, uint fl, IntPtr pdv); }
'@
  $fontRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
  if (Test-Path $fontRoot) {
    $files = Get-ChildItem -Path $fontRoot -Include *.ttf,*.otf -File -Name
    if ($files) {
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
    }
  }
} catch {
  Write-Host "Font registration failed: $_"
}

# --- usbipd attachment ---
if ($UsbipdEnabled) {
  try {
    $usbipd = (Get-Command usbipd.exe -ErrorAction SilentlyContinue).Source
    if (-not $usbipd) { $usbipd = (Get-Command usbipd -ErrorAction SilentlyContinue).Source }
    if (-not $usbipd) {
      $usbipd_default = 'C:\Program Files\usbipd-win\usbipd.exe'
      if (Test-Path $usbipd_default) { $usbipd = $usbipd_default }
    }
    if (-not $usbipd) {
      Write-Host 'usbipd not found; skipping usb attach'
      return
    }

    $distro = $DistroName
    if (-not $distro) {
      $distro = (& wsl.exe -l -q 2>$null | Select-Object -First 1).Trim()
    }
    if (-not $distro) {
      Write-Host 'wsl distro not found; skipping usb attach'
      return
    }

    $deadline = (Get-Date).AddSeconds([Math]::Max(0, $WaitSeconds))
    while ((Get-Date) -lt $deadline) {
      & wsl.exe -d $distro -e /bin/sh -lc 'true' 1>$null 2>$null
      if ($LASTEXITCODE -eq 0) { break }
      Start-Sleep -Milliseconds 500
    }

    $args = @('attach','--wsl','--busid',$BusId)
    if ($AutoAttach) {
      # run with auto-attach as background job to avoid hanging
      $job = Start-Job -ScriptBlock {
        param($usbipd, $args)
        & $usbipd @args 1>$null 2>$null
      } -ArgumentList $usbipd, $args

      # give it a moment to establish connection
      Start-Sleep -Seconds 2

      # detach from job (it will continue running)
      # the job will keep running in background to maintain auto-attach
    } else {
      # without auto-attach, command exits immediately after attach
      & $usbipd @args 1>$null 2>$null
    }
  } catch {
    Write-Host "usbipd attach failed: $_"
  }
}
