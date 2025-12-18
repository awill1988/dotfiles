# wsl-on-logon.ps1
# consolidated script for wsl logon tasks: font registration and usbipd attachment

param(
  [Parameter(Mandatory=$true)]
  [string]$UsbipdEnabled,

  [Parameter(Mandatory=$false)]
  [string]$BusId = $null,

  [Parameter(Mandatory=$false)]
  [string]$AutoAttach = "true",

  [Parameter(Mandatory=$false)]
  [string]$DistroName = $null,

  [Parameter(Mandatory=$false)]
  [int]$WaitSeconds = 30
)

# convert string booleans to actual booleans
$usbipdEnabledBool = $UsbipdEnabled -eq '$true' -or $UsbipdEnabled -eq 'true' -or $UsbipdEnabled -eq '1'
$autoAttachBool = $AutoAttach -eq '$true' -or $AutoAttach -eq 'true' -or $AutoAttach -eq '1'

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
if ($usbipdEnabledBool) {
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

    # check current device state
    $listOutput = & $usbipd list 2>$null
    if (-not $listOutput) {
      Write-Host 'usbipd list failed; skipping usb attach'
      return
    }

    # auto-detect smart card reader or use explicit busid
    $deviceLine = $null
    $detectedBusId = $null

    if ($BusId) {
      # explicit busid provided - use it
      $deviceLine = $listOutput | Where-Object { $_ -match "^\s*$BusId\s+" }
      if ($deviceLine) {
        $detectedBusId = $BusId
      }
    } else {
      # scan for smart card reader
      $deviceLine = $listOutput | Where-Object { $_ -match 'smart\s*card' } | Select-Object -First 1
      if ($deviceLine) {
        # extract busid from line (format: "BUSID  VID:PID  DEVICE...")
        if ($deviceLine -match '^\s*(\S+)\s+') {
          $detectedBusId = $matches[1]
        }
      }
    }

    if (-not $deviceLine -or -not $detectedBusId) {
      Write-Host 'smart card reader not found; skipping usb attach'
      return
    }

    $isAttached = $deviceLine -match '\s+Attached(\s|$)'
    $isShared = $deviceLine -match '\s+(Shared|Attached)(\s|$)'

    # already attached - nothing to do
    if ($isAttached) {
      return
    }

    # ensure wsl is running before proceeding
    $distro = $DistroName
    if (-not $distro) {
      # use --list --running to get only running distros
      $runningDistros = & wsl.exe --list --running 2>$null
      if ($runningDistros -and $runningDistros.Count -gt 1) {
        # skip first line (header) and get first running distro
        for ($i = 1; $i -lt $runningDistros.Count; $i++) {
          $line = $runningDistros[$i]
          # clean the distro name: remove asterisk, non-printable chars, and trim
          $cleaned = ($line -replace '\*', '' -replace '[^\x20-\x7E]', '').Trim()
          # remove (Default) suffix if present
          if ($cleaned -match '^(.+?)\s+\(Default\)$') {
            $cleaned = $matches[1].Trim()
          }
          if ($cleaned) {
            $distro = $cleaned
            break
          }
        }
      }
    }
    if (-not $distro) {
      Write-Host 'wsl distro not found; skipping usb attach'
      return
    }

    # wait for wsl to be ready
    $wslReady = $false
    $deadline = (Get-Date).AddSeconds([Math]::Max(0, $WaitSeconds))
    while ((Get-Date) -lt $deadline) {
      & wsl.exe -d $distro -e /bin/sh -lc 'true' 1>$null 2>$null
      if ($LASTEXITCODE -eq 0) {
        $wslReady = $true
        break
      }
      Start-Sleep -Milliseconds 500
    }

    if (-not $wslReady) {
      Write-Host "wsl distro $distro failed to start; skipping usb attach"
      return
    }

    # not shared - bind it first
    if (-not $isShared) {
      & $usbipd bind --busid $detectedBusId 2>$null
      if ($LASTEXITCODE -ne 0) {
        Write-Host "failed to bind device $detectedBusId; skipping usb attach"
        return
      }
    }

    # attach the device
    & $usbipd attach --wsl --busid $detectedBusId 2>$null
    if ($LASTEXITCODE -ne 0) {
      Write-Host "failed to attach device $detectedBusId"
    }
  } catch {
    Write-Host "usbipd attach failed: $_"
  }
}
