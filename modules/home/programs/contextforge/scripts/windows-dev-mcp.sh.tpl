#!@BASH@
set -euo pipefail

config_file="@CONFIG_DIR@/windows-dev.env"
if [[ -f "$config_file" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$config_file"
  set +a
fi

if [[ "${WINDOWS_DEV_WORKSPACE_ROOT:-}" == /* ]]; then
  export WINDOWS_DEV_WORKSPACE_ROOT="$(/bin/wslpath -w "$WINDOWS_DEV_WORKSPACE_ROOT")"
fi

powershell="/mnt/c/WINDOWS/System32/WindowsPowerShell/v1.0/powershell.exe"
if [[ ! -x "$powershell" ]]; then
  echo "windows-dev: Windows PowerShell is unavailable; this bridge requires WSL interop" >&2
  exit 1
fi

arguments=(
  -NoLogo
  -NoProfile
  -NonInteractive
  -ExecutionPolicy
  Bypass
  -File
  "$(/bin/wslpath -w "@WINDOWS_DEV_MCP_SCRIPT@")"
)

if [[ -n "${WINDOWS_DEV_WORKSPACE_ROOT:-}" ]]; then
  arguments+=( -WorkspaceRoot "$WINDOWS_DEV_WORKSPACE_ROOT" )
fi

exec "$powershell" "${arguments[@]}"
