# setup-wsl-on-logon-task.ps1
# sets up the consolidated wsl logon scheduled task

param(
  [Parameter(Mandatory=$true)]
  [string]$WinProfilePath,

  [Parameter(Mandatory=$true)]
  [bool]$UsbipdEnabled,

  [Parameter(Mandatory=$false)]
  [string]$BusId = $null,

  [Parameter(Mandatory=$false)]
  [bool]$AutoAttach = $true,

  [Parameter(Mandatory=$false)]
  [string]$DistroName = $null,

  [Parameter(Mandatory=$false)]
  [int]$WaitSeconds = 30,

  [Parameter(Mandatory=$false)]
  [bool]$PcscdEnabled = $false,

  [Parameter(Mandatory=$false)]
  [string]$PcscdAutoStartBin = "",

  [Parameter(Mandatory=$false)]
  [switch]$Elevated = $false
)

$ErrorActionPreference = "Stop"

# check if running as administrator
function Test-IsAdmin {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# re-launch with elevation if not already elevated
if (-not (Test-IsAdmin)) {
  # build argument list for elevated process
  $scriptPath = $MyInvocation.MyCommand.Path
  $usbipdArg = if ($UsbipdEnabled) { '$true' } else { '$false' }
  $autoAttachArg = if ($AutoAttach) { '$true' } else { '$false' }
  $pcscdArg = if ($PcscdEnabled) { '$true' } else { '$false' }

  $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -WinProfilePath `"$WinProfilePath`" -UsbipdEnabled:$usbipdArg -AutoAttach:$autoAttachArg -WaitSeconds $WaitSeconds -PcscdEnabled:$pcscdArg -Elevated"
  if ($BusId) { $argList += " -BusId `"$BusId`"" }
  if ($DistroName) { $argList += " -DistroName `"$DistroName`"" }
  if ($PcscdAutoStartBin) { $argList += " -PcscdAutoStartBin `"$PcscdAutoStartBin`"" }

  # find powershell executable
  $psExe = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
  if (-not $psExe) { $psExe = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source }
  if (-not $psExe) { throw "setup-wsl-on-logon-task: no powershell executable found" }

  try {
    Start-Process -FilePath $psExe -ArgumentList $argList -Verb RunAs -Wait -WindowStyle Hidden
    exit 0
  } catch {
    throw "setup-wsl-on-logon-task: failed to elevate: $_"
  }
}

$taskName = "wsl-on-logon"
$scriptPath = "$WinProfilePath\AppData\Local\WslOnLogon\wsl-on-logon.ps1"

# prefer pwsh when available, otherwise fall back to windows powershell (PS5-safe)
function Get-ExePath {
  param([string]$Name)
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if ($cmd -and $cmd.Source) { return $cmd.Source }
  return $null
}

$psExe = Get-ExePath -Name 'pwsh.exe'
if (-not $psExe) { $psExe = Get-ExePath -Name 'powershell.exe' }
if (-not $psExe) { throw "setup-wsl-on-logon-task: no powershell executable found" }

# build argument string manually with proper boolean formatting
$usbipdArg = if ($UsbipdEnabled) { '$true' } else { '$false' }
$autoAttachArg = if ($AutoAttach) { '$true' } else { '$false' }
$pcscdArg = if ($PcscdEnabled) { '$true' } else { '$false' }

$argString = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -UsbipdEnabled:$usbipdArg -AutoAttach:$autoAttachArg -WaitSeconds $WaitSeconds -PcscdEnabled:$pcscdArg"
if ($BusId) {
  $argString += " -BusId `"$BusId`""
}
if ($DistroName) {
  $argString += " -DistroName `"$DistroName`""
}
if ($PcscdAutoStartBin) {
  $argString += " -PcscdAutoStartBin `"$PcscdAutoStartBin`""
}

# create task using powershell cmdlets (no 261 char limit)
$action = New-ScheduledTaskAction -Execute $psExe -Argument $argString
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
# disable execution time limit - script has internal timeout for wsl readiness
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

try {
  Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
} catch {
  throw "setup-wsl-on-logon-task: failed to register scheduled task: $_"
}
