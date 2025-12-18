# nix-wsl-init.ps1
# entrypoint powershell script that orchestrates wsl initialization tasks
# this script sets up the consolidated wsl logon scheduled task

param(
  [Parameter(Mandatory=$true)]
  [string]$WinProfilePath,

  [Parameter(Mandatory=$true)]
  [string]$UsbipdEnabled,

  [Parameter(Mandatory=$false)]
  [string]$UsbipdBusId = "1-1",

  [Parameter(Mandatory=$false)]
  [string]$UsbipdAutoAttach = "true",

  [Parameter(Mandatory=$false)]
  [string]$WslDistroName = "",

  [Parameter(Mandatory=$false)]
  [int]$WslWaitSeconds = 30
)

$ErrorActionPreference = 'Stop'

# get script directory for loading sub-scripts
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# create persistent directory and copy the consolidated logon script
$logonScriptDir = Join-Path $WinProfilePath "AppData\Local\WslOnLogon"
if (-not (Test-Path $logonScriptDir)) {
  New-Item -Path $logonScriptDir -ItemType Directory -Force | Out-Null
}

$logonScriptSrc = Join-Path $scriptDir "wsl-on-logon.ps1"
$logonScriptDest = Join-Path $logonScriptDir "wsl-on-logon.ps1"
if (Test-Path $logonScriptSrc) {
  Copy-Item -Path $logonScriptSrc -Destination $logonScriptDest -Force
}

# setup the scheduled task
$taskSetupScript = Join-Path $scriptDir "setup-wsl-on-logon-task.ps1"
if (Test-Path $taskSetupScript) {
  try {
    $usbipdEnabledBool = $UsbipdEnabled -eq "true"
    $autoAttachBool = $UsbipdAutoAttach -eq "true"
    $params = @{
      WinProfilePath = $WinProfilePath
      UsbipdEnabled = $usbipdEnabledBool
      BusId = $UsbipdBusId
      AutoAttach = $autoAttachBool
      WaitSeconds = $WslWaitSeconds
    }
    if ($WslDistroName) {
      $params['DistroName'] = $WslDistroName
    }
    $scriptOutput = & $taskSetupScript @params 2>&1
  } catch {
    Write-Host "wsl-on-logon task setup failed: $_"
  }
}
