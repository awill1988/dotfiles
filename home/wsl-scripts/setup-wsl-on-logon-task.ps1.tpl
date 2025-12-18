# setup-wsl-on-logon-task.ps1
# sets up the consolidated wsl logon scheduled task

param(
  [Parameter(Mandatory=$true)]
  [string]$WinProfilePath,

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

$ErrorActionPreference = "Stop"

$taskName = "wsl-on-logon"
$scriptPath = "$WinProfilePath\AppData\Local\WslOnLogon\wsl-on-logon.ps1"
$scriptPathForTask = '%LOCALAPPDATA%\WslOnLogon\wsl-on-logon.ps1'

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

function Format-Bool {
  param([bool]$Value)
  if ($Value) { '$true' } else { '$false' }
}

$psExeForTask = if ($psExe -like '*pwsh.exe') { 'pwsh.exe' } elseif ($psExe -like '*powershell.exe') { 'powershell.exe' } else { $psExe }

$taskRunCommand = ('\"{0}\" -NoProfile -ExecutionPolicy Bypass -File \"{1}\" -UsbipdEnabled {2} -BusId \"{3}\" -AutoAttach {4} -WaitSeconds {5}' -f `
  $psExeForTask, $scriptPathForTask, (Format-Bool -Value $UsbipdEnabled), $BusId, (Format-Bool -Value $AutoAttach), $WaitSeconds)
if ($DistroName) { $taskRunCommand += (' -DistroName \"{0}\"' -f $DistroName) }

$schtasksArgs = @(
  '/create'
  '/tn', $taskName
  '/tr', $taskRunCommand
  '/sc', 'ONLOGON'
  '/rl', 'HIGHEST'
  '/ru', $env:USERNAME
  '/f'
)

$schtasksOutput = & schtasks.exe @schtasksArgs 2>&1
if ($LASTEXITCODE -ne 0) {
  if ($schtasksOutput) { Write-Host "setup-wsl-on-logon-task error: $schtasksOutput" }
  throw "setup-wsl-on-logon-task: schtasks.exe failed with exit code $LASTEXITCODE"
}

try {
  $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Seconds 30)
  Set-ScheduledTask -TaskName $taskName -Settings $settings | Out-Null
} catch {
  Write-Host "setup-wsl-on-logon-task error setting execution time: $_"
}
