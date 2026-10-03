#!/usr/bin/env sh
# .agents/_common.sh - shared POSIX runtime helpers for repository agent workflows
set -eu

log_info() {
  printf '[agents] %s\n' "$1"
}

log_error() {
  printf '[agents] error: %s\n' "$1" >&2
}

log_warn() {
  printf '[agents] warning: %s\n' "$1" >&2
}

# Resolve repository root
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  REPO_ROOT="$(git rev-parse --show-toplevel)"
else
  _script_dir="$(cd "$(dirname "$0")" && pwd)"
  case "$_script_dir" in
    */.agents) REPO_ROOT="$(cd "$_script_dir/.." && pwd)" ;;
    *) REPO_ROOT="$(pwd)" ;;
  esac
fi

# Load optional repository-specific agent configuration
if [ -f "${REPO_ROOT}/.agents/config.env" ]; then
  # shellcheck disable=SC1090
  . "${REPO_ROOT}/.agents/config.env"
fi

# Apply mandatory telemetry shutdown
apply_telemetry_guards() {
  export DO_NOT_TRACK="1"
  export DISABLE_TELEMETRY="1"
  export CODEX_DISABLE_TELEMETRY="1"
  export AGY_TELEMETRY_ENABLED="false"
  export ANTIGRAVITY_TELEMETRY_ENABLED="false"
  export OPENCODE_TELEMETRY_ENABLED="false"
  export OTEL_SDK_DISABLED="true"
  export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1"
  export DISABLE_NON_ESSENTIAL_MODEL_CALLS="1"
  export DISABLE_AUTOUPDATER="1"
  export DISABLE_GROWTHBOOK="1"
  export DISABLE_ERROR_REPORTING="1"
}

# Generic agent dispatcher
dispatch_agent() {
  _agent_bin="$1"
  shift

  apply_telemetry_guards

  if ! command -v "$_agent_bin" >/dev/null 2>&1; then
    log_error "agent executable '${_agent_bin}' not found in PATH"
    return 127
  fi

  log_info "dispatching agent: ${_agent_bin}"
  exec "$_agent_bin" "$@"
}
