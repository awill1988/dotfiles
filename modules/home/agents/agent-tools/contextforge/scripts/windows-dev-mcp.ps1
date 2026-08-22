param(
  [string]$WorkspaceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$InformationPreference = "SilentlyContinue"

[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$script:protocol_version = "2024-11-05"
$script:log_directory = Join-Path $env:LOCALAPPDATA "contextforge\windows-dev\logs"
$script:solution_relative_path = "platforms\windows\HoldUp.sln"

if (-not [string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
  $env:WINDOWS_DEV_WORKSPACE_ROOT = $WorkspaceRoot
}

function Write-ProtocolMessage {
  param([Parameter(Mandatory = $true)][object]$message)

  $json = $message | ConvertTo-Json -Depth 16 -Compress
  [Console]::Out.WriteLine($json)
  [Console]::Out.Flush()
}

function New-TextToolResult {
  param(
    [Parameter(Mandatory = $true)][string]$text,
    [bool]$is_error = $false
  )

  return [ordered]@{
    content = @([ordered]@{
      type = "text"
      text = $text
    })
    isError = $is_error
  }
}

function New-JsonToolResult {
  param(
    [Parameter(Mandatory = $true)][object]$value,
    [bool]$is_error = $false
  )

  return New-TextToolResult -text ($value | ConvertTo-Json -Depth 12 -Compress) -is_error $is_error
}

function Get-ArgumentValue {
  param(
    [object]$arguments,
    [Parameter(Mandatory = $true)][string]$name,
    [object]$default_value = $null
  )

  if ($null -eq $arguments) {
    return $default_value
  }

  $property = $arguments.PSObject.Properties[$name]
  if ($null -eq $property -or $null -eq $property.Value) {
    return $default_value
  }

  return $property.Value
}

function Get-WorkspaceConfiguration {
  $configured_root = [string]$env:WINDOWS_DEV_WORKSPACE_ROOT
  if ([string]::IsNullOrWhiteSpace($configured_root)) {
    return [pscustomobject]@{
      configured = $false
      error = "WINDOWS_DEV_WORKSPACE_ROOT is not configured"
      workspace_root = $null
      solution_path = $null
    }
  }

  try {
    $workspace_root = [System.IO.Path]::GetFullPath($configured_root).TrimEnd("\\")
    $user_profile_root = [System.IO.Path]::GetFullPath($env:USERPROFILE).TrimEnd("\\") + "\\"
  }
  catch {
    return [pscustomobject]@{
      configured = $false
      error = "WINDOWS_DEV_WORKSPACE_ROOT is not a valid Windows path"
      workspace_root = $null
      solution_path = $null
    }
  }

  $is_user_workspace = $workspace_root.StartsWith($user_profile_root, [System.StringComparison]::OrdinalIgnoreCase)
  $is_wsl_workspace = $workspace_root.StartsWith("\\wsl.localhost\", [System.StringComparison]::OrdinalIgnoreCase) -or $workspace_root.StartsWith("\\wsl$\", [System.StringComparison]::OrdinalIgnoreCase)
  if (-not $is_user_workspace -and -not $is_wsl_workspace) {
    return [pscustomobject]@{
      configured = $false
      error = "WINDOWS_DEV_WORKSPACE_ROOT must be beneath the current Windows user profile or a WSL UNC path"
      workspace_root = $null
      solution_path = $null
    }
  }

  if ($workspace_root -match '[&|<>^%!\"]') {
    return [pscustomobject]@{
      configured = $false
      error = "WINDOWS_DEV_WORKSPACE_ROOT contains characters that are unsafe for the Windows build launcher"
      workspace_root = $null
      solution_path = $null
    }
  }

  $solution_path = Join-Path $workspace_root $script:solution_relative_path
  return [pscustomobject]@{
    configured = (Test-Path -LiteralPath $workspace_root -PathType Container)
    error = $(if (Test-Path -LiteralPath $workspace_root -PathType Container) { $null } else { "configured workspace root does not exist" })
    workspace_root = $workspace_root
    solution_path = $solution_path
  }
}

function Find-Msbuild {
  $candidates = @(
    "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\MSBuild.exe"
  )

  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
      return $candidate
    }
  }

  $command = Get-Command "MSBuild.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -ne $command) {
    return $command.Source
  }

  return $null
}

function Find-Dotnet {
  $candidate = Join-Path ${env:ProgramFiles} "dotnet\dotnet.exe"
  if (Test-Path -LiteralPath $candidate -PathType Leaf) {
    return $candidate
  }

  $command = Get-Command "dotnet.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -ne $command) {
    return $command.Source
  }

  return $null
}

function Get-ToolchainStatus {
  $workspace = Get-WorkspaceConfiguration
  $msbuild = Find-Msbuild
  $dotnet = Find-Dotnet
  $dotnet_sdks = @()

  if ($null -ne $dotnet) {
    $dotnet_sdks = @(& $dotnet --list-sdks 2>$null)
  }

  return [ordered]@{
    workspace = [ordered]@{
      configured = $workspace.configured
      workspace_root = $workspace.workspace_root
      solution_path = $workspace.solution_path
      solution_exists = $(if ($null -ne $workspace.solution_path) { Test-Path -LiteralPath $workspace.solution_path -PathType Leaf } else { $false })
      error = $workspace.error
    }
    toolchain = [ordered]@{
      msbuild_path = $msbuild
      dotnet_path = $dotnet
      dotnet_sdks = $dotnet_sdks
      developer_mode_enabled = ((Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" -Name AllowDevelopmentWithoutDevLicense -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense -eq 1)
    }
  }
}

function Resolve-BuildOption {
  param(
    [object]$arguments,
    [Parameter(Mandatory = $true)][string]$name,
    [Parameter(Mandatory = $true)][string[]]$allowed,
    [Parameter(Mandatory = $true)][string]$default_value
  )

  $value = [string](Get-ArgumentValue -arguments $arguments -name $name -default_value $default_value)
  foreach ($candidate in $allowed) {
    if ($value.Equals($candidate, [System.StringComparison]::OrdinalIgnoreCase)) {
      return $candidate
    }
  }

  throw "$name must be one of: $($allowed -join ', ')"
}

function Start-Build {
  param([object]$arguments)

  $configuration = Resolve-BuildOption -arguments $arguments -name "configuration" -allowed @("Debug", "Release") -default_value "Debug"
  $platform = Resolve-BuildOption -arguments $arguments -name "platform" -allowed @("x64", "ARM64") -default_value "x64"
  $restore = [bool](Get-ArgumentValue -arguments $arguments -name "restore" -default_value $true)
  $workspace = Get-WorkspaceConfiguration

  if (-not $workspace.configured) {
    throw $workspace.error
  }
  if (-not (Test-Path -LiteralPath $workspace.solution_path -PathType Leaf)) {
    throw "HoldUp solution was not found beneath the configured workspace root"
  }

  $msbuild = Find-Msbuild
  if ($null -eq $msbuild) {
    throw "MSBuild.exe was not found"
  }

  [System.IO.Directory]::CreateDirectory($script:log_directory) | Out-Null
  $build_id = [Guid]::NewGuid().ToString("N")
  $log_path = Join-Path $script:log_directory "$build_id.log"
  $status_path = Join-Path $script:log_directory "$build_id.status.json"
  $worker_path = Join-Path $script:log_directory "$build_id.ps1"
  $job_path = Join-Path $script:log_directory "$build_id.job.json"
  $started_at = [DateTime]::UtcNow.ToString("o")

  $msbuild_arguments = [System.Collections.Generic.List[string]]::new()
  $msbuild_arguments.Add($workspace.solution_path)
  if ($restore) { $msbuild_arguments.Add("/restore") }
  $msbuild_arguments.Add("/m")
  $msbuild_arguments.Add("/nologo")
  $msbuild_arguments.Add("/verbosity:minimal")
  $msbuild_arguments.Add("/p:Configuration=$configuration")
  $msbuild_arguments.Add("/p:Platform=$platform")

  # the detached worker receives its job as data, never as shell text, so paths
  # with spaces (e.g. C:\Users\Adam Williams) carry no quoting hazard
  [System.IO.File]::WriteAllText(
    $job_path,
    ([ordered]@{
      msbuild = $msbuild
      msbuild_arguments = $msbuild_arguments
      workspace_root = $workspace.workspace_root
      log_path = $log_path
      status_path = $status_path
      started_at = $started_at
    } | ConvertTo-Json -Compress),
    [System.Text.UTF8Encoding]::new($false)
  )

  # standalone worker: locates its own job file, runs msbuild with splatted
  # arguments, streams every line to the log, then records a terminal status.
  # literal here-string so $-tokens resolve inside the worker, not here.
  $worker = @'
$ErrorActionPreference = "Stop"
$job_path = [System.IO.Path]::ChangeExtension($PSCommandPath, ".job.json")
$job = Get-Content -LiteralPath $job_path -Raw | ConvertFrom-Json
$exit_code = 1
$writer = [System.IO.StreamWriter]::new($job.log_path, $false, [System.Text.UTF8Encoding]::new($false))
try {
  Push-Location -LiteralPath $job.workspace_root
  try {
    $msbuild_arguments = @($job.msbuild_arguments)
    # native tools may write to stderr; that must not abort log capture, and we
    # need the real process exit code rather than a thrown NativeCommandError
    $ErrorActionPreference = "Continue"
    & $job.msbuild @msbuild_arguments 2>&1 | ForEach-Object {
      $writer.WriteLine($_.ToString())
      $writer.Flush()
    }
    $exit_code = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = "Stop"
    Pop-Location
  }
}
catch {
  $writer.WriteLine($_.Exception.Message)
}
finally {
  $writer.Dispose()
}
[System.IO.File]::WriteAllText(
  $job.status_path,
  ([ordered]@{
    state = "completed"
    exit_code = $exit_code
    started_at = $job.started_at
    completed_at = [DateTime]::UtcNow.ToString("o")
  } | ConvertTo-Json -Compress),
  [System.Text.UTF8Encoding]::new($false)
)
exit $exit_code
'@
  [System.IO.File]::WriteAllText($worker_path, $worker, [System.Text.UTF8Encoding]::new($false))

  # base64-encoded launch sidesteps every layer of shell quoting; the only datum
  # is the worker path, and it travels inside the encoded script, not a CLI token
  $launch_script = "& '$($worker_path.Replace("'", "''"))'"
  $encoded_command = [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($launch_script))

  $process = Start-Process -FilePath "powershell.exe" -ArgumentList @(
    "-NoProfile"
    "-NonInteractive"
    "-ExecutionPolicy", "Bypass"
    "-EncodedCommand", $encoded_command
  ) -WorkingDirectory $script:log_directory -PassThru -WindowStyle Hidden

  [System.IO.File]::WriteAllText(
    $status_path,
    (@{ state = "running"; started_at = $started_at; pid = $process.Id } | ConvertTo-Json -Compress),
    [System.Text.UTF8Encoding]::new($false)
  )

  return [ordered]@{
    build_id = $build_id
    state = "running"
    pid = $process.Id
    configuration = $configuration
    platform = $platform
    started_at = $started_at
  }
}

function Read-BuildLog {
  param([object]$arguments)

  $build_id = [string](Get-ArgumentValue -arguments $arguments -name "build_id")
  if ($build_id -notmatch '^[a-f0-9]{32}$') {
    throw "build_id must be a 32-character lowercase hexadecimal identifier"
  }

  $offset = [long](Get-ArgumentValue -arguments $arguments -name "offset" -default_value 0)
  $length = [int](Get-ArgumentValue -arguments $arguments -name "length" -default_value 16384)
  if ($offset -lt 0) {
    throw "offset must be non-negative"
  }
  if ($length -lt 1 -or $length -gt 65536) {
    throw "length must be between 1 and 65536"
  }

  $log_path = Join-Path $script:log_directory "$build_id.log"
  $status_path = Join-Path $script:log_directory "$build_id.status.json"
  if (-not (Test-Path -LiteralPath $status_path -PathType Leaf)) {
    throw "build_id was not found"
  }

  $status = Get-Content -LiteralPath $status_path -Raw | ConvertFrom-Json
  $state = [string]$status.state
  $exit_code = Get-ArgumentValue -arguments $status -name "exit_code" -default_value $null

  # a build that is still marked running but whose process is gone died before
  # it could record a completion status; surface that instead of running forever
  if ($state -eq "running") {
    $build_pid = Get-ArgumentValue -arguments $status -name "pid" -default_value $null
    if ($null -ne $build_pid -and $null -eq (Get-Process -Id ([int]$build_pid) -ErrorAction SilentlyContinue)) {
      # re-read once in case the build wrote its completion status as it exited
      $status = Get-Content -LiteralPath $status_path -Raw | ConvertFrom-Json
      $state = [string]$status.state
      $exit_code = Get-ArgumentValue -arguments $status -name "exit_code" -default_value $null
      if ($state -eq "running") {
        $state = "failed"
      }
    }
  }

  $total_length = $(if (Test-Path -LiteralPath $log_path -PathType Leaf) { (Get-Item -LiteralPath $log_path).Length } else { 0 })
  $safe_offset = [Math]::Min($offset, $total_length)
  $read_length = [int][Math]::Min($length, $total_length - $safe_offset)
  $text = ""

  if ($read_length -gt 0) {
    $stream = [System.IO.File]::Open($log_path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
      [void]$stream.Seek($safe_offset, [System.IO.SeekOrigin]::Begin)
      $buffer = New-Object byte[] $read_length
      $bytes_read = $stream.Read($buffer, 0, $read_length)
      $text = [System.Text.UTF8Encoding]::new($false).GetString($buffer, 0, $bytes_read)
      $read_length = $bytes_read
    }
    finally {
      $stream.Dispose()
    }
  }

  return [ordered]@{
    build_id = $build_id
    state = $state
    exit_code = $exit_code
    offset = $safe_offset
    next_offset = $safe_offset + $read_length
    total_length = $total_length
    eof = ($safe_offset + $read_length -ge $total_length)
    log = $text
  }
}

$script:tools = @(
  [ordered]@{
    name = "windows_dev_toolchain_status"
    description = "Report the configured Windows workspace and fixed Windows build tools. This command does not modify the host."
    inputSchema = [ordered]@{
      type = "object"
      properties = [ordered]@{}
      additionalProperties = $false
    }
  },
  [ordered]@{
    name = "windows_dev_build_solution"
    description = "Start an asynchronous Debug or Release build of the configured HoldUp Windows solution. Only x64 and ARM64 are accepted."
    inputSchema = [ordered]@{
      type = "object"
      properties = [ordered]@{
        configuration = [ordered]@{ type = "string"; enum = @("Debug", "Release"); default = "Debug" }
        platform = [ordered]@{ type = "string"; enum = @("x64", "ARM64"); default = "x64" }
        restore = [ordered]@{ type = "boolean"; default = $true }
      }
      additionalProperties = $false
    }
  },
  [ordered]@{
    name = "windows_dev_read_build_log"
    description = "Read a bounded byte range from a build log and return the build state."
    inputSchema = [ordered]@{
      type = "object"
      properties = [ordered]@{
        build_id = [ordered]@{ type = "string"; pattern = "^[a-f0-9]{32}$" }
        offset = [ordered]@{ type = "integer"; minimum = 0; default = 0 }
        length = [ordered]@{ type = "integer"; minimum = 1; maximum = 65536; default = 16384 }
      }
      required = @("build_id")
      additionalProperties = $false
    }
  }
)

function Invoke-Tool {
  param([Parameter(Mandatory = $true)][object]$parameters)

  $name = [string](Get-ArgumentValue -arguments $parameters -name "name")
  $arguments = Get-ArgumentValue -arguments $parameters -name "arguments" -default_value $null

  try {
    switch ($name) {
      "windows_dev_toolchain_status" { return New-JsonToolResult -value (Get-ToolchainStatus) }
      "windows_dev_build_solution" { return New-JsonToolResult -value (Start-Build -arguments $arguments) }
      "windows_dev_read_build_log" { return New-JsonToolResult -value (Read-BuildLog -arguments $arguments) }
      default { return New-TextToolResult -text "unknown tool: $name" -is_error $true }
    }
  }
  catch {
    return New-TextToolResult -text $_.Exception.Message -is_error $true
  }
}

while ($true) {
  $line = [Console]::In.ReadLine()
  if ($null -eq $line) {
    break
  }
  if ([string]::IsNullOrWhiteSpace($line)) {
    continue
  }

  try {
    $request = $line | ConvertFrom-Json
    $id = Get-ArgumentValue -arguments $request -name "id" -default_value $null
    $method = [string]$request.method
    $response = $null

    switch ($method) {
      "initialize" {
        $response = [ordered]@{
          jsonrpc = "2.0"
          id = $id
          result = [ordered]@{
            protocolVersion = $script:protocol_version
            capabilities = [ordered]@{ tools = [ordered]@{} }
            serverInfo = [ordered]@{ name = "windows-dev"; version = "0.1.0" }
          }
        }
      }
      "tools/list" {
        $response = [ordered]@{
          jsonrpc = "2.0"
          id = $id
          result = [ordered]@{ tools = $script:tools }
        }
      }
      "tools/call" {
        $response = [ordered]@{
          jsonrpc = "2.0"
          id = $id
          result = Invoke-Tool -parameters $request.params
        }
      }
      "ping" {
        $response = [ordered]@{
          jsonrpc = "2.0"
          id = $id
          result = [ordered]@{}
        }
      }
      { $_ -like "notifications/*" } {
        $response = $null
      }
      default {
        $response = [ordered]@{
          jsonrpc = "2.0"
          id = $id
          error = [ordered]@{
            code = -32601
            message = "method not found: $method"
          }
        }
      }
    }

    if ($null -ne $response) {
      Write-ProtocolMessage -message $response
    }
  }
  catch {
    Write-ProtocolMessage -message ([ordered]@{
      jsonrpc = "2.0"
      id = $null
      error = [ordered]@{
        code = -32700
        message = "invalid request"
      }
    })
  }
}
