#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

# Marker: fedora-shell-reset-v1
FEDORA_ENTRY_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$FEDORA_ENTRY_DIR/lib/common.sh"
# shellcheck disable=SC1091
source "$FEDORA_ENTRY_DIR/lib/guest-config.sh"

FEDORA_ASSUME_YES="${FEDORA_ASSUME_YES:-0}"
MAKE_BACKUP=1

usage() {
  cat >&2 <<'EOF'
Usage: ./scripts/reset.sh [--yes] [--no-backup]

This removes and re-installs only the Fedora container from its recorded OCI
image. The Fedora home, GNOME packages and container data are lost.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --yes) FEDORA_ASSUME_YES=1; shift ;;
    --no-backup) MAKE_BACKUP=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 64 ;;
  esac
done

fedora_init_log
fedora_require_termux
fedora_require_non_root
fedora_require_container

if ! fedora_confirm "Reset Fedora container '$FEDORA_CONTAINER'? All data inside it will be lost."; then
  fedora_die "Reset cancelled."
  exit 1
fi

if fedora_container_running; then
  "$FEDORA_ENTRY_DIR/stop.sh" --yes
fi
if (( MAKE_BACKUP )); then
  "$FEDORA_ENTRY_DIR/backup.sh" --yes
else
  fedora_warn "Skipping backup because --no-backup was explicitly supplied."
fi

fedora_log "Resetting container from its recorded OCI image."
"$FEDORA_PD_BIN" reset "$FEDORA_CONTAINER"
fedora_run_guest_setup
fedora_sync_guest_config
fedora_log "Fedora container reset and GNOME configuration restored."
