#!@BASH@
# podman machine init/start wrapper for launchd
#
# podman machine start spawns gvproxy and vfkit as child processes.
# if this script exits, launchd tears down the process group and kills
# them both. we must stay alive for the lifetime of the machine by
# waiting on the gvproxy pid.
set -euo pipefail
export PATH="@PATH@:$PATH"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

# ensure a default machine exists
if ! podman machine inspect 2>/dev/null; then
  log "no default machine found, initializing..."
  podman machine init
fi

# start the machine (exits quickly once gvproxy/vfkit are forked)
log "starting podman machine..."
podman machine start || true
log "podman machine started"

# find the gvproxy pid and wait on it so the process group stays alive
pid_file="$TMPDIR/podman/gvproxy.pid"
if [[ -f "$pid_file" ]]; then
  gv_pid=$(<"$pid_file")
  log "waiting on gvproxy (pid $gv_pid)..."
  while kill -0 "$gv_pid" 2>/dev/null; do
    sleep 5
  done
  log "gvproxy exited"
else
  log "warning: gvproxy pid file not found, exiting"
fi
