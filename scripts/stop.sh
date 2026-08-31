#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

# Marker: fedora-shell-stop-v1
FEDORA_ENTRY_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$FEDORA_ENTRY_DIR/lib/common.sh"

FEDORA_ASSUME_YES="${FEDORA_ASSUME_YES:-0}"

usage() {
  cat >&2 <<'EOF'
Usage: ./scripts/stop.sh [--yes]

Stops only Fedora Shell's recorded container and project-owned transport
processes. Android and One UI are not modified.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --yes) FEDORA_ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; fedora_die "Unknown option: $1"; exit 64 ;;
  esac
done

fedora_init_log
fedora_require_termux
fedora_require_non_root
fedora_require_pd
fedora_init_state

if fedora_container_exists && fedora_container_running; then
  fedora_log "Stopping only Fedora container '$FEDORA_CONTAINER'."
  "$FEDORA_PD_BIN" kill "$FEDORA_CONTAINER" || fedora_warn "PRoot-Distro did not report a clean stop."
else
  fedora_log "Fedora container is not running."
fi

fedora_kill_owned_pid "$FEDORA_PID_DIR/virgl.pid" virgl_test_server_android
fedora_kill_owned_pid "$FEDORA_PID_DIR/termux-x11.pid" termux-x11
rm -f -- "$FEDORA_PID_DIR/termux-x11.args"
if [[ -x "$FEDORA_INSTALL_ROOT/audio/stop.sh" ]]; then
  "$FEDORA_INSTALL_ROOT/audio/stop.sh" || true
fi

if [[ -x /system/bin/am ]]; then
  /system/bin/am broadcast -a com.termux.x11.ACTION_STOP -p com.termux.x11 \
    >> "$FEDORA_LOG_FILE" 2>&1 || true
fi
rm -f -- "$FEDORA_STATE_DIR/session-host.env" \
  "$FEDORA_TERMUX_PREFIX/tmp/fedora-runtime/fedora-session-state.env"
fedora_log "Fedora Shell stopped. Android/One UI was not modified."
