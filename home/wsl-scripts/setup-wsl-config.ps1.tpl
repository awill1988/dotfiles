# setup-wsl-config.ps1.tpl
# manages windows defender real-time exclusions for wsl performance

param(
  [Parameter(Mandatory=$true)]
  [string]$WinProfilePath,

  [Parameter(Mandatory=$false)]
  [string]$DefenderExclusionsEnable = "true"
)

$ErrorActionPreference = "Stop"

function Test-IsAdmin {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if ($DefenderExclusionsEnable -eq "true") {
  try {
    $mpPref = Get-MpPreference -ErrorAction SilentlyContinue
    if ($mpPref) {
      $currPaths = $mpPref.ExclusionPath
      $currProcs = $mpPref.ExclusionProcess

      $targetPaths = @(
        (Join-Path $WinProfilePath "AppData\Local\Packages"),
        (Join-Path $WinProfilePath "AppData\Local\Docker\wsl")
      )
      $targetProcs = @("wsl.exe", "vmmemWSL.exe")

      $missingPaths = @()
      foreach ($p in $targetPaths) {
        if ($currPaths -notcontains $p) { $missingPaths += $p }
      }

      $missingProcs = @()
      foreach ($pr in $targetProcs) {
        if ($currProcs -notcontains $pr) { $missingProcs += $pr }
      }

      if ($missingPaths.Count -gt 0 -or $missingProcs.Count -gt 0) {
        Write-Host "wsl-config: missing defender exclusions detected"
        if (Test-IsAdmin) {
          foreach ($p in $missingPaths) { Add-MpPreference -ExclusionPath $p -ErrorAction SilentlyContinue }
          foreach ($pr in $missingProcs) { Add-MpPreference -ExclusionProcess $pr -ErrorAction SilentlyContinue }
          Write-Host "wsl-config: defender exclusions applied"
        } else {
          $psExe = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
          if (-not $psExe) { $psExe = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source }
          if ($psExe) {
            $cmdList = ""
            foreach ($p in $missingPaths) { $cmdList += "Add-MpPreference -ExclusionPath '$p'; " }
            foreach ($pr in $missingProcs) { $cmdList += "Add-MpPreference -ExclusionProcess '$pr'; " }
            try {
              Start-Process -FilePath $psExe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$cmdList`"" -Verb RunAs -WindowStyle Hidden
              Write-Host "wsl-config: dispatched elevated prompt for defender exclusions"
            } catch {
              Write-Host "wsl-config: elevated prompt for defender exclusions skipped/failed"
            }
          }
        }
      } else {
        Write-Host "wsl-config: defender exclusions are already set"
      }
    }
  } catch {
    Write-Host "wsl-config: defender exclusion check skipped: $_"
  }
}
